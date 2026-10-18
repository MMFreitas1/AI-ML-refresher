#!/usr/bin/env bash
# Builds a signed Release copy and installs it to /Applications. Xcode doesn't need to be open.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

xcodegen generate
xcodebuild -project AIBrief.xcodeproj -scheme AIBrief -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$BUILD_DIR" -allowProvisioningUpdates -quiet build

pkill -x "AI Brief" || true
rm -rf "/Applications/AI Brief.app"
ditto "$BUILD_DIR/Build/Products/Release/AI Brief.app" "/Applications/AI Brief.app"
open "/Applications/AI Brief.app"
echo "Installed /Applications/AI Brief.app"
