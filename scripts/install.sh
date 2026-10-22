#!/usr/bin/env bash
# Builds a signed Release and installs it to /Applications. Xcode doesn't need to be open.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d)"
# Forget the temporary build in Launch Services too, or macOS may later look for the app there.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
trap 'find "$BUILD_DIR" -name "*.app" -prune -exec "$LSREGISTER" -u {} \; 2>/dev/null; rm -rf "$BUILD_DIR"' EXIT

APP="$(./scripts/build-release.sh "$BUILD_DIR" | tail -1)"
NAME="$(basename "$APP" .app)"

pkill -x "$NAME" || true
rm -rf "/Applications/$NAME.app"
ditto "$APP" "/Applications/$NAME.app"
open "/Applications/$NAME.app"
# Restart the background helper so it runs the newly installed copy, not the replaced one.
sleep 2
launchctl kickstart -k "gui/$(id -u)/com.mmfreitas.aibrief.helper" 2>/dev/null || true
echo "Installed /Applications/$NAME.app"
