//! AnkiConnect HTTP client.
//!
//! AnkiConnect is a GUI-bound add-on that exposes
//! <https://github.com/FooSoft/anki-connect> on
//! `http://127.0.0.1:8765` with a JSON request shape:
//!
//! ```json
//! { "action": "...", "version": 6, "params": { ... } }
//! ```
//!
//! The response is always `{ "result": ..., "error": null | "msg" }`. We keep
//! this module small and typed only at the edges — the wire format is
//! `serde_json::Value` because the return shape varies by action.

pub mod client;
pub mod model;
pub mod note_type;
pub mod template_state;

pub use client::{AnkiConnect, AnkiError};
pub use model::{ManagedNote, ModelKind};
pub use note_type::{NoteTypeSpec, ensure_note_type, push_model_styling, build_field_values};
pub use template_state::TemplateState;
