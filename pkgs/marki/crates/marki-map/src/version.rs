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

pub const RENDER_VERSION_MAP: u32 = 22;
