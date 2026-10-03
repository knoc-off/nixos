//! Tag helpers shared between the reconcile engine and the note writer.
//!
//! Identity model:
//!
//!   * `#id(<hex>)` in the markdown becomes the note's `guid` directly (the
//!     direct-SQLite writer sets `notes.guid`), so identity is no longer
//!     carried in a tag.
//!   * content hash -> stored as a tag `marki::hash:<hex>` on the note.
//!
//! Every managed note also carries the marker tag `marki`, so a whole-tag
//! match on ` marki ` returns exactly the set we are responsible for.

/// Marker tag applied to every managed note. A note carrying it is one marki
/// manages; anything else in the collection is left alone.
pub const MARKER_TAG: &str = "marki";

/// Prefix of the content-hash tag: full form is `marki::hash:<16 hex>`.
pub const HASH_TAG_PREFIX: &str = "marki::hash:";

/// Prefix of the own-input hash tag, set only on notes whose model reads
/// other notes (`ctx:notes`): `marki::src:<16 hex>` over the note's own
/// source and model script. Output changed but this didn't = the change
/// came from another note.
pub const SRC_TAG_PREFIX: &str = "marki::src:";

/// Tag applied to a note that has been quarantined (soft-deleted): it no
/// longer has a matching `.md` source, so it was suspended and tagged
/// rather than deleted. `tag:marki::orphan` lists them, and `marki prune`
/// purges them. Because it lives in the `marki::` namespace it is stripped
/// from user-visible tags and cleared automatically if the source file
/// reappears and the note is updated.
pub const ORPHAN_TAG: &str = "marki::orphan";

/// Remove the marker tag and every `marki::*` tag from a list.
pub fn strip_marker(tags: &[String]) -> Vec<String> {
    tags.iter()
        .filter(|t| !is_marker_tag(t))
        .cloned()
        .collect()
}

/// Produce the full tag set to store on a note: marker tag + hash tag (+
/// own-input tag) + user tags (with any stray marker-namespace tags
/// filtered out). Identity lives in the note's `guid`, not in a tag.
pub fn full_tag_set(user_tags: &[String], hash: &str, own_hash: Option<&str>) -> Vec<String> {
    let mut out = Vec::with_capacity(user_tags.len() + 3);
    out.push(MARKER_TAG.to_string());
    out.push(format!("{HASH_TAG_PREFIX}{hash}"));
    if let Some(s) = own_hash {
        out.push(format!("{SRC_TAG_PREFIX}{s}"));
    }
    for t in user_tags {
        if !is_marker_tag(t) {
            out.push(t.clone());
        }
    }
    out
}

/// Extract the hash from a note's tag list, if any.
pub fn hash_from_tags(tags: &[String]) -> Option<String> {
    tags.iter()
        .find_map(|t| t.strip_prefix(HASH_TAG_PREFIX).map(String::from))
}

/// Extract the own-input hash (see [`SRC_TAG_PREFIX`]), if any.
pub fn src_hash_from_tags(tags: &[String]) -> Option<String> {
    tags.iter().find_map(|t| t.strip_prefix(SRC_TAG_PREFIX).map(String::from))
}

fn is_marker_tag(tag: &str) -> bool {
    tag == MARKER_TAG || tag.starts_with("marki::")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn full_tag_set_round_trip() {
        let user = vec!["geography".to_string(), "europe".to_string()];
        let hash = "a1b2c3d4e5f60718";
        let full = full_tag_set(&user, hash, Some("0011223344556677"));

        assert!(full.contains(&"marki".to_string()));
        assert!(full.contains(&format!("marki::hash:{hash}")));

        let back_user = strip_marker(&full);
        assert_eq!(user, back_user);

        assert_eq!(hash_from_tags(&full).as_deref(), Some(hash));
        assert_eq!(src_hash_from_tags(&full).as_deref(), Some("0011223344556677"));
        assert_eq!(src_hash_from_tags(&full_tag_set(&user, hash, None)), None);
    }

    #[test]
    fn unknown_marki_namespace_is_dropped_from_user_tags() {
        let tags = vec![
            "marki".into(),
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
        let full = full_tag_set(&already, "deadbeefdeadbeef", None);
        assert_eq!(full.iter().filter(|t| t.as_str() == "marki").count(), 1);
    }
}
