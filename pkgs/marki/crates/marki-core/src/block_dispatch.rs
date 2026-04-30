//! Block-renderer dispatch surface.
//!
//! marki-core stays pure — it never touches the filesystem or network. But
//! it does need to know about *external* fenced-code-block languages (e.g.
//! ` ```map `) so the parser can split them out of the normal markdown
//! pipeline and hand them to a renderer that lives outside this crate.
//!
//! The contract is intentionally small:
//!
//!   1. The parser is given a list of "external" lang tokens.
//!   2. When it sees a fenced block whose info string starts with one of
//!      those tokens, it does NOT highlight the body. Instead it:
//!         * mints a stable [`BlockReqId`] for the block,
//!         * pushes a [`BlockRequest`] onto `Card::block_requests`,
//!         * emits a placeholder HTML comment `<!--MARKI-BLOCK:<id>-->`
//!           into `front_html` or `back_html` (whichever side the block
//!           lived on).
//!   3. Some downstream caller (the markid daemon) holds a registry of
//!      [`BlockRenderer`] impls. After parsing, it iterates the requests,
//!      calls [`BlockRenderer::render`], and splices the result back into
//!      the rendered HTML.
//!
//! The [`BlockRenderer`] trait, its associated types, and the placeholder
//! syntax all live here so both the parser and the daemon can speak the
//! same protocol without a circular dep. No I/O happens in this module.

use std::path::Path;

/// Stable id for a single fenced-block-handed-off-to-a-renderer.
///
/// Currently a short hex string derived deterministically from
/// (block index, lang) so re-running the parser on the same source
/// produces the same id. The id only has to be unique *within* a single
/// parse — the daemon never compares ids across files.
pub type BlockReqId = String;

/// One fenced block the parser deferred to an external renderer.
#[derive(Debug, Clone)]
pub struct BlockRequest {
    /// Stable id for this request within its parse.
    pub id: BlockReqId,
    /// The fenced lang token (`map`, `mermaid`, …) that matched.
    pub lang: String,
    /// Verbatim block body — everything between the fence lines, with no
    /// trailing newline normalisation.
    pub source: String,
    /// Byte offset of the opening fence, for diagnostics.
    pub byte_offset: usize,
    /// Which side of the card the block was authored on. The placeholder
    /// is written to this side; renderer output replaces the placeholder.
    pub side: BlockSide,
}

/// Which "side" of a `---`-split card a block lived on.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BlockSide {
    Front,
    Back,
}

/// What an external renderer hands back. The daemon is responsible for:
///
///   * replacing `<!--MARKI-BLOCK:<id>-->` in the side that was authored
///     in with [`RenderedBlock::front_html`],
///   * appending [`RenderedBlock::back_html_extras`] to the back side,
///   * pushing each [`EmittedAsset`] into Anki's media collection.
#[derive(Debug, Clone, Default)]
pub struct RenderedBlock {
    /// HTML that replaces the placeholder on the side the block was
    /// authored on.
    pub front_html: String,
    /// HTML appended to the back side after the placeholder is replaced.
    /// Used for things like `<style>` blocks that override front-side
    /// CSS to implement reveal-on-flip.
    pub back_html_extras: String,
    /// Side-channel files the renderer produced (SVGs, JSON sidecar, …).
    /// Daemon uploads them to Anki's media collection by `filename`.
    pub assets: Vec<EmittedAsset>,
}

/// One file emitted by an external renderer. The daemon stores these in
/// Anki's media collection verbatim, using `filename` as the key.
#[derive(Debug, Clone)]
pub struct EmittedAsset {
    /// Final media basename. Renderers are expected to produce
    /// content-addressed names so two cards referencing the same logical
    /// asset converge.
    pub filename: String,
    /// Raw bytes. Held in memory; for milestone-1 outline-mode SVGs this
    /// is comfortably small (tens of KB at most).
    pub bytes: Vec<u8>,
    /// MIME hint, primarily for diagnostics — Anki infers content type
    /// from the filename extension.
    pub mime: AssetMime,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AssetMime {
    SvgXml,
    ImagePng,
    ApplicationJson,
}

impl AssetMime {
    pub fn as_str(self) -> &'static str {
        match self {
            AssetMime::SvgXml => "image/svg+xml",
            AssetMime::ImagePng => "image/png",
            AssetMime::ApplicationJson => "application/json",
        }
    }
}

/// Context passed to a renderer at `render` time. Kept minimal on
/// purpose — anything that needs to grow goes here, not into the trait
/// signature.
pub struct RenderCtx<'a> {
    /// Path to the markdown file the block came from. Renderers may use
    /// this for diagnostics. May be a synthetic path during tests.
    pub source_path: &'a Path,
    /// Cache root the renderer is allowed to write into. Daemons typically
    /// pass `$XDG_CACHE_HOME/marki/`; tests pass a tempdir.
    pub cache_dir: &'a Path,
}

/// Errors a renderer can return. The daemon turns each into a per-card
/// failure (logged, recorded in the cycle outcome, batch continues).
#[derive(Debug, thiserror::Error)]
pub enum BlockError {
    /// Bad DSL / bad block body.
    #[error("parse: {0}")]
    Parse(String),
    /// Reference to data that doesn't exist (unknown OSM relation, etc).
    #[error("resolve: {0}")]
    Resolve(String),
    /// Network failure or rate limit.
    #[error("network: {0}")]
    Network(String),
    /// Cache I/O problem.
    #[error("cache: {0}")]
    Cache(String),
    /// Other I/O problem.
    #[error("io: {0}")]
    Io(String),
    /// Catch-all for renderer-internal errors.
    #[error("render: {0}")]
    Internal(String),
}

/// Implemented by external block renderers (e.g. `marki-map`'s
/// `MapRenderer`). The daemon owns a registry keyed by [`Self::lang`].
///
/// Renderer output format changes are signaled by bumping
/// [`crate::version::RENDER_VERSION`]; that's coarse but cheap and
/// good enough for now.
pub trait BlockRenderer: Send + Sync {
    /// Fenced lang token this renderer handles (e.g. `"map"`).
    fn lang(&self) -> &'static str;

    /// Render one block.
    fn render(&self, src: &str, ctx: &mut RenderCtx<'_>) -> Result<RenderedBlock, BlockError>;
}

/// Mint a deterministic short id for a block at `index` of lang `lang`
/// within a single parse. Format: 8 hex chars.
pub(crate) fn mint_block_req_id(index: usize, lang: &str) -> BlockReqId {
    let mut hasher = blake3::Hasher::new();
    hasher.update(&(index as u64).to_le_bytes());
    hasher.update(lang.as_bytes());
    let hex = hasher.finalize().to_hex();
    hex.as_str()[..8].to_string()
}

/// Produce the placeholder string the parser inserts and the daemon
/// replaces. Centralised so tests can use it without copy-pasting.
pub fn placeholder_for(id: &BlockReqId) -> String {
    format!("<!--MARKI-BLOCK:{id}-->")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_are_stable() {
        assert_eq!(mint_block_req_id(0, "map"), mint_block_req_id(0, "map"));
        assert_ne!(mint_block_req_id(0, "map"), mint_block_req_id(1, "map"));
        assert_ne!(mint_block_req_id(0, "map"), mint_block_req_id(0, "plain"));
    }

    #[test]
    fn placeholder_round_trip() {
        let id = mint_block_req_id(3, "map");
        let p = placeholder_for(&id);
        assert!(p.contains(&id));
        assert!(p.starts_with("<!--MARKI-BLOCK:"));
        assert!(p.ends_with("-->"));
    }
}
