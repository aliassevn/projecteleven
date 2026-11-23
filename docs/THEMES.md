# Thema's

Het uiterlijk van de tablet komt uit twee delen:

1. **Sjabloon** `shared/pad/pad.css`: de stijl van de tablet, maar met kleurnamen in plaats van kleuren.
2. **Thema** `shared/themes/<id>.json`: welke kleuren, welk lettertype, hoeveel afronding en welke effecten.

De computer vult het sjabloon in en serveert het als `GET /pad.css`. Zo zijn er geen CSS-variabelen nodig en
werkt het ook in Safari uit iOS 9. macOS en Windows doen precies hetzelfde.

## Thema-bestand

```json
{
  "id": "cyberdeck",
  "name": "Cyberdeck",
  "description": "Neon cyaan en magenta …",
  "colors": { "bg": "#05060a", "bg2": "#12040e", "text": "#c8fff6", "accent": "#00ffe0", "accent2": "#ff2bd6",
              "accent2Text": "#ff9cf0", "danger": "#ff3b5c", "dangerText": "#ff8199", "ok": "#00ffa3", "okText": "#7dffb0" },
  "font": "Menlo, \"SF Mono\", Consolas, monospace",
  "radius": 0,
  "effects": { "scanlines": true, "glow": true, "grid": true, "corner": true, "glitch": true, "upper": true, "bold": false }
}
```

| Kleur | Gebruikt voor |
|---|---|
| `bg`, `bg2` | achtergrond, achtergrond van meldingen |
| `text` | tekst (vaak met doorzichtigheid) |
| `accent` | randen, waarden, gewone knoppen |
| `accent2`, `accent2Text` | knoppen die **aan** staan, vergaderpaneel |
| `danger`, `dangerText` | fouten, verbinding weg, "gevaarlijk" |
| `ok`, `okText` | online-stip, terminaluitvoer |

| Effect | Aan = |
|---|---|
| `scanlines` | lichte scanlijnen over het scherm |
| `glow` | gloed rond randen en tekst |
| `grid` | raster op de achtergrond |
| `corner` | schuine hoek rechtsboven op tegels |
| `glitch` | af en toe een glitch op de naam en bij indrukken |
| `upper` | labels in HOOFDLETTERS |
| `bold` | vette labels (handig bij dunne letters zoals Courier) |

## Sjabloon invullen (voor wie een eigen server bouwt)

- `{{naam}}` → de waarde: een kleur (`#rrggbb`), `font` of `radius`.
- `{{naam 0.45}}` → `rgba(r,g,b,0.45)` van die kleur.
- Onbekende kleur → `transparent`.

De tablet krijgt in de layout `themeClasses` (bijv. `"fx-noscan fx-nogrid fx-bold"`) voor de effecten, en
`themeKey`: verandert die, dan laadt de tablet `pad.css?v=<themeKey>` opnieuw zonder te flikkeren.

## Eigen aanpassingen

In de editor (**THEMA**) kies je een thema en pas je kleuren, lettertype, afronding en effecten aan. Dat komt
als `themeOverrides` in de layout (en gaat dus mee in een `.cyberpad`-export):

```json
"theme": "minimal",
"themeOverrides": { "colors": { "accent": "#0f9d58" }, "radius": 4, "effects": { "glow": true } }
```

De computer controleert alles: kleuren alleen als `#rrggbb`, een lettertype alleen met letters, cijfers, spaties,
komma's en aanhalingstekens, en een afronding van 0–30. Zo kan een layout geen eigen CSS binnensmokkelen.

Een nieuw thema voor iedereen: zet een `.json`-bestand in `shared/themes/` en bouw de app opnieuw.

## Lettertypen

De thema's gebruiken lettertypen die al op iPad, Mac en Windows staan (Menlo, Courier New, Avenir Next Condensed,
Futura, Helvetica, Segoe UI…). Er hoeft dus niets gedownload te worden en het werkt offline. Ontbreekt het eerste
lettertype, dan gebruikt het apparaat het volgende uit de lijst.

## Iconen

Een tegel kan als `icon` hebben:

| Waarde | Toont |
|---|---|
| `"💡"` of tekst | emoji of tekst |
| `"app:com.apple.Safari"` | het icoon van die app op de computer |
| `"img:<16 hex>.png"` | een eigen afbeelding, geüpload in de editor (max. 700 KB, verkleind tot 256 px) |

Afbeelding-iconen haalt de tablet op via `GET /api/icon?src=…` (met token). Eigen afbeeldingen staan in
`~/Library/Application Support/Cyberpad/Icons/`. Een tegel kan ook een eigen `color` (`#rrggbb`) hebben.
