//! Render-format version. Bumped whenever a change in this crate can alter the
//! rendered HTML output for an unchanged markdown input. The per-card
//! content hash incorporates this value, so bumping it forces every managed
//! note to be re-rendered and re-pushed to Anki on the next sync cycle.
//!
//! Bump on:
//!   * pulldown-cmark upgrade or option change affecting emitted HTML
//!   * syntect theme change (`highlighter.rs`)
//!   * cloze algorithm change (`parser.rs` Strong/Emphasis handling)
//!   * math / code-block HTML wrapping changes
//!
//! Do NOT bump on:
//!   * CSS-only changes (CSS lives in the Anki model and is updated separately)
//!   * tag parsing changes that don't alter rendered HTML
//!   * refactors, comments, dep bumps that don't affect output bytes
pub const RENDER_VERSION: u32 = 2;
