//! Version-bound content hash.
//!
//! The hash is BLAKE3 over (RENDER_VERSION || content), truncated to 16 hex
//! characters (64 bits). That gives us effectively zero accidental collisions
//! at any realistic collection size, while being short enough to sit on a
//! single line of a markdown file.
//!
//! Version-binding means bumping `RENDER_VERSION` invalidates every stored
//! hash, so the diff engine naturally re-pushes every note on the next cycle.

use crate::version::RENDER_VERSION;

/// Stable 16-hex-char version+content signature used in `#hash(...)`.
pub fn content_hash(content: &str) -> String {
    let mut hasher = blake3::Hasher::new();
    hasher.update(&RENDER_VERSION.to_le_bytes());
    hasher.update(content.as_bytes());
    truncate_hash(hasher)
}

/// Version-bound hash over the final rendered HTML (front + back).
///
/// Called by the sync engine *after* external block placeholders have
/// been spliced. A NUL separator prevents collisions from content
/// that could be rearranged across front/back to produce the same
/// concatenation.
pub fn content_hash_html(front: &str, back: &str) -> String {
    let mut hasher = blake3::Hasher::new();
    hasher.update(&RENDER_VERSION.to_le_bytes());
    hasher.update(front.as_bytes());
    hasher.update(&[0]);
    hasher.update(back.as_bytes());
    truncate_hash(hasher)
}

fn truncate_hash(hasher: blake3::Hasher) -> String {
    let out = hasher.finalize();
    let bytes = out.as_bytes();
    // 8 bytes = 16 hex chars
    let mut s = String::with_capacity(16);
    for b in &bytes[..8] {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_is_16_hex_chars() {
        let h = content_hash("hello");
        assert_eq!(h.len(), 16);
        assert!(h.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn hash_is_stable() {
        assert_eq!(content_hash("hello"), content_hash("hello"));
    }

    #[test]
    fn hash_changes_with_content() {
        assert_ne!(content_hash("hello"), content_hash("world"));
    }

    #[test]
    fn html_hash_is_stable() {
        let a = content_hash_html("<p>front</p>", "<p>back</p>");
        let b = content_hash_html("<p>front</p>", "<p>back</p>");
        assert_eq!(a, b);
        assert_eq!(a.len(), 16);
    }

    #[test]
    fn html_hash_not_fooled_by_front_back_swap() {
        let a = content_hash_html("ab", "cd");
        let b = content_hash_html("abc", "d");
        assert_ne!(a, b);
    }
}
