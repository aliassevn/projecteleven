# Talen

Cyberpad werkt in het **Engels** (standaard), **Nederlands** en **Spaans**. De taal geldt voor alles tegelijk:
het menubalk-venster op de Mac, alle tablets en de editor.

## Wisselen

- **Mac:** menubalk-venster › onderaan **Language / Taal / Idioma**.
- **Tablet:** ⚙ › **Language**.
- **Editor:** **MORE ▾** › 🌐 English / Nederlands / Español.

Na een wissel laden de tablets zichzelf opnieuw. De editor op de Mac herlaadt ook; heb je daar nog niet-opgeslagen
wijzigingen, dan blijft hij staan en vraagt hij je eerst op te slaan.

## Jouw eigen namen

Namen van pagina's, tegels en profielen zijn van jou en worden niet vertaald. Uitzondering: staat er nog een naam
uit de standaard-layout (bijv. "Knoppen", "Geluid uit", "Werkdag"), dan toont de tablet die in de gekozen taal.
In de editor zie je altijd de naam zoals hij in `layout.json` staat.

## Hoe het werkt

- In de code is de **Nederlandse tekst de sleutel**: `L("Geen internet")` in Swift, `T('Geen internet')` in
  `pad.js` en `editor.js`, en `data-t` / `data-t-title` / `data-t-ph` in de HTML.
- `shared/i18n/en.json` en `shared/i18n/es.json` geven per sleutel de vertaling. Ontbreekt er een, dan blijft de
  Nederlandse tekst staan. `{0}`, `{1}`… zijn plaatshouders.
- Namen en labels uit `shared/editor/schema.json`, sneltoetsen uit `shared/catalog/shortcuts.json` en de namen en
  omschrijvingen van de thema's worden via hetzelfde woordenboek vertaald.
- De computer serveert het woordenboek als `GET /i18n.js` (zie [PROTOCOL.md](PROTOCOL.md)); de Windows-versie
  gebruikt dezelfde bestanden.

## Controleren of een taal toevoegen

```bash
python3 macos/scripts/i18n-keys.py
```

Dit zoekt alle teksten in de code en meldt per taal wat ontbreekt, wat overbodig is en waar een plaatshouder niet
klopt. Een nieuwe taal: maak `shared/i18n/<code>.json`, zet de code in `Localizer.languages` (Swift) en in `LANGS`
(editor) en de taalkeuze op de tablet (`SETTING_ROWS` in `pad.js`), en voeg de code toe in `i18n-keys.py`.
