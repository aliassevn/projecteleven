# Project Eleven — Cyberpad

A home-made macro pad, widget board and smart home panel for the Mac (and Windows), controlled from an old
iPad/tablet through its web browser. At least on par with dustyPad Pro in features, but lighter, safer and with extras.

> Ground rule: we only look at dustyPad for its *structure* (which parts, which techniques).
> We do not copy code, themes, texts or images from `dustyPad.app`, and we build nothing around its licence/trial.
> Open-source parts (Lucide/Tabler icons, open fonts) are fine, with their licences.

---

## 1. What the analysis of dustyPad.app (v1.7.0) showed

| Part | What dustyPad uses |
|---|---|
| Mac app | **Electron** (Node.js + Chromium), menu bar app, macOS 13+, ~500 MB |
| Server to tablet | Node HTTP server + **WebSocket**, port 7341, plain HTTP |
| Discoverable on the network | **Bonjour/mDNS** → `dustypad.local` |
| Pairing | 6-digit code + QR code |
| Tablet page | `index.html` + `pad.js` + `pad.css` in **ES5**, WebSocket with XHR fallback → works on iOS 9 |
| Themes | One CSS file per theme on top of a base CSS |
| Native helpers | 4 separate Swift/ObjC programs: keys (Carbon), audio (CoreAudio), images (ImageIO), emoji/app icons (AppKit) |
| Icons | Lucide + Tabler (open source) |
| Updates | GitHub Releases |

**What we do differently:**
- **Native Swift instead of Electron** → one app of ~10 MB, no separate helpers, little power/memory.
- **Stronger security** (per-tablet tokens, revoking, rate limiting, dangerous actions only from the editor).
- **Plugin system** from day one.
- **Offline-resilient tablet page.**
- Extra features: meeting button, Home Assistant/HomeKit, terminal widget, contextual layouts, macros and more.

---

## 2. Cyberpad architecture

```
┌──────────── iPad (Safari) ────────────┐        ┌─────────── Mac: Cyberpad.app (Swift) ───────────┐
│  pad/ (ES5, no build step)            │  Wi-Fi │  SwiftUI menu bar app (MenuBarExtra)            │
│  - grid, pages, widgets               │◄──────►│  Network.framework:                             │
│  - theme CSS + animations             │   WS   │   - HTTP + WebSocket server  :7420              │
│  - cached layout (offline)            │        │   - Bonjour  cyberpad.local                     │
│  - tap / long / double / swipe        │        │  Pairing & tokens                               │
│  - web editor mode                    │        │  Action router ──► actions + plugins            │
└───────────────────────────────────────┘        │  Widget feeds (audio, stats, calendar, HA, ...) │
                                                 │  Context engine (frontmost app, Focus, time)    │
                                                 │  Editor window                                  │
                                                 └─────────────────────────────────────────────────┘
                                                        │                │
                                               Home Assistant /    Webhooks / MQTT /
                                               HomeKit             scripts / Shortcuts
```

**macOS frameworks we use:** CGEvent (keys/text), CoreAudio (volume, mic, output), AppKit/NSWorkspace (apps, icons,
frontmost app), EventKit (calendar), IOKit (battery), Network.framework (server, Bonjour), Security (Keychain).

**Protocol (JSON over WebSocket):** see [docs/PROTOCOL.md](docs/PROTOCOL.md).

---

## 3. Roadmap

### Phase 0 — Preparation (½ day)
1. Install Xcode (full, not just the Command Line Tools) and Git.
2. `git init` in this folder; put `dustyPad.app/` in `.gitignore`.
3. Project structure: `macos/` (Swift package), `shared/` (tablet page, editor, catalogue, themes), `docs/`.

### Phase 1 — Minimal connection (2 days)
4. SwiftUI menu bar app (`MenuBarExtra`), option "start at login" (`SMAppService`).
5. HTTP server with `NWListener` serving `pad/`; WebSocket.
6. Tablet page in ES5: draw the grid, tap → message. Test on the old iPad.
7. XHR polling as a fallback for old Safari; reconnect automatically.

