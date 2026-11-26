**Cyberpad for Windows 10/11 — first test version.** Turn an old iPad or tablet into a macro pad for your PC.

## Installing

1. Download **CyberpadSetup-…exe** below and run it.
2. Windows will probably show **"Windows protected your PC"** (SmartScreen), because the installer is not yet
   code-signed. Click **More info** › **Run anyway**.
3. Leave **"Allow tablets on my home network to connect"** ticked: it opens the Windows Firewall for Cyberpad, on
   private networks only.
4. After installing, the pairing window appears with an address, a QR code and a pairing code. Open the address in
   Safari/Chrome on your tablet and enter the code.

The tablet and the PC must be on the same Wi-Fi network. If Windows treats the network as *Public*, set it to
*Private* (Settings › Network & internet).

**Smart App Control:** on a Windows 11 PC with Smart App Control turned on, Windows blocks this unsigned version
("An Application Control policy has blocked this file"). Code signing is planned; until then, use a PC without
Smart App Control.

## What already works

- Pairing, tablet page, themes, languages (English, Dutch, Spanish) and the layout editor (tray icon › *Edit layout…*,
  or on the tablet via ⚙).
- Media and volume buttons, volume and microphone sliders, mute, microphone off.
- Key combinations (`ctrl`, `shift`, `alt`, `win`; `cmd` from a Mac layout becomes Ctrl), typing text, macros, apps from
  the Start menu, links (default browser or a chosen browser).
- Lock, display off, screenshot, keep awake, dark mode.
- Widgets: clock, world clock, weather, timer, pomodoro, system (CPU/RAM/network/battery), now playing (Spotify,
  browsers, Media Player…), photos, terminal.
- Touchpad and dials.

## Not yet (next version)

Home Assistant, MQTT, webhooks, plugins, the meeting button, calendar and context pages per app. A layout from the Mac
works, but buttons with those actions report "not available on Windows yet".

Your data lives in `%APPDATA%\Cyberpad` and stays when you uninstall Cyberpad.
