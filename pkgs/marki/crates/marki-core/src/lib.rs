//! Core library for `markid`: parse markdown notes, render to HTML,
//! compute version-bound content hash, extract tags, mint stable ids.
//!
//! This crate is pure — it never touches the filesystem or the network.

pub mod block_dispatch;
pub mod hash;
pub mod highlighter;
pub mod id;
pub mod note;
pub mod note_parser;
pub mod render;
pub mod tag;
pub mod util;
pub mod version;

pub use block_dispatch::{
    AssetMime, BlockError, BlockRenderer, BlockReqId, BlockRequest, BlockSide, EmittedAsset,
    RenderCtx, RenderedBlock,
};
pub use hash::{content_hash, content_hash_html};
pub use id::mint_id;
pub use note::{Block, ListItem, Note, TagValue};
pub use note_parser::parse_note;
pub use tag::{SystemTag, TAG_REGEX, TagParseError};
pub use util::escape_html;
pub use version::RENDER_VERSION;
