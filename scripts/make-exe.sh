#!/usr/bin/env bash
# Builds the Windows app as one self-contained .exe in dist/ (no .NET install needed to run it).
# Runs on macOS, Linux or Windows (Git Bash) with the .NET 10 SDK.
#
# Official builds: if the private Brand/windows package is present, its name, icon and intro are
# used. Otherwise the neutral "AI-ML Refresher" is built.
set -euo pipefail
cd "$(dirname "$0")/.."
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
DOTNET="$(command -v dotnet || echo "$HOME/.dotnet/dotnet")"
ARCH="${1:-x64}"   # x64 or arm64

APP_DISPLAY_NAME="AI-ML Refresher"
if [ -f Brand/brand.env ] && [ -f Brand/windows/Brand.Windows.csproj ]; then
  # shellcheck disable=SC1091
  source Brand/brand.env
fi
VERSION="$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' windows/Directory.Build.props | head -1)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

"$DOTNET" publish windows/Refresher.App -c Release -r "win-$ARCH" --self-contained \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
  -p:EnableCompressionInSingleFile=true -p:DebugType=none -o "$WORK" >&2

mkdir -p dist
SUFFIX=""; [ "$ARCH" = x64 ] || SUFFIX="-$ARCH"
OUT="dist/${APP_DISPLAY_NAME// /-}-${VERSION%.0}-windows${SUFFIX}.exe"
cp "$WORK/Refresher.exe" "$OUT"
echo "Created $OUT ($(du -h "$OUT" | cut -f1))"
