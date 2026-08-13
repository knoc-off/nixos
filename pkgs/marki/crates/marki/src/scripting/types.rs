//! Lua UserData for `Note`, `Block`, and `TagValue`.
//!
//! Model scripts receive a `note` userdata and query it with method
//! calls: `note:heading(1)`, `note:code_block("map")`, `block:html()`,
//! etc. Indices are 1-based, matching Lua convention -- `note:heading(1)`
//! is the first heading. A missing element yields `nil`.

use mlua::{MetaMethod, UserData, UserDataMethods, Value};

use crate::note::{Block, Note, TagValue};

/// Convert a 1-based Lua index to a 0-based Rust index. Returns `None`
/// for `n < 1` so callers can hand back `nil` instead of underflowing.
fn zero_based(n: i64) -> Option<usize> {
    if n >= 1 {
        Some((n - 1) as usize)
    } else {
        None
    }
}

impl UserData for Note {
    fn add_methods<M: UserDataMethods<Self>>(m: &mut M) {
        m.add_method("id", |_, this, ()| Ok(this.id.clone()));
        m.add_method("model", |_, this, ()| Ok(this.model.clone()));
        m.add_method("source", |_, this, ()| Ok(this.source.clone()));
        m.add_method("anki_tags", |_, this, ()| Ok(this.anki_tags.clone()));

        m.add_method("sections", |_, this, ()| {
            Ok(this
                .sections()
                .into_iter()
                .map(|sec| sec.to_vec())
                .collect::<Vec<Vec<Block>>>())
        });
        m.add_method("section", |_, this, n: i64| {
            Ok(zero_based(n).map(|i| this.section(i).to_vec()).unwrap_or_default())
        });

        m.add_method("paragraphs", |_, this, ()| {
            Ok(this.paragraphs().into_iter().cloned().collect::<Vec<Block>>())
        });
        m.add_method("paragraph", |_, this, n: i64| {
            Ok(zero_based(n).and_then(|i| this.paragraph(i).cloned()))
        });

        m.add_method("headings", |_, this, ()| {
            Ok(this.headings().into_iter().cloned().collect::<Vec<Block>>())
        });
        m.add_method("heading", |_, this, n: i64| {
            Ok(zero_based(n).and_then(|i| this.heading(i).cloned()))
        });

        m.add_method("code_blocks", |_, this, lang: String| {
            Ok(this.code_blocks(&lang).into_iter().cloned().collect::<Vec<Block>>())
        });
        m.add_method("code_block", |_, this, lang: String| {
            Ok(this.code_block(&lang).cloned())
        });

        m.add_method("lists", |_, this, ()| {
            Ok(this.lists().into_iter().cloned().collect::<Vec<Block>>())
        });
        m.add_method("blockquotes", |_, this, ()| {
            Ok(this.blockquotes().into_iter().cloned().collect::<Vec<Block>>())
        });

        m.add_method("tag", |_, this, name: String| Ok(this.tag(&name).cloned()));
        m.add_method("has_tag", |_, this, name: String| Ok(this.has_tag(&name)));
    }
}

impl UserData for Block {
    fn add_methods<M: UserDataMethods<Self>>(m: &mut M) {
        m.add_method("text", |_, this, ()| Ok(this.text().to_string()));
        m.add_method("html", |_, this, ()| Ok(this.html().to_string()));
        m.add_method("lang", |_, this, ()| Ok(this.lang().map(str::to_string)));
        m.add_method("source", |_, this, ()| Ok(this.source().map(str::to_string)));
    }
}

impl UserData for TagValue {
    fn add_methods<M: UserDataMethods<Self>>(m: &mut M) {
        m.add_method("is_bool", |_, this, ()| Ok(matches!(this, TagValue::Bool)));
        m.add_method("value", |lua, this, ()| match this {
            TagValue::Bool => Ok(Value::Boolean(true)),
            TagValue::Param(s) => Ok(Value::String(lua.create_string(s)?)),
        });
        m.add_meta_method(MetaMethod::ToString, |_, this, ()| {
            Ok(match this {
                TagValue::Bool => "true".to_string(),
                TagValue::Param(s) => s.clone(),
            })
        });
    }
}
