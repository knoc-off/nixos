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
highlights = ["adm1/DEU/Bayern"]
```

---

**Bavaria** (Bayern).

#geography
````

That's the whole authoring loop for the most common pattern
(country-outline-with-region-highlight):

1. The `base` layer draws Germany and its neighbours.
2. The `answer` layer highlights Bavaria (geoBoundaries ADM1 `Bayern`).
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
| `hull`       | table          | Makes this a *hull layer* — wraps features in a rounded hull (see below) |

### Per-layer style override

Any layer can override the theme's `highlight` role styling via a
`[layers.<name>.style]` sub-table. Unset fields inherit from the
active theme.

```toml
[layers.answer]
highlights = ["adm1/DEU/Bayern"]
[layers.answer.style]
fill = "#3388ff"
stroke = "#1a5599"
stroke_width = 2.0
```

### Hull layers (hard-to-spot landmasses)

Tiny island nations (Fiji, Tonga, Kiribati, the eastern-Caribbean
microstates) are almost invisible on a regional map. A **hull layer**
wraps each referenced feature in a *rounded convex hull* — the convex
hull of the feature's vertices, expanded outward with rounded corners —
so the whole region (every island of an archipelago) is enclosed in one
smooth, padded shape that's easy to find.

A hull layer is an ordinary layer: it stacks by TOML source order and
reveals like any overlay (`fade` by default). Place it where you want
it — typically above the base and below the real answer, so the island
draws on top of its hull.

```toml
[layers.base]
features = ["coastline"]

[layers.halo]
[layers.halo.hull]
features = ["country/FJI"]
# radius   = 0.04   # outward padding as a fraction of the viewport diagonal
# min_px   = 10     # hard pixel floor — keeps tiny islands visible
# max_frac = 0.20   # cap as a fraction of the diagonal
[layers.halo.style]            # optional; reuses the style override
fill = "#c64f3f55"             # translucent so the coast reads through

[layers.answer]
highlights = ["country/FJI"]   # the real island draws over its hull
```

The padding (and corner radius) is computed at render time as
`clamp(radius × diagonal, min_px, max_frac × diagonal)`, so the hull
keeps a roughly constant, always-spottable margin around the feature
with `min_px` as a hard floor. A single-vertex feature degenerates to a
circle. Antimeridian-spanning features (Fiji, Kiribati) are handled by
the same frame-rotation the rest of the pipeline uses. Hull references
must be polygon features; lines/points (e.g. `coastline`) have no area
and are skipped.

The hull `style` override and the `hull` theme role both control the
hull fill/stroke; the bundled `atlas` theme ships a translucent default.

## Project defaults & path rules

A marki project can set DSL defaults for every `map` block in its
`.markid/config.toml`, and override them per directory. This keeps cards
terse — set a theme or viewport tuning once, not in every block.

```toml
# Applies to every map card in the project.
[map.defaults]
style = "atlas"
[map.defaults.viewport]
simplify_px = 1.0

# Scope overrides to a glob, matched against the card path RELATIVE to
# cards_dir. Several matching rules layer in declaration order.
[[map.rules]]
match = "Geography/**"
[map.rules.defaults.viewport]
cluster_factor = 0.3

