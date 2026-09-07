#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ScreenOff"
BUNDLE_ID="com.frameflowtech.screenoff"
LEGACY_BUNDLE_ID="com.ethan.screenoff"
TEAM_ID="${SCREENOFF_TEAM_ID:-PRYY9PKKUP}"
SIGNING_IDENTITY="${SCREENOFF_SIGNING_IDENTITY:-Developer ID Application: Hangzhou FrameFlow Information Technology Services Co., Ltd. ($TEAM_ID)}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/ScreenOff.xcodeproj"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
INSTALL_APP="/Applications/$APP_NAME.app"
APP_BINARY="$INSTALL_APP/Contents/MacOS/$APP_NAME"

case "$MODE" in
    run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify) ;;
    *)
        echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode-26.6.0.app" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-26.6.0.app/Contents/Developer"
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "缺少命令：xcodegen" >&2
    exit 1
fi
if [[ ! -w /Applications || -L "$INSTALL_APP" ]]; then
    echo "安装位置不可写或是符号链接：$INSTALL_APP" >&2
    exit 1
fi
if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
    echo "未找到公司 Developer ID Application 证书：$SIGNING_IDENTITY" >&2
    exit 1
fi

validate_installed_app() {
    if [[ -e "$INSTALL_APP" ]]; then
        local installed_id
        installed_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALL_APP/Contents/Info.plist" 2>/dev/null || true)"
        if [[ "$installed_id" != "$BUNDLE_ID" && "$installed_id" != "$LEGACY_BUNDLE_ID" ]]; then
            echo "拒绝替换 Bundle ID 不匹配的 App：$INSTALL_APP ($installed_id)" >&2
            exit 1
        fi
    fi
}
validate_installed_app
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
xcodegen generate

/usr/bin/xcrun xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$APP_NAME" \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    CODE_SIGNING_ALLOWED=YES \
    build

BUILT_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")"
if [[ "$BUILT_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
    echo "构建产物 Bundle ID 错误：$BUILT_BUNDLE_ID" >&2
    exit 1
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
SIGNING_DETAILS="$(/usr/bin/codesign -dvvv "$APP_BUNDLE" 2>&1)"
grep -Fq "Authority=Developer ID Application:" <<< "$SIGNING_DETAILS"
grep -Fq "Authority=$SIGNING_IDENTITY" <<< "$SIGNING_DETAILS"
grep -Fq "TeamIdentifier=$TEAM_ID" <<< "$SIGNING_DETAILS"

validate_installed_app
BACKUP_PATH=""
if [[ -e "$INSTALL_APP" ]]; then
    BACKUP_DIR="$ROOT_DIR/build/AppBackups"
    mkdir -p "$BACKUP_DIR"
    BACKUP_DIR="$(mktemp -d "$BACKUP_DIR/$APP_NAME.XXXXXX")"
    BACKUP_PATH="$BACKUP_DIR/$APP_NAME.zip"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$INSTALL_APP" "$BACKUP_PATH"
    /usr/bin/unzip -tq "$BACKUP_PATH" >/dev/null
    /bin/rm -rf "$INSTALL_APP"
    echo "旧 App 已备份：$BACKUP_PATH"
fi

if ! /usr/bin/ditto "$APP_BUNDLE" "$INSTALL_APP" \
    || ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$INSTALL_APP"; then
    if [[ -n "$BACKUP_PATH" ]]; then
        /bin/rm -rf "$INSTALL_APP"
        /usr/bin/ditto -x -k "$BACKUP_PATH" /Applications
        echo "安装失败，已还原旧 App。" >&2
    fi
    exit 1
fi

open_app() {
    /usr/bin/open -n "$INSTALL_APP"
}

case "$MODE" in
    run)
        open_app
        ;;
    --debug|debug)
        /usr/bin/xcrun lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
    --telemetry|telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
    --verify|verify)
        open_app
        for _ in {1..20}; do
            if pgrep -x "$APP_NAME" >/dev/null; then
                exit 0
            fi
            sleep 0.25
        done
        echo "$APP_NAME 未能启动" >&2
        exit 1
        ;;
    *)
        echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac
