//! `marki-map` -- render `map` blocks to SVG layers + JSON sidecar.
//!
//! Implements `marki_render::Renderer` for the lang token `map`.
//! See `dsl.rs` for the TOML body format and `tests/fixtures/` for
//! authored examples.
//!
//! The renderer parses the DSL, resolves geometry references against
//! Natural Earth (and, for OSM relation/way refs, the Overpass API),
//! projects them to SVG units, composes one styled SVG per layer, and
//! emits the bytes as `marki_render::Asset`s for the daemon to
//! upload to Anki.

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

use marki_render::{Fragment, Input, RenderCtx, RenderError, Renderer, Tool};

pub use defaults::MapDefaults;
pub use error::MapError;

/// Lang token this renderer handles: `map`.
pub const MAP_LANG: &str = "map";

/// Map block renderer. Construct with [`MapRenderer::new`] (no project
/// defaults) or [`MapRenderer::with_defaults`], and register against the
/// marki daemon's [`crate::Registry`].
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

impl Renderer for MapRenderer {
    fn lang(&self) -> &'static str {
        MAP_LANG
    }

    fn render(&self, input: Input<'_>, ctx: &mut RenderCtx<'_>) -> Result<Fragment, RenderError> {
        let spec = if self.defaults.is_empty() {
            input.deserialize()?
        } else {
            // Merge: project defaults (global + matching rules) underneath
            // the card's own block, then build the spec from the result.
            let mut merged = self.defaults.effective_table(ctx.source_path);
            let card = input.into_table()?;
            defaults::deep_merge(&mut merged, &card);
            toml::Value::Table(merged)
                .try_into()
                .map_err(|e: toml::de::Error| RenderError::Parse(e.to_string()))?
        };
        Ok(pipeline::run(&spec, ctx.cache_dir)?)
    }

    fn docs(&self) -> &'static str {
        include_str!("../README.md")
    }

    fn tools(&self) -> Vec<Tool> {
        vec![
            Tool {
                name: "units",
                description: "Valid admin unit names for adm1/adm2/adm3 refs (`adm<level>/<ISO3>/<name>`) of one country, from the bundled geoBoundaries data. Use before writing an adm ref instead of guessing names; levels differ per country (Italian regioni are adm2).",
                schema: serde_json::json!({
                    "type": "object",
                    "properties": {
                        "iso": {"type": "string", "description": "ISO 3166-1 alpha-3, e.g. DEU."},
                        "level": {"type": "integer", "enum": [1, 2, 3]}
                    },
                    "required": ["iso", "level"]
                }),
            },
            Tool {
                name: "find",
                description: "Search OpenStreetMap by name (Nominatim) for features no bundled ref covers: cities, lakes, rivers, parks, walls, historic regions. Returns `relation/N` / `way/N` refs usable directly in a map layer. Check `kind` to pick the right hit.",
                schema: serde_json::json!({
                    "type": "object",
                    "properties": {"query": {"type": "string", "description": "Place name, e.g. \"Lake Constance\"."}},
                    "required": ["query"]
                }),
            },
        ]
    }

    fn call_tool(&self, name: &str, args: serde_json::Value, ctx: &RenderCtx<'_>) -> Result<serde_json::Value, RenderError> {
        let s = |k: &str| {
            args.get(k)
                .and_then(|v| v.as_str())
                .ok_or_else(|| RenderError::Parse(format!("missing string argument `{k}`")))
        };
        match name {
            "units" => {
                let iso = s("iso")?.to_uppercase();
                let level = args.get("level").and_then(|v| v.as_u64()).unwrap_or(0);
                if !(1..=3).contains(&level) {
                    return Err(RenderError::Parse("level must be 1, 2 or 3".into()));
                }
                if !data::geoboundaries::country_codes()?.contains(&iso) {
                    return Err(RenderError::Resolve(format!("unknown country {iso} (use ISO 3166-1 alpha-3)")));
                }
                let units = data::geoboundaries::admin_units(&iso, level as u8)?;
                Ok(serde_json::json!({
                    "ref_prefix": format!("adm{level}/{iso}/"),
                    "units": units,
                }))
            }
            "find" => Ok(serde_json::json!({ "hits": data::overpass::search(s("query")?, ctx.cache_dir)? })),
            _ => Err(RenderError::Internal(format!("no tool `{name}`"))),
        }
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
        let err = r.render(Input::Raw("not = [valid toml"), &mut ctx).unwrap_err();
        assert!(matches!(err, RenderError::Parse(_)));
    }
}
