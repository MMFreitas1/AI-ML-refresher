#!/usr/bin/env bash
# Generates Refresher.xcodeproj from project.yml, and the app icon set.
# With the private Brand/ package present, the project uses the brand's name, icon and intro;
# otherwise the neutral "AI-ML Refresher". Requires full Xcode (not just Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

APP_DISPLAY_NAME="AI-ML Refresher"
if [ -f Brand/brand.env ]; then
  # shellcheck disable=SC1091
  source Brand/brand.env
fi
export APP_DISPLAY_NAME

command -v xcodegen >/dev/null || brew install xcodegen
swift run -q app-assets icon App/Assets.xcassets/AppIcon.appiconset >/dev/null
xcodegen generate --quiet
echo "Generated Refresher.xcodeproj for \"$APP_DISPLAY_NAME\"" >&2
