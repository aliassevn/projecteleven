#!/bin/bash
# Bouwt macos/build/Cyberpad.app (release, ad-hoc ondertekend).
# Gebruik: macos/scripts/build.sh            → voor deze Mac
#          macos/scripts/build.sh universal  → arm64 + x86_64 (vereist volledige Xcode)
set -euo pipefail
cd "$(dirname "$0")/.."          # macos/
SHARED=../shared                 # tablet-pagina en catalogus, gedeeld met de Windows-versie

ARGS=(-c release)
if [[ "${1:-}" == "universal" ]]; then ARGS+=(--arch arm64 --arch x86_64); fi

swift build "${ARGS[@]}"
BIN="$(swift build "${ARGS[@]}" --show-bin-path)/Cyberpad"

APP=build/Cyberpad.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Cyberpad"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R "$SHARED/pad" "$APP/Contents/Resources/pad"
cp -R "$SHARED/catalog" "$APP/Contents/Resources/catalog"
if [[ -d "$SHARED/plugins" ]]; then cp -R "$SHARED/plugins" "$APP/Contents/Resources/plugins"; fi
cp -R "$SHARED/editor" "$APP/Contents/Resources/editor"
codesign --force --sign - "$APP"

echo "Klaar: macos/$APP"
