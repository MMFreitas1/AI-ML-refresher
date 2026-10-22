#!/usr/bin/env bash
# Builds the official .dmg (macOS) and .exe (Windows) and attaches them to a draft GitHub release
# tagged v<version>. Review the draft on GitHub, then publish it.
#
# Runs on a Mac with Xcode, the .NET 10 SDK, the GitHub CLI (gh, signed in) and the private brand
# kit cloned next to this repository (../brand-kit). Release from an up-to-date main.
# Usage: scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f ../brand-kit/products/ai-ml-refresher/brand.env ] || {
  echo "Official releases need the brand kit at ../brand-kit." >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first." >&2; exit 1; }
[ "$(git branch --show-current)" = main ] || { echo "Release from main." >&2; exit 1; }
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || {
  echo "main isn't the same as origin/main; pull or push first." >&2; exit 1; }

VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml | head -1)"
EXE_VERSION="$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' windows/Directory.Build.props | head -1)"
[ "${EXE_VERSION%.0}" = "$VERSION" ] || {
  echo "Versions differ: project.yml $VERSION, windows/Directory.Build.props $EXE_VERSION." >&2; exit 1; }
TAG="v$VERSION"
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Release $TAG already exists; raise the version first." >&2; exit 1
fi

DMG="$(./scripts/make-dmg.sh | sed -n 's/^Created \(.*\.dmg\) .*/\1/p')"
EXE="$(./scripts/make-exe.sh | sed -n 's/^Created \(.*\.exe\) .*/\1/p')"
[ -f "$DMG" ] && [ -f "$EXE" ] || { echo "Build failed." >&2; exit 1; }

gh release create "$TAG" "$DMG" "$EXE" --draft --target main --title "$VERSION" --notes "\
**macOS** (15 or later, Apple silicon): download the \`.dmg\`, open it and drag the app to Applications. It isn't notarized yet, so macOS blocks the first launch: go to **System Settings → Privacy & Security** and click **Open Anyway**.

**Windows** (10 or 11, 64-bit): download the \`.exe\` and run it. It isn't code-signed yet, so Windows may say \"Windows protected your PC\": click **More info → Run anyway**."
echo "Draft release $TAG created with $(basename "$DMG") and $(basename "$EXE"). Publish it on GitHub when ready." >&2
