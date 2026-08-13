//! Reconciliation: scan the disk, read the collection, apply the diff.

pub mod engine;
pub mod media;

pub use engine::{Outcome, reconcile, render_stock};
