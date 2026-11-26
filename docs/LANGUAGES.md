# Languages

Cyberpad works in **English** (default), **Dutch** and **Spanish**. The language applies to everything at once: the
menu bar window on the Mac (or the tray menu on Windows), all tablets and the editor.

## Switching

- **Mac:** menu bar window › at the bottom **Language / Taal / Idioma**. **Windows:** tray icon › **Language**.
- **Tablet:** ⚙ › **Language**.
- **Editor:** **MORE ▾** › 🌐 English / Nederlands / Español.

After a switch the tablets reload themselves. The editor reloads too; if it still has unsaved changes, it stays as it
is and asks you to save first.

## Your own names

Names of pages, tiles and profiles are yours and are not translated. Exception: if a name from the default layout is
still there (e.g. "Knoppen", "Geluid uit", "Werkdag"), the tablet shows it in the chosen language.
The editor always shows the name as it is stored in `layout.json`.

## How it works

- In the code, the **Dutch text is the key** (the project started in Dutch): `L("Geen internet")` in Swift and C#,
  `T('Geen internet')` in `pad.js` and `editor.js`, and `data-t` / `data-t-title` / `data-t-ph` in the HTML.
- `shared/i18n/en.json` and `shared/i18n/es.json` give the translation per key. If one is missing, the Dutch text
  stays. `{0}`, `{1}`… are placeholders.
- Names and labels from `shared/editor/schema.json`, keyboard shortcuts from `shared/catalog/shortcuts.json` and the
  names and descriptions of the themes are translated through the same dictionary.
- The computer serves the dictionary as `GET /i18n.js` (see [PROTOCOL.md](PROTOCOL.md)); the Windows version uses the
  same files.

## Checking or adding a language

```bash
python3 macos/scripts/i18n-keys.py
```

This finds every text in the code (Mac, Windows, tablet page and editor) and reports per language what is missing,
what is superfluous and where a placeholder does not match. To add a language: create `shared/i18n/<code>.json`, add the
code to `Localizer.languages` (Swift), `I18n.Languages` (C#), `LANGS` (editor) and the language choice on the tablet
(`SETTING_ROWS` in `pad.js`), and add it in `i18n-keys.py`.
