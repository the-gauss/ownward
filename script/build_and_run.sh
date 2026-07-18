#!/usr/bin/env bash
set -euo pipefail

MODE="run"
BUILD_CONFIGURATION="debug"
APP_NAME="Ownward"
BUNDLE_ID="com.ownward.app"
MIN_SYSTEM_VERSION="15.0"
MARKETING_VERSION="1.0.0"
BUILD_NUMBER="1"

for argument in "$@"; do
  case "$argument" in
    --release|release) BUILD_CONFIGURATION="release" ;;
    --debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify) MODE="$argument" ;;
    run) MODE="run" ;;
    *)
      echo "usage: $0 [--release] [run|--debug|--logs|--telemetry|--verify]" >&2
      exit 2
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build -c "$BUILD_CONFIGURATION"
BUILD_DIR="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [[ -d "$BUILD_DIR/Ownward_OwnwardApp.bundle" ]]; then
  cp -R "$BUILD_DIR/Ownward_OwnwardApp.bundle" "$APP_RESOURCES/"
fi
cp "$ROOT_DIR/Sources/OwnwardApp/Resources/Brand/Ownward.icns" "$APP_RESOURCES/Ownward.icns"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>Ownward.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# SwiftPM signs the raw executable ad hoc. Re-sign the completed bundle so the
# generated Info.plist and copied resources are sealed as one valid local app.
/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
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
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [--release] [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
