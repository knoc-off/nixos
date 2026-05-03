# marki-map

Renders fenced ` ```map ` blocks in markdown cards to one SVG per layer
plus a JSON sidecar, ready to be uploaded to Anki's media collection
by the `markid` daemon.

## TL;DR

````markdown
What German state is highlighted in red?

```map
[layers.base]
features = ["country/DEU"]
context = ["neighbors/DEU"]

[layers.answer]
highlights = ["admin1/DEU/Bavaria"]
```

---

**Bavaria** (Bayern).

#geography
````

That's the whole authoring loop for the most common pattern
(country-outline-with-region-highlight):

1. The `base` layer draws Germany and its neighbours.
2. The `answer` layer highlights Bavaria.
3. The renderer emits `base.svg` and `answer.svg` and embeds both
   `<img>`s in the card.
4. CSS hides the answer layer on the front (`opacity: 0`) and
   transitions it to `opacity: 1` on the back. No JavaScript.

## DSL

The block body is TOML.

| Field         | Type                  | Notes                                                    |
|---------------|-----------------------|----------------------------------------------------------|
| `size`        | `[u32, u32]`          | Optional; defaults to `[600, 400]` — see "Canvas sizing" |
| `style`       | string                | Theme name; defaults to `atlas` (only one bundled)       |
| `layers`      | table (required)      | At least one layer; see below                            |

### Canvas sizing

`size = [W, H]` is a *maximum budget*. The renderer projects the
data's bbox under Mercator, computes its aspect ratio, and chooses the
largest canvas with that aspect that still fits inside `[W, H]`. So a
wide region with a 600×400 budget may render as 600×280, and a tall
region as 280×400 — there's never any letterboxing.

If you omit `size`, the renderer uses `[600, 400]` as the budget.

The map embed itself is **responsive**: the container caps at
`max-width: <W>px` and uses CSS `aspect-ratio` to scale down
proportionally on narrower viewports — so a 600×280 map fits on an
Anki phone card without horizontal scroll, and the SVG re-renders
crisply at any size.

Each entry in `[layers.<name>]`:

| Field        | Type           | Notes                                                            |
|--------------|----------------|------------------------------------------------------------------|
| `features`   | `[string]`     | Geometry references to draw; define the viewport bbox            |
| `context`    | `[string]`     | Geometry drawn for visual context; excluded from viewport bbox   |
| `highlights` | `[string]`     | Feature references drawn with the theme's `highlight` role       |
| `reveal`     | `none`/`fade`  | Default: base layer = none, others = fade                       |
| `style`      | table          | Optional per-layer highlight style override (see below)         |

### Per-layer style override

Any layer can override the theme's `highlight` role styling via a
`[layers.<name>.style]` sub-table. Unset fields inherit from the
active theme.

```toml
[layers.answer]
highlights = ["admin1/DEU/Bavaria"]
[layers.answer.style]
fill = "#3388ff"
stroke = "#1a5599"
stroke_width = 2.0
```

## Feature references

The renderer understands these reference shapes:

- `coastline` — every coastline polyline from Natural Earth.
- `country/<ISO_A3>` — one country by three-letter ISO code (`DEU`,
  `FRA`, `JPN`, …). Source: Natural Earth `ne_10m_admin_0_countries`.
  Always returns the full geometry; outlying components (Alaska,
  French Guiana, Chatham Islands, …) are drawn but the viewport is
  auto-focused on the main cluster — see "Auto-focus" below.
- `admin1/<ISO_A3>/<NAME>` — one admin-1 entry inside a country
  (province, state, oblast, …). Indexed by both `name_en` and
  `name` (case-insensitive). Source: Natural Earth
  `ne_10m_admin_1_states_provinces`.
- `region/<ISO_A3>/<NAME>` — composite of all admin-1 entries whose
  NE `region` column matches `<NAME>` (case-insensitive). Use this
  for Italian regioni (`region/ITA/Sicily`), French régions
  (`region/FRA/Île-de-France`), etc. Not all countries populate this
  column; see "admin1 vs. region" below.
- `neighbors/<ISO_A3>` — every country that shares a border with
  the target (topological adjacency). Falls back to bbox-intersect
  for island nations with no shared edges. Source: Natural Earth.
- `continent/<NAME>` — composite of all countries whose NE
  `CONTINENT` column matches (case-insensitive). Values: `Africa`,
  `Antarctica`, `Asia`, `Europe`, `North America`, `Oceania`,
  `South America`.
- `subregion/<NAME>` — composite of all countries whose NE
  `SUBREGION` column matches (case-insensitive). Values include
  `Western Europe`, `Eastern Europe`, `Southern Europe`,
  `Northern Europe`, `Northern Africa`, `Central America`,
  `South-Eastern Asia`, etc. (~20 UN subregions).
- `relation/<N>` and `way/<N>` — fetched from
  [Overpass](https://overpass-api.de/) and cached
  content-addressably. Use this when Natural Earth's admin-1
  boundaries don't match the political boundary you want.

## Auto-focus

Most countries with overseas territories (USA + Alaska + Hawaii,
France + Corsica + Guiana, NZ + Chatham, …) would otherwise produce
a viewport so wide that the main landmass is a tiny dot.

The renderer auto-focuses on the **main cluster** of polygon
components: it picks the largest by area as a seed and pulls in any
component whose bbox lies within `0.3 ×` the seed's diagonal.

Concretely:

- `country/USA` → CONUS + Alaska + Aleutians (Hawaii drawn but clipped).
- `country/FRA` → Metropolitan France + Corsica (Guiana drawn but clipped).
- `country/NZL` → North + South Islands (Chatham drawn but clipped).
- `country/ITA` → Peninsula + Sicily + Sardinia.
- `country/DEU`, `country/POL`, `country/CHE` → unchanged (single component).

If you explicitly highlight an outlying region — say
`highlights = ["admin1/USA/Hawaii"]` over a `country/USA` base — the
viewport stretches to include the highlight, so your answer never
gets clipped.

Geometry is **never thrown away**. Outlying islands always render;
they just fall outside the SVG viewBox in the unfocused case.

## World-wrapping

For maps that span the antimeridian (NZ + Fiji, Russia + Alaska, …)
the renderer picks an optimal central meridian so the data forms a
contiguous coordinate range — no more 350°-wide bboxes that fill the
canvas with empty ocean. Authors don't need to think about this;
write `features = ["country/NZL", "country/FJI"]` and you'll get a
tight Pacific view.

### admin1 vs. region

NE's `ne_10m_admin_1_states_provinces` has two useful name tiers:

- **`admin1/<ISO>/<NAME>`** resolves a single entry (e.g. one
  Italian province like `admin1/ITA/Milan` or one US state like
  `admin1/USA/Texas`).
- **`region/<ISO>/<NAME>`** merges every entry whose `region`
  column matches — giving you the *composite outline* of e.g.
  all Sicilian provinces (`region/ITA/Sicily`).

Use `admin1` for federal first-order divisions (US states, German
Länder, Russian oblasts — NE doesn't populate `region` for these).
Use `region` for sub-national groupings (Italian regioni, French
régions, Spanish autonomous communities).

See **Finding feature IDs** below for how to look these up in practice.

## Finding feature IDs

When you author a `map` block you'll mostly be filling in three kinds
of references. Here's how to find each.

### `country/<ISO_A3>`

Three-letter codes from ISO 3166-1 alpha-3 (with a few Natural-Earth
extras for unrecognised territories).

- Quick reference: <https://en.wikipedia.org/wiki/ISO_3166-1_alpha-3>
- Cheatsheet for common ones:
  `DEU FRA GBR ITA ESP NLD BEL CHE AUT POL CZE`
  `SWE NOR FIN DNK IRL PRT GRC TUR UKR RUS`
  `USA CAN MEX BRA ARG CHL JPN CHN KOR IND IDN AUS NZL ZAF EGY`

### `admin1/<ISO_A3>/<NAME>` and `region/<ISO_A3>/<NAME>`

`<NAME>` matches NE's `name_en` or `name` (case-insensitive, both
are tried). For many countries that's the standard English name —
`Bavaria`, not `Bayern`; `Hesse`, not `Hessen`. Local names (e.g.
`Hovedstaden` for the Capital Region of Denmark) also work because
the `name` column is indexed.

To list entries for a given country (inside `nix develop .#marki`
where gdal + `NATURAL_EARTH_DATA` are available):

