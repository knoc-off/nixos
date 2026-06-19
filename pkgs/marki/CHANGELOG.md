# marki — changelog

## Unreleased

### Changed

- **Breaking (map data source)**: `marki-map` now resolves country and
  administrative boundaries from **geoBoundaries gbOpen** instead of
  Natural Earth. Natural Earth is retained only for `coastline`.
  `RENDER_VERSION_MAP` bumped to `21` (cache invalidation).
  - New reference vocabulary: `country/<ISO3>`,
    `adm1|adm2|adm3/<ISO3>/<NAME>`, `neighbors/<ISO3>`,
    `continent/<NAME>`, `subregion/<NAME>`, `coastline`.
  - **Removed**: `admin1/<ISO3>/<NAME>` and `region/<ISO3>/<NAME>`. Use
    the raw geoBoundaries level (`adm1`/`adm2`/`adm3`) that matches the
    division you want — geoBoundaries levels are not uniform across
    countries (e.g. Italian regioni are `adm2/ITA/<name>`, not `adm1`).
  - Names are now **local-language `shapeName`** (`adm1/DEU/Bayern`,
    not `admin1/DEU/Bavaria`; `adm2/ITA/Lazio`). One-shot card migration
    will be needed for any `admin1/`/`region/` references.
  - New `geoboundaries-data` Nix derivation provides the dataset via the
    `GEOBOUNDARIES_DATA` env var (ADM0/1/2 simplified geometry + the
    open metadata CSV). The `markid` module gains a `geoBoundariesData`
    option alongside `naturalEarthData`.
  - Known caveat: gbOpen country polygons are sourced independently per
    country, so `neighbors/` mostly relies on the coarser bbox-intersect
    fallback rather than exact topological adjacency.

### Added

- New `marki-media` crate (replaces `marki-flag`): renders fenced
  ` ```media ` blocks to images or audio. Supports both image
  (svg/png/webp/jpg/jpeg/gif) and audio (mp3/ogg/m4a/wav) types.
  The block author's `src` field can omit the file extension — the
  resolver tries a fixed preference list (svg → png → webp → jpg
  → jpeg → gif → mp3 → ogg → m4a → wav) and infers the renderer
  from the resolved file. Multiple named sources, search-all
  fallback, prefix routing, and case-insensitive lookup all work
  the same as the old flag block.
- `marki-media` emits a content-addressed `EmittedAsset` instead of
  inlining base64 into the HTML, matching how `marki-map` ships its
  SVGs. Smaller HTML, native Anki media-collection dedup.

### Changed

- **Breaking DSL**: `flag` block lang renamed to `media`. The
  `flag = "..."` and `country = "..."` fields are replaced by
  `src = "..."`. `deny_unknown_fields` means existing cards using
  the old shape get an immediate parse error. One-shot migration
  in the cards repo:
  ```bash
  find . -name '*.md' -print0 | xargs -0 sed -i '
    s/^```flag$/```media/
    /^```media$/,/^```$/ {
      s/^flag = /src = /
      s/^country = /src = /
    }
  '
  ```
- `media` blocks support new optional fields beyond `src`/`size`/`alt`:
  `controls` (default `true`), `loop` (default `false`), `autoplay`
  (default `false`), and `preload` (default `"auto"` — Anki stores
  media locally so there's no fetch cost). All four are silently
  ignored when `src` resolves to an image; `size` is silently
  ignored when `src` resolves to audio.
- **Breaking config**: `flag_sources` config key renamed to
  `media_sources`. `MARKID_FLAG_DIR` env renamed to
  `MARKID_MEDIA_DIR`. `--flag-dir` CLI flag renamed to
  `--media-dir`. Home-Manager options `flagSources`/`flagDir`
  renamed to `mediaSources`/`mediaDir`. No alias retained.
- `AssetMime` gains `ImageJpeg`, `ImageWebp`, `ImageGif`,
  `AudioMpeg`, `AudioOgg`, `AudioMp4`, `AudioWav` variants. Anki
  infers content type from filename extension, so this is for
  diagnostics only.

### Notes for upgraders

- Cards that used `flag` blocks will re-push on the next sync cycle
  because the rendered HTML changes byte-for-byte (file-ref instead
  of inline base64). The sync engine hashes final HTML, so the
  re-push is automatic — no `RENDER_VERSION` bump needed.

## Earlier (was Unreleased)

### Added

- New `marki-map` crate: renders fenced ` ```map ` blocks to one SVG
  per layer plus a JSON sidecar. Outline mode only; vector geometry
  pulled from Natural Earth (`country/<iso>`, `admin1/<iso>/<name>`,
  `region/<iso>/<name>`, `continent/<name>`, `subregion/<name>`,
  `coastline`, `neighbors/<iso>`) and
  OpenStreetMap via Overpass (`relation/<N>`, `way/<N>`). See
  `crates/marki-map/README.md`.
- Block-renderer dispatch: `marki-core` now exposes a `BlockRenderer`
  trait, `BlockRequest`/`RenderedBlock` types, and a parser that
  defers external langs to a registry held by the daemon.
- `markid render-map <FILE> --out DIR`: render every external block
  in one card to disk + a preview HTML, with no Anki round-trip.
  Useful for theme iteration.
- `pkgs.natural-earth-data`: Nix derivation that fetches and unpacks
  Natural Earth 10m countries, admin-1 regions, and coastline
  shapefiles. Wired through `services.markid.naturalEarthData`
  (default = derivation), exposed at runtime as
  `NATURAL_EARTH_DATA`.
- `region/<ISO>/<NAME>` feature reference: composite of all admin-1
  entries whose NE `region` column matches. Use for Italian regioni
  (`region/ITA/Sicily`), French régions (`region/FRA/Île-de-France`),
  etc.
