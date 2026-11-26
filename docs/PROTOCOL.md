# Cyberpad protocol (tablet ↔ computer)

This document describes what the tablet page (`shared/pad/`) expects from the computer. The macOS version (`macos/`)
and the Windows version (`windows/`) both follow this protocol, so one tablet page, one layout format and one set of
plugins works for both.

Version: 1 (phases 0–12).

## Connection

- HTTP/1.1 and WebSocket on **port 7420**, on all network interfaces.
- Only connections from the local network (private addresses and link-local) are accepted.
- Discoverable as `cyberpad.local` (mDNS A record) and as a Bonjour/DNS-SD service `_http._tcp` (Mac).
- The tablet page is served by the same server (`GET /` → `index.html`, `/pad.js`, `/pad.css`, `/manifest.json`,
  `/icons/…`). Paths containing `..` or starting with a dot are refused.
- `GET /i18n.js` (no token): sets `window.CP_LANG` (`en`, `nl` or `es`) and `window.CP_I18N` (dictionary Dutch →
  chosen language) for the tablet and the editor. See [LANGUAGES.md](LANGUAGES.md).
- `POST /api/lang` with `{"lang": "es"}` (device token or editor token): switches the language for everything. All
  tablets then receive a new `layout` with `"lang"`; if it differs from `CP_LANG`, the tablet reloads.

## Pairing

1. The computer shows a 6-digit **pairing code**. It expires after 120 s and works once.
2. `POST /api/pair` with `{"code": "123456", "name": "iPad"}`.
   - `200 {"token": "<64 hex>", "deviceId": "…"}`
   - `401 {"error": "wrong", "attemptsLeft": n}`
   - `429 {"error": "blocked", "seconds": n}`: blocked for 60 s after 5 errors per IP address; a new code after 20 errors.
3. The computer only stores the **SHA-256 hash** of the token. Comparisons are constant-time.
4. Revoking immediately closes all connections of that device.

## Authentication

- HTTP: header `X-Cyberpad-Token: <token>` → otherwise `401 {"error": "unauthorized"}`.
- WebSocket: within 10 s of opening, `{"type": "hello", "token": "…"}`; otherwise `{"type": "unauthorized"}` and close.

## WebSocket `/ws`

Frames per RFC 6455; messages from the tablet must be masked and are at most 64 KB.

| Direction | Message |
|---|---|
| tablet → computer | `{"type":"hello","token":"…"}` |
| | `{"type":"ping"}` (every 25 s) → `{"type":"pong"}` |
| | `{"type":"press","id":"<tile>","gesture":"long"\|"double"}`: without `gesture` = tap |
| | `{"type":"slider","id":"<tile>","value":0.0…1.0}` |
| | `{"type":"widget","id":"<tile>","action":"…","value":n?}` |
| | `{"type":"meeting","action":"mute\|video\|hand\|share\|leave"}` |
| | `{"type":"pointer","id":"<touchpad tile>","op":"move\|scroll","dx":n,"dy":n}`: at most ~40× per second |
| | `{"type":"pointer","id":"…","op":"click","button":"left\|right"}`, `"op":"down"` / `"up"` (dragging) |
| | `{"type":"dial","id":"<dial tile>","steps":n}`: n ticks of 15°, positive = clockwise |
| | `{"type":"viewport","w":988,"h":644,"vw":1024,"vh":768}`: space for tiles and window size (for the editor preview) |
| computer → tablet | `{"type":"welcome","device":"iPad"}` |
| | `{"type":"layout","layout":{…}}` (see below) |
| | `{"type":"state","state":{…}}`: on every change, at most ~7× per second |
| | `{"type":"ack","id":"…","ok":bool,"error":"…"?}` |
| | `{"type":"toast","text":"…"}`: message on the tablet |
| | `{"type":"unauthorized"}` |

## HTTP fallback (for older tablets without a working WebSocket)

All with token, all JSON:

| Route | Response |
|---|---|
| `GET /api/ping` | `{"ok":true,"app":"Cyberpad"}` (no token) |
| `GET /api/layout` | `{"layout":{…},"state":{…}}` |
| `GET /api/state` | `{"state":{…}}` (the tablet polls this every 2 s) |
| `POST /api/press` | body like the WS message → `{"ok":bool,"error"?}` |
| `POST /api/slider`, `/api/widget`, `/api/meeting`, `/api/dial` | same (`pointer` only over WebSocket) |
| `GET /api/photo?tile=<id>&i=<n>` | JPEG (max. 1280 px) for a `photos` tile |

