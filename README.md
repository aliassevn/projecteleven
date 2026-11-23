# Cyberpad (prototype)

Maak van een oude iPad of tablet een macropad voor je Mac. De tablet heeft alleen een browser nodig.
Dit is het prototype uit fase 0–3 van [STAPPENPLAN.md](STAPPENPLAN.md).

## Bouwen en starten

```bash
scripts/build.sh
```

```bash
open build/Cyberpad.app
```

Er verschijnt een rasterpictogram in de menubalk. Klik erop voor het adres, de QR-code en de koppelcode.

Op de tablet: open `http://<ip-van-je-mac>:7420` (staat in het menu, of scan de QR-code)
en voer de 6-cijferige code in. Daarna onthoudt de tablet de koppeling.

## Rechten op de Mac

| Recht | Waarvoor | Waar |
|---|---|---|
| Lokaal netwerk | tablet bereiken, `cyberpad.local` publiceren | Systeeminstellingen › Privacy en beveiliging › Lokaal netwerk |
| Toegankelijkheid | media-toetsen, vergrendelen, screenshots | Privacy en beveiliging › Toegankelijkheid (knop in het menu) |
| Automatisering › System Events | dark mode wisselen | wordt gevraagd bij eerste gebruik |

Let op: de app is ad-hoc ondertekend. Na elke nieuwe build kan macOS de Toegankelijkheid-toestemming
vergeten; zet hem dan uit en weer aan.

## Layout aanpassen

Menu › **Layout bewerken** opent `~/Library/Application Support/Cyberpad/layout.json`.
Wijzigingen verschijnen binnen 2 seconden op alle tablets.

Beschikbare acties (`action.type`):

| Type | Doet |
|---|---|
| `media.playPause`, `media.next`, `media.previous` | mediatoetsen |
| `audio.volumeUp`, `audio.volumeDown`, `audio.mute`, `audio.micMute` | geluid |
| `audio.volume` | voor een tegel met `"kind": "slider"` |
| `app.open` + `"app"` | app openen (bundle-id zoals `com.apple.Safari` of naam zoals `Notes`) |
| `url.open` + `"url"` | http(s)-link openen |
| `system.darkMode`, `system.keepAwake` | aan/uit-knoppen |
| `system.lock`, `system.displayOff`, `system.screenshot`, `system.screenshotArea` | systeem |

Tegelsoorten (`kind`): `button` (standaard), `slider`, `clock`. Plaats met `x`, `y` en optioneel `w`, `h`.

## Beveiliging

- Elke tablet krijgt een eigen token; op de Mac wordt alleen de SHA-256-hash bewaard (`devices.json`, alleen leesbaar voor jou).
- Intrekken in het menu verbreekt de verbinding direct.
- Koppelcode verloopt na 2 minuten en werkt één keer. Na 5 foute pogingen wordt een adres 1 minuut geblokkeerd.
- Alleen verbindingen uit het lokale netwerk worden aangenomen.
- De tablet stuurt alleen een tegel-id. Wat er gebeurt staat in de layout op de Mac.

## Opbouw

```
Sources/Cyberpad/
  CyberpadApp.swift   menubalk-venster
  Core.swift          koppelt alles aan elkaar
  Server.swift        HTTP + WebSocket op poort 7420 (+ XHR-terugval)
  WebSocket.swift     frames (RFC 6455)
  Pairing.swift       koppelcodes, tokens, rate-limit
  Layout.swift        layout-model en bestand
  Actions.swift       alle acties
  Audio.swift         CoreAudio
  HostAlias.swift     cyberpad.local via mDNS
  NetUtil.swift       IP-adressen, lokaal-netwerkcontrole
pad/                  tablet-pagina (ES5, werkt vanaf iOS 9)
```

Ontwikkelen zonder opnieuw te bouwen: `CYBERPAD_PAD_DIR=$PWD/pad build/Cyberpad.app/Contents/MacOS/Cyberpad`
laadt de tablet-pagina direct uit `pad/`. `CYBERPAD_DEBUG=1` schrijft de koppelcode naar de console.
