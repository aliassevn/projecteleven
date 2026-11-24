# Cyberpad-protocol (tablet ↔ computer)

Dit document beschrijft wat de tablet-pagina (`shared/pad/`) van de computer verwacht. De macOS-versie
(`macos/`) en de toekomstige Windows-versie (`windows/`) volgen allebei dit protocol, zodat één tablet-pagina,
één layout-formaat en één set plugins voor beide werkt.

Versie: 1 (fase 0–12).

## Verbinding

- HTTP/1.1 en WebSocket op **poort 7420**, op alle netwerkkaarten.
- Alleen verbindingen uit het lokale netwerk (privé-adressen en link-local) worden aangenomen.
- Vindbaar als `cyberpad.local` (mDNS A-record) en als Bonjour/DNS-SD-dienst `_http._tcp`.
- De tablet-pagina wordt door dezelfde server geserveerd (`GET /` → `index.html`, `/pad.js`, `/pad.css`,
  `/manifest.json`, `/icons/…`).
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
| | `{"type":"pointer","id":"<touchpad-tegel>","op":"move\|scroll","dx":n,"dy":n}`: hooguit ~40× per seconde |
| | `{"type":"pointer","id":"…","op":"click","button":"left\|right"}`, `"op":"down"` / `"up"` (slepen) |
| | `{"type":"dial","id":"<dial-tegel>","steps":n}`: n tikken van 15°, positief = met de klok mee |
| | `{"type":"viewport","w":988,"h":644,"vw":1024,"vh":768}`: ruimte voor tegels en venstermaat (voor het voorbeeld in de editor) |
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
| `POST /api/slider`, `/api/widget`, `/api/meeting`, `/api/dial` | idem (`pointer` alleen via WebSocket) |
| `GET /api/photo?tile=<id>&i=<n>` | JPEG (max. 1280 px) voor een `photos`-tegel |

## Editor (`/editor/`)

De editor (`shared/editor/`) is een gewone webpagina op dezelfde server. `schema.json` beschrijft alle actietypes,
tegelsoorten en hun velden; macOS en Windows gebruiken dezelfde editor en hetzelfde schema.

| Toegang | Hoe |
|---|---|
| Op de computer zelf | header `X-Cyberpad-Editor: <token>`; het token staat alleen in het editorvenster (via `#mac=` in de URL) en werkt alleen vanaf 127.0.0.1 / ::1 |
| Vanaf een tablet | `POST /api/editor/request` (apparaat-token) → op de computer verschijnt *Toestaan / Weigeren*; `GET /api/editor/status` → `granted`, `pending` of `denied`; toestemming geldt 30 min, verlengd bij gebruik |

| Route (met editor-toegang) | Doet |
|---|---|
| `GET /api/editor/layout` | `{layout, revision}`: de volledige layout mét acties |
| `PUT /api/editor/layout` | `{layout, baseRevision}` → `200 {ok, revision}`, `409` (intussen gewijzigd) of `422 {errors: […]}` |
| `POST /api/editor/validate` | `{layout}` → `{errors: […]}` (zonder op te slaan) |
| `GET /api/editor/catalog` | `{platform, presets[], plugins[], apps[], shortcuts[], devices[]}`: keuzelijsten, toevoegen-lijst en de gemelde schermmaten van tablets |
| `GET /api/editor/themes` | alle thema's (volledige definities) |
| `POST /api/editor/icon` | `{data: "<base64 of data-URL>"}` → `{icon: "img:<naam>"}` (max. 700 KB, wordt 256 px PNG) |

Na opslaan stuurt de computer elke tablet een nieuw `layout`-bericht. Export/import gebruikt het formaat
`{"format": "cyberpad-layout", "version": 1, "exported": "…", "layout": {…}}` (extensie `.cyberpad`).

## Layout zoals de tablet hem krijgt

De computer stuurt een **uitgeklede** versie: alleen wat nodig is om te tekenen. Wat een knop doet (toetsen,
teksten, URL's, commando's) verlaat de computer nooit; de tablet stuurt alleen een tegel-id.

