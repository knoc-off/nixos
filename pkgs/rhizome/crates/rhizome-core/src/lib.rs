pub mod buffer;
pub mod convert;
pub mod dom;
pub mod segment;
pub mod source;

pub use convert::to_md::Escaping;
pub use convert::{blocks_to_markdown, markdown_to_html};
pub use dom::{Element, Node, equivalent, normalize, parse, serialize};
pub use segment::{
    Block, BlockKind, OpaqueReason, RebuildError, Resolved, Segment, Segments, Stats, segment,
    splice, splice_resolved, verify_rebuild,
};
