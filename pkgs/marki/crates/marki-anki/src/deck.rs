//! Building deck rows. Deck names are stored in Anki's "native" form where
//! nesting is a `0x1f` unit separator (not `::`), and every ancestor deck
//! must exist as its own row. Both rules are ported verbatim from rslib
//! (`rslib/src/decks/name.rs`); getting them wrong makes decks vanish from
//! the browser or reappear on sync.

use std::borrow::Cow;

use unicode_normalization::{UnicodeNormalization, is_nfc};

use crate::proto::decks::deck::kind_container::Kind;
use crate::proto::decks::deck::{Common, KindContainer, Normal};

/// The native nesting separator. `geography::europe` is stored as
/// `geography\x1feurope`.
pub const SEPARATOR: char = '\u{1f}';

/// Every new deck references the single default deck-config row (`id = 1`),
/// exactly as Anki does when creating a deck without a custom preset.
pub const DEFAULT_CONFIG_ID: i64 = 1;

/// rslib `normalize_to_nfc`: NFC form, borrowing when already normalized.
fn normalize_to_nfc(s: &str) -> Cow<'_, str> {
    if is_nfc(s) {
        Cow::Borrowed(s)
    } else {
        Cow::Owned(s.nfc().collect())
    }
}

fn invalid_char_for_deck_component(c: char) -> bool {
    c.is_ascii_control()
}

/// rslib `normalized_deck_name_component`: NFC, strip ASCII control chars,
/// trim surrounding whitespace and `:`, and map an empty result to the
/// literal `"blank"`.
fn normalized_component(comp: &str) -> String {
    let mut out = normalize_to_nfc(comp).into_owned();
    if out.contains(invalid_char_for_deck_component) {
        out = out.replace(invalid_char_for_deck_component, "");
    }
    let trimmed = out.trim_matches(|c: char| c.is_whitespace() || c == ':');
    if trimmed.is_empty() {
        "blank".to_string()
    } else {
        trimmed.to_string()
    }
}

/// Convert a human `::`-separated deck name to native `\x1f` form, mirroring
/// `NativeDeckName::from_human_name`.
pub fn human_to_native(human: &str) -> String {
    human
        .split("::")
        .map(normalized_component)
        .collect::<Vec<_>>()
        .join(&SEPARATOR.to_string())
}

/// Build a human deck name from ordered path components (e.g. a directory
/// path `["geography", "europe"]` -> `"geography::europe"`).
pub fn human_from_components<I, S>(components: I) -> String
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    components
        .into_iter()
        .map(|c| c.as_ref().to_string())
        .collect::<Vec<_>>()
        .join("::")
}

/// The immediate parent of a native deck name, or `None` at the top level.
pub fn immediate_parent(native: &str) -> Option<&str> {
    native.rsplit_once(SEPARATOR).map(|(parent, _)| parent)
}

/// Convert a native `\x1f`-separated deck name back to human `::` form, the
/// inverse of [`human_to_native`] for display and diffing.
pub fn native_to_human(native: &str) -> String {
    native.replace(SEPARATOR, "::")
}

/// A fresh deck's `common` blob: all defaults (no study history yet).
pub fn common() -> Common {
    Common::default()
}

/// A fresh deck's `kind` blob: a normal (non-filtered) deck bound to the
/// default deck config.
pub fn normal_kind(config_id: i64) -> KindContainer {
    KindContainer {
        kind: Some(Kind::Normal(Normal {
            config_id,
            ..Default::default()
        })),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn human_to_native_matches_rslib_vectors() {
        // Straight from rslib name.rs `from_human` test.
        assert_eq!(human_to_native("foo"), "foo");
        assert_eq!(human_to_native("foo::bar"), "foo\u{1f}bar");
        assert_eq!(human_to_native("foo::::baz"), "foo\u{1f}blank\u{1f}baz");
        assert_eq!(human_to_native("fo\u{1f}o::ba\nr"), "foo\u{1f}bar");
        assert_eq!(human_to_native("fo\u{a}o\u{1f}bar"), "foobar");
        assert_eq!(human_to_native("foo:::bar"), "foo\u{1f}bar");
        assert_eq!(human_to_native("foo:::bar:baz: "), "foo\u{1f}bar:baz");
    }

    #[test]
    fn parents_walk_up_the_hierarchy() {
        assert_eq!(immediate_parent("foo"), None);
        assert_eq!(immediate_parent("foo\u{1f}bar"), Some("foo"));
        assert_eq!(
            immediate_parent("foo\u{1f}bar\u{1f}baz"),
            Some("foo\u{1f}bar")
        );
    }

    #[test]
    fn components_join_to_human() {
        assert_eq!(
            human_from_components(["geography", "europe"]),
            "geography::europe"
        );
    }

    #[test]
    fn normal_kind_binds_default_config() {
        let k = normal_kind(DEFAULT_CONFIG_ID);
        match k.kind {
            Some(Kind::Normal(n)) => assert_eq!(n.config_id, 1),
            other => panic!("expected normal kind, got {other:?}"),
        }
    }
}