### Phase 2 — Discoverable and safe pairing (2 days)
8. Bonjour advertisement → `cyberpad.local:7420`.
9. Pairing: the Mac shows a 6-digit code + QR; the tablet gets **its own token per device**.
10. A "Paired tablets" list in the app with name, last seen and **Revoke**.
11. **Rate limiting**: block for 1 minute after 5 wrong codes; a code expires after 2 minutes.
12. Only accept connections from the local subnet.
13. **Dangerous actions** (typing text, scripts/terminal, webhooks) only run when they were set up in the editor on the
    Mac. The tablet only sends a button id, never a command or text of its own.
14. Optional: HTTPS with a self-made certificate for modern tablets (old iOS stays on HTTP).

### Phase 3 — Basic actions (2–3 days)
15. Action router: `action id → handler`, every action described in a catalogue (name, icon, parameters).
16. Media: play/pause, next/previous (media keys via CGEvent).
17. Volume up/down/mute, mic mute (CoreAudio).
18. Open an app or URL, dark mode, lock screen, screenshots, keep awake, display off.
19. Ask for macOS permissions properly, with explanations (Accessibility, Automation, Local Network, Calendar).

### Phase 4 — Pro actions (3 days)
20. **Shortcut library** (`catalog/shortcuts.json`) for Zoom, Meet, Teams, Slack, Loom, VS Code…
21. Any key combination and typing text (CGEvent).
22. Shortcuts app: `shortcuts run "Name"`; Focus mode via a shortcut.
23. **On/off buttons** that show their state.
24. **Multi-step macros**: open app → wait → key combination → type text → …
25. **Second and third action per button**: tap, long press, double tap.

### Phase 5 — ⭐ Meeting button (2 days)
26. Detect an active meeting app (Zoom, Teams, Meet in the browser, Webex) via `NSWorkspace` + window titles.
27. Then show a meeting panel automatically: **mute, camera, raise hand, share screen, hang up**.
28. Show the **mute state** (red/green) as reliably as the app allows (Zoom via menu items with Accessibility;
    otherwise keep our own toggle state).
29. Calendar widget (EventKit): next event, countdown, **"Join"** button (opens the meeting link).

### Phase 6 — Widgets (3–4 days)
30. Basics: clock, weather (Open-Meteo, no API key), now playing, volume/mic slider, track position.
31. Pro: timer, Pomodoro, world clock, photo slideshow, music player, system stats (CPU, RAM, network, battery of
    accessories via IOKit).
32. ⭐ **Terminal widget**: start a command defined in the editor and show its output live (build, ping, `tail -f` of a
    log). Confirmation on the tablet for commands marked "dangerous"; stop button; maximum run time.

### Phase 7 — ⭐ Smart home and integrations (3 days)
33. **Home Assistant**: URL + long-lived token in the Keychain; lights, scenes, switches, temperature; live state via
    the HA WebSocket API.
34. **HomeKit**: *decided:* via Home Assistant's HomeKit integration; a HomeKit integration of our own needs a paid
    developer account and a Catalyst app.
35. **Webhook button** (GET/POST with a custom body) for IFTTT, Zapier, n8n or your own scripts.
36. **MQTT button** and MQTT widget (show the value of a topic).

### Phase 8 — Plugin system (2–3 days)
37. Folder `~/Library/Application Support/Cyberpad/Plugins/`; each plugin = `plugin.json` + a script.
38. `plugin.json` describes actions/widgets, parameters and icon; the editor shows them automatically.
39. Plugins run as a separate process with JSON over stdin/stdout (if a plugin crashes, Cyberpad keeps running).
40. Built-in features use the same catalogue where possible, so plugins are first-class.

### Phase 9 — Context and profiles (2 days)
41. **Contextual layouts**: the page switches automatically based on the frontmost app (Photoshop → Photoshop buttons).
42. **Profiles by time of day or Focus mode** (work during the day, media in the evening).
43. **Several tablets, each with its own layout** (tied to the per-device token).

### Phase 10 — Tablet experience (3 days)
44. **Offline-resilient**: layout and theme in `localStorage`; when the connection drops everything stays visible,
    with a "connection lost" notice and a countdown to the next attempt.
45. **Touchpad mode**: the tablet as an extra trackpad, plus a dial gesture for volume/scrolling.
    *Built as tiles* (`touchpad`, `dial`), so you can put them next to ordinary buttons on a page.
