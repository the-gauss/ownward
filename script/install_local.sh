#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist/Ownward.app"
TARGET_APP="/Applications/Ownward.app"
AUTOMATION_DIR="$HOME/Library/Application Support/Ownward/Automation"
LAUNCH_AGENT_SOURCE="$ROOT_DIR/script/com.ownward.scheduled-launch.plist"
LAUNCH_AGENT_TARGET="$HOME/Library/LaunchAgents/com.ownward.scheduled-launch.plist"
LAUNCH_DOMAIN="gui/$(id -u)"
STAGING_DIR="$(mktemp -d /tmp/ownward-install.XXXXXX)"
PREVIOUS_APP="$STAGING_DIR/Ownward.previous.app"

restore_previous_app() {
  if [[ -d "$PREVIOUS_APP" && ! -d "$TARGET_APP" ]]; then
    mv "$PREVIOUS_APP" "$TARGET_APP"
  fi
  rm -rf "$STAGING_DIR"
}
trap restore_previous_app EXIT

"$ROOT_DIR/script/build_and_run.sh" --release --verify
pkill -x Ownward >/dev/null 2>&1 || true

if [[ -d "$TARGET_APP" ]]; then
  mv "$TARGET_APP" "$PREVIOUS_APP"
fi
/usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$TARGET_APP"

mkdir -p "$AUTOMATION_DIR" "$HOME/Library/LaunchAgents"
/usr/bin/install -m 755 "$ROOT_DIR/mcp/ownward_mcp.py" "$AUTOMATION_DIR/ownward_mcp.py"
/usr/bin/install -m 644 "$LAUNCH_AGENT_SOURCE" "$LAUNCH_AGENT_TARGET"
/usr/bin/plutil -lint "$LAUNCH_AGENT_TARGET" >/dev/null

/bin/launchctl bootout "$LAUNCH_DOMAIN/com.ownward.scheduled-launch" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "$LAUNCH_DOMAIN" "$LAUNCH_AGENT_TARGET"
/bin/launchctl kickstart "$LAUNCH_DOMAIN/com.ownward.scheduled-launch"

rm -rf "$PREVIOUS_APP"
/usr/bin/open -g "$TARGET_APP"
