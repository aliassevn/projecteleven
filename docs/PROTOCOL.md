# Cyberpad-protocol (tablet ↔ computer)

Dit document beschrijft wat de tablet-pagina (`shared/pad/`) van de computer verwacht. De macOS-versie
(`macos/`) en de toekomstige Windows-versie (`windows/`) volgen allebei dit protocol, zodat één tablet-pagina,
één layout-formaat en één set plugins voor beide werkt.

Versie: 1 (fase 0–9).

## Verbinding

- HTTP/1.1 en WebSocket op **poort 7420**, op alle netwerkkaarten.
- Alleen verbindingen uit het lokale netwerk (privé-adressen en link-local) worden aangenomen.
- Vindbaar als `cyberpad.local` (mDNS A-record) en als Bonjour/DNS-SD-dienst `_http._tcp`.
- De tablet-pagina wordt door dezelfde server geserveerd (`GET /` → `index.html`, `/pad.js`, `/pad.css`).
  Paden met `..` of die met een punt beginnen worden geweigerd.

## Koppelen

1. De computer toont een **koppelcode** van 6 cijfers. Die verloopt na 120 s en werkt één keer.
2. `POST /api/pair` met `{"code": "123456", "name": "iPad"}`.
   - `200 {"token": "<64 hex>", "deviceId": "…"}`
   - `401 {"error": "wrong", "attemptsLeft": n}`
   - `429 {"error": "blocked", "seconds": n}`: na 5 fouten per IP-adres 60 s geblokkeerd; na 20 fouten een nieuwe code.
3. De computer bewaart alleen de **SHA-256-hash** van het token. Vergelijken gebeurt in constante tijd.
4. Intrekken verbreekt direct alle verbindingen van dat apparaat.

## Authenticatie

- HTTP: header `X-Cyberpad-Token: <token>` → anders `401 {"error": "unauthorized"}`.
- WebSocket: binnen 10 s na het openen `{"type": "hello", "token": "…"}`; anders `{"type": "unauthorized"}` en sluiten.

## WebSocket `/ws`

Frames volgens RFC 6455; berichten van de tablet moeten gemaskeerd zijn en zijn maximaal 64 KB.

| Richting | Bericht |
|---|---|
| tablet → computer | `{"type":"hello","token":"…"}` |
| | `{"type":"ping"}` (elke 25 s) → `{"type":"pong"}` |
| | `{"type":"press","id":"<tegel>","gesture":"long"\|"double"}`: zonder `gesture` = tik |
| | `{"type":"slider","id":"<tegel>","value":0.0…1.0}` |
| | `{"type":"widget","id":"<tegel>","action":"…","value":n?}` |
| | `{"type":"meeting","action":"mute\|video\|hand\|share\|leave"}` |
| computer → tablet | `{"type":"welcome","device":"iPad"}` |
| | `{"type":"layout","layout":{…}}` (zie hieronder) |
| | `{"type":"state","state":{…}}`: bij elke wijziging, hooguit ~7× per seconde |
| | `{"type":"ack","id":"…","ok":bool,"error":"…"?}` |
| | `{"type":"toast","text":"…"}`: melding op de tablet |
| | `{"type":"unauthorized"}` |

## HTTP-terugval (voor oudere tablets zonder werkende WebSocket)

Alle met token, allemaal JSON:

| Route | Antwoord |
|---|---|
| `GET /api/ping` | `{"ok":true,"app":"Cyberpad"}` (zonder token) |
| `GET /api/layout` | `{"layout":{…},"state":{…}}` |
| `GET /api/state` | `{"state":{…}}` (de tablet vraagt dit elke 2 s op) |
| `POST /api/press` | body als het WS-bericht → `{"ok":bool,"error"?}` |
| `POST /api/slider`, `/api/widget`, `/api/meeting` | idem |
| `GET /api/photo?tile=<id>&i=<n>` | JPEG (max. 1280 px) voor een `photos`-tegel |

## Layout zoals de tablet hem krijgt

De computer stuurt een **uitgeklede** versie: alleen wat nodig is om te tekenen. Wat een knop doet (toetsen,
teksten, URL's, commando's) verlaat de computer nooit; de tablet stuurt alleen een tegel-id.

```json
{
  "version": 1, "columns": 5, "rows": 3, "theme": "cyberdeck",
  "profile": { "id": "werk", "name": "Werkdag", "fixed": false },
  "pages": [{ "id": "main", "name": "Main", "context": false, "tiles": [
    { "id": "mute", "label": "Geluid uit", "icon": "🔇", "kind": "button", "x": 3, "y": 0,
      "w": 1, "h": 1, "hasLong": true, "hasDouble": false, "toggle": true, "stateKey": "muted" }
  ]}]
}
```

