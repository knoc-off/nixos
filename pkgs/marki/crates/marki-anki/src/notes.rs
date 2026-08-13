//! Note field encoding: the exact transforms rslib applies before a note is
//! written. Every function here mirrors `rslib/src/notes/mod.rs` and
//! `rslib/src/text.rs`; the field-count / csum / sfld rules are the single
//! most common way to corrupt a collection, so this stays faithful.

use std::sync::LazyLock;

use regex::Regex;
use sha1::{Digest, Sha1};
use unicode_normalization::{UnicodeNormalization, is_nfc};

/// The field separator Anki joins `flds` with.
pub const FIELD_SEPARATOR: char = '\u{1f}';

// rslib text.rs: comments, style/script blocks, then any tag.
static HTML: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?si)(<!--.*?-->)|(<style.*?>.*?</style>)|(<script.*?>.*?</script>)|(<.*?>)")
        .unwrap()
});

// rslib text.rs HTML_MEDIA_TAGS: img/audio/video/object/source, capturing the
// src/data filename in one of three groups (double / single / unquoted).
static HTML_MEDIA_TAGS: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r#"(?xsi)
            <\b(?:img|audio|video|object|source)\b
            (?:
                [^>]
            |
                "[^"]+?"
            |
                '[^']+?'
            )+?
            \b(?:src|data)\b=
            (?:
                    "
                    ([^"]+?)
                    "
                    [^>]*>
                |
                    '
                    ([^']+?)
                    '
                    [^>]*>
                |
                    ([^ >]+?)
                    (?:
                        \x20[^>]*>
                        |
                        >
                    )
            )
            "#,
    )
    .unwrap()
});

/// rslib `decode_entities`: html-unescape, then map non-breaking spaces to
/// regular spaces. Only runs when an `&` is present.
fn decode_entities(html: &str) -> String {
    if html.contains('&') {
        match htmlescape::decode_html(html) {
            Ok(text) => text.replace('\u{a0}', " "),
            Err(_) => html.to_string(),
        }
    } else {
        html.to_string()
    }
}

/// rslib `strip_html`: strip tags/comments/style/script, then decode entities.
fn strip_html(html: &str) -> String {
    let stripped = HTML.replace_all(html, "");
    decode_entities(&stripped)
}

/// rslib `strip_html_preserving_media_filenames`: replace media tags with a
/// space-padded copy of their src/data filename, then strip remaining HTML.
/// This is what `csum` and `sfld` are computed from.
pub fn strip_html_preserving_media_filenames(html: &str) -> String {
    let with_media = HTML_MEDIA_TAGS.replace_all(html, " ${1}${2}${3} ");
    strip_html(&with_media)
}

/// rslib `field_checksum`: first 4 bytes of the SHA-1 of the (already
/// media-preserving-stripped) text, big-endian.
pub fn field_checksum(text: &str) -> u32 {
    let mut hash = Sha1::new();
    hash.update(text);
    let digest = hash.finalize();
    u32::from_be_bytes(digest[..4].try_into().unwrap())
}

/// rslib `invalid_char_for_field`: ASCII control chars other than newline
/// and tab, which are stripped from every field.
fn invalid_char_for_field(c: char) -> bool {
    c.is_ascii_control() && c != '\n' && c != '\t'
}

/// rslib `normalize_field`: drop invalid control chars, then NFC-normalize
/// (when `normalize_text`, which is the default).
pub fn normalize_field(field: &mut String, normalize_text: bool) {
    if field.contains(invalid_char_for_field) {
        *field = field.replace(invalid_char_for_field, "");
    }
    if normalize_text && !is_nfc(field) {
        *field = field.chars().nfc().collect();
    }
}

/// Join fields into the on-disk `flds` string.
pub fn join_fields(fields: &[String]) -> String {
    fields.join(&FIELD_SEPARATOR.to_string())
}

/// Split an on-disk `flds` string back into fields.
pub fn split_fields(flds: &str) -> Vec<String> {
    flds.split(FIELD_SEPARATOR).map(str::to_string).collect()
}

/// The 91-character alphabet Anki encodes guids with (`rslib/src/notes/mod.rs`).
const BASE91_TABLE: &[u8] =
    b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&()*+,-./:;<=>?@[]^_`{|}~";

/// rslib `to_base_n`: positional encoding of `n` in the given alphabet,
/// most-significant digit first. `0` encodes to the empty string.
fn to_base_n(mut n: u64, table: &[u8]) -> String {
    let base = table.len() as u64;
    let mut buf = Vec::new();
    while n > 0 {
        buf.push(table[(n % base) as usize]);
        n /= base;
    }
    buf.reverse();
    String::from_utf8(buf).unwrap()
}

/// rslib `anki_base91`: base-91 guid encoding. Anki mints note guids by
/// encoding a random `u64` this way; marki instead derives the number from a
/// note's stable source identity so re-runs update rather than duplicate.
pub fn anki_base91(n: u64) -> String {
    to_base_n(n, BASE91_TABLE)
}

/// Canonical on-disk form of a note's tags: trimmed, de-duplicated, sorted,
/// and (when non-empty) wrapped in a single leading and trailing space, which
/// is how Anki stores `notes.tags` (`rslib` `join_tags`).
pub fn canonical_tags(tags: &[String]) -> String {
    let mut out: Vec<String> = tags
        .iter()
        .map(|t| t.trim().to_string())
        .filter(|t| !t.is_empty())
        .collect();
    out.sort_unstable();
    out.dedup();
    if out.is_empty() {
        String::new()
    } else {
        format!(" {} ", out.join(" "))
    }
}

/// Mirror of `Note::prepare_for_update`: normalize every field, then derive
/// `(csum, sfld)`. `csum` is always from field 0; `sfld` short-circuits to
/// the same stripped field-0 text when `sort_field_idx == 0`.
///
/// Returns the normalized fields alongside the derived values so the caller
/// can write a consistent row.
pub fn prepare_fields(
    mut fields: Vec<String>,
    sort_field_idx: u32,
    normalize_text: bool,
) -> (Vec<String>, u32, String) {
    for f in &mut fields {
        normalize_field(f, normalize_text);
    }
    let field1_nohtml = strip_html_preserving_media_filenames(&fields[0]);
    let csum = field_checksum(&field1_nohtml);
    let sort_field = if sort_field_idx == 0 {
        field1_nohtml
    } else {
        strip_html_preserving_media_filenames(
            fields.get(sort_field_idx as usize).map(String::as_str).unwrap_or(""),
        )
    };
    (fields, csum, sort_field)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn field_checksum_matches_rslib_vectors() {
        // Exact vectors from rslib notes/mod.rs test_field_checksum.
        assert_eq!(field_checksum("test"), 2_840_236_005);
        assert_eq!(field_checksum("今日"), 1_464_653_051);
    }

    #[test]
    fn strips_tags_but_keeps_media_filename() {
        let s = strip_html_preserving_media_filenames(
            r#"<p>see <img src="pic.png"> here</p>"#,
        );
        assert!(s.contains("pic.png"), "media filename preserved: {s:?}");
        assert!(!s.contains('<'), "tags stripped: {s:?}");
    }

    #[test]
    fn decodes_entities() {
        let s = strip_html_preserving_media_filenames("a &amp; b");
        assert_eq!(s, "a & b");
    }

    #[test]
    fn base91_matches_rslib_vectors() {
        assert_eq!(anki_base91(0), "");
        assert_eq!(anki_base91(1), "b");
        assert_eq!(anki_base91(1234567890), "saAKk");
        assert_eq!(anki_base91(u64::MAX), "Rj&Z5m[>Zp");
    }

    #[test]
    fn tags_are_sorted_deduped_and_space_wrapped() {
        assert_eq!(canonical_tags(&[]), "");
        assert_eq!(
            canonical_tags(&["geography".into(), "asia".into(), "geography".into()]),
            " asia geography "
        );
        // Whitespace-only / empty tags are dropped.
        assert_eq!(canonical_tags(&["  ".into(), "x".into()]), " x ");
    }
}