```sh
# Admin-1 entries (provinces, states, …):
ogrinfo -geom=NO -where "adm0_a3='ITA'" \
  "$NATURAL_EARTH_DATA/ne_10m_admin_1_states_provinces.shp" \
  ne_10m_admin_1_states_provinces \
  | grep -E "^  (name_en|name) "

# Region groupings:
ogrinfo -geom=NO -where "adm0_a3='ITA'" \
  "$NATURAL_EARTH_DATA/ne_10m_admin_1_states_provinces.shp" \
  ne_10m_admin_1_states_provinces \
  | grep -E "^  region " | sort -u
```

Swap `ITA` for whichever country you're after.

### `relation/<N>` and `way/<M>`

These come straight from OpenStreetMap. Use them when you need a
boundary NE doesn't carry — a city, a neighbourhood, a lake, a park,
a custom multipolygon.

The fastest workflow:

1. Search at <https://www.openstreetmap.org/>.
2. Click your result. The URL becomes
   `…/relation/2145268` (Bavaria) or `…/way/29094425`
   (Lake Constance) — copy the number and the type.
3. Paste as `relation/2145268` or `way/29094425` into your map block.

For programmatic / batch use, [Nominatim] returns `osm_type` +
`osm_id` per hit:

```sh
curl 'https://nominatim.openstreetmap.org/search?q=Bavaria&format=jsonv2' \
  | jq '.[] | {osm_type, osm_id, display_name}'
```

