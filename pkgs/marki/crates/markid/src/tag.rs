//! Tag system.
//!
//! One enum, one hand-written parser. During scan we regex out every
//! `#word` or `#word(arg)` token from the source markdown and attempt to
//! parse each into a `SystemTag`:
//!
//!   * success -> strip from source; do not forward to Anki; act on it
//!   * failure (unknown keyword / malformed) -> leave in source; pass through
//!     to Anki as a standard tag

use regex::Regex;
use std::str::FromStr;
use std::sync::LazyLock;
use strum::{Display, EnumString};

/// Regex matching a `#tag` or `#tag(args)` token. Used by all parsers/renderers.
pub static TAG_REGEX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"#([A-Za-z][\w:\-]*(?:\([^)]*\))?)").unwrap()
});

/// Our stable identity for a note. Completely independent of Anki's own
/// `noteId` — we mint these as hex-encoded 128-bit random UUIDs and store
/// the value on Anki notes via the hidden `Marki_Id` field.
pub type NoteId = String;

/// Strategy used to number `**bold**` / `*italic*` spans as `{{cN::...}}`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Display, EnumString, Default)]
#[strum(serialize_all = "lowercase")]
pub enum ClozeAlgorithm {
    /// Every emphasised span gets the next integer (c1, c2, c3, ...).
    Increment,
    /// Bold → c1, italic → c2.
    Duo,
    /// Pick `Duo` if the note mixes bold+italic, else `Increment`.
    #[default]
    Auto,
}

/// The closed set of system tags we recognise. Everything else in the
/// markdown that syntactically looks like a tag passes through as an Anki tag.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SystemTag {
    /// `#id(<hex>)` -- stable marki identity. 32 hex chars expected but we
    /// don't enforce length here; the parser just takes whatever string.
    Id(NoteId),

    /// `#model(<name>)` -- selects the model script. Built-in names:
    /// `basic`, `cloze`. Any other string loads `models/<name>`.
    Model(String),

    /// `#cloze` or `#cloze(duo|auto|increment)` -- implies cloze model.
    Cloze(Option<ClozeAlgorithm>),

    /// `#basic` -- explicit basic model (default).
    Basic,
}

impl FromStr for SystemTag {
    type Err = TagParseError;

    /// Parse one `#keyword` or `#keyword(arg)` token.
    ///
    /// A leading `#` is optional so callers can pass either the raw token or
    /// the regex capture group.
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let s = s.trim();
        let s = s.strip_prefix('#').unwrap_or(s);

        let (keyword, arg) = match s.find('(') {
            Some(open) => {
                if !s.ends_with(')') {
                    return Err(TagParseError::Malformed(s.to_string()));
                }
                (&s[..open], Some(&s[open + 1..s.len() - 1]))
            }
            None => (s, None),
        };

        let require = |kw: &str| {
            arg.ok_or_else(|| TagParseError::MissingArg(kw.to_string()))
        };
        let forbid = |kw: &str| match arg {
            Some(_) => Err(TagParseError::UnexpectedArg(kw.to_string())),
            None => Ok(()),
        };

        match keyword {
            // Id and Model take the argument verbatim, so there is no
            // way for them to fail beyond being absent.
            "id" => Ok(SystemTag::Id(require("id")?.to_string())),
            "model" => Ok(SystemTag::Model(require("model")?.to_string())),
            "cloze" => match arg {
                None => Ok(SystemTag::Cloze(None)),
                Some(a) => a
                    .parse()
                    .map(|alg| SystemTag::Cloze(Some(alg)))
                    .map_err(|_| TagParseError::BadArg {
                        tag: "cloze".to_string(),
                        arg: a.to_string(),
                    }),
            },
            "basic" => {
                forbid("basic")?;
                Ok(SystemTag::Basic)
            }
            other => Err(TagParseError::Unknown(other.to_string())),
        }
    }
}

/// Error type produced by [`SystemTag::from_str`].
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum TagParseError {
    #[error("unknown tag `{0}`")]
    Unknown(String),
    #[error("tag `{tag}` got invalid argument `{arg}`")]
    BadArg { tag: String, arg: String },
    #[error("tag `{0}` requires an argument")]
    MissingArg(String),
    #[error("tag `{0}` takes no argument")]
    UnexpectedArg(String),
    #[error("malformed tag `{0}`")]
    Malformed(String),
}

/// Outcome of attempting to deserialize one `#...` token.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Parsed {
    System(SystemTag),
    AnkiTag(String),
    Error(TagParseError),
}

pub fn parse_token(token: &str) -> Parsed {
    match SystemTag::from_str(token) {
        Ok(tag) => Parsed::System(tag),
        Err(TagParseError::Unknown(kw)) => Parsed::AnkiTag(kw),
        Err(e) => Parsed::Error(e),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bare_unit_variant() {
        assert_eq!(parse_token("#basic"), Parsed::System(SystemTag::Basic));
    }

    #[test]
    fn id_with_hex() {
        assert_eq!(
            parse_token("#id(abcdef0123456789abcdef0123456789)"),
            Parsed::System(SystemTag::Id(
                "abcdef0123456789abcdef0123456789".into()
            ))
        );
    }

    #[test]
    fn id_missing_arg_errors() {
        let r = parse_token("#id");
        assert!(matches!(r, Parsed::Error(TagParseError::MissingArg(_))));
    }

    #[test]
    fn optional_arg_absent() {
        assert_eq!(parse_token("#cloze"), Parsed::System(SystemTag::Cloze(None)));
    }

    #[test]
    fn optional_arg_present() {
        assert_eq!(
            parse_token("#cloze(auto)"),
            Parsed::System(SystemTag::Cloze(Some(ClozeAlgorithm::Auto)))
        );
    }

    #[test]
    fn unknown_keyword_is_anki_tag() {
        assert_eq!(
            parse_token("#geography"),
            Parsed::AnkiTag("geography".into())
        );
    }

    #[test]
    fn malformed_unclosed_paren() {
        let r = parse_token("#id(123");
        assert!(matches!(r, Parsed::Error(TagParseError::Malformed(_))));
    }

    #[test]
    fn model_arg() {
        assert_eq!(
            parse_token("#model(cloze)"),
            Parsed::System(SystemTag::Model("cloze".into()))
        );
    }

    #[test]
    fn model_custom_name() {
        assert_eq!(
            parse_token("#model(geographic-location)"),
            Parsed::System(SystemTag::Model("geographic-location".into()))
        );
    }

    #[test]
    fn unit_with_args_errors() {
        let r = parse_token("#basic(foo)");
        assert!(matches!(r, Parsed::Error(TagParseError::UnexpectedArg(_))));
    }
}
