//! Rhai scripting engine for custom model scripts.
//!
//! Model scripts live in `models/<name>.rhai` and define how a parsed
//! `Note` is transformed into card field values for Anki. The engine
//! loads, compiles, caches, and executes these scripts.
//!
//! Stock models (basic, cloze) bypass this engine entirely and use
//! the old parser → Card → stock Anki model pipeline instead.

pub mod context;
pub mod engine;
pub mod types;
