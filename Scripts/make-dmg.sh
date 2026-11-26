#!/usr/bin/env bash
# Builds a Release RutaWave.app and packs it into a drag-to-Applications DMG.
#   Scripts/make-dmg.sh 0.2.0 [build-number]   -> build/dmg/RutaWave-0.2.0.dmg
set -euo pipefail

VERSION="${1:?usage: make-dmg.sh <version> [build-number]}"
BUILD_NUMBER="${2:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/release"
OUT="$ROOT/build/dmg"
APP="$DERIVED/Build/Products/Release/RutaWave.app"
DMG="$OUT/RutaWave-$VERSION.dmg"

cd "$ROOT"
xcodegen generate --quiet
xcodebuild build \
  -project Rutawave.xcodeproj \
  -scheme Rutawave \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -quiet \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

codesign --verify --deep --strict "$APP"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$OUT"
rm -f "$DMG"
hdiutil create -volname "RutaWave $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
echo "$DMG"
