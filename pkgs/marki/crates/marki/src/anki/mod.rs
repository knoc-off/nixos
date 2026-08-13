//! Tag helpers and the note-writer bridge to the direct-SQLite collection.
//!
//! Historically this module wrapped AnkiConnect (a GUI-bound HTTP add-on).
//! The reconcile engine now writes the collection file directly through
//! `marki-anki`, so all that remains here is the tag vocabulary shared
//! between the engine and the writer.

pub mod model;

pub use model::{MARKER_TAG, ORPHAN_TAG, full_tag_set, hash_from_tags, strip_marker};
