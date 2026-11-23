# Cyberpad (prototype)

Maak van een oude iPad of tablet een macropad voor je Mac. De tablet heeft alleen een browser nodig.
Dit is het prototype met fase 0–8 van [STAPPENPLAN.md](STAPPENPLAN.md).

Er komen twee versies: deze voor **macOS** (`macos/`) en later een voor **Windows 11** (`windows/`).
Tablet-pagina, protocol, layout-formaat en plugins zijn gedeeld (`shared/`, `docs/`).

## Bouwen en starten

```bash
macos/scripts/build.sh
```

```bash
open macos/build/Cyberpad.app
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
| Sleutelhanger | Home Assistant-token, MQTT-wachtwoord, webhook-geheimen | na elke nieuwe build vraagt macOS één keer om toegang; kies *Altijd toestaan* |

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
| `ha.toggle` + `"entity"` | Home Assistant-apparaat aan/uit, scène of script starten (zie *Smart home*) |
| `ha.service` + `"service"` (+ `"entity"`, `"data"`) | willekeurige Home Assistant-dienst, bijv. `"light.turn_on"` |
| `ha.level` + `"entity"` | voor een `slider`: helderheid, rolluik, volume, ventilator of getal |
| `webhook.call` + `"webhook"` of `"url"` | HTTP-verzoek (`method`, `headers`, `body`) |
| `mqtt.publish` + `"topic"` (+ `"payload"`, `"retain"`) | MQTT-bericht versturen |
| `plugin` + `"plugin"`, `"action"` (+ `"params"`) | actie van een plugin |

Toetsnamen: `cmd`, `shift`, `alt`/`option`, `ctrl`, `fn` + een letter, cijfer, leesteken of
`return`, `tab`, `space`, `delete`, `esc`, `up`/`down`/`left`/`right`, `home`, `end`, `pageup`, `pagedown`, `f1`–`f20`.
De toetsen volgen de Amerikaanse indeling (ook US-International).

Tegelsoorten (`kind`): `button` (standaard), `slider`, `clock`, `agenda` en de widgets hieronder. Plaats met `x`, `y` en optioneel `w`, `h`.

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

### Widgets

Widgets krijgen hun instellingen in `"config"`. Voorbeelden staan op de pagina **Widgets** van de standaard-layout.

| `kind` | Toont | `config` | Bediening op de tablet |
|---|---|---|---|
| `weather` | temperatuur, weer, min/max, regenkans (Open-Meteo) | `city` of `lat` + `lon` | tik = verversen |
| `nowplaying` | titel, artiest, voortgang uit Muziek of Spotify | `player`: `music` / `spotify` | tik = play/pauze, tik op balk = spoelen; vanaf 3 breed ook ⏮ ⏯ ⏭ |
| `timer` | aftellen, loopt op de Mac door | `seconds` | tik = start/pauze, lang = reset, 2× = +1 min |
| `pomodoro` | werk/pauze-rondes met geluid | `work`, `rest` (minuten) | als timer |
| `worldclock` | tijd in andere zones | `zones`: bijv. `["America/New_York"]` (max. 4) | — |
| `photos` | diavoorstelling | `folder` (standaard `~/Pictures/Cyberpad`), `seconds` | tik = volgende |
| `stats` | CPU, geheugen, netwerk, batterij, Magic-accessoires | `show`: bijv. `["cpu","ram"]` | — |
| `terminal` | live uitvoer van een commando | `command`, `cwd`, `timeout` (max. 600 s), `dangerous` | tik = start/stop |
| `slider` + `audio.micVolume` | microfoonvolume | — | schuiven |

- **Terminal:** het commando staat alleen in de layout op de Mac en draait in je eigen login-shell (`zsh -l`).
  Met `"dangerous": true` moet je op de tablet twee keer tikken en weigert de Mac het zonder die bevestiging.
  Na `timeout` seconden stopt Cyberpad het commando.
- **Nu speelt** vraagt eenmalig om *Automatisering › Spotify/Muziek*; Cyberpad start die apps nooit zelf.
- **Weer:** alleen de plaatsnaam of coördinaten gaan naar Open-Meteo.
- **Niveaumeter** zit er bewust niet in: daarvoor moet Cyberpad continu de microfoon openen (oranje stip in de
  menubalk) en dan zou de vergaderherkenning Cyberpad zelf als vergadering zien.

### Smart home en koppelingen

Menu › **Koppelingen…** opent een venster voor Home Assistant en MQTT. Adressen komen in
`integrations.json` in de Cyberpad-map. Tokens en wachtwoorden komen alleen in de **sleutelhanger** van macOS.

**Home Assistant.** Je vult het adres in (bijv. `http://homeassistant.local:8123`) en een *long-lived access token*.
Dat token maak je in Home Assistant via Profiel › Beveiliging. Cyberpad houdt een WebSocket-verbinding open, zodat
de knoppen op de tablet direct de echte stand tonen. Ook als je met de afstandsbediening of een andere app iets
omzet, ziet de tablet het meteen.
Er gaan alleen entiteiten die in je layout staan naar de tablet, en daarvan alleen naam, stand en een paar waarden.

