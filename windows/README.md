# Cyberpad for Windows 10/11

The same tablet page, editor, themes and languages as on the Mac, with a program of its own for Windows in
C# / .NET 8. Cyberpad runs as an icon in the notification area (bottom right, next to the clock).

**Download:** see [Releases](https://github.com/aliassevn/projecteleven/releases) (`CyberpadSetup-<version>.exe`).
Installing and first steps: [RELEASE_NOTES.md](RELEASE_NOTES.md).

> **Smart App Control:** the installer is not yet code-signed. On a Windows 11 PC with Smart App Control turned on,
> Windows blocks Cyberpad ("An Application Control policy has blocked this file"). Code signing is planned.

## What already works (version 0.1)

| Part | Windows |
|---|---|
| Server | Kestrel (HTTP + WebSocket) on port 7420, local network only; no administrator rights needed |
| Pairing | pairing window with address, QR code and a 6-digit code (same rules as the Mac) |
| Tablet page, editor, themes, languages | from `shared\` (the same files as the Mac); the editor in a WebView2 window |
| Media, volume, mic | `SendInput` (media keys) and Core Audio (`IAudioEndpointVolume`) |
| Keys and text | `SendInput`; `cmd` becomes Ctrl, `win` = Windows key; text as Unicode |
| Apps | name from the Start menu, path to an `.exe`/`.lnk`, or a name Windows knows (`notepad`) |
| Links | default browser or a chosen browser (`StartMenuInternet` in the registry) |
| System | lock, display off, screenshot (Win+PrtSc / Win+Shift+S), keep awake, dark mode |
| Widgets | clock, world clock, weather, timer, pomodoro, system, now playing (Windows media controls), photos, terminal (`cmd`) |
| Touchpad and dials | `SendInput` with mouse and scroll wheel |
| Icons | `app:<name>` via the Windows Shell (`IShellItemImageFactory`); custom images like on the Mac |
| Profiles | time rules and a fixed profile per tablet |

## Still to do

| Part | Plan |
|---|---|
| Home Assistant, MQTT, webhooks | the same logic as the Mac, in C# (WebSocket and MQTT clients) |
| Plugins | the same `plugin.json`; `run.windows` (e.g. `py -3`) |
| Meeting button | detect Teams/Zoom; keyboard shortcuts as `keysWindows` in `shared/catalog/shortcuts.json` |
| Calendar | Outlook / Microsoft Graph |
| Context pages | `SetWinEventHook(EVENT_SYSTEM_FOREGROUND)` → process name |
| `cyberpad.local` | DNS-SD (`DnsServiceRegister`); for now use the IP address from the pairing window |
| Signing | a code-signing certificate, so SmartScreen and Smart App Control accept the installer |

## Files

| Where | What |
|---|---|
| `%APPDATA%\Cyberpad\layout.json` | your layout (same format as on the Mac) |
| `%APPDATA%\Cyberpad\devices.json` | paired tablets (only token hashes) |
| `%APPDATA%\Cyberpad\settings.json` | language |
| `%APPDATA%\Cyberpad\Icons\` | custom tile images |
| `C:\Program Files\Cyberpad\` | the program and `shared\` |

## Building

Also works from macOS or Linux (only running it does not):

```
dotnet publish windows/Cyberpad -c Release -o windows/build/app
```

On Windows, [Inno Setup 6](https://jrsoftware.org/isinfo.php) then makes the installer:

```
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DAppVersion=0.1.0 windows\installer\Cyberpad.iss
```

GitHub Actions ([.github/workflows/windows.yml](../.github/workflows/windows.yml)) does both on every push to `main`
that touches `windows/` or `shared/`. A tag `windows-v<version>` (e.g. `windows-v0.1.1`) turns it into a Release.

Testing without the installer: `dotnet run --project windows/Cyberpad` on Windows. Set `CYBERPAD_SHARED_DIR` to use a
different `shared\` folder.

## Notes

- **Firewall:** the installer adds a rule for Cyberpad, only for private and domain networks. On a network that
  Windows treats as *Public*, the tablet cannot connect.
- **Programs running as administrator** do not receive keys from Cyberpad (UIPI). That is a Windows security feature.
- **Using a Mac layout:** copy `layout.json` to `%APPDATA%\Cyberpad\`. Mac apps (`com.apple.Safari`) and Shortcuts do
  not work on Windows; replace them in the editor.