[[map.rules]]
match = "Geography/Africa/**"
[map.rules.defaults.viewport]
simplify_px = 0.8
```

**Precedence** (low → high): built-in DSL defaults → `[map.defaults]` →
every matching `[[map.rules]]` in order → the card's own `map` block. The
author always wins; a rule only fills in fields the card didn't set.

Merging is a recursive table merge: nested tables (`viewport`,
`layers.<name>.style`, …) merge key-wise, while scalars and arrays
(`size`, feature lists) replace wholesale. Because the merge feeds the
same `MapSpec` deserializer, an unknown key in a default is a hard error
that names the offending field — and changing a default re-renders the
affected cards (the render cache keys off the merged spec).

`match` uses [globset](https://docs.rs/globset) syntax: `**` spans
directories, so `Geography/**` matches every card under `Geography/`.

## Feature references

The renderer understands these reference shapes:

- `coastline` — every coastline polyline from Natural Earth.
- `country/<ISO_A3>` — one country by three-letter ISO code (`DEU`,
  `FRA`, `JPN`, …). Source: geoBoundaries gbOpen ADM0. Always returns
  the full geometry; outlying components (Alaska, French Guiana,
  Chatham Islands, …) are drawn but the viewport is auto-focused on
  the main cluster — see "Auto-focus" below.
- `adm1/<ISO_A3>/<NAME>`, `adm2/<ISO_A3>/<NAME>`, `adm3/<ISO_A3>/<NAME>`
  — one administrative unit at the given geoBoundaries level, keyed by
  the **local** `shapeName` (case-insensitive: `Bayern`, not
  `Bavaria`). Source: geoBoundaries gbOpen ADM1/ADM2/ADM3.

  **Levels are not uniform across countries.** geoBoundaries follows
  each country's own administrative hierarchy, so the same level maps
  to different real-world divisions:

  | Country | ADM1 | ADM2 | ADM3 |
  |---------|------|------|------|
  | Germany | Länder | Kreise | — |
  | USA | states | counties | — |
  | Italy | macroregions (5) | regioni (20) | province (107) |

  Pick the level that matches the division you want — e.g.
  `adm1/DEU/Bayern` for a German state, but `adm2/ITA/Lazio` for an
  Italian region. See "Finding feature IDs" below.
- `neighbors/<ISO_A3>` — every country that shares a border with
  the target (topological adjacency). Falls back to bbox-intersect
  for island nations with no shared edges. Source: geoBoundaries ADM0.
- `continent/<NAME>` — composite of all countries whose geoBoundaries
  `Continent` matches (case-insensitive). Values include `Africa`,
  `Asia`, `Europe`, `Oceania`, `South America`, `Northern America`.
- `subregion/<NAME>` — composite of all countries whose geoBoundaries
  `UNSDG-subregion` matches (case-insensitive). Values include
  `Western Europe`, `Eastern Europe`, `Southern Europe`,
  `Northern Africa`, `South-Eastern Asia`, etc.
- `relation/<N>` and `way/<N>` — fetched from
  [Overpass](https://overpass-api.de/) and cached
  content-addressably. Use this when geoBoundaries' admin
  boundaries don't match the political boundary you want.

## Auto-focus

Most countries with overseas territories (USA + Alaska + Hawaii,
France + Corsica + Guiana, NZ + Chatham, …) would otherwise produce
a viewport so wide that the main landmass is a tiny dot.

The renderer auto-focuses on the **main cluster** of polygon
components: it picks the largest by area as a seed and pulls in any
component whose bbox lies within `0.15 ×` the seed's diagonal.

Concretely:

- `country/USA` → CONUS only (Alaska, Hawaii drawn but clipped).
- `country/FRA` → Metropolitan France + Corsica (Guiana drawn but clipped).
- `country/NZL` → North + South Islands (Chatham drawn but clipped).
- `country/ITA` → Peninsula + Sicily + Sardinia.
- `country/DEU`, `country/POL`, `country/CHE` → unchanged (single component).
- `subregion/Western Europe` → mainland Europe + UK + Ireland (Svalbard, Iceland drawn but clipped).

If you explicitly highlight an outlying region — say
`highlights = ["adm1/USA/Alaska"]` over a `country/USA` base — the
viewport stretches to include the highlight, so your answer never
gets clipped.

Geometry is **never thrown away** by auto-focus. Outlying islands
always render; they just fall outside the SVG viewBox in the unfocused
case. (Sub-pixel specks *are* dropped at draw time — see
[Detail reduction](#detail-reduction).)

## Detail reduction

Archipelago and subregion features (e.g. `subregion/Melanesia`, which
flattens every member country into one geometry) can carry hundreds of
tiny disconnected islands. At regional zoom these become sub-pixel
specks — visual noise that bloats the SVG. The renderer culls them
**per feature, in rendered-pixel space**, with a rule that protects
small features that are themselves the answer:

A polygon component is **kept** when **any** of these holds:

- its projected area is at least `min_island_px²` (individually
  visible — keeps small, medium and large islands), or
- its area is at least `island_rel_frac ×` the feature's largest
  component (comparable to the main mass — keeps clusters of roughly
  equal islands intact), or
- it is the largest component (so a tiny island nation that *is* the
  answer is never garbage-collected, even zoomed far out).

Because a feature's granularity follows its reference, this does the
right thing automatically: on a `subregion/Melanesia` **base** layer
New Guinea dominates, so distant Fiji specks drop; on a `country/FJI`
**answer** layer Fiji *is* the feature, so all its islands stay (and
the hull, computed from the full geometry, always wraps the whole
region regardless).

Outline detail is also simplified with Douglas-Peucker at `simplify_px`
pixels. All three knobs live in `[viewport]`:

```toml
[viewport]
min_island_px = 2.0     # cull landmasses smaller than 2×2 px (0 = off)
island_rel_frac = 0.05  # …unless ≥ 5% of the feature's largest mass
simplify_px = 1.5        # Douglas-Peucker tolerance in px (0 = off)
```

The defaults are gentle: only sub-2px specks are removed and small/
medium/large islands are kept. Set `min_island_px = 0` to disable
culling, or raise it for cleaner regional overviews.

## World-wrapping

For maps that span the antimeridian (NZ + Fiji, Russia + Alaska, …)
the renderer picks an optimal central meridian so the data forms a
contiguous coordinate range — no more 350°-wide bboxes that fill the
canvas with empty ocean. Authors don't need to think about this;
write `features = ["country/NZL", "country/FJI"]` and you'll get a
tight Pacific view.

### Choosing an admin level

geoBoundaries names every administrative unit by its **local**
`shapeName` and slots it into a per-country level hierarchy
(`ADM1` → `ADM2` → `ADM3`). The catch is that the *meaning* of a level
varies by country, so you choose the level that lines up with the
division you're after:

- **`adm1/<ISO>/<NAME>`** is the first-order division for most
  countries — German `Länder` (`adm1/DEU/Bayern`), US states
  (`adm1/USA/Texas`), French régions (`adm1/FRA/Île-de-France`).
- For countries whose first administrative tier is a statistical
  grouping, the political division you expect sits one level deeper:
  Italian regioni are `adm2/ITA/Lazio`; Italian province are
  `adm3/ITA/Roma`.

Names are matched case-insensitively against `shapeName` and are
**local-language** — `Bayern` not `Bavaria`, `Roma` not `Rome`,
`München` not `Munich`.

See **Finding feature IDs** below for how to look these up in practice.

## Finding feature IDs

When you author a `map` block you'll mostly be filling in three kinds
of references. Here's how to find each.

### `country/<ISO_A3>`

Three-letter codes from ISO 3166-1 alpha-3.

- Quick reference: <https://en.wikipedia.org/wiki/ISO_3166-1_alpha-3>
- Cheatsheet for common ones:
  `DEU FRA GBR ITA ESP NLD BEL CHE AUT POL CZE`
  `SWE NOR FIN DNK IRL PRT GRC TUR UKR RUS`
  `USA CAN MEX BRA ARG CHL JPN CHN KOR IND IDN AUS NZL ZAF EGY`

### `adm1|adm2|adm3/<ISO_A3>/<NAME>`

`<NAME>` matches geoBoundaries' local `shapeName` (case-insensitive).
To list the units at a given level for a country (inside
`nix develop .#marki`, where gdal + `GEOBOUNDARIES_DATA` are
available):

```sh
# Units at ADM1 for Germany:
ogrinfo -geom=NO "$GEOBOUNDARIES_DATA/DEU_ADM1.geojson" \
  | grep "shapeName (String)"

# Units at ADM2 for Italy (the regioni):
ogrinfo -geom=NO "$GEOBOUNDARIES_DATA/ITA_ADM2.geojson" \
  | grep "shapeName (String)"
```

Swap the ISO and `ADM<n>` for whichever country/level you're after.
If a file is missing, that country has no boundaries at that level.

### `relation/<N>` and `way/<M>`

These come straight from OpenStreetMap. Use them when you need a
boundary geoBoundaries doesn't carry — a city, a neighbourhood, a
lake, a park, a custom multipolygon.

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

Gives you `cargo`, `gdal` (for `ogrinfo`), `curl`, `jq`,
`GEOBOUNDARIES_DATA`, and `NATURAL_EARTH_DATA` pre-set. Useful for
exploring admin unit names without installing anything globally.

## Caching

Three layers of caching keep things fast and offline-friendly:

1. **Render cache** at `$XDG_CACHE_HOME/marki/render/<key>/`.
   Key = blake3(canonical TOML || theme bytes || `RENDER_VERSION_MAP`).
   On a hit, no resolve / project / compose work runs at all.
2. **Overpass cache** at `$XDG_CACHE_HOME/marki/net/overpass/`.
   Key = blake3(query string). Entries don't expire.
3. **Offline boundary bundles** delivered by Nix derivations:
   `pkgs.geoboundaries-data` (admin boundaries, via
   `GEOBOUNDARIES_DATA`) and `pkgs.natural-earth-data` (coastline, via
   `NATURAL_EARTH_DATA`).

## Failure modes

The daemon never aborts the corpus on one bad map. When something
goes wrong (data env unset, bad TOML, OSM 404, network down, …) the
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
- geoBoundaries admin levels are not uniform across countries (e.g.
  Italian regioni are at ADM2, not ADM1). Pick the level that matches
  the division you want.
- The bundled dataset ships geoBoundaries ADM0/ADM1/ADM2 only; ADM3+
  references won't resolve until those levels are added to the
  `geoboundaries-data` derivation.

These are deliberate M1 cuts; see the RFC for the full vocabulary.