- Admin-1 entries are now indexed by both `name_en` and `name`
  (case-insensitive). Fixes lookups that relied on local names (e.g.
  `admin1/DNK/Hovedstaden`).
- Dev shell: `nix develop .#marki` now includes `gdal`, `curl`, `jq`,
  and sets `NATURAL_EARTH_DATA` for exploring NE data with `ogrinfo`.
- Authoring docs: new "Finding feature IDs" and "admin1 vs. region"
  sections in `crates/marki-map/README.md`.
- Smart viewport: `country/<ISO>` now auto-focuses on the main
  cluster of polygon components — `country/USA` shows CONUS + Alaska
  + Aleutians without losing Hawaii from the geometry (Hawaii is
  drawn but clipped by the viewBox); `country/FRA` shows Metropolitan
  + Corsica without zooming out for Guiana; `country/ITA` keeps
  Sicily and Sardinia in frame. Highlighting an outlying region (e.g.
  `highlights = ["admin1/USA/Hawaii"]`) stretches the viewport to
  include the highlight.
- Cross-dateline maps (NZ + Fiji, Russia + Alaska, Pacific Rim, …)
  now pick an optimal central meridian automatically and project as
  a tight contiguous bbox instead of a 350°-wide world span. No DSL
  changes required — write `features = ["country/NZL", "country/FJI"]`
  and you'll get a correct Pacific view.

### Changed

- **Breaking DSL**: removed `id`, `type`, `caption`, and `region_hint`
  fields from `MapSpec`. All four were either redundant or unused.
  `deny_unknown_fields` means existing cards with these fields get an
  immediate parse error — remove the lines to fix. Only `size`,
  `style`, and `layers` remain at top level.
- **Breaking DSL**: `highlight` (singular string) replaced by
  `highlights` (list of strings). Multiple regions can now be
  highlighted in a single layer — Italy's industrial triangle card
  drops from 4 layers to 2.
- **Breaking DSL**: removed the `/mainland` modifier from
  `country/`, `continent/`, and `subregion/` references. The smart
  viewport (above) supersedes it: geometry is always full, viewport
  auto-focuses on the main cluster. Cards that still write
  `country/USA/mainland` get a resolve error — drop the suffix.
- `continent/<name>` and `subregion/<name>` feature references:
  composite MultiPolygon of all countries in a UN continent or
  subregion (read from NE's `CONTINENT` / `SUBREGION` columns).
  `features = ["continent/Europe"]` draws all ~45 European countries.
- Per-layer style override: layers can now carry a `[layers.X.style]`
  sub-table with `fill`, `stroke`, and `stroke_width` to override the
  theme's highlight role per layer. Unset fields inherit from the theme.
- Sync engine now hashes the final rendered HTML (after block dispatch)
  instead of the raw markdown source. Bumping `RENDER_VERSION_MAP`,
  changing the theme, or tweaking simplification epsilon now
  automatically triggers a re-push — no manual card edits needed.
- `markid status` dispatches blocks to compute the HTML hash,
  matching what the sync engine stores.
- Douglas-Peucker simplification epsilon raised from 0.5 px to 1.0 px
  for smaller SVGs. Imperceptible at card viewing distance.
- Map embed is now horizontally centred (`margin:0 auto`).
- CSS reveal rules no longer use `data-id` scoping — bare `.marki-map`
  selector. One map per card (Model A) makes per-id scoping unnecessary.
- Media filenames simplified from `marki-map-{key}-{id}-{layer}.svg`
  to `marki-map-{key}-{layer}.svg`. The BLAKE3 key prevents collisions.
- Sidecar JSON no longer carries an `id` field.
- SVG compose now renders roles in explicit stacking order
  (coast → neighbor → outline → highlight) instead of alphabetical.
  Fixes highlight-on-base-layer being buried under opaque country fills.
- `neighbors/<ISO>` now returns each neighbour's full geometry rather
  than only the largest polygon. Smart viewport handles outlying
  components correctly.
- `RENDER_VERSION_MAP` bumped to `15`. Existing render cache entries
  will rebuild lazily on next sync.
- `marki-map` default projection is now Mercator (was equirectangular).
  Mid-latitude regions like Germany no longer appear horizontally
  squashed.
- `size = [W, H]` is now optional (defaults to `[600, 400]`) and
  treated as a *maximum budget*. The renderer matches the projected
  aspect and shrinks one dimension as needed; no more letterboxing.
- Map embeds are now responsive: the container uses `max-width` +
  `aspect-ratio` instead of fixed pixel dimensions, so cards fit
  phone-narrow viewports without horizontal scroll.
- `neighbors/<ISO>` now uses true topological adjacency derived from
  shared boundary segments, not bbox intersection. France no longer
  claims Brazil; the US no longer claims Russia. Falls back to
  bbox-intersect for island nations with no shared edges.
- Sidecar gains a `requested_size: [W, H]` field to record the
  author's budget alongside the actual rendered `width`/`height`,
  and now derives `Deserialize` so the pipeline can re-read it on a
  cache hit.

### Notes for upgraders

- Adding the map renderer doesn't bump the marki-core
  `RENDER_VERSION`, so existing cards keep their stored hashes and
  won't be re-pushed. Cards that *contain* `map` blocks will have a
  freshly different `front_html`/`back_html` and will be pushed as
  updates on the next cycle.
- A `RENDER_VERSION` bump (any change to marki-core's HTML output)
  invalidates every card's hash and re-pushes the whole corpus on
  the next cycle. This is expected and harmless; pushes are
  idempotent.