- Elke tablet krijgt zijn **eigen** layout: alleen de pagina's uit zijn profiel, in die volgorde.
  Bij een profielwissel stuurt de computer een nieuw `layout`-bericht; de tablet onthoudt de pagina op `id`.
- `context: true`: pagina hoort bij een of meer apps (zie `state.context`).
- `kind`: `button`, `slider`, `clock`, `agenda`, `weather`, `nowplaying`, `timer`, `pomodoro`, `worldclock`,
  `photos`, `stats`, `terminal`, `ha`, `mqtt`, `plugin`.
- `stateKey`: welke statuswaarde de knop laat oplichten (of de schuif vult):
  ingebouwd (`muted`, `micMuted`, `keepAwake`, `darkMode`, `volume`, `micVolume`),
  `ha:<entiteit>` of `mqtt:<topic>`.
- `toggle: true` zonder `stateKey`: de computer onthoudt aan/uit in `state.toggles[<tegel>]`.
- `dangerous: true` (alleen `terminal`): de tablet vraagt een tweede tik en stuurt dan `value: 1`.

## Status (`state`)

```json
{
  "muted": false, "micMuted": true, "keepAwake": false, "darkMode": true,
  "volume": 0.42, "micVolume": 0.8, "toggles": { "focus": true },
  "meeting": null | { "app": "zoom", "name": "Zoom", "muted": true, "video": false,
                      "statusSource": "menu" | "estimated", "since": 1763900000000, "actions": ["mute", …] },
  "agenda": { "status": "ok" | "none" | "noAccess" | "denied", "title": "…", "start": ms, "end": ms,
              "hasLink": true, "app": "zoom" },
  "widgets": { "<tegel>": { … } },
  "ha": { "<entiteit>": { "status": "ok", "state": "on", "on": true, "name": "…", "level": 0.6, … } },
  "mqtt": { "<topic>": "<laatste bericht>" },
  "integrations": { "ha": "off|connecting|connected|error", "mqtt": "…" },
  "context": { "page": "work" | null }
}
```

`context.page` is de pagina die bij de app vooraan hoort. De tablet springt erheen als die pagina in zijn layout
staat, en terug naar de laatst zelf gekozen pagina als `page` weer `null` wordt. Welke app er vooraan staat,
gaat niet naar de tablet.

Tijden zijn milliseconden sinds 1970 (UTC). De tablet rekent tijden zelf uit, omdat oude Safari geen tijdzones kent.

### Widgetgegevens per soort

| `kind` | Velden |
|---|---|
| `weather` | `status`, `temp`, `icon`, `desc`, `code`, `min`, `max`, `rain`, `place`, `updated`, `error` |
| `nowplaying` | `status`, `app`, `state`, `title`, `artist`, `album`, `position`, `duration`, `at` |
| `timer` / `pomodoro` | `mode`, `running`, `remaining`, `duration`, `endsAt`, `phase`, `round` |
| `worldclock` | `zones: [{label, offset, abbr}]` |
| `photos` | `count`, `interval`, `error` |
| `stats` | `cpu`, `ram` (`used`, `total`), `net` (`up`, `down`), `battery` (`percent`, `charging`, `plugged`), `accessories[]` (`name`, `percent`) |
| `terminal` | `status`, `output`, `exit`, `started`, `ended`, `dangerous` |
| `ha` | als `state.ha[…]` |
| `mqtt` | `status`, `value`, `unit`, `topic` |
| `plugin` | `status`, `title`, `value`, `unit`, `sub`, `icon`, `progress`, `active`, `lines[]`, `buttons[]`, `error` |

## Layout-bestand op de computer (`layout.json`)

Zelfde opbouw als hierboven, maar mét acties. Zie de README voor alle actietypes. Platformverschillen:

| Actie | macOS | Windows (gepland) |
|---|---|---|
| `keys.press` | `cmd` = ⌘ | `cmd` wordt Ctrl; `win` = Windows-toets |
| `app.open` | bundle-id of app-naam | AppUserModelID, pad naar .exe of naam uit het Startmenu |
| `shortcut.run` | Opdrachten-app | PowerShell-script of Power Automate-flow |
| `system.darkMode` | systeemvormgeving | app- en systeemthema (register) |
| `preset` | `shared/catalog/shortcuts.json` → `keys` | idem → `keysWindows` (nog in te vullen) |
| `page.apps` | bundle-id of app-naam | naam van het .exe-bestand (bijv. `Photoshop.exe`) of AppUserModelID |
| profiel wisselen | `cyberpad://profile/<id>` (Opdrachten/Focus) | `cyberpad://profile/<id>` (protocol-handler) |

Een layout die alleen platformneutrale acties gebruikt (media, audio, `url.open`, `ha.*`, `mqtt.*`,
`webhook.call`, `plugin`, widgets) werkt op beide zonder aanpassing.
