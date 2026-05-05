//! `marki-typst` — render `typst` blocks by shelling out to the
//! `typst` binary.
//!
//! Implements `marki_core::BlockRenderer` for the lang token `typst`.
//! The block body is **raw Typst** (not TOML, unlike `map` and `media`).
//! In a card's markdown, authors write a fenced block tagged `typst`
//! containing arbitrary Typst source — `#import` directives, math,
//! circuit diagrams via `@preview/circuiteria`, and so on.
//!
//! The renderer prepends a small preamble that auto-sizes the page
//! to the content and removes default margins/fill, invokes
//! `typst compile --format svg`, and emits the resulting SVG as an
//! [`marki_core::EmittedAsset`].
//!
//! Compiled SVGs are cached at `<cache_dir>/typst/<key>/output.svg`,
//! keyed by `blake3(RENDER_VERSION_TYPST | preamble | source)`.
//! Subsequent renders of the same block source skip the subprocess.
//!
//! The user controls the `typst` binary path — they can install
//! plugins, fonts, or pin a version however they like and pass it in
//! via the markid config / `MARKID_TYPST` env var.

pub mod error;
pub mod render;
pub mod version;

use std::path::PathBuf;

use marki_core::{BlockError, BlockRenderer, RenderCtx, RenderedBlock};

pub use error::TypstError;
pub use version::RENDER_VERSION_TYPST;

/// Lang token this renderer handles: `typst`.
pub const TYPST_LANG: &str = "typst";

/// Typst block renderer. Construct with [`TypstRenderer::new`] and
/// register against the markid daemon's renderer registry.
pub struct TypstRenderer {
    /// Path to the `typst` CLI binary. The user supplies this — we
    /// don't pin a version or require a particular install method.
    binary: PathBuf,
}

impl TypstRenderer {
    pub fn new(binary: PathBuf) -> Self {
        Self { binary }
    }
}

impl BlockRenderer for TypstRenderer {
    fn lang(&self) -> &'static str {
        TYPST_LANG
    }

    fn render(&self, src: &str, ctx: &mut RenderCtx<'_>) -> Result<RenderedBlock, BlockError> {
        Ok(render::run(&self.binary, src, ctx)?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn lang_token_is_typst() {
        let r = TypstRenderer::new(PathBuf::from("/nonexistent"));
        assert_eq!(r.lang(), "typst");
    }
}
