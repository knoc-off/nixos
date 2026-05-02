//! TOML body of a `flag` fenced block.
//!
//! Authors write things like:
//!
//! ```toml
//! flag = "circle/de"       # circular German flag
//! flag = "flags/de/by"     # rectangular Bavarian flag
//! flag = "de"              # bare name, searches all sources
//! size = 200               # optional; max-width in CSS pixels
//! ```
//!
//! The `flag` field is a path with an optional source prefix. If the
//! first component matches a registered source name, the rest is looked
//! up in that source's directory. Otherwise all sources are searched in
//! registration order and the first match wins.
//!
//! `country` is accepted as an alias for `flag` for backwards compat.

use serde::{Deserialize, Serialize};

/// Top-level flag block.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct FlagSpec {
    /// Flag identifier — optionally prefixed with a source name.
    /// E.g. `"circle/de"`, `"flags/de/by"`, or just `"de"`.
    #[serde(alias = "country")]
    pub flag: String,

    /// Max-width in CSS pixels. Defaults to 200.
    #[serde(default = "default_size")]
    pub size: u32,
}

fn default_size() -> u32 {
    200
}

pub fn parse_flag_spec(src: &str) -> Result<FlagSpec, toml::de::Error> {
    toml::from_str(src)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_with_flag_field() {
        let spec = parse_flag_spec(r#"flag = "circle/de""#).unwrap();
        assert_eq!(spec.flag, "circle/de");
        assert_eq!(spec.size, 200);
    }

    #[test]
    fn parses_country_alias() {
        let spec = parse_flag_spec(r#"country = "de""#).unwrap();
        assert_eq!(spec.flag, "de");
    }

    #[test]
    fn parses_with_size() {
        let spec = parse_flag_spec("flag = \"de\"\nsize = 400").unwrap();
        assert_eq!(spec.flag, "de");
        assert_eq!(spec.size, 400);
    }

    #[test]
    fn rejects_unknown_fields() {
        let err = parse_flag_spec("flag = \"de\"\nbogus = true").unwrap_err();
        assert!(err.to_string().contains("bogus"));
    }

    #[test]
    fn requires_flag_field() {
        let err = parse_flag_spec("size = 200").unwrap_err();
        // Neither `flag` nor `country` present
        assert!(err.to_string().contains("flag"));
    }
}
