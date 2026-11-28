#!/usr/bin/env bash
# Zips a built RutaWave.app for Sparkle, signs the archive with the EdDSA key in SPARKLE_PRIVATE_KEY,
# and writes appcast-item.json, which Scripts/appcast.py reads back from the GitHub release.
#   Scripts/sign-update.sh build/release/Build/Products/Release/RutaWave.app build/dmg
set -euo pipefail

APP="${1:?usage: sign-update.sh <RutaWave.app> <out-dir>}"
OUT="${2:?usage: sign-update.sh <RutaWave.app> <out-dir>}"
: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY is not set}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGN_UPDATE="${SIGN_UPDATE:-$ROOT/build/release/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update}"
INFO="$APP/Contents/Info.plist"

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$INFO"; }
SHORT_VERSION="$(plist CFBundleShortVersionString)"
VERSION="$(plist CFBundleVersion)"
MINIMUM_SYSTEM="$(plist LSMinimumSystemVersion)"

mkdir -p "$OUT"
ZIP="$OUT/RutaWave-$SHORT_VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

ATTRIBUTES="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$ZIP")"
SIGNATURE="$(sed -nE 's/.*sparkle:edSignature="([A-Za-z0-9+/=]+)".*/\1/p' <<<"$ATTRIBUTES")"
LENGTH="$(sed -nE 's/.*length="([0-9]+)".*/\1/p' <<<"$ATTRIBUTES")"
if [[ -z "$SIGNATURE" || -z "$LENGTH" ]]; then
  echo "sign_update printed no signature and length" >&2
  exit 1
fi

python3 - "$OUT/appcast-item.json" "$VERSION" "$SHORT_VERSION" "$SIGNATURE" "$LENGTH" "$MINIMUM_SYSTEM" <<'EOF'
import json, sys
path, version, short, signature, length, minimum = sys.argv[1:]
with open(path, "w") as file:
    json.dump({"version": version, "shortVersion": short, "edSignature": signature,
               "length": int(length), "minimumSystemVersion": minimum}, file, indent=2)
EOF
echo "$ZIP"
