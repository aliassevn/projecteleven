# Writing plugins

A plugin adds actions and widgets to Cyberpad without changing the app itself. A plugin is a folder with a
`plugin.json` and a program in a language of your choice. The same format works on macOS and (later) on Windows.

## Where

| | macOS | Windows (planned) |
|---|---|---|
| Your plugins | `~/Library/Application Support/Cyberpad/Plugins/<folder>/` | `%APPDATA%\Cyberpad\Plugins\<folder>\` |
| Bundled | inside the app (`shared/plugins/` in the repo) | same |
| Plugin data | `…/Cyberpad/PluginData/<id>/` → `CYBERPAD_DATA_DIR` | `%APPDATA%\Cyberpad\PluginData\<id>\` |

Cyberpad notices new or changed plugins within a few seconds.

## Security

- A plugin runs as a **separate program with your permissions**. That is why every plugin starts **off**.
  Turn it on in the menu bar › Plugins › *Turn on…*.
- When you turn it on, Cyberpad stores a **fingerprint** (SHA-256) of all files in the plugin folder.
  If anything changes afterwards, the plugin no longer starts until you allow it again.
- The plugin gets a minimal environment: `PATH`, `HOME`, `USER`, `LANG`, `TMPDIR` and the `CYBERPAD_*` variables
  below; no tokens or other Cyberpad secrets.
- The tablet can only use actions and widgets that are in `plugin.json` **and** in your layout. It can never make up a
  program or parameter of its own.
- Whatever a plugin sends to the tablet is filtered down to fixed fields with maximum lengths (see *Widgets*).
  The tablet never runs plugin code.

## `plugin.json`

```json
{
  "id": "hallo",
  "name": "Hello world",
  "version": "1.0.0",
  "description": "Example",
  "author": "You",
  "icon": "👋",
  "run": {
    "macos":   ["/usr/bin/python3", "plugin.py"],
    "windows": ["py", "-3", "plugin.py"],
    "default": ["python3", "plugin.py"]
  },
  "actions": [
    { "id": "groet", "name": "Greet",
      "params": [{ "id": "naam", "name": "Name", "type": "string", "default": "world" }] }
  ],
  "widgets": [
    { "id": "teller", "name": "Counter", "interval": 30,
      "params": [{ "id": "stap", "type": "number", "default": 1 }] }
  ]
}
```

- `id` (and the ids of actions and widgets): lowercase letters, digits and `-`, max. 40 characters.
- `run`: the command per platform; `default` when there is no specific one. A name without `/` (such as `python3`) is
  looked up in `PATH`; a relative path (`./myprogram`) is relative to the plugin folder. The working directory is the
  plugin folder.
- `params`: description for the editor; `default` is sent when the layout does not fill in a value.
- `interval`: how often Cyberpad asks for widget data (1–3600 s, default 10). Only while a tablet is connected.

## In the layout

```json
{ "id": "hi", "label": "Say hello", "x": 0, "y": 0,
  "action": { "type": "plugin", "plugin": "hallo", "action": "groet", "params": { "naam": "Cyberpad" } } }

{ "id": "count", "label": "Counter", "kind": "plugin", "x": 1, "y": 0, "w": 2,
  "config": { "plugin": "hallo", "widget": "teller", "params": { "stap": 5 } } }
```

A plugin action can also be a `longPress` or `doubleTap`, a step in a `macro`, or part of an on/off button.

## Messages

One JSON object per line (UTF-8, terminated by `\n`) over **stdin** (from Cyberpad) and **stdout** (to Cyberpad).
Write log lines to **stderr** or as a `log` message, never loose on stdout. Remember to flush
(`PYTHONUNBUFFERED=1` is already set).

### Cyberpad → plugin

| Message | When |
|---|---|
| `{"type":"hello","version":1,"host":"Cyberpad","platform":"macos","dataDir":"…"}` | right after starting |
| `{"type":"invoke","id":7,"action":"groet","params":{…},"tile":"hi","gesture":"tap"}` | button pressed |
| `{"type":"widget","id":8,"widget":"teller","tile":"count","params":{…}}` | widget needs new data |
| `{"type":"widgetAction","id":9,"widget":"teller","tile":"count","action":"plus","value":1?,"params":{…}}` | button on the widget |

### Plugin → Cyberpad

| Message | Meaning |
|---|---|
| `{"type":"result","id":7,"ok":true}` | reply to `invoke`, within 10 s |
| `{"type":"result","id":8,"ok":true,"data":{…}}` | reply to `widget` / `widgetAction` with widget data |
| `{"type":"result","id":9,"ok":false,"error":"…"}` | failed; the text is shown as a message |
| `{"type":"update","tile":"count","data":{…}}` | send new widget data unprompted |
| `{"type":"toast","text":"…"}` | message on the tablet |
| `{"type":"log","text":"…"}` | line in the Cyberpad log |

No reply within 10 s counts as an error. If the plugin stops unexpectedly, Cyberpad retries later
(after 2, 4, 8 … up to 60 s).

### Widgets

The tablet draws a fixed tile with these fields (all optional):

| Field | Type | Shows |
|---|---|---|
| `title` | text (200) | heading (otherwise the tile's label) |
| `icon` | text | emoji before the heading |
| `value` + `unit` | text/number | large value |
| `sub` | text | line below the value |
| `progress` | 0…1 | bar |
| `active` | bool | value in the accent colour |
| `lines` | max. 8 × `{label, value}` | small table |
| `buttons` | max. 4 × `{id, label}` | buttons; a tap sends `widgetAction` with that `id` |
| `error` | text | error message (tile turns grey) |

## Examples

- `shared/plugins/hallo/`: an action with a message and a counter widget with buttons (Python, standard library only).
- `shared/plugins/bereikbaar/`: checks whether a server is reachable and how fast.

Testing without Cyberpad:

```bash
printf '%s\n' '{"type":"widget","id":1,"widget":"teller","tile":"t","params":{}}' | python3 shared/plugins/hallo/plugin.py
```
