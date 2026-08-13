//! Lua scripting engine for custom model scripts.
//!
//! Model scripts live in `models/<name>.lua` and define how a parsed
//! `Note` becomes card field values for Anki. Each script is a Lua module
//! returning a table with `card_names()` and `generate(note, ctx)`. The
//! engine loads, caches, and executes them.
//!
//! Stock models (basic, cloze) bypass this engine entirely and render
//! through `sync::engine::render_stock`.

pub mod context;
pub mod engine;
pub mod types;