46. **Ambient mode**: after X minutes without touching, show a dimmed clock, stats or photos; tap = back.
47. **Animations and sound** on press (can be turned off; kept light for old iPads).
48. "Add to Home Screen" (web app manifest, full screen, no address bar).
    Plus a ⛶ button and the setting *Always full screen* (Fullscreen API, iPadOS 12+), without pairing again.
    *Limitation:* without https there is no service worker; if the Mac is off, a (re)opened page cannot load.
    A page that is already open keeps working with the last known state.

### Phase 11 — Editors (4–5 days)
49. **Editor on the Mac**: grid size, dragging buttons, choosing an action, icon/colour/label, pages, profiles.
    *Decided:* one web editor (`shared/editor/`) for the Mac window, the tablet and Windows (WebView2), instead of a
    separate SwiftUI editor. That way the editor does not have to be rebuilt per platform.
50. Icon picker: emoji, app icons, custom images/logos. Bundling Lucide/Tabler can come later (with their licences,
    ±1–3 MB of SVGs).
51. **Web editor on the tablet**: edit mode with drag and drop.
52. Push changes live to all tablets.
53. **Export/import layouts** as a `.cyberpad` file. A whole layout does not fit in a QR code; sharing via QR could
    later work through a one-time download link.

### Phase 12 — Themes, including our own Cyberdeck (2–3 days)
54. *Built as:* one template (`shared/pad/pad.css`, and `shared/editor/editor.css` for the editor) that the computer
    fills in per theme; no CSS variables needed, so it works on old Safari.
55. Own designs: **Cyberdeck** (neon, scanlines, glitch, mono font), Terminal, Cockpit, Vapor, Minimal, Night,
    Graphite, Contrast, Ocean.
56. Fonts: for now fonts that already ship with iPad/Mac/Windows (works offline, nothing to download). Bundling open
    fonts (JetBrains Mono, VT323, Barlow Condensed, Orbitron) can come later, with their licence (OFL).
57. **Theme builder**: colours, glow, borders, font, effects → saved with the layout and shared via export.

### Phase 13 — Diagnostics (1 day)
58. Diagnostics page in the Mac app and on the tablet: connection state, latency (ping), missing macOS permissions
    with an "Open System Settings" button, IP address/port, log of the latest actions.

### Phase 14 — Packaging and distribution (1–2 days)
59. Universal build (arm64 + x86_64), `.dmg`. *Done:* `macos/scripts/make-dmg.sh` and a GitHub Actions workflow.
60. Code signing + notarisation (Apple Developer account, $99/year).
61. Automatic updates with **Sparkle**.
62. Optional: licence keys via Gumroad or Lemon Squeezy, with a fair free version.

### Phase 15 — Testing
63. Devices: old iPad (iOS 9–12), new iPad, Android tablet, phone; Intel and Apple silicon Macs; Windows 10/11.
64. Scenarios: Wi-Fi gone/back, Mac asleep, two tablets at once, permissions denied, token revoked, plugin crashes,
    Home Assistant unreachable, terminal command hangs.

---

### Phase 16 — Windows 10/11 version (3–4 weeks)
Same tablet page, protocol, layout format and plugins (`shared/`, `docs/PROTOCOL.md`, `docs/PLUGINS.md`); a program of
its own for Windows in C#/.NET 8 with Kestrel, `SendInput`, Core Audio and DNS-SD.
*Version 0.1 done* (core features and installer); see [windows/README.md](windows/README.md) for what follows.

## 4. Priorities

| Priority | Phases | Result |
|---|---|---|
| **1 — Prototype** | 0–3 | The iPad controls your Mac safely (a weekend to a week) |
| **2 — Pro parity** | 4, 6, 11, 12 | Comparable to dustyPad Pro |
| **3 — Distinctive** ⭐ | 5, 7, 6 (terminal) | Meeting button, smart home, terminal widget |
| **4 — Finishing** | 8–10, 13–15 | Plugins, context, offline, diagnostics, distribution |
| **5 — Windows** | 16 | The same tablet page and plugins on Windows |

## 5. Estimate
Roughly **8–10 weeks** part-time for the full version with all extras.
The prototype (phases 0–3) takes a weekend to a week, depending on your Swift experience.
