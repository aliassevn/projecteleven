# Project Eleven — Cyberpad

Een eigen macropad, widgetbord en smart-home-paneel voor de Mac, bediend vanaf een oude iPad/tablet via de browser.
Functioneel minstens gelijk aan dustyPad Pro, maar lichter, veiliger en met extra's.

> Uitgangspunt: we kijken naar dustyPad alleen voor de *opbouw* (welke onderdelen, welke technieken).
> We kopiëren geen code, thema's, teksten of afbeeldingen uit `dustyPad.app` en bouwen niets om de
> licentie/trial heen. Open-source onderdelen (Lucide/Tabler-iconen, open fonts) mogen wel, met hun licentie.

---

## 1. Wat de analyse van dustyPad.app (v1.7.0) liet zien

| Onderdeel | Wat dustyPad gebruikt |
|---|---|
| Mac-app | **Electron** (Node.js + Chromium), menubalk-app, macOS 13+, ~500 MB |
| Server naar tablet | Node HTTP-server + **WebSocket**, poort 7341, gewone HTTP |
| Vindbaar op netwerk | **Bonjour/mDNS** → `dustypad.local` |
| Koppelen | 6-cijferige code + QR-code |
| Tablet-pagina | `index.html` + `pad.js` + `pad.css` in **ES5**, WebSocket met XHR-terugval → werkt op iOS 9 |
| Thema's | Eén CSS-bestand per thema bovenop een basis-CSS |
| Native hulpjes | 4 losse Swift/ObjC-programma's: toetsen (Carbon), audio (CoreAudio), afbeeldingen (ImageIO), emoji/app-iconen (AppKit) |
| Iconen | Lucide + Tabler (open source) |
| Updates | GitHub Releases |

**Wat we anders doen:**
- **Native Swift i.p.v. Electron** → één app van ~10 MB, geen losse hulpprogramma's, weinig stroom/geheugen.
- **Sterkere beveiliging** (per-tablet tokens, intrekken, rate-limit, gevaarlijke acties alleen vanuit de editor).
- **Plugin-systeem** vanaf dag één.
- **Offline-bestendige tablet-pagina.**
- Extra functies: vergaderknop, Home Assistant/HomeKit, terminal-widget, contextuele layouts, macro's en meer.

---

## 2. Architectuur Cyberpad

```
┌──────────── iPad (Safari) ────────────┐        ┌─────────── Mac: Cyberpad.app (Swift) ───────────┐
│  pad/ (ES5, geen build-stap)          │  Wi-Fi │  SwiftUI menubalk-app (MenuBarExtra)            │
│  - grid, pagina's, widgets            │◄──────►│  Network.framework:                             │
│  - thema-CSS + animaties              │   WS   │   - HTTP + WebSocket-server  :7420              │
│  - layout gecachet (offline)          │        │   - Bonjour  cyberpad.local                     │
│  - tik / lang / dubbel / swipe        │        │  Pairing & tokens (Keychain)                    │
│  - webeditor-modus                    │        │  Actie-router ──► acties + plugins              │
└───────────────────────────────────────┘        │  Widget-feeds (audio, stats, agenda, HA, ...)   │
                                                 │  Context-engine (actieve app, Focus, tijd)      │
                                                 │  SwiftUI editor-venster                         │
                                                 └─────────────────────────────────────────────────┘
                                                        │                │
                                               Home Assistant /    Webhooks / MQTT /
                                               HomeKit             scripts / Shortcuts
```

**Macos-frameworks die we gebruiken:** CGEvent (toetsen/tekst), CoreAudio (volume, mic, uitvoer),
AppKit/NSWorkspace (apps, iconen, actieve app), EventKit (agenda), HomeKit (optioneel), IOKit (batterij),
Network.framework (server, Bonjour), Security (Keychain).

**Protocol (JSON over WebSocket):**
- tablet → Mac: `{type:"press", id, gesture:"tap|long|double"}`, `{type:"slider", id, value}`, `{type:"touchpad", dx, dy}`
- Mac → tablet: `{type:"layout", ...}`, `{type:"state", id, ...}`, `{type:"context", profile}`

---

## 3. Stappenplan

### Fase 0 — Voorbereiding (½ dag)
1. Installeer Xcode (volledig, niet alleen Command Line Tools) en Git.
2. `git init` in deze map; zet `dustyPad.app/` in `.gitignore`.
3. Projectstructuur:
   ```
   Cyberpad/            # Xcode-project (SwiftUI, macOS 13+)
     App/               # menubalk, venster, app-lifecycle
     Server/            # HTTP, WebSocket, Bonjour, pairing
     Actions/           # ingebouwde acties
     Widgets/           # widget-feeds
     Plugins/           # plugin-loader
     Context/           # actieve app, Focus, tijdsprofielen
     Editor/            # SwiftUI-editor
   pad/                 # tablet-pagina (ES5, plain JS/CSS)
   catalog/             # JSON: shortcut-bibliotheek, thema's
   ```

