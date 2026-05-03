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

pub const RENDER_VERSION_MAP: u32 = 15;
