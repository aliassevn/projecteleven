# Themes

The look of the tablet comes from two parts:

1. **Template** `shared/pad/pad.css`: the tablet's style, but with colour names instead of colours.
2. **Theme** `shared/themes/<id>.json`: which colours, which font, how much corner radius and which effects.

The computer fills in the template and serves it as `GET /pad.css`. The editor works the same way:
`shared/editor/editor.css` is a template too (`GET /editor/editor.css`), so the editor looks like the chosen theme.
No CSS variables are needed, so it also works in Safari on iOS 9. macOS and Windows do exactly the same.

## Theme file

```json
{
  "id": "cyberdeck",
  "name": "Cyberdeck",
  "description": "Neon cyan and magenta …",
  "colors": { "bg": "#05060a", "bg2": "#12040e", "text": "#c8fff6", "accent": "#00ffe0", "accent2": "#ff2bd6",
              "accent2Text": "#ff9cf0", "danger": "#ff3b5c", "dangerText": "#ff8199", "ok": "#00ffa3", "okText": "#7dffb0" },
  "font": "Menlo, \"SF Mono\", Consolas, monospace",
  "radius": 0,
  "effects": { "scanlines": true, "glow": true, "grid": true, "corner": true, "glitch": true, "upper": true, "bold": false }
}
```

| Colour | Used for |
|---|---|
| `bg`, `bg2` | background, background of notices |
| `text` | text (often with transparency) |
| `accent` | borders, values, ordinary buttons |
| `accent2`, `accent2Text` | buttons that are **on**, meeting panel |
| `danger`, `dangerText` | errors, connection lost, "dangerous" |
| `ok`, `okText` | online dot, terminal output |
| `panel`, `panelBorder` | *optional:* background and border of widgets, sliders and dials |
| `button`, `buttonText`, `buttonBorder` | *optional:* ordinary buttons (e.g. white with dark text) |
| `buttonActive`, `buttonActiveText` | *optional:* buttons that are on |

If a theme leaves out the optional colours, they are derived from the others: panel and button are `accent` at 4%
opacity with a 45% border, button text is `text` at 75%, "on" is `accent2` at 12%. That way older themes look exactly
the same.

| Effect | On = |
|---|---|
| `scanlines` | light scanlines over the screen |
| `glow` | glow around borders and text |
| `grid` | grid on the background |
| `corner` | cut corner at the top right of tiles |
| `glitch` | an occasional glitch on the name and when pressing |
| `upper` | labels in UPPERCASE |
| `bold` | bold labels (handy with thin fonts such as Courier) |

## Filling in the template (if you build your own server)

- `{{name}}` → the value: a colour (`#rrggbb`), `font` or `radius`.
- `{{name 0.45}}` → `rgba(r,g,b,0.45)` of that colour.
- Unknown colour → `transparent`.
- Optional colours that the theme leaves out are derived first (see above); such a derived colour is already
  `rgba(…)` and is used without extra transparency.

The tablet receives `themeClasses` in the layout (e.g. `"fx-noscan fx-nogrid fx-bold"`) for the effects, and
`themeKey`: when it changes, the tablet reloads `pad.css?v=<themeKey>` without flickering.

## Your own adjustments

In the editor (**THEME**) you choose a theme and adjust colours, font, corner radius and effects. That is stored as
`themeOverrides` in the layout (and so travels along in a `.cyberpad` export):

```json
"theme": "minimal",
"themeOverrides": { "colors": { "accent": "#0f9d58" }, "radius": 4, "effects": { "glow": true } }
```

The computer checks everything: colours only as `#rrggbb`, a font only with letters, digits, spaces, commas and quotes,
and a corner radius of 0–30. That way a layout cannot smuggle in CSS of its own.

A new theme for everyone: put a `.json` file in `shared/themes/` and rebuild the app.

## Bundled themes

| Theme | Character |
|---|---|
| Cyberdeck | neon cyan/magenta, scanlines, glitch, mono |
| Terminal | green phosphor on black, bold |
| Cockpit | amber on dark grey, narrow letters |
| Vapor | purple/pink/mint, rounded, glow |
| Minimal | light, blue accents |
| Night | black with white round buttons, orange for "on" |
| Graphite | dark grey like iPadOS, blue and green |
| Contrast | black with yellow buttons and bold letters, for maximum legibility |
| Ocean | deep blue, turquoise, glassy round buttons |

(Theme names and descriptions are translated in the app; the files keep their Dutch names as keys.)

## Fonts

The themes use fonts that already ship with iPad, Mac and Windows (Menlo, Courier New, Avenir Next Condensed, Futura,
Helvetica, Segoe UI…). Nothing needs downloading and it works offline. If the first font is missing, the device uses
the next one in the list.

## Icons

A tile can have as `icon`:

| Value | Shows |
|---|---|
| `"💡"` or text | emoji or text |
| `"app:com.apple.Safari"` | the icon of that app on the computer (on Windows: the name from the Start menu) |
| `"img:<16 hex>.png"` | your own image, uploaded in the editor (max. 700 KB, scaled down to 256 px) |

The tablet fetches image icons via `GET /api/icon?src=…` (with its token). Custom images are stored in
`~/Library/Application Support/Cyberpad/Icons/` (Windows: `%APPDATA%\Cyberpad\Icons\`). A tile can also have its own
`color` (`#rrggbb`).
