//! `marki-map` — render `map` blocks to SVG layers + JSON sidecar.
//!
//! Implements `marki_core::BlockRenderer` for the lang token `map`.
//! See `dsl.rs` for the TOML body format and `tests/fixtures/` for
//! authored examples.
//!
//! The renderer parses the DSL, resolves geometry references against
//! Natural Earth (and, for OSM relation/way refs, the Overpass API),
//! projects them to SVG units, composes one styled SVG per layer, and
//! emits the bytes as `marki_core::EmittedAsset`s for the daemon to
//! upload to Anki.
//!
//! For now this crate ships a stub renderer (Step 2e); the actual
//! pipeline lands in steps 3–7.

pub mod cache;
pub mod clip;
pub mod cluster;
pub mod compose;
pub mod data;
pub mod dsl;
pub mod embed;
pub mod error;
pub mod geometry;
pub mod hash;
pub mod pipeline;
pub mod project;
pub mod sidecar;
pub mod simplify;
pub mod style;
pub mod unwrap;
pub mod version;

use marki_core::{BlockError, BlockRenderer, RenderCtx, RenderedBlock};

pub use error::MapError;

/// Lang token this renderer handles: `map`.
pub const MAP_LANG: &str = "map";

/// Map block renderer. Construct with [`MapRenderer::new`] and register
/// against the markid daemon's [`crate::Registry`].
pub struct MapRenderer {
    // Hooks for natural-earth path / overpass client / theme cache go
    // here as the pipeline lands. For the stub renderer this is empty.
}

impl Default for MapRenderer {
    fn default() -> Self {
        Self::new()
    }
}

impl MapRenderer {
    pub fn new() -> Self {
        Self {}
    }
}

impl BlockRenderer for MapRenderer {
    fn lang(&self) -> &'static str {
        MAP_LANG
    }

    fn render(&self, src: &str, ctx: &mut RenderCtx<'_>) -> Result<RenderedBlock, BlockError> {
        let spec = dsl::parse_map_spec(src).map_err(|e| BlockError::Parse(e.to_string()))?;
        Ok(pipeline::run(&spec, ctx.cache_dir)?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn renderer_rejects_bad_toml() {
        let r = MapRenderer::new();
        let mut ctx = RenderCtx {
            source_path: &PathBuf::from("/tmp/x.md"),
            cache_dir: &PathBuf::from("/tmp/cache"),
        };
        let err = r.render("not = [valid toml", &mut ctx).unwrap_err();
        assert!(matches!(err, BlockError::Parse(_)));
    }
}