## Editor (`/editor/`)

The editor (`shared/editor/`) is an ordinary web page on the same server. `schema.json` describes all action types,
tile types and their fields; macOS and Windows use the same editor and the same schema. `GET /editor/editor.css` is a
theme template filled in with the current theme (see [THEMES.md](THEMES.md)).

| Access | How |
|---|---|
| On the computer itself | header `X-Cyberpad-Editor: <token>`; the token only lives in the editor window (via `#mac=` in the URL) and only works from 127.0.0.1 / ::1 |
| From a tablet | just the device token (`X-Cyberpad-Token`): every paired tablet may edit. `POST /api/editor/request` and `GET /api/editor/status` still exist for older editor pages and always answer `granted` |

| Route (with editor access) | Does |
|---|---|
| `GET /api/editor/layout` | `{layout, revision}`: the full layout including actions |
| `PUT /api/editor/layout` | `{layout, baseRevision}` → `200 {ok, revision}`, `409` (changed in the meantime) or `422 {errors: […]}` |
| `POST /api/editor/validate` | `{layout}` → `{errors: […]}` (without saving) |
| `GET /api/editor/catalog` | `{platform, presets[], plugins[], apps[], shortcuts[], timeZones[], browsers[], devices[]}`: choice lists, the add list and the screen sizes reported by tablets |
| `GET /api/editor/themes` | all themes (full definitions) |
| `POST /api/editor/icon` | `{data: "<base64 or data URL>"}` → `{icon: "img:<name>"}` (max. 700 KB, becomes a 256 px PNG) |

After saving, the computer sends every tablet a new `layout` message. Export/import uses the format
`{"format": "cyberpad-layout", "version": 1, "exported": "…", "layout": {…}}` (extension `.cyberpad`).

## The layout as the tablet receives it

The computer sends a **stripped** version: only what is needed to draw. What a button does (keys, texts, URLs,
commands) never leaves the computer; the tablet only sends a tile id.

```json
{
  "version": 1, "columns": 5, "rows": 3, "theme": "cyberdeck", "lang": "en",
  "profile": { "id": "work", "name": "Workday", "fixed": false },
  "themeClasses": "fx-glitch fx-upper", "themeKey": "55f9c631698d",
  "pages": [{ "id": "main", "name": "Main", "context": false, "tiles": [
    { "id": "mute", "label": "Mute", "icon": "🔇", "kind": "button", "x": 3, "y": 0,
      "w": 1, "h": 1, "hasLong": true, "hasDouble": false, "toggle": true, "stateKey": "muted" }
  ]}]
}
```

- `themeClasses` go on `<html>`; when `themeKey` changes, the tablet reloads `pad.css?v=<themeKey>` (see
  [THEMES.md](THEMES.md)). `pad.css` is the template with the theme colours filled in.
- A tile can have a `color` (`#rrggbb`) and an `icon` as `app:<id>` or `img:<name>`; that image comes from
  `GET /api/icon?src=…&size=…` (device token or editor access; `size` 16–256, default 256).
- Every tablet gets its **own** layout: only the pages of its profile, in that order.
  When the profile changes, the computer sends a new `layout` message; the tablet remembers its page by `id`.
- `context: true`: the page belongs to one or more apps (see `state.context`).
- `columns` / `rows` on a page: a grid of its own for that page (e.g. 10×6 compact); otherwise the layout's grid.
- An `agenda` tile has `count` (1–5): how many events from `state.agenda.items` to show.
- `kind`: `button`, `slider`, `clock`, `agenda`, `weather`, `nowplaying`, `timer`, `pomodoro`, `worldclock`, `photos`,
  `stats`, `terminal`, `ha`, `mqtt`, `plugin`, `touchpad`, `dial`.
- `stateKey`: which state value lights up the button (or fills the slider):
  built-in (`muted`, `micMuted`, `keepAwake`, `darkMode`, `volume`, `micVolume`), `ha:<entity>` or `mqtt:<topic>`.