### Fase 1 — Minimale verbinding (2 dagen)
4. SwiftUI-menubalk-app (`MenuBarExtra`), optie "start bij inloggen" (`SMAppService`).
5. HTTP-server met `NWListener` die `pad/` serveert; WebSocket via `NWProtocolWebSocket`.
6. Tablet-pagina in ES5: grid tekenen, tik → bericht. Testen op je oude iPad.
7. XHR-polling als terugval voor oude Safari; automatisch opnieuw verbinden.

### Fase 2 — Vindbaar & veilig koppelen (2 dagen)
8. Bonjour-advertentie → `cyberpad.local:7420`.
9. Pairing: Mac toont 6-cijferige code + QR; tablet krijgt een **eigen token per apparaat**.
10. Tokens opslaan in de **Keychain**; in de app een lijst "Gekoppelde tablets" met naam, laatst gezien en **Intrekken**.
11. **Rate-limit**: na 5 foute codes 1 minuut blokkeren; code verloopt na 2 minuten.
12. Alleen verbindingen uit het lokale subnet accepteren.
13. **Gevaarlijke acties** (tekst typen, script/terminal, webhooks) worden alleen uitgevoerd als ze in de
    editor op de Mac zijn ingesteld. De tablet stuurt alleen een knop-id, nooit zelf een commando of tekst.
14. Optioneel: HTTPS met een zelfgemaakt certificaat voor moderne tablets (oude iOS blijft op HTTP).

### Fase 3 — Basisacties (2–3 dagen)
15. Actie-router: `actie-id → handler`, elke actie beschreven in een catalogus (naam, icoon, parameters).
16. Media: play/pause, volgende/vorige (media-toetsen via CGEvent of AppleScript naar Music/Spotify).
17. Volume op/neer/mute, mic mute, uitvoerapparaat wisselen (CoreAudio).
18. App of URL openen, dark mode, scherm vergrendelen, screenshots, wakker houden, beeldscherm uit.
19. macOS-rechten netjes aanvragen + uitleg (Toegankelijkheid, Automation, Lokaal netwerk, Agenda).

### Fase 4 — Pro-acties (3 dagen)
20. **Shortcut-bibliotheek** (`catalog/shortcuts.json`) voor Zoom, Meet, Teams, Slack, Loom, Photoshop, VS Code…
21. Willekeurige toetscombinatie en tekst typen (CGEvent).
22. Opdrachten-app: `shortcuts run "Naam"`; Focus-modus via een Shortcut.
23. **Aan/uit-knoppen** die hun status tonen.
24. **Macro's met meerdere stappen**: app openen → wachten → toetscombinatie → tekst typen → …
25. **Tweede en derde actie per knop**: tik, lang indrukken, dubbeltikken.

### Fase 5 — ⭐ Vergaderknop (2 dagen)
26. Detecteer actieve vergader-app (Zoom, Teams, Meet in browser, Webex) via `NSWorkspace` + venstertitels.
27. Toon dan automatisch een vergaderpaneel: **mute, camera, hand opsteken, scherm delen, ophangen**.
28. Toon de **mute-status** (rood/groen) — zo betrouwbaar als de app toelaat (Zoom/Teams via menu-items
    met Toegankelijkheid; anders eigen toggle-status bijhouden).
29. Agenda-widget (EventKit): volgende afspraak, aftellen, knop **"Deelnemen"** (opent de vergaderlink).

### Fase 6 — Widgets (3–4 dagen)
30. Basis: klok, weer (Open-Meteo, geen API-key), nu-speelt, volume-/mic-slider, trackpositie.
31. Pro: timer, Pomodoro, wereldklok, fotoslideshow, muziekspeler, niveaumeter,
    systeemstats (CPU, RAM, netwerk, batterij van accessoires via IOKit).
32. ⭐ **Terminal-widget**: een in de editor vastgelegd commando starten en de uitvoer live tonen
    (build, ping, `tail -f` van een log). Bevestiging op de tablet bij commando's die als "gevaarlijk" zijn gemarkeerd;
    stopknop; maximale looptijd.

### Fase 7 — ⭐ Smart home & koppelingen (3 dagen)
33. **Home Assistant**: URL + long-lived token in de Keychain; lampen, scènes, schakelaars, temperatuur;
    live status via de HA-WebSocket-API.
34. **HomeKit** (optioneel; vereist entitlement en is beperkter op macOS) — anders via Home Assistant.
    *Besloten:* via de HomeKit-integratie van Home Assistant; een eigen HomeKit-koppeling vraagt een betaald
    ontwikkelaarsaccount en een Catalyst-app.
35. **Webhook-knop** (GET/POST met eigen body) voor IFTTT, Zapier, n8n of eigen scripts.
36. **MQTT-knop** en MQTT-widget (waarde van een topic tonen).

