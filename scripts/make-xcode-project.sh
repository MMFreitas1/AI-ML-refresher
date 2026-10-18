#!/usr/bin/env bash
# Generates AIBrief.xcodeproj from project.yml. Requires full Xcode (not just Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate
echo "Open AIBrief.xcodeproj, pick your team under Signing & Capabilities for both targets, then Run (⌘R)."
