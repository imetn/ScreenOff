#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-build}"
if [[ "$MODE" != "build" && "$MODE" != "--publish" ]]; then
    echo "用法：$0 [build|--publish]" >&2
    exit 2
fi

APP_NAME="ScreenOff"
REPOSITORY="imetn/ScreenOff"
REPOSITORY_URL="https://github.com/$REPOSITORY"
TEAM_ID="${SCREENOFF_TEAM_ID:-PRYY9PKKUP}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/ScreenOff.xcodeproj"
DERIVED_DATA="$ROOT_DIR/build/ReleaseDerivedData"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode-27.0.0-Beta.4.app" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-27.0.0-Beta.4.app/Contents/Developer"
elif [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode-26.6.0.app" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-26.6.0.app/Contents/Developer"
fi

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "缺少命令：$1" >&2
        exit 1
    fi
}

require_command xcodegen
require_command gh
require_command xmllint

cd "$ROOT_DIR"
xcodegen generate

if [[ -n "$(git status --porcelain)" ]]; then
    echo "发布前工作区必须干净，请先提交全部变更。" >&2
    exit 1
fi

BUILD_SETTINGS="$(
    /usr/bin/xcrun xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$APP_NAME" \
        -configuration Release \
        -showBuildSettings
)"

VERSION="$(awk -F ' = ' '/ MARKETING_VERSION = / { print $2; exit }' <<< "$BUILD_SETTINGS")"
BUILD_NUMBER="$(awk -F ' = ' '/ CURRENT_PROJECT_VERSION = / { print $2; exit }' <<< "$BUILD_SETTINGS")"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "版本号无效：version=$VERSION build=$BUILD_NUMBER" >&2
    exit 1
fi

TAG="v$VERSION"
RELEASE_DIR="$ROOT_DIR/build/releases/$TAG"
ARCHIVE_PATH="$RELEASE_DIR/$APP_NAME.xcarchive"
STAGING_DIR="$RELEASE_DIR/staging"
APP_PATH="$STAGING_DIR/$APP_NAME.app"
UPDATE_ARCHIVE="$RELEASE_DIR/$APP_NAME.zip"
APPCAST_PATH="$RELEASE_DIR/appcast.xml"
UPLOAD_OPTIONS="$RELEASE_DIR/UploadOptions.plist"
NOTARIZED_EXPORT="$RELEASE_DIR/notarized"
RELEASE_NOTES="$ROOT_DIR/docs/releases/$TAG.md"

case "$RELEASE_DIR" in
    "$ROOT_DIR"/build/releases/v*) ;;
    *)
        echo "拒绝清理异常发布目录：$RELEASE_DIR" >&2
        exit 1
        ;;
esac

if [[ ! -f "$RELEASE_NOTES" ]]; then
    echo "缺少发行说明：$RELEASE_NOTES" >&2
    exit 1
fi

rm -rf "$RELEASE_DIR"
mkdir -p "$STAGING_DIR"

echo "正在归档 $APP_NAME $VERSION ($BUILD_NUMBER)…"
/usr/bin/xcrun xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    -allowProvisioningUpdates \
    archive

plutil -create xml1 "$UPLOAD_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :method string developer-id" "$UPLOAD_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :destination string upload" "$UPLOAD_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :signingStyle string automatic" "$UPLOAD_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$UPLOAD_OPTIONS"

echo "正在使用公司 Developer ID 上传 Apple 公证…"
/usr/bin/xcrun xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$RELEASE_DIR/upload" \
    -exportOptionsPlist "$UPLOAD_OPTIONS" \
    -allowProvisioningUpdates

echo "等待 Apple 完成公证…"
for attempt in {1..40}; do
    rm -rf "$NOTARIZED_EXPORT"
    if /usr/bin/xcrun xcodebuild \
        -exportNotarizedApp \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$NOTARIZED_EXPORT" >/dev/null 2>&1; then
        break
    fi
    if [[ "$attempt" -eq 40 ]]; then
        echo "等待公证超时，请在 Xcode Organizer 查看该 Archive。" >&2
        exit 1
    fi
    sleep 30
done

/usr/bin/ditto "$NOTARIZED_EXPORT/$APP_NAME.app" "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNING_DETAILS="$(codesign -dvvv "$APP_PATH" 2>&1)"
grep -Fq "Authority=Developer ID Application:" <<< "$SIGNING_DETAILS"
grep -Eq "flags=.*runtime" <<< "$SIGNING_DETAILS"
grep -Fq "TeamIdentifier=$TEAM_ID" <<< "$SIGNING_DETAILS"

INFO_PLIST="$APP_PATH/Contents/Info.plist"
FEED_URL="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$INFO_PLIST")"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST")"
SIGNED_FEED="$(/usr/libexec/PlistBuddy -c 'Print :SURequireSignedFeed' "$INFO_PLIST")"
VERIFY_BEFORE_EXTRACTION="$(/usr/libexec/PlistBuddy -c 'Print :SUVerifyUpdateBeforeExtraction' "$INFO_PLIST")"

[[ "$FEED_URL" == "$REPOSITORY_URL/releases/latest/download/appcast.xml" ]]
[[ -n "$PUBLIC_KEY" ]]
[[ "$SIGNED_FEED" == "true" ]]
[[ "$VERIFY_BEFORE_EXTRACTION" == "true" ]]

/usr/bin/xcrun stapler validate "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$UPDATE_ARCHIVE"
cp "$RELEASE_NOTES" "$RELEASE_DIR/$APP_NAME.md"

GENERATE_APPCAST="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [[ ! -x "$GENERATE_APPCAST" ]]; then
    echo "未找到 Sparkle generate_appcast：$GENERATE_APPCAST" >&2
    exit 1
fi

"$GENERATE_APPCAST" \
    --download-url-prefix "$REPOSITORY_URL/releases/download/$TAG/" \
    --link "$REPOSITORY_URL" \
    --maximum-versions 1 \
    --maximum-deltas 0 \
    --embed-release-notes \
    -o "$APPCAST_PATH" \
    "$RELEASE_DIR"

xmllint --noout "$APPCAST_PATH"
grep -Fq "sparkle:edSignature=" "$APPCAST_PATH"
grep -Fq "<!-- sparkle-signatures:" "$APPCAST_PATH"
grep -Fq "$REPOSITORY_URL/releases/download/$TAG/$APP_NAME.zip" "$APPCAST_PATH"

shasum -a 256 "$UPDATE_ARCHIVE" "$APPCAST_PATH" > "$RELEASE_DIR/SHA256SUMS"

if [[ "$MODE" == "--publish" ]]; then
    if gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
        echo "GitHub Release 已存在：$TAG" >&2
        exit 1
    fi

    CURRENT_BRANCH="$(git branch --show-current)"
    if [[ "$CURRENT_BRANCH" != "main" ]]; then
        echo "只允许从 main 发布，当前分支：$CURRENT_BRANCH" >&2
        exit 1
    fi

    git push origin HEAD:main
    gh release create "$TAG" \
        "$UPDATE_ARCHIVE" \
        "$APPCAST_PATH" \
        "$RELEASE_DIR/SHA256SUMS" \
        --repo "$REPOSITORY" \
        --target "$(git rev-parse HEAD)" \
        --title "Screen Off $VERSION" \
        --notes-file "$RELEASE_NOTES"
fi

echo "发布产物已就绪：$RELEASE_DIR"
