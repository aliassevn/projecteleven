#!/bin/bash
# Bouwt build/Cyberpad.app (release, ad-hoc ondertekend).
# Gebruik: scripts/build.sh            → voor deze Mac
#          scripts/build.sh universal  → arm64 + x86_64 (vereist volledige Xcode)
set -euo pipefail
cd "$(dirname "$0")/.."

ARGS=(-c release)
if [[ "${1:-}" == "universal" ]]; then ARGS+=(--arch arm64 --arch x86_64); fi

swift build "${ARGS[@]}"
BIN="$(swift build "${ARGS[@]}" --show-bin-path)/Cyberpad"

APP=build/Cyberpad.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Cyberpad"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R pad "$APP/Contents/Resources/pad"
codesign --force --sign - "$APP"

echo "Klaar: $APP"
