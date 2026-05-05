//! Render-format version for `typst` blocks. Bump when the preamble,
//! embed HTML, or any other byte that influences the cached output
//! changes — this invalidates every existing cache entry on next run.
pub const RENDER_VERSION_TYPST: u32 = 1;
