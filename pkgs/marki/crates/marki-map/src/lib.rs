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
pub mod defaults;
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
pub mod trim;
pub mod unwrap;
pub mod version;

use marki_core::{BlockError, BlockRenderer, RenderCtx, RenderedBlock};

pub use defaults::MapDefaults;
pub use error::MapError;

/// Lang token this renderer handles: `map`.
pub const MAP_LANG: &str = "map";

/// Map block renderer. Construct with [`MapRenderer::new`] (no project
/// defaults) or [`MapRenderer::with_defaults`], and register against the
/// markid daemon's [`crate::Registry`].
pub struct MapRenderer {
    /// Project-level DSL defaults + path rules, merged underneath each
    /// card's own block. Empty for a bare [`MapRenderer::new`].
    defaults: defaults::CompiledDefaults,
}

impl Default for MapRenderer {
    fn default() -> Self {
        Self::new()
    }
}

impl MapRenderer {
    pub fn new() -> Self {
        Self {
            defaults: defaults::CompiledDefaults::empty(),
        }
    }

    /// Construct a renderer that merges project-level [`MapDefaults`]
    /// underneath every card. `cards_dir` anchors the relative paths
    /// that rule globs match against. Errors only on a malformed glob.
    pub fn with_defaults(
        defs: MapDefaults,
        cards_dir: std::path::PathBuf,
    ) -> Result<Self, String> {
        Ok(Self {
            defaults: defaults::CompiledDefaults::compile(defs, cards_dir)?,
        })
    }
}

impl BlockRenderer for MapRenderer {
    fn lang(&self) -> &'static str {
        MAP_LANG
    }

    fn render(&self, src: &str, ctx: &mut RenderCtx<'_>) -> Result<RenderedBlock, BlockError> {
        let spec = if self.defaults.is_empty() {
            dsl::parse_map_spec(src).map_err(|e| BlockError::Parse(e.to_string()))?
        } else {
            // Merge: project defaults (global + matching rules) underneath
            // the card's own block, then build the spec from the result.
            let mut merged = self.defaults.effective_table(ctx.source_path);
            let card: toml::Table =
                toml::from_str(src).map_err(|e| BlockError::Parse(e.to_string()))?;
            defaults::deep_merge(&mut merged, &card);
            toml::Value::Table(merged)
                .try_into()
                .map_err(|e| BlockError::Parse(e.to_string()))?
        };
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