| Tegel | Voorbeeld |
|---|---|
| knop aan/uit | `{"type": "ha.toggle", "entity": "light.woonkamer"}`: licht op als het apparaat aan staat |
| scène / script | `{"type": "ha.toggle", "entity": "scene.film"}` |
| dienst | `{"type": "ha.service", "service": "light.turn_on", "entity": "light.bureau", "data": {"brightness_pct": 30, "color_name": "red"}}` |
| schuif | `"kind": "slider"` met `{"type": "ha.level", "entity": "light.woonkamer"}` (ook `cover.*`, `media_player.*`, `fan.*`, `input_number.*`) |
| widget | `"kind": "ha"` met `"config": {"entity": "sensor.buiten_temperatuur"}`; thermostaten (`climate.*`) krijgen − en + |

Een slot (`lock.*`) gaat met `ha.toggle` alleen **op** slot. Ontgrendelen kan alleen met een aparte knop
`ha.service` `lock.unlock`. Een alarm bedien je ook alleen met `ha.service`.

**HomeKit** heeft geen eigen koppeling. Op de Mac vereist HomeKit een betaald ontwikkelaarsaccount en een
Catalyst-app. Gebruik daarom de HomeKit-integratie van Home Assistant; alles wat daar staat, kan Cyberpad bedienen.

**MQTT.** Je vult de server, poort (standaard 1883, of 8883 met TLS), gebruiker en wachtwoord in.

- `"kind": "mqtt"` met `"config": {"topic": "huis/zolder/temperatuur", "unit": "°C"}` toont de laatste waarde.
  Bij JSON-berichten pak je één veld met `"field": "temperature"` (of `"sensor.temp"`).
- Een aan/uit-knop met `mqtt.publish` en `"config": {"topic": "…/state"}` volgt de echte stand van dat topic.
  Waarden als `ON`, `true`, `1` en `open` gelden als *aan*.
- Wildcards (`+`, `#`) worden niet gebruikt; Cyberpad abonneert zich alleen op de topics uit je layout.

**Webhooks.** Een losse knop kan een `url` hebben. Webhooks met een naam staan in `integrations.json`:

```json
{
  "webhooks": {
    "n8n": { "url": "https://n8n.example.com/webhook/abc", "method": "POST",
             "body": "{\"bron\": \"cyberpad\"}", "secretHeader": "Authorization" }
  }
}
```

Met `secretHeader` komt de waarde van die header uit de sleutelhanger. Die vul je in via **Koppelingen…**.
Een body in JSON krijgt vanzelf `Content-Type: application/json`. Geeft de webhook een fout (status 400 of hoger,
of time-out na 10 s), dan verschijnt er een melding op de tablet en springt een aan/uit-knop terug.

