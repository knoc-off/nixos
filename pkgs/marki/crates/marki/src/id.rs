//! Random id minting. We use 128 bits of OS-provided randomness, hex-encoded,
//! yielding a 32-char lowercase hex string. Collision-free for all practical
//! collection sizes.

use crate::tag::NoteId;

pub fn mint_id() -> NoteId {
    let mut bytes = [0u8; 16];
    getrandom::fill(&mut bytes).expect("OS randomness");
    let mut s = String::with_capacity(32);
    for b in bytes {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mint_is_32_hex() {
        let id = mint_id();
        assert_eq!(id.len(), 32);
        assert!(id.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn mints_are_unique() {
        let a = mint_id();
        let b = mint_id();
        assert_ne!(a, b);
    }
}