If you want to *experiment* with an Overpass query before committing
an ID, try [overpass-turbo].

[Nominatim]: https://nominatim.openstreetmap.org/ui/search.html
[overpass-turbo]: https://overpass-turbo.eu

### `coastline` and `neighbors/<ISO>`

No lookup needed:

- `coastline` is parameter-free — every Natural-Earth coastline line.
  The projection's bbox crops it to whatever else you've drawn.
- `neighbors/<ISO>` takes the same ISO as `country/<ISO>`. Uses
  topological adjacency (shared boundary segments) to determine true
  neighbours. Falls back to bbox-intersect for island nations with
  no shared edges in the dataset.

## Reveal model (M1)

The renderer emits one `<img>` per layer, stacked absolutely. CSS
controls visibility via `data-reveal`:

- `data-reveal="none"` — always visible. The `base` layer defaults
  to this.
- `data-reveal="fade"` — `opacity: 0` on the front, `opacity: 1` on
  the back, with a 0.5s ease transition. Every non-base layer
  defaults to this.

To override the default, set `reveal = "none"` (always visible) or
`reveal = "fade"` (always faded-in-on-back) on the layer.

The renderer returns a `back_html_extras` chunk (`<style>` block
overriding to `opacity: 1`); the `markid` daemon appends it to the
card's back HTML.

## CLI: theme iteration without Anki

```sh
markid render-map path/to/card.md --out ./out
```

Writes the rendered SVGs and a `preview.html` to `./out/`. Handy when
fiddling with theme TOML — no AnkiConnect / sync round-trip needed.

## Dev shell

```sh
nix develop .#marki
```

Gives you `cargo`, `gdal` (for `ogrinfo`), `curl`, `jq`, and
`NATURAL_EARTH_DATA` pre-set. Useful for exploring admin-1 names and
regions without installing anything globally.

## Caching

Three layers of caching keep things fast and offline-friendly:

1. **Render cache** at `$XDG_CACHE_HOME/marki/render/<key>/`.
   Key = blake3(canonical TOML || theme bytes || `RENDER_VERSION_MAP`).
   On a hit, no resolve / project / compose work runs at all.
2. **Overpass cache** at `$XDG_CACHE_HOME/marki/net/overpass/`.
   Key = blake3(query string). Entries don't expire.
3. **Natural Earth bundle** delivered by Nix derivation
   (`pkgs.natural-earth-data`); the path is passed in via
   `NATURAL_EARTH_DATA`.

## Failure modes

The daemon never aborts the corpus on one bad map. When something
goes wrong (NE env unset, bad TOML, OSM 404, network down, …) the
renderer returns an error and the daemon splices a small red-bordered
`block failed:` `<div>` into the card so the issue is visible during
study without blocking unrelated cards.

## Limitations (current)

- Only outline mode (vector → SVG). Location mode (raster tiles +
  overlay SVG) not implemented.
- Only `none` and `fade` reveal modes. `draw-on` requires SMIL or
  per-path stroke-dashoffset animation; not in M1.
- Mercator (Web Mercator) only. The DSL doesn't yet allow choosing
  other projections; the equirectangular code path remains in tree
  for unit-test scaffolding but isn't a runtime option.
- The `region` column isn't populated for all countries in NE
  (e.g. US, Germany). For those, use `admin1` directly.

These are deliberate M1 cuts; see the RFC for the full vocabulary.
