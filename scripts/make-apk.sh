#!/usr/bin/env bash
# Builds the Android app as a signed .apk in dist/. Install it on a phone by opening the file
# (allow installs from that app when Android asks).
#
# Needs a JDK 17+ and the Android SDK: found through JAVA_HOME / ANDROID_HOME, or in ~/.jdk and
# ~/.android-sdk, or Android Studio's. Signing reads android/keystore.properties (not in git; see
# README). Without it, the .apk is built unsigned and Android won't install it.
#
# Official builds: if the private brand kit is cloned next to this repository (../brand-kit),
# this app's name, icon and intro are used. Otherwise the neutral "AI-ML Refresher" is built.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${JAVA_HOME:-}" ]; then
  for j in "$HOME"/.jdk/*/Contents/Home "/Applications/Android Studio.app/Contents/jbr/Contents/Home"; do
    [ -x "$j/bin/java" ] && { export JAVA_HOME="$j"; break; }
  done
fi
if [ -z "${ANDROID_HOME:-}" ]; then
  for s in "$HOME/.android-sdk" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    [ -d "$s/platforms" ] && { export ANDROID_HOME="$s"; break; }
  done
fi
[ -n "${JAVA_HOME:-}" ] || { echo "No JDK found: set JAVA_HOME." >&2; exit 1; }
[ -n "${ANDROID_HOME:-}" ] || { echo "No Android SDK found: set ANDROID_HOME." >&2; exit 1; }
[ -f android/keystore.properties ] || echo "warning: android/keystore.properties missing; the .apk will be unsigned." >&2

APP_DISPLAY_NAME="AI-ML Refresher"
BRAND_DIR=../brand-kit/products/ai-ml-refresher
if [ -f "$BRAND_DIR/brand.env" ] && [ -f "$BRAND_DIR/android/brand.properties" ]; then
  # shellcheck disable=SC1090
  source "$BRAND_DIR/brand.env"
fi
VERSION="$(sed -n 's/^ *versionName = "\(.*\)"/\1/p' android/app/build.gradle.kts | head -1)"

(cd android && ./gradlew -q :core:test :app:assembleRelease) >&2
APK=android/app/build/outputs/apk/release/app-release.apk
[ -f "$APK" ] || APK=android/app/build/outputs/apk/release/app-release-unsigned.apk

mkdir -p dist
OUT="dist/${APP_DISPLAY_NAME// /-}-${VERSION}-android.apk"
cp "$APK" "$OUT"
echo "Created $OUT ($(du -h "$OUT" | cut -f1))"
