//! Types shared between the AnkiConnect client and the diff engine.
//!
//! Identity model:
//!
//!   * `#id(<hex>)` in the markdown → used as the Anki note's `guid` on
//!     `addNote`. That guid stays stable across all devices, so moving a
//!     file or renaming doesn't confuse any client.
//!   * content hash → stored as a tag `marki::hash:<hex>` on the note.
//!     No hidden fields, no custom note types — stock `Basic` / `Cloze`
//!     are used verbatim.
//!
//! The tag `marki` is applied to every managed note so
//! `findNotes tag:marki` returns only ours.

use serde::{Deserialize, Serialize};

/// Which stock Anki note type a card uses.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ModelKind {
    Basic,
    Cloze,
}

impl ModelKind {
    pub fn model_name(self) -> &'static str {
        match self {
            ModelKind::Basic => "Basic",
            ModelKind::Cloze => "Cloze",
        }
    }

    /// Field names in the stock Anki models.
    pub fn field_names(self) -> &'static [&'static str] {
        match self {
            ModelKind::Basic => &["Front", "Back"],
            ModelKind::Cloze => &["Text", "Back Extra"],
        }
    }
}

/// Marker tag applied to every managed note. `findNotes "tag:marki"`
/// returns exactly the set we're responsible for.
pub const MARKER_TAG: &str = "marki";

/// Prefix of the identity tag: full form is `marki::id:<hex>`.
pub const ID_TAG_PREFIX: &str = "marki::id:";

/// Prefix of the content-hash tag: full form is `marki::hash:<16 hex>`.
pub const HASH_TAG_PREFIX: &str = "marki::hash:";

/// Subset of `notesInfo` / `cardsInfo` output we care about.
#[derive(Debug, Clone)]
pub struct ManagedNote {
    /// Anki-assigned noteId. Used when issuing follow-up updates.
    pub anki_note_id: i64,
    /// Our stable identity, recovered from the `marki::id:<hex>` tag.
    pub marki_id: String,
    /// Content hash recovered from the `marki::hash:<hex>` tag.
    pub hash: String,
    pub model_name: String,
    /// Deck path ("math::algebra") for this note's first card.
    pub deck: String,
    /// User-visible Anki tags, with every `marki`-prefixed tag stripped.
    pub anki_tags: Vec<String>,
    /// Card ids attached to this note, needed by `changeDeck`.
    pub card_ids: Vec<i64>,
}

/// Remove the marker tag and every `marki::*` tag from a list.
pub fn strip_marker(tags: &[String]) -> Vec<String> {
    tags.iter()
        .filter(|t| !is_marker_tag(t))
        .cloned()
        .collect()
}

/// Produce the full tag set to store on an Anki note: marker tag +
/// id tag + hash tag + user tags (with any stray marker-namespace tags
/// filtered out).
pub fn full_tag_set(user_tags: &[String], marki_id: &str, hash: &str) -> Vec<String> {
    let mut out = Vec::with_capacity(user_tags.len() + 3);
    out.push(MARKER_TAG.to_string());
    out.push(format!("{ID_TAG_PREFIX}{marki_id}"));
    out.push(format!("{HASH_TAG_PREFIX}{hash}"));
    for t in user_tags {
        if !is_marker_tag(t) {
            out.push(t.clone());
        }
    }
    out
}

/// Extract the marki id from a note's tag list, if any.
pub fn id_from_tags(tags: &[String]) -> Option<String> {
    tags.iter()
        .find_map(|t| t.strip_prefix(ID_TAG_PREFIX).map(String::from))
}

/// Extract the hash from a note's tag list, if any.
pub fn hash_from_tags(tags: &[String]) -> Option<String> {
    tags.iter()
        .find_map(|t| t.strip_prefix(HASH_TAG_PREFIX).map(String::from))
}

fn is_marker_tag(tag: &str) -> bool {
    tag == MARKER_TAG || tag.starts_with(&format!("{MARKER_TAG}::"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn full_tag_set_round_trip() {
        let user = vec!["geography".to_string(), "europe".to_string()];
        let id = "deadbeef00000001";
        let hash = "a1b2c3d4e5f60718";
        let full = full_tag_set(&user, id, hash);

        assert!(full.contains(&"marki".to_string()));
        assert!(full.contains(&format!("marki::id:{id}")));
        assert!(full.contains(&format!("marki::hash:{hash}")));

        let back_user = strip_marker(&full);
        assert_eq!(user, back_user);

        assert_eq!(id_from_tags(&full).as_deref(), Some(id));
        assert_eq!(hash_from_tags(&full).as_deref(), Some(hash));
    }

    #[test]
    fn unknown_marki_namespace_is_dropped_from_user_tags() {
        let tags = vec![
            "marki".into(),
            "marki::id:deadbeef".into(),
            "marki::hash:abcdef0011223344".into(),
            "marki::some-future-ns".into(),
            "real-tag".into(),
        ];
        let user = strip_marker(&tags);
        assert_eq!(user, vec!["real-tag".to_string()]);
    }

    #[test]
    fn stray_marker_tags_in_input_dont_duplicate_on_build() {
        let already = vec!["marki".into(), "x".into()];
        let full = full_tag_set(&already, "id1", "deadbeefdeadbeef");
        assert_eq!(full.iter().filter(|t| t.as_str() == "marki").count(), 1);
    }
}
