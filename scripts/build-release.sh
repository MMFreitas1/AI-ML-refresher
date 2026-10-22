#!/usr/bin/env bash
# Builds a signed Release of the app (with its widget and background helper) into <build-dir>
# and prints the path of the built .app on the last line.
#
# Official builds: if the private Brand/ package is present, its name, icon and intro are used
# (Brand/brand.env sets APP_DISPLAY_NAME). Otherwise the neutral "AI-ML Refresher" is built.
# Usage: scripts/build-release.sh <build-dir>
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_DIR="${1:?usage: build-release.sh <build-dir>}"

./scripts/make-xcode-project.sh
APP_DISPLAY_NAME="AI-ML Refresher"
if [ -f Brand/brand.env ]; then
  # shellcheck disable=SC1091
  source Brand/brand.env
fi
xcodebuild -project Refresher.xcodeproj -scheme Refresher -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$BUILD_DIR" -allowProvisioningUpdates -quiet \
  build >&2

echo "$BUILD_DIR/Build/Products/Release/$APP_DISPLAY_NAME.app"
