# Cyberpad (prototype)

Maak van een oude iPad of tablet een macropad voor je Mac. De tablet heeft alleen een browser nodig.
Dit is het prototype met fase 0–5 van [STAPPENPLAN.md](STAPPENPLAN.md).

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
| Agenda | volgende afspraak tonen | wordt gevraagd als er een agendategel is, of via het menu |

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
| `keys.press` + `"keys"` | willekeurige toetscombinatie, bijv. `"cmd+shift+a"`, `"ctrl+up"`, `"f5"` |
| `text.type` + `"text"` | tekst typen (max. 2000 tekens) |
| `preset` + `"preset"` | sneltoets uit de bibliotheek, bijv. `"zoom.mute"` (zie hieronder) |
| `shortcut.run` + `"shortcut"` | opdracht uit de Opdrachten-app uitvoeren (op naam) |
| `macro` + `"steps"` | meerdere acties na elkaar; `{"type": "delay", "ms": 500}` voor een pauze |

Toetsnamen: `cmd`, `shift`, `alt`/`option`, `ctrl`, `fn` + een letter, cijfer, leesteken of
`return`, `tab`, `space`, `delete`, `esc`, `up`/`down`/`left`/`right`, `home`, `end`, `pageup`, `pagedown`, `f1`–`f20`.
De toetsen volgen de Amerikaanse indeling (ook US-International).

Tegelsoorten (`kind`): `button` (standaard), `slider`, `clock`, `agenda`. Plaats met `x`, `y` en optioneel `w`, `h`.

### Gebaren en aan/uit-knoppen

```json
{
  "id": "copy", "label": "Kopieer", "icon": "📋", "x": 0, "y": 1,
  "action":    { "type": "keys.press", "keys": "cmd+c" },
  "longPress": { "type": "keys.press", "keys": "cmd+x" },
  "doubleTap": { "type": "keys.press", "keys": "cmd+a" }
}
```

- `longPress`: ± 0,5 s ingedrukt houden. `doubleTap`: twee keer snel tikken.
  Alleen knoppen mét een dubbeltik wachten heel even (0,28 s) met de gewone tik.
- `"toggle": true` maakt er een aan/uit-knop van: Cyberpad onthoudt de stand en de knop licht op.
  Met `offAction` kies je een andere actie voor "uit". Mislukt de actie, dan springt de knop terug.

### Shortcut-bibliotheek

`catalog/shortcuts.json` bevat standaard-sneltoetsen voor Zoom, Teams, Google Meet, Webex, Slack, Discord, Loom en
VS Code. Gebruik ze met `{"type": "preset", "preset": "<app>.<id>"}`, bijv. `zoom.mute`, `zoom.video`, `teams.hand`,
`meet.mute`, `slack.huddleMute`, `discord.deafen`, `vscode.palette`. Waar nodig zet Cyberpad de app eerst vooraan.
Heb je sneltoetsen in een app aangepast, gebruik dan `keys.press`.

### Opdrachten (Shortcuts) en Focus

macOS heeft geen openbare manier om Focus direct aan te zetten. Maak in de Opdrachten-app twee opdrachten,
bijv. **Focus aan** (actie "Stel focus in" → aan) en **Focus uit**, en gebruik ze met `shortcut.run`.
De standaard-layout heeft hier al een aan/uit-knop voor op de pagina **Werk**.

### Vergaderingen

Zodra je in een vergadering zit, verschijnt op de tablet vanzelf een **vergaderpaneel** met microfoon, camera,
hand opsteken, scherm delen en ophangen (ophangen = twee keer tikken). Met *Verbergen* ga je terug naar je
knoppen; het roze label in de statusbalk haalt het paneel terug.

- **Herkenning:** een vergader-app (Zoom, Teams, Webex) draait én gebruikt de microfoon. Google Meet wordt herkend
  aan de venstertitel in de browser (vereist Toegankelijkheid).
- **Mute-status:** bij Zoom leest Cyberpad die uit het menu van Zoom (vereist Toegankelijkheid). Bij de andere apps
  houdt Cyberpad zelf bij wat jij via de tablet doet; dat staat dan als "geschat" op het paneel.
- Welke toetsen er gestuurd worden staat in `catalog/shortcuts.json`.

### Agenda

Een tegel met `"kind": "agenda"` toont je volgende afspraak met aftelling. Staat er een Zoom-, Teams-, Meet-, Webex-,
FaceTime- of Whereby-link in de afspraak, dan opent **Deelnemen** die link. Cyberpad vraagt bij de eerste start om
toegang tot Agenda als er een agendategel in je layout staat; anders via *Toestaan…* in het menu.
Titels en tijden van afspraken gaan alleen naar gekoppelde tablets.

Testen zonder echte vergadering of agenda: start met `CYBERPAD_FAKE_MEETING=teams` (of `zoom`, `meet`, `webex`)
en/of `CYBERPAD_FAKE_AGENDA=1`. In de vergader-testmodus worden geen toetsen verstuurd.

Menu › **Standaard-layout terugzetten…** zet de voorbeeldlayout terug; je huidige layout wordt eerst als back-up bewaard.

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
  Actions.swift       alle acties, macro's, aan/uit-knoppen
  Keys.swift          toetscombinaties en tekst typen
  MeetingMonitor.swift vergaderingen herkennen en bedienen
  Agenda.swift        volgende afspraak en vergaderlink
  Catalog.swift       shortcut-bibliotheek
  Audio.swift         CoreAudio
  HostAlias.swift     cyberpad.local via mDNS
  NetUtil.swift       IP-adressen, lokaal-netwerkcontrole
pad/                  tablet-pagina (ES5, werkt vanaf iOS 9)
catalog/              shortcuts.json (sneltoetsen per app)
```

Ontwikkelen zonder opnieuw te bouwen: `CYBERPAD_PAD_DIR=$PWD/pad build/Cyberpad.app/Contents/MacOS/Cyberpad`
laadt de tablet-pagina direct uit `pad/`. `CYBERPAD_DEBUG=1` schrijft de koppelcode naar de console.
