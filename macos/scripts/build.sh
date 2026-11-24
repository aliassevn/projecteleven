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
# Versie voor een release (bijv. CYBERPAD_VERSION=0.2.0); anders die uit Info.plist.
if [[ -n "${CYBERPAD_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $CYBERPAD_VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${CYBERPAD_BUILD:-1}" "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R "$SHARED/pad" "$APP/Contents/Resources/pad"
cp -R "$SHARED/catalog" "$APP/Contents/Resources/catalog"
if [[ -d "$SHARED/plugins" ]]; then cp -R "$SHARED/plugins" "$APP/Contents/Resources/plugins"; fi
cp -R "$SHARED/editor" "$APP/Contents/Resources/editor"
cp -R "$SHARED/themes" "$APP/Contents/Resources/themes"
cp -R "$SHARED/i18n" "$APP/Contents/Resources/i18n"
codesign --force --sign - "$APP"

echo "Klaar: macos/$APP"
