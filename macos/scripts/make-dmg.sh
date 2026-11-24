#!/bin/bash
# Maakt de Mac-installer: macos/build/Cyberpad-<versie>.dmg met Cyberpad.app en een snelkoppeling naar Apps.
# Gebruik: macos/scripts/make-dmg.sh [versie] [universal]
#   macos/scripts/make-dmg.sh                 → versie uit Info.plist, voor deze Mac
#   macos/scripts/make-dmg.sh 0.2.0 universal → Apple-chip én Intel (vereist volledige Xcode)
set -euo pipefail
cd "$(dirname "$0")/.."          # macos/

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
CYBERPAD_VERSION="$VERSION" scripts/build.sh ${2:-}

STAGE=build/dmg
DMG="build/Cyberpad-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/Cyberpad.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Lees mij - Read me.txt" <<TXT
Cyberpad $VERSION

NL  Sleep Cyberpad naar Apps. Open het de eerste keer met rechtsklik › Open (of: Systeeminstellingen ›
    Privacy en beveiliging › "Open toch"), omdat de app niet bij Apple is aangemeld.
    Cyberpad staat daarna als icoon in de menubalk. Klik erop voor de koppelcode.

EN  Drag Cyberpad to Applications. The first time, open it with right-click › Open (or: System Settings ›
    Privacy & Security › "Open Anyway"), because the app is not notarized by Apple.
    Cyberpad then lives in the menu bar. Click its icon for the pairing code.

ES  Arrastra Cyberpad a Aplicaciones. La primera vez, ábrelo con clic derecho › Abrir (o: Ajustes del
    Sistema › Privacidad y seguridad › "Abrir igualmente"), porque la app no está notarizada por Apple.
    Después, Cyberpad aparece en la barra de menús. Haz clic en su icono para ver el código.
TXT

hdiutil create -volname "Cyberpad $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Klaar: macos/$DMG ($(du -h "$DMG" | cut -f1))"
