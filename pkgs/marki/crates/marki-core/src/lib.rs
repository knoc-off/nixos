//! Core library for `markid`: parse markdown → card, render to HTML,
//! compute version-bound content hash, extract tags, mint stable ids.
//!
//! This crate is pure — it never touches the filesystem or the network.

pub mod block_dispatch;
pub mod card;
pub mod hash;
pub mod highlighter;
pub mod id;
pub mod parser;
pub mod render;
pub mod tag;
pub mod version;

pub use block_dispatch::{
    AssetMime, BlockError, BlockRenderer, BlockReqId, BlockRequest, BlockSide, EmittedAsset,
    RenderCtx, RenderedBlock, placeholder_for,
};
pub use card::{Card, NoteType};
pub use hash::{content_hash, content_hash_html};
pub use id::mint_id;
pub use tag::{SystemTag, TagParseError};
pub use version::RENDER_VERSION;
