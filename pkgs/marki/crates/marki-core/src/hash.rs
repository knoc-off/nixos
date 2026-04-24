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
}
