//! Bumped whenever marki-map would emit different bytes for the same
//! source. Mixed into cache keys; not (currently) into the per-card
//! content hash, since that's a marki-core concern.
//!
//! ## History
//!
//! - `1` — initial release: equirectangular projection, fixed canvas
//!   at `spec.size`.
//! - `2` — switched default projection to Mercator and made `size`
//!   a max budget (canvas autosizes to the projected aspect).
//! - `3` — responsive embed (`max-width` + `aspect-ratio`);
//!   `region/<ISO>/<NAME>` reference; admin1 indexed by both
//!   `name_en` and `name`; topological neighbour graph.
//! - `4` — non-base layers get transparent backgrounds (fixes
//!   highlight/reveal); Douglas-Peucker simplification on projected
//!   coordinates; antimeridian normalization for cross-dateline
//!   geometries; `context` features (drawn but excluded from viewport
//!   bbox).
//! - `5` — base layer always emitted first in the DOM so overlays
//!   stack on top (fixes highlight invisible behind base).
//! - `15` — viewport now auto-focuses on the main cluster of
//!   components (CONUS + Alaska on `country/USA`, peninsula + Sicily
//!   + Sardinia on `country/ITA`, …). Cross-dateline maps (NZ + Fiji,
//!   Russia + Alaska) pick an optimal central meridian so the bbox
//!   stays tight. The `/mainland` modifier is removed; geometry is
//!   always full and outliers clip naturally outside the viewBox.
//!   Wrap-meridian splitting: polygons whose outer ring genuinely
//!   wraps around the globe (e.g. Russia drawn from a European-
//!   centred frame) are now cut at the wrap meridian into proper
//!   closed fragments instead of streaking across the canvas.
//! - `17` — Natural Earth dateline-stitching: shapefile-pre-split
//!   polygons (Russia's Chukotka peninsula, etc.) are reunited at
//!   load time into a single ring. Removes the visible vertical seam
//!   through eastern Russia on Asia-centric maps. Per-feature
//!   viewport bbox + Sutherland-Hodgman clipping at 10% margin
//!   shrink SVGs by ~70–80%.
//! - `19` — Geometry-density viewport trimming: sparse Mercator-
//!   stretched edges (e.g. northern Norway/Finland on a Europe map)
//!   are cropped based on actual vertex density, with a hard
//!   Mercator aspect-ratio floor as a safety net. Tunable per-card
//!   via the new `[viewport]` TOML section: `min_density`,
//!   `min_aspect`, and `cluster_factor`.
//! - `20` — Density trimming and aspect floor are off by default
//!   (`min_density = 0.0`, `min_aspect = 0.0`); the machinery is
//!   kept in place for opt-in use, but defaults preserve the natural
//!   Mercator framing of country geometry.
//! - `21` — Admin boundary source switched from Natural Earth to
//!   geoBoundaries gbOpen. Reference vocabulary is now `country/<iso>`,
//!   `adm1|adm2|adm3/<iso>/<name>` (raw geoBoundaries levels, local
//!   `shapeName`), `neighbors/<iso>`, `continent/<name>`,
//!   `subregion/<name>`. The old `admin1/` and `region/` references are
//!   gone. Natural Earth is retained only for `coastline`.
//! - `22` — Hull layers. A layer with a `[layers.<name>.hull]` table
//!   draws scale-aware halo circles around its features' centroids
//!   instead of outlines, making hard-to-spot island nations findable.
//!   New `hull` theme role.
//! - `23` — Central-meridian selection rewritten. The frame is now
//!   chosen by the largest empty longitude gap (smallest enclosing arc)
//!   instead of the raw bbox midpoint, so antimeridian-spanning cards
//!   (Melanesia + Polynesia, Fiji, Kiribati, …) get a tight Pacific
//!   viewport instead of a globe-spanning strip. Near-global data is
//!   left un-rotated.
//! - `24` — Hull geometry upgraded from a centroid circle to a rounded
//!   convex hull: the convex hull of a feature's vertices, expanded
//!   outward with rounded corners. A hull now wraps the feature's whole
//!   extent (every island of an archipelago) in one smooth region
//!   instead of marking only its centre. Single-point features still
//!   degenerate to the old circle.
//! - `25` — Detail reduction. Small disconnected landmasses are culled
//!   per feature in projected pixel space: a component is dropped only
//!   when it is both sub-threshold (`min_island_px²`) and small relative
//!   to the feature's largest mass (`island_rel_frac`), and the largest
//!   component is always kept — so archipelago/subregion features stop
//!   emitting hundreds of sub-pixel specks without GC-ing a small-island
//!   answer. Outline simplification is now tunable (`simplify_px`,
//!   default raised 1.0 → 1.5). All three knobs live in `[viewport]`.
//! - `26` — Cleaner borders and outlines. Multi-country composites
//!   (`continent/`, `subregion/`, `neighbors/`) are now boolean-unioned
//!   (i_overlay) so shared internal borders dissolve instead of drawing
//!   as double lines from independently-digitized neighbours. Closed
//!   rings that simplify below a triangle are dropped, and sub-pixel
//!   holes are area-culled, removing the "dotted" speckle from messy
//!   source geometry. Default `simplify_px` lowered 1.5 → 1.0.
//! - `27` — Single-source border data. The boundary set switched from
//!   gbOpen (per-country, independently digitized) to geoBoundaries
//!   CGAZ, which shares identical vertices along every shared edge, so
//!   composites draw one border per edge with no boolean union. The
//!   runtime dissolve (i_overlay) is gone; composite features
//!   (`continent/`, `subregion/`, `neighbors/`) instead render
//!   faithfully — no per-feature simplification or island culling —
//!   which would otherwise split those coincident borders or drop small
//!   member countries.
//! - `28` — Restore island culling for composites. Only per-feature
//!   outline *simplification* splits coincident shared borders into
//!   double lines, so that alone is disabled for composites; small-
//!   island culling — which drops whole disconnected specks (offshore
//!   islands) and never touches a shared land border — is back on,
//!   removing the noisy speckle that `27` reintroduced (e.g. Chile's
//!   southern archipelago).

pub const RENDER_VERSION_MAP: u32 = 28;
