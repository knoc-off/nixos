//! Theme loader.
//!
//! Themes are TOML files describing a per-role palette. Bundled themes
//! are `include_str!`'d into the binary so the renderer ships
//! self-contained. The `style` field on [`crate::dsl::MapSpec`] picks
//! one by name; unknown names fall back to `atlas`.

use crate::compose::{LayerStyle, RoleStyle};
use crate::error::MapError;
use serde::Deserialize;

const ATLAS_BYTES: &[u8] = include_bytes!("themes/atlas.toml");

#[derive(Debug, Deserialize)]
struct ThemeFile {
    #[serde(default)]
    background: Option<String>,
    #[serde(default)]
    role: Vec<RoleEntry>,
}

#[derive(Debug, Deserialize)]
struct RoleEntry {
    role: String,
    #[serde(default)]
    fill: Option<String>,
    #[serde(default)]
    stroke: Option<String>,
    #[serde(default = "default_sw")]
    stroke_width: f64,
}

fn default_sw() -> f64 {
    1.0
}

/// Result of loading a theme: parsed [`LayerStyle`] plus the raw bytes
/// (for cache-key mixing).
pub struct LoadedTheme {
    pub style: LayerStyle,
    pub bytes: Vec<u8>,
}

/// Load a bundled theme by name. Unknown names fall back to `atlas`
/// and emit a warning.
pub fn load(name: &str) -> Result<LoadedTheme, MapError> {
    let (chosen_name, bytes) = match name {
        "atlas" => ("atlas", ATLAS_BYTES),
        other => {
            tracing::warn!("unknown theme `{other}`, falling back to `atlas`");
            ("atlas", ATLAS_BYTES)
        }
    };
    let _ = chosen_name; // currently unused but kept for future logs
    let parsed: ThemeFile = toml::from_slice(bytes)
        .map_err(|e| MapError::Internal(format!("theme parse: {e}")))?;
    let style = LayerStyle {
        background: parsed.background,
        roles: parsed
            .role
            .into_iter()
            .map(|r| RoleStyle {
                role: r.role,
                fill: r.fill.unwrap_or_else(|| "none".into()),
                stroke: r.stroke.unwrap_or_else(|| "#000".into()),
                stroke_width: r.stroke_width,
            })
            .collect(),
    };
    Ok(LoadedTheme {
        style,
        bytes: bytes.to_vec(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn atlas_theme_loads() {
        let t = load("atlas").unwrap();
        assert!(t.style.background.is_some());
        assert!(t.style.role("highlight").is_some());
        assert!(t.style.role("outline").is_some());
        assert!(!t.bytes.is_empty());
    }

    #[test]
    fn unknown_theme_falls_back_to_atlas() {
        let t = load("nonexistent").unwrap();
        assert!(t.style.role("outline").is_some());
    }
}