### Fase 8 — Plugin-systeem (2–3 dagen)
37. Map `~/Library/Application Support/Cyberpad/Plugins/`; elke plugin = `plugin.json` + script.
38. `plugin.json` beschrijft acties/widgets, parameters en icoon; de editor toont ze automatisch.
39. Plugins draaien als apart proces met JSON via stdin/stdout (crasht een plugin, dan blijft Cyberpad draaien).
40. Ingebouwde functies zoveel mogelijk via dezelfde catalogus, zodat plugins gelijkwaardig zijn.

### Fase 9 — Context & profielen (2 dagen)
41. **Contextuele layouts**: pagina wisselt automatisch op basis van de actieve app (Photoshop → Photoshop-knoppen).
42. **Profielen per tijdstip of Focus-modus** (werk overdag, media 's avonds).
43. **Meerdere tablets met elk een eigen layout** (gekoppeld aan het token per apparaat).

### Fase 10 — Tablet-ervaring (3 dagen)
44. **Offline-bestendig**: layout en thema in `localStorage`; bij verbindingsverlies blijft alles zichtbaar
    met de melding "verbinding weg" en een teller tot het opnieuw verbinden.
45. **Aanraakpad-modus**: tablet als extra trackpad, plus draaiknop-gebaar voor volume/scrollen.
46. **Ambient-modus**: na X minuten zonder aanraken klok, stats of foto's tonen, gedimd; tik = terug.
47. **Animaties en geluid** bij indrukken (uit te zetten; licht houden voor oude iPads).
48. "Toevoegen aan beginscherm" (web-app-manifest, schermvullend, geen adresbalk).

### Fase 11 — Editors (4–5 dagen)
49. **SwiftUI-editor op de Mac**: grid-grootte, knoppen slepen, actie kiezen, icoon/kleur/label, pagina's, profielen.
50. Iconenkiezer: Lucide + Tabler (licenties meeleveren), emoji, app-iconen, eigen afbeeldingen/logo's.
51. **Webeditor op de tablet**: bewerkmodus met slepen en neerzetten (na bevestiging op de Mac of met PIN).
52. Wijzigingen live naar alle tablets pushen.
53. **Layouts exporteren/importeren** als `.cyberpad`-bestand of QR-code.

### Fase 12 — Thema's, waaronder een eigen Cyberdeck (2–3 dagen)
54. Basis-CSS met variabelen; per thema een gegenereerd CSS-bestand voor oude Safari.
55. Eigen ontwerpen: **Cyberdeck** (neon, scanlines, glitch, mono-font), Terminal, Cockpit, Vapor, Minimal.
56. Open fonts (JetBrains Mono, VT323, Barlow Condensed, Orbitron).
57. **Thema-bouwer**: kleuren, glow, randen, font, animaties → eigen thema opslaan en delen.

### Fase 13 — Diagnose (1 dag)
58. Diagnosepagina in de Mac-app én op de tablet: verbindingsstatus, vertraging (ping), ontbrekende
    macOS-rechten met knop "Open Systeeminstellingen", IP-adres/poort, logboek van de laatste acties.

### Fase 14 — Verpakken & distribueren (1–2 dagen)
59. Universal build (arm64 + x86_64), `.dmg`.
60. Code-signing + notarisatie (Apple Developer-account, $99/jaar).
61. Auto-updates met **Sparkle**.
62. Optioneel: licentiesleutels via Gumroad of Lemon Squeezy, met een eerlijke gratis versie.

### Fase 15 — Testen
63. Apparaten: oude iPad (iOS 9–12), nieuwe iPad, Android-tablet, telefoon; Intel- én Apple-silicon-Mac.
64. Scenario's: wifi weg/terug, Mac slaapt, twee tablets tegelijk, rechten geweigerd, token ingetrokken,
    plugin crasht, Home Assistant onbereikbaar, terminal-commando hangt.

---

### Fase 16 — Windows 11-versie (3–4 weken)
Zelfde tablet-pagina, protocol, layout-formaat en plugins (`shared/`, `docs/PROTOCOL.md`, `docs/PLUGINS.md`);
een eigen programma voor Windows in C#/.NET 8 met Kestrel, `SendInput`, Core Audio en DNS-SD.
Uitgewerkt in [windows/README.md](windows/README.md).

## 4. Prioriteiten

| Prioriteit | Fases | Resultaat |
|---|---|---|
| **1 — Prototype** | 0–3 | iPad bedient je Mac veilig (één weekend tot een week) |
| **2 — Pro-gelijk** | 4, 6, 11, 12 | Vergelijkbaar met dustyPad Pro |
| **3 — Onderscheidend** ⭐ | 5, 7, 6 (terminal) | Vergaderknop, smart home, terminal-widget |
| **4 — Afwerking** | 8–10, 13–15 | Plugins, context, offline, diagnose, distributie |
| **5 — Windows** | 16 | Zelfde tablet en plugins op Windows 11 |

## 5. Inschatting
Ongeveer **8–10 weken** parttime voor de volledige versie met alle extra's.
Het prototype (fase 0–3) kan in een weekend tot een week, afhankelijk van je Swift-ervaring.
