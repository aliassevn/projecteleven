# Cyberpad (prototype)

Turn an old iPad or tablet into a macro pad for your Mac or Windows PC. The tablet only needs a web browser.
This is the prototype covering phases 0–12 of the [ROADMAP.md](ROADMAP.md).

There are two versions: one for **macOS** (`macos/`) and one for **Windows 10/11** (`windows/`, first test version;
installer under [Releases](https://github.com/aliassevn/projecteleven/releases), see [windows/README.md](windows/README.md)).
The tablet page, protocol, layout format and plugins are shared (`shared/`, `docs/`).

## Installing

Ready-made installers are available under [Releases](https://github.com/aliassevn/projecteleven/releases):
**Cyberpad-<version>.dmg** for the Mac ([instructions](macos/RELEASE_NOTES.md)) and **CyberpadSetup-<version>.exe** for
Windows ([instructions](windows/RELEASE_NOTES.md)). GitHub Actions builds them; a tag `macos-v<version>` or
`windows-v<version>` turns a build into a Release.

## Building and running

```bash
macos/scripts/build.sh
```

To make an installer (`macos/build/Cyberpad-<version>.dmg`), run `macos/scripts/make-dmg.sh [version] [universal]`.

```bash
open macos/build/Cyberpad.app
```

A grid icon appears in the menu bar. Click it for the address, the QR code and the pairing code.

On the tablet: open `http://<your-mac-ip>:7420` (shown in the menu, or scan the QR code) and enter the 6-digit code.
The tablet remembers the pairing from then on.

## Permissions on the Mac

| Permission | What for | Where |
|---|---|---|
| Local Network | reach the tablet, publish `cyberpad.local` | System Settings › Privacy & Security › Local Network |
| Accessibility | media keys, key combinations, locking, screenshots | Privacy & Security › Accessibility (button in the menu) |
| Automation › System Events | toggling dark mode | asked on first use |
| Calendar | showing your next event | asked when the layout has a calendar tile, or via the menu |
| Keychain | Home Assistant token, MQTT password, webhook secrets | after each new build macOS asks once; choose *Always Allow* |

Note: the app is ad-hoc signed. After a new build macOS may forget the Accessibility permission; turn it off and on again.

## Language

Cyberpad is available in **English** (default), **Dutch** and **Spanish**. Switch in the menu bar window
(**Language**), on the tablet (⚙ › **Language**) or in the editor (**MORE ▾**). The language applies to the Mac, all
tablets and the editor at once. See [docs/LANGUAGES.md](docs/LANGUAGES.md).

## Editing the layout

Menu › **Edit layout…** opens the editor in its own window:

- **Adding:** **+ ADD** (or tap an empty cell) opens a list of everything that is possible, with a search field and
  groups: all apps on your Mac (with their icons), your shortcuts from the Shortcuts app, media and sound, widgets,
  touchpad and dials, system, keys and text, keyboard shortcuts per app, smart home and plugins. Pick something and it
  appears with a label, icon, action and a suitable size (automatically larger on a compact page). If something still
  needs filling in (such as a web address), it is ready on the right. Calendar, Reminders and Notes are at the top.
- **Tiles:** tap an empty cell (+) to add one, drag to move, drag the pink corner to resize. On the right you choose
  the label, icon, type, settings and what a tap, long press and double tap do. Macros are built step by step, with
  pauses.
- **Grid per page:** *Default* (e.g. 5×3), *Compact* (twice as many cells: tiles half the size, so more fit on a page)
  or a custom size. Existing tiles are scaled along when you switch. *Apply to all pages* gives every page the same
  grid. Small tiles automatically get smaller text and icons on the tablet.
- **Pages:** tabs at the top; *+ Page* adds one. Per page: name, order and the apps it is a context page for.
- **Profiles:** which pages per profile, time rules and the default profile.
- **Save** (⌘S): the Mac checks everything (nothing outside the grid, no overlap, no duplicate ids), keeps the previous
  version as `layout-backup-editor-….json` (the last 20) and updates all tablets immediately. If someone else saved in
  the meantime, you get a warning instead of overwriting their work.
- **↶ / ↷** (⌘Z / ⇧⌘Z) undo and redo. **MORE** has *Export* (a `.cyberpad` file), *Import* (only takes effect after
  Save) and the language. On the tablet, **✕ CLOSE** takes you back to the buttons.
- **Preview** (bar at the bottom): choose *As your tablet is now* or an iPad model, optionally *rotated* (portrait) or
  *full screen*. The editor then shows the grid at the tablet's real size, scaled to the window, including how much
  space one cell gets. That way you see on the Mac what fits on the iPad. A tablet reports its screen size as soon as
  it connects (also after rotating or going full screen).
- **Theme:** the **THEME** button. Choose from nine themes (including Cyberdeck, Night with white round buttons on
  black, Graphite, Contrast, Ocean and the light Minimal), and optionally adjust colours, font, corner radius and
  effects (with a preview). After Save, all tablets switch to the new look immediately; the editor follows the theme
  too. See [docs/THEMES.md](docs/THEMES.md).
- **Icons and colour per tile:** emoji, the icon of an app on your Mac, or your own image (PNG/JPEG/HEIC, max. 700 KB).
  A tile can also get its own colour (stripe at the top and border).

**On the tablet:** ⚙ › *Edit layout*. Every paired tablet can edit straight away, without extra permission on the
Mac. A tablet that is not paired (or that you revoked) never sees the full layout with its actions.

**Full screen on the iPad:** tap **⛶** in the status bar, or turn on ⚙ › *Always full screen*; it then switches on
the first tap (Safari only allows full screen after a tap). Works on iPadOS 12 and later. Cyberpad leaves room for
the iPadOS status bar and its ✕. Leave with ✕ (or ⛶); Cyberpad then stays out of full screen until you reopen the page.
On an iPhone or an older iPad: Safari › Share › *Add to Home Screen*.

## Editing the layout by hand

Menu › **Open layout.json** opens `~/Library/Application Support/Cyberpad/layout.json`.
Changes appear on all tablets within 2 seconds.

Available actions (`action.type`):

| Type | Does |
|---|---|
| `media.playPause`, `media.next`, `media.previous` | media keys |
| `audio.volumeUp`, `audio.volumeDown`, `audio.mute`, `audio.micMute` | sound |
| `audio.volume` | for a tile with `"kind": "slider"` |
| `app.open` + `"app"` | open an app (bundle id such as `com.apple.Safari` or a name such as `Notes`) |
| `url.open` + `"url"` | open an http(s) link in your default browser; with `"app"` (e.g. `com.google.Chrome`) in that browser |
| `system.darkMode`, `system.keepAwake` | on/off buttons |
| `system.lock`, `system.displayOff`, `system.screenshot`, `system.screenshotArea` | system |
| `keys.press` + `"keys"` | any key combination, e.g. `"cmd+shift+a"`, `"ctrl+up"`, `"f5"` |
| `text.type` + `"text"` | type text (max. 2000 characters) |
| `preset` + `"preset"` | keyboard shortcut from the library, e.g. `"zoom.mute"` (see below) |
| `shortcut.run` + `"shortcut"` | run a shortcut from the Shortcuts app (by name) |
| `macro` + `"steps"` | several actions in a row; `{"type": "delay", "ms": 500}` for a pause |
| `ha.toggle` + `"entity"` | toggle a Home Assistant device, or start a scene or script (see *Smart home*) |
| `ha.service` + `"service"` (+ `"entity"`, `"data"`) | any Home Assistant service, e.g. `"light.turn_on"` |
| `ha.level` + `"entity"` | for a `slider`: brightness, cover, volume, fan or number |
| `webhook.call` + `"webhook"` or `"url"` | HTTP request (`method`, `headers`, `body`) |
| `mqtt.publish` + `"topic"` (+ `"payload"`, `"retain"`) | send an MQTT message |
| `plugin` + `"plugin"`, `"action"` (+ `"params"`) | a plugin action |

Key names: `cmd`, `shift`, `alt`/`option`, `ctrl`, `fn` + a letter, digit, punctuation mark or
`return`, `tab`, `space`, `delete`, `esc`, `up`/`down`/`left`/`right`, `home`, `end`, `pageup`, `pagedown`, `f1`–`f20`.
Keys follow the US layout (also US International).

Tile types (`kind`): `button` (default), `slider`, `clock`, `agenda` and the widgets below. Place them with `x`, `y`
and optionally `w`, `h`.

### Gestures and on/off buttons

```json
{
  "id": "copy", "label": "Copy", "icon": "📋", "x": 0, "y": 1,
  "action":    { "type": "keys.press", "keys": "cmd+c" },
  "longPress": { "type": "keys.press", "keys": "cmd+x" },
  "doubleTap": { "type": "keys.press", "keys": "cmd+a" }
}
```

- `longPress`: hold for about 0.5 s. `doubleTap`: tap twice quickly.
  Only buttons with a double tap wait briefly (0.28 s) before a normal tap.
- `"toggle": true` turns it into an on/off button: Cyberpad remembers the state and the button lights up.
  `offAction` sets a different action for "off". If the action fails, the button switches back.

### Shortcut library

`catalog/shortcuts.json` contains default keyboard shortcuts for Zoom, Teams, Google Meet, Webex, Slack, Discord, Loom
and VS Code. Use them with `{"type": "preset", "preset": "<app>.<id>"}`, e.g. `zoom.mute`, `zoom.video`, `teams.hand`,
`meet.mute`, `slack.huddleMute`, `discord.deafen`, `vscode.palette`. Where needed, Cyberpad brings the app to the front
first. If you changed the shortcuts in an app, use `keys.press` instead.

### Shortcuts app and Focus

macOS has no public way to turn on a Focus directly. Create two shortcuts in the Shortcuts app, e.g. **Focus on**
(action "Set Focus" → on) and **Focus off**, and use them with `shortcut.run`. The default layout already has an
on/off button for this on the **Work** page.

### Widgets

Widgets get their settings in `"config"`. Examples are on the **Widgets** page of the default layout.

| `kind` | Shows | `config` | On the tablet |
|---|---|---|---|
| `weather` | temperature, weather, min/max, chance of rain (Open-Meteo) | `city` or `lat` + `lon` | tap = refresh |
| `nowplaying` | title, artist, progress from Music or Spotify | `player`: `music` / `spotify` | tap = play/pause, tap the bar = seek; ⏮ ⏯ ⏭ from 3 cells wide |
| `timer` | countdown, keeps running on the Mac | `seconds` | tap = start/pause, hold = reset, 2× = +1 min |
| `pomodoro` | work/break rounds with sound | `work`, `rest` (minutes) | like the timer |
| `worldclock` | time in other zones | `zones`: e.g. `["America/New_York"]` (max. 4; the editor has a drop-down) | — |
| `photos` | slideshow | `folder` (default `~/Pictures/Cyberpad`), `seconds` | tap = next |
| `stats` | CPU, memory, network, battery, Magic accessories | `show`: e.g. `["cpu","ram"]` | — |
| `terminal` | live output of a command | `command`, `cwd`, `timeout` (max. 600 s), `dangerous` | tap = start/stop |
| `slider` + `audio.micVolume` | microphone volume | — | slide |

- **Terminal:** the command only lives in the layout on the Mac and runs in your own login shell (`zsh -l`).
  With `"dangerous": true` you have to tap twice on the tablet, and the Mac refuses without that confirmation.
  Cyberpad stops the command after `timeout` seconds.
- **Now playing** asks once for *Automation › Spotify/Music*; Cyberpad never launches those apps itself.
- **Weather:** only the place name or coordinates are sent to Open-Meteo.
- **Level meter** is deliberately left out: Cyberpad would have to keep the microphone open (orange dot in the menu
  bar), and meeting detection would then see Cyberpad itself as a meeting.

### Smart home and integrations

Menu › **Integrations…** opens a window for Home Assistant and MQTT. Addresses go into `integrations.json` in the
Cyberpad folder. Tokens and passwords are stored only in the macOS **Keychain**.

**Home Assistant.** Enter the address (e.g. `http://homeassistant.local:8123`) and a *long-lived access token*, which
you create in Home Assistant under Profile › Security. Cyberpad keeps a WebSocket connection open, so the buttons on
the tablet show the real state immediately, also when you switch something with a remote or another app.
Only entities in your layout are sent to the tablet, and only their name, state and a few values.

| Tile | Example |
|---|---|
| on/off button | `{"type": "ha.toggle", "entity": "light.living_room"}`: lights up when the device is on |
| scene / script | `{"type": "ha.toggle", "entity": "scene.movie"}` |
| service | `{"type": "ha.service", "service": "light.turn_on", "entity": "light.desk", "data": {"brightness_pct": 30, "color_name": "red"}}` |
| slider | `"kind": "slider"` with `{"type": "ha.level", "entity": "light.living_room"}` (also `cover.*`, `media_player.*`, `fan.*`, `input_number.*`) |
| widget | `"kind": "ha"` with `"config": {"entity": "sensor.outside_temperature"}`; thermostats (`climate.*`) get − and + |

A lock (`lock.*`) can only be **locked** with `ha.toggle`. Unlocking needs a separate `ha.service` button with
`lock.unlock`. An alarm can also only be controlled with `ha.service`.

**HomeKit** has no integration of its own: on the Mac, HomeKit requires a paid developer account and a Catalyst app.
Use Home Assistant's HomeKit integration instead; anything in there, Cyberpad can control.

**MQTT.** Enter the server, port (default 1883, or 8883 with TLS), user and password.

- `"kind": "mqtt"` with `"config": {"topic": "home/attic/temperature", "unit": "°C"}` shows the latest value.
  For JSON messages, pick one field with `"field": "temperature"` (or `"sensor.temp"`).
- An on/off button with `mqtt.publish` and `"config": {"topic": "…/state"}` follows the real state of that topic.
  Values such as `ON`, `true`, `1` and `open` count as *on*.
- Wildcards (`+`, `#`) are not used; Cyberpad only subscribes to the topics in your layout.

**Webhooks.** A single button can have a `url`. Named webhooks live in `integrations.json`:

```json
{
  "webhooks": {
    "n8n": { "url": "https://n8n.example.com/webhook/abc", "method": "POST",
             "body": "{\"source\": \"cyberpad\"}", "secretHeader": "Authorization" }
  }
}
```

With `secretHeader`, the value of that header comes from the Keychain; enter it via **Integrations…**.
A JSON body automatically gets `Content-Type: application/json`. If the webhook fails (status 400 or higher, or a
timeout after 10 s), a message appears on the tablet and an on/off button switches back.

If Home Assistant or the broker drops out, Cyberpad keeps retrying (2 s up to 1 min). The tiles turn grey with the
reason. A rejected token or password is not retried until you change it.

### On the tablet

- **⚙ at the top right** opens the settings of *that* tablet: language, idle screen (after 2–30 min, or off), photos
  on the idle screen, tap sound, animations (off = faster on old iPads; off by default on iOS 12 and older),
  always full screen, edit layout and *unpair this tablet*.
- **Connection lost:** everything stays visible with the last known state. A red bar counts down to the next attempt;
  *Try now* tries straight away.
- **Idle screen:** after the set time without touching, a dimmed clock with the date, the next event and what is
  playing, optionally over photos from your `photos` tile. The clock moves a little every minute (against burn-in).
  A tap brings you back without pressing anything. A meeting also dismisses the idle screen.
- **Home Screen app:** Safari › Share › *Add to Home Screen*. Then pair once more: iOS keeps the pairing of the Home
  Screen app separate from Safari.

| Tile | Does | Settings |
|---|---|---|
| `"kind": "touchpad"` | trackpad: move with 1 finger, tap = click, scroll with 2 fingers, tap with 2 = right-click, hold and move = drag | `config.speed` (default 1.5), `config.natural` (natural scrolling, on by default) |
| `"kind": "dial"` | dial: turn circles with one finger, one step per 15° | `action` (see below), `config.step` |

A dial with `audio.volume`, `audio.micVolume` or `ha.level` changes that value per step (`config.step`, default 0.03).
With `pointer.scroll` it scrolls. With any other action it runs that action clockwise and the `offAction`
counter-clockwise, e.g. `ctrl+right` / `ctrl+left` to switch desktops. Touchpad and dial only work when that tile is in
your layout, and need Accessibility (except volume and `ha.level`). The touchpad only works over WebSocket, not over
the fallback for old tablets.

### Profiles and context pages

**Context page:** give a page a list of `apps`. When one of those apps comes to the front on the Mac, the tablet jumps
to that page (its tab gets a ◆). When you switch to another app, the tablet returns to the page you last chose
yourself. Choosing a tab yourself always wins.

```json
{ "id": "photoshop", "name": "Photoshop", "apps": ["com.adobe.Photoshop", "Adobe Photoshop 2026"], "tiles": [ … ] }
```

**Profiles** decide which pages a tablet shows, and in which order:

```json
"profiles": [
  { "id": "work", "name": "Workday", "pages": ["main", "work", "widgets"],
    "when": [{ "days": [1, 2, 3, 4, 5], "from": "08:00", "to": "18:00" }] },
  { "id": "home", "name": "At home", "pages": ["main", "home", "widgets"], "default": true }
]
```

- `days`: 1 = Monday … 7 = Sunday (leave out = every day). A `from` later than `to` runs past midnight.
- Which profile a tablet gets, in order:
  1. a **fixed profile for that tablet** (menu › Paired tablets, picker next to the name);
  2. a **manually chosen profile** (menu › Profile);
  3. the first profile whose **time rule** matches now;
  4. the profile with `"default": true`.
- The profile name is shown in the tablet's status bar.

**Focus mode:** macOS gives apps no access to the active Focus. Use an automation in the Shortcuts app instead:
*Automation › Focus › Work › When turning on › Open URL* `cyberpad://profile/work` (and when turning off
`cyberpad://profile/auto`). The same links work in ordinary shortcuts too.

### Plugins

Plugins add actions and widgets without changing Cyberpad itself; see [docs/PLUGINS.md](docs/PLUGINS.md).
They live in `~/Library/Application Support/Cyberpad/Plugins/` (the **Plugins** button in the menu opens that folder).
Two examples are included: *Hello world* and *Reachable?*; the *Plugins* page of the default layout uses them.

- Every plugin starts **off**. Turn it on in the menu bar › Plugins › *Turn on…*.
- If a plugin's files change, it is turned off again until you allow it again.
- A plugin is a separate program: if it crashes, Cyberpad keeps running.

```json
{ "id": "hi", "label": "Say hello", "x": 0, "y": 0,
  "action": { "type": "plugin", "plugin": "hallo", "action": "groet", "params": { "naam": "Cyberpad" } } }
```

### Meetings

As soon as you are in a meeting, a **meeting panel** appears on the tablet with microphone, camera, raise hand,
share screen and hang up (hang up = tap twice). *Hide* takes you back to your buttons; the pink label in the status
bar brings the panel back.

- **Detection:** a meeting app (Zoom, Teams, Webex) is running *and* using the microphone. Google Meet is detected
  by the window title in the browser (requires Accessibility).
- **Mute state:** for Zoom, Cyberpad reads it from Zoom's menu (requires Accessibility). For the other apps, Cyberpad
  keeps track of what you do via the tablet; the panel then shows it as "estimated".
- Which keys are sent is defined in `catalog/shortcuts.json`.

### Calendar

A tile with `"kind": "agenda"` shows your next event with a countdown; with `"config": {"count": 3}` also the events
after it (max. 5, next 7 days). If the event contains a Zoom, Teams, Meet, Webex, FaceTime or Whereby link, **Join**
opens it. Cyberpad asks for Calendar access at first launch if your layout has a calendar tile; otherwise use
*Allow…* in the menu. Event titles and times are only sent to paired tablets.

Testing without a real meeting or calendar: start with `CYBERPAD_FAKE_MEETING=teams` (or `zoom`, `meet`, `webex`)
and/or `CYBERPAD_FAKE_AGENDA=1`. No keys are sent in meeting test mode.

Menu › **Restore default layout…** brings back the example layout; your current layout is backed up first.

## Security

- Every tablet gets its own token; the Mac stores only its SHA-256 hash (`devices.json`, readable only by you).
- Revoking in the menu cuts the connection immediately.
- A pairing code expires after 2 minutes and works once. After 5 wrong attempts an address is blocked for 1 minute.
- Only connections from the local network are accepted.
- The tablet only sends a tile id. What happens is defined in the layout on the Mac.

## Structure

```
macos/                    Mac version (Swift)
  Package.swift
  Resources/Info.plist
  scripts/build.sh        builds macos/build/Cyberpad.app
  scripts/make-dmg.sh     makes the installer Cyberpad-<version>.dmg
  scripts/make-pad-icons.swift  draws shared/pad/icons
  scripts/i18n-keys.py    checks that every text is translated
  Sources/Cyberpad/
    CyberpadApp.swift     menu bar window
    Core.swift            ties everything together
    Localizer.swift       language (English, Dutch, Spanish) and L("…")
    Server.swift          HTTP + WebSocket on port 7420 (+ XHR fallback)
    WebSocket.swift       frames (RFC 6455)
    Pairing.swift         pairing codes, tokens, rate limiting
    Layout.swift          layout model and file
    Actions.swift         all actions, macros, on/off buttons
    Keys.swift            key combinations and typing text
    Pointer.swift         mouse and scrolling for the touchpad
    MeetingMonitor.swift  detecting and controlling meetings
    Agenda.swift          next event and meeting link
    Widgets/              weather, now playing, timers, system stats, photos, terminal
    Integrations/         Home Assistant, MQTT, webhooks, Keychain, Integrations window
    Plugins/              finding, allowing, starting and talking to plugins
    Context/              frontmost app, profiles, cyberpad:// links
    Editor/               editor access and the editor window (WKWebView)
    Theme/                reading themes, filling in the tablet and editor CSS, app icons and custom images
    Catalog.swift         shortcut library
    Audio.swift           CoreAudio
    HostAlias.swift       cyberpad.local via mDNS
    NetUtil.swift         IP addresses, local network check
shared/                   shared by macOS and Windows
  pad/                    tablet page (ES5, works from iOS 9), manifest and icons
  catalog/                shortcuts.json (keyboard shortcuts per app), timezones.json
  plugins/                bundled example plugins
  editor/                 layout editor (ES5) + schema.json with all actions and tile types
  themes/                 nine themes (see docs/THEMES.md)
  i18n/                   translations: en.json, es.json (see docs/LANGUAGES.md)
docs/
  PROTOCOL.md             tablet ↔ computer: routes, messages, state
  PLUGINS.md              writing plugins
  THEMES.md               themes and icons
  LANGUAGES.md            languages and translations
windows/                  Windows 10/11 version (C#/.NET 8, see windows/README.md)
```

Developing without rebuilding:
`CYBERPAD_PAD_DIR=$PWD/shared/pad macos/build/Cyberpad.app/Contents/MacOS/Cyberpad` loads the tablet page straight
from `shared/pad/` (`CYBERPAD_PLUGINS_DIR` does the same for the bundled plugins). `CYBERPAD_DEBUG=1` prints the
pairing code to the console.

Testing integrations without the Keychain (only together with `CYBERPAD_DEBUG=1`):
`CYBERPAD_INTEGRATIONS=/path/to/test.json` uses a different settings file, and
`CYBERPAD_SECRET_HOMEASSISTANT_TOKEN`, `CYBERPAD_SECRET_MQTT_PASSWORD` and `CYBERPAD_SECRET_WEBHOOK_<NAME>`
pass in the secrets.