- `toggle: true` without `stateKey`: the computer remembers on/off in `state.toggles[<tile>]`.
- Errors from `pointer` (e.g. no Accessibility permission) are reported at most once every 3 s.
  If the connection drops while dragging, the computer releases the mouse button.
- `dangerous: true` (only `terminal`): the tablet asks for a second tap and then sends `value: 1`.

## State (`state`)

```json
{
  "muted": false, "micMuted": true, "keepAwake": false, "darkMode": true,
  "volume": 0.42, "micVolume": 0.8, "toggles": { "focus": true },
  "meeting": null | { "app": "zoom", "name": "Zoom", "muted": true, "video": false,
                      "statusSource": "menu" | "estimated", "since": 1763900000000, "actions": ["mute", …] },
  "agenda": { "status": "ok" | "none" | "noAccess" | "denied", "title": "…", "start": ms, "end": ms,
              "hasLink": true, "app": "zoom",
              "items": [{ "title": "…", "start": ms, "end": ms, "hasLink": false }] },
  "widgets": { "<tile>": { … } },
  "ha": { "<entity>": { "status": "ok", "state": "on", "on": true, "name": "…", "level": 0.6, … } },
  "mqtt": { "<topic>": "<latest message>" },
  "integrations": { "ha": "off|connecting|connected|error", "mqtt": "…" },
  "context": { "page": "work" | null }
}
```

`context.page` is the page that belongs to the frontmost app. The tablet jumps there if that page is in its layout,
and back to the page it last chose itself when `page` becomes `null` again. Which app is in front is not sent to the
tablet.

Times are milliseconds since 1970 (UTC). The tablet calculates times itself, because old Safari knows no time zones.

### Widget data per kind

| `kind` | Fields |
|---|---|
| `weather` | `status`, `temp`, `icon`, `desc`, `code`, `min`, `max`, `rain`, `place`, `updated`, `error` |
| `nowplaying` | `status`, `app`, `state`, `title`, `artist`, `album`, `position`, `duration`, `at` |
| `timer` / `pomodoro` | `mode`, `running`, `remaining`, `duration`, `endsAt`, `phase`, `round` |
| `worldclock` | `zones: [{label, offset, abbr}]` |
| `photos` | `count`, `interval`, `error` |
| `stats` | `cpu`, `ram` (`used`, `total`), `net` (`up`, `down`), `battery` (`percent`, `charging`, `plugged`), `accessories[]` (`name`, `percent`) |
| `terminal` | `status`, `output`, `exit`, `started`, `ended`, `dangerous` |
| `ha` | as `state.ha[…]` |
| `mqtt` | `status`, `value`, `unit`, `topic` |
| `plugin` | `status`, `title`, `value`, `unit`, `sub`, `icon`, `progress`, `active`, `lines[]`, `buttons[]`, `error` |

## Layout file on the computer (`layout.json`)

The same structure as above, but with actions. See the README for all action types. Platform differences:

| Action | macOS | Windows |
|---|---|---|
| `keys.press` | `cmd` = ⌘ | `cmd` becomes Ctrl; `win` = Windows key |
| `app.open` | bundle id or app name | name from the Start menu, path to an .exe/.lnk, or a name Windows knows (`notepad`) |
| `url.open` + `app` | bundle id of a browser | browser from `StartMenuInternet` (name or id) |
| `shortcut.run` | Shortcuts app | not available |
| `system.darkMode` | system appearance | app and system theme (registry) |
| `preset` | `shared/catalog/shortcuts.json` → `keys` | same → `keysWindows`, otherwise `keys` with `cmd` → Ctrl |
| `page.apps` | bundle id or app name | planned: .exe name (e.g. `Photoshop.exe`) |
| switching profile | `cyberpad://profile/<id>` (Shortcuts/Focus) | planned |
| touchpad | CGEvent (mouse, scroll wheel) | `SendInput` with `MOUSEINPUT` / `MOUSEEVENTF_WHEEL` |
| `icon: "app:…"` | bundle id → icon via NSWorkspace | Start menu name → icon via the Windows Shell |

A layout that only uses platform-neutral actions (media, audio, `url.open`, `ha.*`, `mqtt.*`, `webhook.call`, `plugin`,
widgets) works on both without changes. Windows 0.1 does not yet support `ha.*`, `mqtt.*`, `webhook.call`, `plugin`,
the meeting panel and the calendar; see [windows/README.md](../windows/README.md).
