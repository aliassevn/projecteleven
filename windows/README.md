# Cyberpad voor Windows 11 (gepland)

Hier komt de Windows-versie. Nog niets gebouwd; dit is het plan.

## Wat gedeeld wordt met macOS

| Onderdeel | Waar | Windows hoeft het niet opnieuw te maken |
|---|---|---|
| Tablet-pagina | `shared/pad/` | ✓ wordt door de Windows-server geserveerd |
| Protocol | `docs/PROTOCOL.md` | ✓ zelfde routes, berichten en status |
| Layout-formaat | `layout.json` | ✓ platformneutrale acties werken direct |
| Shortcut-bibliotheek | `shared/catalog/shortcuts.json` | aanvullen met `keysWindows` per sneltoets |
| Plugins | `shared/plugins/`, `docs/PLUGINS.md` | ✓ zelfde `plugin.json` en berichten; `run.windows` |
| Layout-editor | `shared/editor/` | ✓ in een WebView2-venster; alleen de editor-API (`docs/PROTOCOL.md`) en een export-brug |
| Thema's | `shared/themes/`, `docs/THEMES.md` | ✓ sjabloon invullen (een paar regels code); app-iconen via de Windows Shell |
| Talen | `shared/i18n/`, `docs/TALEN.md` | ✓ zelfde woordenboeken; `/i18n.js` en `/api/lang` nabouwen |

## Voorgestelde techniek

**C# / .NET 8**, één programma in het systeemvak (naast de klok), met een klein instellingenvenster.

| Mac (Swift) | Windows |
|---|---|
| MenuBarExtra | systeemvak-icoon (WinForms `NotifyIcon` of WPF) |
| Network.framework-server | Kestrel (ASP.NET Core, ingebouwd): HTTP + WebSocket zonder beheerdersrechten |
| Bonjour / `cyberpad.local` | `DnsServiceRegister` (Windows 10+ DNS-SD-API) |
| CGEvent (toetsen, tekst) | `SendInput` (ook Unicode-tekst) |
| Mediatoetsen | `SendInput` met `VK_MEDIA_PLAY_PAUSE` enz. |
| CoreAudio (volume, mic) | Core Audio-COM: `IAudioEndpointVolume` |
| Wie gebruikt de microfoon | register `CapabilityAccessManager\ConsentStore\microphone` |
| Nu speelt | `GlobalSystemMediaTransportControlsSessionManager` (Spotify, browsers, Media Player…) |
| EventKit (agenda) | Outlook / Microsoft Graph (later, optioneel) |
| Opdrachten-app | PowerShell-script of Power Automate Desktop-flow |
| Sleutelhanger | Windows Referentiebeheer (Credential Manager) / DPAPI |
| Toegankelijkheid | niet nodig; wel een eenmalige vraag van de Windows Firewall |
| Actieve app (contextpagina) | `SetWinEventHook(EVENT_SYSTEM_FOREGROUND)` → procesnaam |
| Focus-modus → profiel | geen API; `cyberpad://profile/<id>` via protocol-handler of Taakplanner |
| Ad-hoc ondertekening | onondertekend → SmartScreen-waarschuwing; later code-signing |

## Aandachtspunten

- **Firewall:** bij de eerste start vraagt Windows om toegang tot het *privénetwerk*. Alleen dat aanvinken.
- **Toetsen naar apps met beheerdersrechten** werken niet vanuit een normaal programma (UIPI). Dat is bewust zo.
- **Vergaderknop:** Teams en Zoom hebben op Windows andere sneltoetsen. Die komen in de catalogus als `keysWindows`.
- **Plugins:** `run.windows` gebruikt meestal `py -3` (Python Launcher) of een `.exe`.

## Volgorde (na fase 8 op de Mac)

1. Server, koppelen, tablet-pagina serveren, mediatoetsen en volume (vergelijkbaar met fase 1–3).
2. Toetsen, tekst, macro's, apps en URL's; shortcut-bibliotheek met `keysWindows`.
3. Vergaderknop, widgets, Home Assistant/MQTT/webhooks, plugins.
4. Installatieprogramma (MSIX of Inno Setup) en ondertekening.

Schatting: 3–4 weken, omdat tablet-pagina, protocol en plugins al klaar zijn.
