#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ScreenOff"
BUNDLE_ID="com.ethan.screenoff"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/ScreenOff.xcodeproj"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode-26.6.0.app" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-26.6.0.app/Contents/Developer"
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

/usr/bin/xcrun xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$APP_NAME" \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    build

open_app() {
    /usr/bin/open -n "$APP_BUNDLE"
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