```json
{
  "version": 1, "columns": 5, "rows": 3, "theme": "cyberdeck",
  "profile": { "id": "werk", "name": "Werkdag", "fixed": false },
  "themeClasses": "fx-glitch fx-upper", "themeKey": "55f9c631698d",
  "pages": [{ "id": "main", "name": "Main", "context": false, "tiles": [
    { "id": "mute", "label": "Geluid uit", "icon": "🔇", "kind": "button", "x": 3, "y": 0,
      "w": 1, "h": 1, "hasLong": true, "hasDouble": false, "toggle": true, "stateKey": "muted" }
  ]}]
}
```

- `themeClasses` gaan op `<html>`; verandert `themeKey`, dan laadt de tablet `pad.css?v=<themeKey>` opnieuw
  (zie [THEMES.md](THEMES.md)). `pad.css` is het sjabloon met de themakleuren ingevuld.
- Een tegel kan `color` (`#rrggbb`) en een `icon` als `app:<id>` of `img:<naam>` hebben; die afbeelding komt van
  `GET /api/icon?src=…&size=…` (apparaat-token of editor-toegang; `size` 16–256, standaard 256).
- Elke tablet krijgt zijn **eigen** layout: alleen de pagina's uit zijn profiel, in die volgorde.
  Bij een profielwissel stuurt de computer een nieuw `layout`-bericht; de tablet onthoudt de pagina op `id`.
- `context: true`: pagina hoort bij een of meer apps (zie `state.context`).
- `columns` / `rows` op een pagina: eigen raster voor die pagina (bijv. 10×6 compact); anders dat van de layout.
- Een `agenda`-tegel heeft `count` (1–5): zoveel afspraken uit `state.agenda.items` tonen.
- `kind`: `button`, `slider`, `clock`, `agenda`, `weather`, `nowplaying`, `timer`, `pomodoro`, `worldclock`,
  `photos`, `stats`, `terminal`, `ha`, `mqtt`, `plugin`, `touchpad`, `dial`.
- `stateKey`: welke statuswaarde de knop laat oplichten (of de schuif vult):
  ingebouwd (`muted`, `micMuted`, `keepAwake`, `darkMode`, `volume`, `micVolume`),
  `ha:<entiteit>` of `mqtt:<topic>`.
- `toggle: true` zonder `stateKey`: de computer onthoudt aan/uit in `state.toggles[<tegel>]`.
- Fouten bij `pointer` (bijv. geen Toegankelijkheid) meldt de computer hooguit eens per 3 s.
  Valt de verbinding weg tijdens slepen, dan laat de computer de muisknop los.
- `dangerous: true` (alleen `terminal`): de tablet vraagt een tweede tik en stuurt dan `value: 1`.

## Status (`state`)

```json
{
  "muted": false, "micMuted": true, "keepAwake": false, "darkMode": true,
  "volume": 0.42, "micVolume": 0.8, "toggles": { "focus": true },
  "meeting": null | { "app": "zoom", "name": "Zoom", "muted": true, "video": false,
                      "statusSource": "menu" | "estimated", "since": 1763900000000, "actions": ["mute", …] },
  "agenda": { "status": "ok" | "none" | "noAccess" | "denied", "title": "…", "start": ms, "end": ms,
              "hasLink": true, "app": "zoom",
              "items": [{ "title": "…", "start": ms, "end": ms, "hasLink": false }] },
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
| aanraakpad | CGEvent (muis, scrollwiel) | `SendInput` met `MOUSEINPUT` / `MOUSEEVENTF_WHEEL` |
| `icon: "app:…"` | bundle-id → icoon via NSWorkspace | AppUserModelID of .exe → `SHGetFileInfo` / `IShellItemImageFactory` |

Een layout die alleen platformneutrale acties gebruikt (media, audio, `url.open`, `ha.*`, `mqtt.*`,
`webhook.call`, `plugin`, widgets) werkt op beide zonder aanpassing.
