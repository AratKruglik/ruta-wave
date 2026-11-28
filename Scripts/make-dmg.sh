#!/usr/bin/env bash
# Builds a Release RutaWave.app and packs it into a drag-to-Applications DMG.
#   Scripts/make-dmg.sh 0.2.0 [build-number]   -> build/dmg/RutaWave-0.2.0.dmg
# CODESIGN_IDENTITY="Developer ID Application: …" re-signs the app and the DMG for notarization;
# without it the app keeps Xcode's ad-hoc signature.
set -euo pipefail

VERSION="${1:?usage: make-dmg.sh <version> [build-number]}"
BUILD_NUMBER="${2:-1}"
IDENTITY="${CODESIGN_IDENTITY:-}"
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
  ARCHS=arm64 \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

if [[ -n "$IDENTITY" ]]; then
  sign() {
    codesign --force --sign "$IDENTITY" --options runtime --timestamp --preserve-metadata=entitlements "$1"
  }
  # shortcut: nested code is found by bundle extension plus Sparkle's bare Autoupdate binary; add names here when a dependency ships other loose executables.
  while IFS= read -r -d '' nested; do
    sign "$nested"
  done < <(find "$APP/Contents" -depth \
    \( -type d \( -name '*.xpc' -o -name '*.app' -o -name '*.framework' \) \
    -o -type f \( -name '*.dylib' -o -name Autoupdate \) \) -print0)
  sign "$APP"
fi

codesign --verify --deep --strict "$APP"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$OUT"
rm -f "$DMG"
hdiutil create -volname "RutaWave $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
[[ -z "$IDENTITY" ]] || codesign --sign "$IDENTITY" --timestamp "$DMG"
echo "$DMG"
