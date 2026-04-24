//! Reconciliation: scan the disk, query Anki, emit the destructive diff.

pub mod engine;
pub mod media;

pub use engine::{Outcome, reconcile};
