# Cyberpad voor Windows 10/11

Dezelfde tablet-pagina, editor, thema's en talen als op de Mac, met een eigen programma voor Windows in C# / .NET 8.
Cyberpad draait als icoon in het systeemvak (rechtsonder, naast de klok).

**Downloaden:** zie [Releases](https://github.com/aliassevn/projecteleven/releases) (`CyberpadSetup-<versie>.exe`).
Installeren en eerste stappen: [RELEASE_NOTES.md](RELEASE_NOTES.md).

## Wat er al werkt (versie 0.1)

| Onderdeel | Windows |
|---|---|
| Server | Kestrel (HTTP + WebSocket) op poort 7420, alleen lokaal netwerk; geen beheerdersrechten nodig |
| Koppelen | koppelvenster met adres, QR-code en code van 6 cijfers (zelfde regels als de Mac) |
| Tablet-pagina, editor, thema's, talen | uit `shared\` (zelfde bestanden als de Mac); editor in een WebView2-venster |
| Media, volume, mic | `SendInput` (mediatoetsen) en Core Audio (`IAudioEndpointVolume`) |
| Toetsen en tekst | `SendInput`; `cmd` wordt Ctrl, `win` = Windows-toets; tekst als Unicode |
| Apps | naam uit het Startmenu, pad naar `.exe`/`.lnk`, of een naam die Windows kent (`notepad`) |
| Links | standaardbrowser of een gekozen browser (`StartMenuInternet` in het register) |
| Systeem | vergrendelen, scherm uit, schermafbeelding (Win+PrtSc / Win+Shift+S), wakker houden, donkere modus |
| Widgets | klok, wereldklok, weer, timer, pomodoro, systeem, nu speelt (Windows-mediabediening), foto's, terminal (`cmd`) |
| Aanraakpad en draaiknoppen | `SendInput` met muis en scrollwiel |
| Iconen | `app:<naam>` via de Windows Shell (`IShellItemImageFactory`); eigen afbeeldingen zoals op de Mac |
| Profielen | tijdregels en een vast profiel per tablet |

## Nog te doen

| Onderdeel | Plan |
|---|---|
| Home Assistant, MQTT, webhooks | dezelfde code als de Mac, in C# (WebSocket- en MQTT-client) |
| Plugins | zelfde `plugin.json`; `run.windows` (bijv. `py -3`) |
| Vergaderknop | Teams/Zoom herkennen; sneltoetsen als `keysWindows` in `shared/catalog/shortcuts.json` |
| Agenda | Outlook / Microsoft Graph |
| Contextpagina's | `SetWinEventHook(EVENT_SYSTEM_FOREGROUND)` → procesnaam |
| `cyberpad.local` | DNS-SD (`DnsServiceRegister`); nu werkt het IP-adres uit het koppelvenster |
| Ondertekening | code-signing-certificaat, zodat SmartScreen niet meer waarschuwt |

## Bestanden

| Waar | Wat |
|---|---|
| `%APPDATA%\Cyberpad\layout.json` | je layout (zelfde formaat als op de Mac) |
| `%APPDATA%\Cyberpad\devices.json` | gekoppelde tablets (alleen hashes van tokens) |
| `%APPDATA%\Cyberpad\settings.json` | taal |
| `%APPDATA%\Cyberpad\Icons\` | eigen tegel-afbeeldingen |
| `C:\Program Files\Cyberpad\` | het programma en `shared\` |

## Bouwen

Lukt ook vanaf macOS of Linux (alleen draaien kan niet):

```
dotnet publish windows/Cyberpad -c Release -o windows/build/app
```

Op Windows maakt [Inno Setup 6](https://jrsoftware.org/isinfo.php) daarna de installer:

```
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DAppVersion=0.1.0 windows\installer\Cyberpad.iss
```

GitHub Actions ([.github/workflows/windows.yml](../.github/workflows/windows.yml)) doet beide bij elke push naar `main` die
`windows/` of `shared/` raakt. Een tag `windows-v<versie>` (bijv. `windows-v0.1.1`) maakt er een Release van.

Testen zonder installer: `dotnet run --project windows/Cyberpad` op Windows. Zet `CYBERPAD_SHARED_DIR` om een andere
`shared\`-map te gebruiken.

## Aandachtspunten

- **Firewall:** de installer zet een regel voor Cyberpad, alleen voor privé- en domeinnetwerken. Op een netwerk dat in
  Windows op *Openbaar* staat, kan de tablet niet verbinden.
- **Programma's met beheerdersrechten** ontvangen geen toetsen van Cyberpad (UIPI). Dat is een beveiliging van Windows.
- **Mac-layout gebruiken:** kopieer `layout.json` naar `%APPDATA%\Cyberpad\`. Mac-apps (`com.apple.Safari`) en
  Opdrachten werken op Windows niet; vervang ze in de editor.
