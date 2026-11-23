# Plugins schrijven

Met een plugin voeg je acties en widgets aan Cyberpad toe zonder de app zelf te veranderen. Een plugin is
een map met een `plugin.json` en een programma in een taal naar keuze. Hetzelfde formaat werkt op macOS en
straks op Windows.

## Waar

| | macOS | Windows (gepland) |
|---|---|---|
| Jouw plugins | `~/Library/Application Support/Cyberpad/Plugins/<map>/` | `%APPDATA%\Cyberpad\Plugins\<map>\` |
| Meegeleverd | in de app (`shared/plugins/` in de repo) | idem |
| Gegevens van de plugin | `…/Cyberpad/PluginData/<id>/` → `CYBERPAD_DATA_DIR` | `%APPDATA%\Cyberpad\PluginData\<id>\` |

Cyberpad ziet nieuwe of gewijzigde plugins binnen een paar seconden.

## Veiligheid

- Een plugin draait als **apart programma met jouw rechten**. Daarom staat elke plugin eerst **uit**.
  Je zet hem aan in de menubalk › Plugins › *Aanzetten…*.
- Bij het aanzetten bewaart Cyberpad een **vingerafdruk** (SHA-256) van alle bestanden in de pluginmap.
  Verandert er daarna iets, dan start de plugin niet meer tot je hem opnieuw toestaat.
- De plugin krijgt een kleine omgeving: `PATH`, `HOME`, `USER`, `LANG`, `TMPDIR` en de `CYBERPAD_*`-variabelen
  hieronder, geen tokens of andere geheimen van Cyberpad.
- De tablet kan alleen acties en widgets gebruiken die in `plugin.json` staan **en** in je layout. Hij kan
  nooit zelf een programma of parameter verzinnen.
- Wat een plugin naar de tablet stuurt, wordt gefilterd tot vaste velden met maximale lengtes (zie *Widgets*).
  De tablet voert nooit code van een plugin uit.

## `plugin.json`

```json
{
  "id": "hallo",
  "name": "Hallo wereld",
  "version": "1.0.0",
  "description": "Voorbeeld",
  "author": "Jij",
  "icon": "👋",
  "run": {
    "macos":   ["/usr/bin/python3", "plugin.py"],
    "windows": ["py", "-3", "plugin.py"],
    "default": ["python3", "plugin.py"]
  },
  "actions": [
    { "id": "groet", "name": "Groet",
      "params": [{ "id": "naam", "name": "Naam", "type": "string", "default": "wereld" }] }
  ],
  "widgets": [
    { "id": "teller", "name": "Teller", "interval": 30,
      "params": [{ "id": "stap", "type": "number", "default": 1 }] }
  ]
}
```

- `id` (en de id's van acties en widgets): kleine letters, cijfers en `-`, max. 40 tekens.
- `run`: de opdracht per platform; `default` als er geen specifieke is. Een naam zonder `/` (zoals `python3`)
  wordt in `PATH` gezocht; een relatief pad (`./mijnprogramma`) vanuit de pluginmap. De werkmap is de pluginmap.
- `params`: beschrijving voor de (latere) editor; `default` wordt meegestuurd als de layout niets invult.
- `interval`: hoe vaak Cyberpad om widgetgegevens vraagt (1–3600 s, standaard 10). Alleen als er een tablet
  verbonden is.

## In de layout

```json
{ "id": "hoi", "label": "Zeg hallo", "x": 0, "y": 0,
  "action": { "type": "plugin", "plugin": "hallo", "action": "groet", "params": { "naam": "Sven" } } }

{ "id": "tel", "label": "Teller", "kind": "plugin", "x": 1, "y": 0, "w": 2,
  "config": { "plugin": "hallo", "widget": "teller", "params": { "stap": 5 } } }
```

Een plugin-actie kan ook als `longPress`, `doubleTap`, in een `macro` of in een aan/uit-knop staan.

## Berichten

Eén JSON-object per regel (UTF-8, afgesloten met `\n`) via **stdin** (van Cyberpad) en **stdout** (naar
Cyberpad). Schrijf logregels naar **stderr** of als `log`-bericht, nooit los naar stdout. Vergeet niet te flushen
(`PYTHONUNBUFFERED=1` staat al aan).

### Cyberpad → plugin

| Bericht | Wanneer |
|---|---|
| `{"type":"hello","version":1,"host":"Cyberpad","platform":"macos","dataDir":"…"}` | direct na het starten |
| `{"type":"invoke","id":7,"action":"groet","params":{…},"tile":"hoi","gesture":"tap"}` | knop ingedrukt |
| `{"type":"widget","id":8,"widget":"teller","tile":"tel","params":{…}}` | widget heeft nieuwe gegevens nodig |
| `{"type":"widgetAction","id":9,"widget":"teller","tile":"tel","action":"plus","value":1?,"params":{…}}` | knop op de widget |

### Plugin → Cyberpad

| Bericht | Betekenis |
|---|---|
| `{"type":"result","id":7,"ok":true}` | antwoord op `invoke`, binnen 10 s |
| `{"type":"result","id":8,"ok":true,"data":{…}}` | antwoord op `widget` / `widgetAction` met widgetgegevens |
| `{"type":"result","id":9,"ok":false,"error":"…"}` | mislukt; de tekst verschijnt als melding |
| `{"type":"update","tile":"tel","data":{…}}` | uit zichzelf nieuwe widgetgegevens sturen |
| `{"type":"toast","text":"…"}` | melding op de tablet |
| `{"type":"log","text":"…"}` | regel in het Cyberpad-log |

Geen antwoord binnen 10 s telt als fout. Stopt de plugin onverwacht, dan probeert Cyberpad het later opnieuw
(na 2, 4, 8 … tot 60 s).

### Widgets

De tablet tekent een vaste tegel met deze velden (alles optioneel):

| Veld | Type | Toont |
|---|---|---|
| `title` | tekst (200) | kop (anders het label van de tegel) |
| `icon` | tekst | emoji vóór de kop |
| `value` + `unit` | tekst/getal | grote waarde |
| `sub` | tekst | regel onder de waarde |
| `progress` | 0…1 | balk |
| `active` | bool | waarde in accentkleur |
| `lines` | max. 8 × `{label, value}` | kleine tabel |
| `buttons` | max. 4 × `{id, label}` | knoppen; een tik stuurt `widgetAction` met dat `id` |
| `error` | tekst | foutmelding (tegel wordt grijs) |

## Voorbeelden

- `shared/plugins/hallo/`: actie met melding en een teller-widget met knoppen (Python, alleen standaardbibliotheek).
- `shared/plugins/bereikbaar/`: meet of een server bereikbaar is en hoe snel.

Testen zonder Cyberpad:

```bash
printf '%s\n' '{"type":"widget","id":1,"widget":"teller","tile":"t","params":{}}' | python3 shared/plugins/hallo/plugin.py
```