Bij wegvallen van Home Assistant of de broker probeert Cyberpad steeds opnieuw (2 s tot 1 min). De tegels worden
grijs met de reden erbij. Een geweigerd token of wachtwoord wordt niet opnieuw geprobeerd tot je het aanpast.

### Plugins

Plugins voegen acties en widgets toe zonder dat Cyberpad zelf verandert; zie [docs/PLUGINS.md](docs/PLUGINS.md).
Ze staan in `~/Library/Application Support/Cyberpad/Plugins/` (knop **Plugins** in het menu opent die map).
Twee voorbeelden worden meegeleverd: *Hallo wereld* en *Bereikbaar?*; de pagina *Plugins* in de standaard-layout
gebruikt ze.

- Elke plugin staat eerst **uit**. Je zet hem aan in de menubalk › Plugins › *Aanzetten…*.
- Verandert er iets aan de bestanden van een plugin, dan staat hij weer uit tot je hem opnieuw toestaat.
- Een plugin is een apart programma: crasht hij, dan blijft Cyberpad gewoon draaien.

```json
{ "id": "hoi", "label": "Zeg hallo", "x": 0, "y": 0,
  "action": { "type": "plugin", "plugin": "hallo", "action": "groet", "params": { "naam": "Sven" } } }
```

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
macos/                    Mac-versie (Swift)
  Package.swift
  Resources/Info.plist
  scripts/build.sh        bouwt macos/build/Cyberpad.app
  Sources/Cyberpad/
    CyberpadApp.swift     menubalk-venster
    Core.swift            koppelt alles aan elkaar
    Server.swift          HTTP + WebSocket op poort 7420 (+ XHR-terugval)
    WebSocket.swift       frames (RFC 6455)
    Pairing.swift         koppelcodes, tokens, rate-limit
    Layout.swift          layout-model en bestand
    Actions.swift         alle acties, macro's, aan/uit-knoppen
    Keys.swift            toetscombinaties en tekst typen
    MeetingMonitor.swift  vergaderingen herkennen en bedienen
    Agenda.swift          volgende afspraak en vergaderlink
    Widgets/              weer, nu speelt, timers, systeemstats, foto's, terminal
    Integrations/         Home Assistant, MQTT, webhooks, sleutelhanger, venster Koppelingen
    Plugins/              plugins zoeken, toestaan, starten en berichten
    Catalog.swift         shortcut-bibliotheek
    Audio.swift           CoreAudio
    HostAlias.swift       cyberpad.local via mDNS
    NetUtil.swift         IP-adressen, lokaal-netwerkcontrole
shared/                   gedeeld door macOS en Windows
  pad/                    tablet-pagina (ES5, werkt vanaf iOS 9)
  catalog/                shortcuts.json (sneltoetsen per app)
  plugins/                meegeleverde voorbeeldplugins
docs/
  PROTOCOL.md             tablet ↔ computer: routes, berichten, status
  PLUGINS.md              plugins schrijven
windows/                  Windows 11-versie (gepland)
```

Ontwikkelen zonder opnieuw te bouwen:
`CYBERPAD_PAD_DIR=$PWD/shared/pad macos/build/Cyberpad.app/Contents/MacOS/Cyberpad` laadt de tablet-pagina direct
uit `shared/pad/` (`CYBERPAD_PLUGINS_DIR` doet hetzelfde voor de meegeleverde plugins). `CYBERPAD_DEBUG=1` schrijft de koppelcode naar de console.

Koppelingen testen zonder sleutelhanger (alleen samen met `CYBERPAD_DEBUG=1`):
`CYBERPAD_INTEGRATIONS=/pad/naar/test.json` gebruikt een ander instellingenbestand, en
`CYBERPAD_SECRET_HOMEASSISTANT_TOKEN`, `CYBERPAD_SECRET_MQTT_PASSWORD` en `CYBERPAD_SECRET_WEBHOOK_<NAAM>`
geven de geheimen mee.
