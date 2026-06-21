//! Project-level map defaults and path-scoped rules.
//!
//! A marki project can set DSL defaults for every `map` block in its
//! `config.toml`, and override them per directory via glob rules:
//!
//! ```toml
//! [map.defaults]
//! style = "blueprint"
//! [map.defaults.viewport]
//! simplify_px = 1.2
//!
//! [[map.rules]]
//! match = "Geography/**"          # globset, relative to cards_dir
//! [map.rules.defaults.viewport]
//! cluster_factor = 0.3
//! ```
//!
//! These are merged underneath each card's own `map` block before the
//! [`crate::dsl::MapSpec`] is built, so an author's explicit values
//! always win. Precedence, low → high:
//!
//! 1. hardcoded DSL defaults (serde `#[serde(default)]`)
//! 2. `[map.defaults]` (global)
//! 3. every matching `[[map.rules]]`, in declaration order (layered)
//! 4. the card's ```` ```map ```` block
//!
//! Merging happens at the `toml::Table` level (see [`deep_merge`]):
//! tables merge key-wise and recursively; scalars and arrays replace
//! wholesale. The merged table is then deserialized into a `MapSpec`,
//! so `deny_unknown_fields` still catches typos in config defaults.

use globset::{Glob, GlobMatcher};
use serde::Deserialize;
use std::path::{Path, PathBuf};
use toml::{Table, Value};

/// Raw `[map]` config section, as deserialized from `config.toml`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MapDefaults {
    /// Global defaults applied to every map card.
    #[serde(default)]
    pub defaults: Table,
    /// Path-scoped overrides, applied in order on top of `defaults`.
    #[serde(default)]
    pub rules: Vec<MapRule>,
}

/// One path-scoped default rule.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MapRule {
    /// Glob (globset syntax) matched against the card path **relative to
    /// `cards_dir`**, e.g. `Geography/**` or `**/*.md`.
    #[serde(rename = "match")]
    pub pattern: String,
    /// Default DSL values applied when the rule matches.
    #[serde(default)]
    pub defaults: Table,
}

/// Compiled, ready-to-apply form of [`MapDefaults`]: globs are compiled
/// once and matching is done against paths relative to `cards_dir`.
#[derive(Clone)]
pub struct CompiledDefaults {
    global: Table,
    rules: Vec<(GlobMatcher, Table)>,
    cards_dir: PathBuf,
}

impl CompiledDefaults {
    /// An empty set of defaults — the renderer behaves exactly as if no
    /// `[map]` config were present.
    pub fn empty() -> Self {
        Self {
            global: Table::new(),
            rules: Vec::new(),
            cards_dir: PathBuf::new(),
        }
    }

    /// Compile rule globs. Returns an error naming the first bad pattern.
    pub fn compile(defs: MapDefaults, cards_dir: PathBuf) -> Result<Self, String> {
        let mut rules = Vec::with_capacity(defs.rules.len());
        for r in defs.rules {
            let glob = Glob::new(&r.pattern)
                .map_err(|e| format!("invalid map rule pattern `{}`: {e}", r.pattern))?;
            rules.push((glob.compile_matcher(), r.defaults));
        }
        Ok(Self {
            global: defs.defaults,
            rules,
            cards_dir,
        })
    }

    /// True when there is nothing to merge.
    pub fn is_empty(&self) -> bool {
        self.global.is_empty() && self.rules.is_empty()
    }

    /// Build the effective default table for a card at `source_path`:
    /// the global defaults with every matching rule layered on top in
    /// declaration order.
    pub fn effective_table(&self, source_path: &Path) -> Table {
        let mut out = self.global.clone();
        let rel = source_path
            .strip_prefix(&self.cards_dir)
            .unwrap_or(source_path);
        for (matcher, table) in &self.rules {
            if matcher.is_match(rel) {
                deep_merge(&mut out, table);
            }
        }
        out
    }
}

/// Recursively merge `over` into `base`. Nested tables are merged
/// key-wise; every other value (scalars, arrays, mixed type changes)
/// from `over` replaces the one in `base`. `over` therefore has higher
/// precedence.
pub fn deep_merge(base: &mut Table, over: &Table) {
    for (k, v) in over {
        match (base.get_mut(k), v) {
            (Some(Value::Table(bt)), Value::Table(ot)) => deep_merge(bt, ot),
            _ => {
                base.insert(k.clone(), v.clone());
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn table(src: &str) -> Table {
        src.parse().unwrap()
    }

    #[test]
    fn deep_merge_recurses_tables_and_replaces_scalars() {
        let mut base = table("style = \"atlas\"\n[viewport]\nsimplify_px = 1.5\nmin_island_px = 2.0");
        let over = table("style = \"blueprint\"\n[viewport]\nsimplify_px = 0.8");
        deep_merge(&mut base, &over);
        assert_eq!(base["style"].as_str(), Some("blueprint"));
        let vp = base["viewport"].as_table().unwrap();
        // Scalar replaced…
        assert_eq!(vp["simplify_px"].as_float(), Some(0.8));
        // …sibling key preserved (recursive merge, not wholesale replace).
        assert_eq!(vp["min_island_px"].as_float(), Some(2.0));
    }

    #[test]
    fn deep_merge_replaces_arrays_wholesale() {
        let mut base = table("size = [600, 400]");
        let over = table("size = [800, 800]");
        deep_merge(&mut base, &over);
        let arr: Vec<i64> = base["size"]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_integer().unwrap())
            .collect();
        assert_eq!(arr, vec![800, 800]);
    }

    #[test]
    fn effective_layers_matching_rules_in_order() {
        let defs = MapDefaults {
            defaults: table("style = \"atlas\"\n[viewport]\nsimplify_px = 1.5"),
            rules: vec![
                MapRule {
                    pattern: "Geography/**".into(),
                    defaults: table("[viewport]\nsimplify_px = 1.0\ncluster_factor = 0.3"),
                },
                MapRule {
                    pattern: "Geography/Africa/**".into(),
                    defaults: table("[viewport]\nsimplify_px = 0.8"),
                },
            ],
        };
        let c = CompiledDefaults::compile(defs, PathBuf::from("/cards")).unwrap();

        // A card outside Geography: only globals.
        let t = c.effective_table(Path::new("/cards/History/rome.md"));
        assert_eq!(t["viewport"].as_table().unwrap()["simplify_px"].as_float(), Some(1.5));
        assert!(t["viewport"].as_table().unwrap().get("cluster_factor").is_none());

        // A card under Geography but not Africa: global + first rule.
        let t = c.effective_table(Path::new("/cards/Geography/asia.md"));
        let vp = t["viewport"].as_table().unwrap();
        assert_eq!(vp["simplify_px"].as_float(), Some(1.0));
        assert_eq!(vp["cluster_factor"].as_float(), Some(0.3));

        // A card under Geography/Africa: both rules layer, last wins.
        let t = c.effective_table(Path::new("/cards/Geography/Africa/rwanda.md"));
        let vp = t["viewport"].as_table().unwrap();
        assert_eq!(vp["simplify_px"].as_float(), Some(0.8));
        assert_eq!(vp["cluster_factor"].as_float(), Some(0.3));
    }

    #[test]
    fn compile_rejects_bad_glob() {
        let defs = MapDefaults {
            defaults: Table::new(),
            rules: vec![MapRule {
                pattern: "a/[".into(),
                defaults: Table::new(),
            }],
        };
        assert!(CompiledDefaults::compile(defs, PathBuf::new()).is_err());
    }

    #[test]
    fn empty_defaults_are_empty() {
        assert!(CompiledDefaults::empty().is_empty());
    }
}
