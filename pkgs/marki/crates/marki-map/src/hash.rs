//! Cache key derivation.
//!
//! The key for a rendered map is a 16-hex-char prefix of BLAKE3 over
//! a stable byte sequence:
//!
//! ```text
//! BLAKE3(
//!     RENDER_VERSION_MAP_le ||
//!     theme_name ||
//!     theme_bytes ||
//!     canonical_toml_of(spec)
//! )
//! ```
//!
//! `canonical_toml_of` re-serialises the parsed [`MapSpec`] so author
//! whitespace tweaks don't bust the cache. Because we use an
//! `IndexMap` for `layers`, layer order is preserved from the TOML
//! source — reordering layers changes the visual output and therefore
//! produces a different cache key.

use crate::dsl::MapSpec;
use crate::error::MapError;
use crate::version::RENDER_VERSION_MAP;

/// Compute the 16-hex-char cache key for a map render. The caller
/// supplies the theme bytes (e.g. the loaded `atlas.toml`) so theme
/// edits invalidate cached renders.
pub fn cache_key(spec: &MapSpec, theme_bytes: &[u8]) -> Result<String, MapError> {
    // Re-serialise to TOML for canonical form. We could also serialise
    // to a manually-canonicalised buffer of (key, value) pairs, but
    // toml's serializer is already deterministic for our `BTreeMap`-
    // keyed shapes and the workspace already pulls it in.
    let canonical = toml::to_string(spec)
        .map_err(|e| MapError::Internal(format!("canonical toml: {e}")))?;

    let mut hasher = blake3::Hasher::new();
    hasher.update(&RENDER_VERSION_MAP.to_le_bytes());
    hasher.update(spec.style.as_bytes());
    hasher.update(theme_bytes);
    // Hash layer names in insertion order so that reordering layers
    // (which changes DOM stacking) produces a different cache key.
    // The canonical TOML alone doesn't capture order because the toml
    // serializer sorts table keys alphabetically.
    for name in spec.layers.keys() {
        hasher.update(name.as_bytes());
        hasher.update(&[0]);
    }
    hasher.update(canonical.as_bytes());
    let hex = hasher.finalize().to_hex();
    Ok(hex.as_str()[..16].to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dsl::parse_map_spec;

    fn spec(s: &str) -> MapSpec {
        parse_map_spec(s).unwrap()
    }

    #[test]
    fn key_is_stable() {
        let s = spec(
            r#"
size = [600, 400]

[layers.base]
features = ["country/DEU"]
"#,
        );
        let a = cache_key(&s, b"theme1").unwrap();
        let b = cache_key(&s, b"theme1").unwrap();
        assert_eq!(a, b);
        assert_eq!(a.len(), 16);
    }

    #[test]
    fn key_changes_with_content() {
        let a = cache_key(
            &spec(r#"
size = [600, 400]
[layers.base]
features = ["country/DEU"]
"#),
            b"t",
        )
        .unwrap();
        let b = cache_key(
            &spec(r#"
size = [600, 400]
[layers.base]
features = ["country/FRA"]
"#),
            b"t",
        )
        .unwrap();
        assert_ne!(a, b);
    }

    #[test]
    fn key_changes_with_theme_bytes() {
        let s = spec(
            r#"
size = [600, 400]
[layers.base]
features = []
"#,
        );
        let a = cache_key(&s, b"theme1").unwrap();
        let b = cache_key(&s, b"theme2").unwrap();
        assert_ne!(a, b);
    }

    #[test]
    fn key_changes_with_layer_order() {
        // Reordering layers changes DOM stacking, so the cache key
        // must differ.
        let a = cache_key(
            &spec(r#"
size = [600, 400]
[layers.alpha]
features = []
[layers.zeta]
features = []
"#),
            b"t",
        )
        .unwrap();
        let b = cache_key(
            &spec(r#"
size = [600, 400]
[layers.zeta]
features = []
[layers.alpha]
features = []
"#),
            b"t",
        )
        .unwrap();
        assert_ne!(a, b);
    }
}
