#!/usr/bin/env bash
# Packages the app as a drag-to-install disk image in dist/.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml | head -1)"
WORK="$(mktemp -d)"
# Forget the temporary build in Launch Services too, or macOS may later look for the app there.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
trap 'hdiutil detach -quiet "$WORK/mnt" 2>/dev/null || true; find "$WORK" -name "*.app" -prune -exec "$LSREGISTER" -u {} \; 2>/dev/null; rm -rf "$WORK"' EXIT

APP="$(./scripts/build-release.sh "$WORK/build" | tail -1)"
NAME="$(basename "$APP" .app)"
OUT="dist/${NAME// /-}-${VERSION}.dmg"

# Contents: the app and a shortcut to Applications to drag it onto.
mkdir -p "$WORK/stage"
ditto "$APP" "$WORK/stage/$NAME.app"
ln -s /Applications "$WORK/stage/Applications"

# Build read-write first so the volume can get the app's icon, then compress.
hdiutil create -quiet -volname "$NAME" -srcfolder "$WORK/stage" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
mkdir -p "$WORK/mnt"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$WORK/mnt" "$WORK/rw.dmg"
cp "$WORK/stage/$NAME.app/Contents/Resources/AppIcon.icns" "$WORK/mnt/.VolumeIcon.icns"
xcrun SetFile -a C "$WORK/mnt"
hdiutil detach -quiet "$WORK/mnt"

mkdir -p dist
rm -f "$OUT"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"
echo "Created $OUT ($(du -h "$OUT" | cut -f1))"
