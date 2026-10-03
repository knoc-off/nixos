//! Reconciliation: scan the disk, read the collection, apply the diff.

pub mod client;
pub mod engine;
pub mod media;

pub use engine::{Change, ChangeKind, Outcome, RenderedNote, reconcile, render_note, render_stock};
