//! Text utilities for the LSP surface: position mapping and wiki-link scanning.
//!
//! Kept apart from the server itself because these are the parts that can be
//! tested without a Trilium instance to talk to.

use crate::meta::Kind;

/// A `[[noteId|Title]]` reference found in buffer text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WikiLink {
    /// The resolved target: `path`'s last `/`-separated segment. Every
    /// consumer that talks to Trilium (hover, gd, references, `gf`) wants
    /// this, never `path` -- see `note_id_of_path`.
    pub note_id: String,
    /// The link target exactly as it appears in the buffer -- a bare noteId
    /// most of the time, but sometimes a full notePath (see
    /// `note_id_of_path`). Kept only for the one consumer that rewrites
    /// buffer text and must match what is actually there.
    pub path: String,
    pub title: String,
    /// Byte range of the whole `[[...]]`, including the brackets.
    pub start: usize,
    pub end: usize,
}

/// Trilium link targets are sometimes a bare noteId and sometimes a full
/// notePath -- a `/`-joined chain of ancestors ending in the target, e.g.
/// `abc123/def456/ghi789`. Both forms point at the same note and Trilium
/// itself emits either one depending on how the link was made (even its own
/// User Guide links one note both ways from different pages), so the target
/// is always the last non-empty segment. A bare id has no `/` and returns
/// unchanged.
pub fn note_id_of_path(s: &str) -> &str {
    s.rsplit('/')
        .find(|segment| !segment.is_empty())
        .unwrap_or(s)
}

/// Find every wiki link in `text`.
///
/// CKEditor distinguishes a reference link, which renders the target's title,
/// from a plain link to the same note. Markdown link syntax cannot express that
/// difference, so reference links get their own syntax -- which doubles as the
/// thing `[[` completion completes.
pub fn wiki_links(text: &str) -> Vec<WikiLink> {
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;

    while i + 1 < bytes.len() {
        if bytes[i] != b'[' || bytes[i + 1] != b'[' {
            i += 1;
            continue;
        }
        let Some(close) = text[i + 2..].find("]]").map(|n| i + 2 + n) else {
            break;
        };
        let inner = &text[i + 2..close];
        // A newline means the brackets were never a link to begin with.
        if !inner.contains('\n') {
            let (path, title) = match inner.split_once('|') {
                Some((id, title)) => (id.trim(), title.trim()),
                None => (inner.trim(), inner.trim()),
            };
            if !path.is_empty() {
                out.push(WikiLink {
                    note_id: note_id_of_path(path).to_string(),
                    path: path.to_string(),
                    title: title.to_string(),
                    start: i,
                    end: close + 2,
                });
            }
        }
        i = close + 2;
    }
    out
}

/// The wiki link containing a byte offset, if any.
pub fn link_at(text: &str, offset: usize) -> Option<WikiLink> {
    wiki_links(text)
        .into_iter()
        .find(|l| offset >= l.start && offset <= l.end)
}

/// Maps byte offsets to LSP positions.
///
/// LSP counts columns in UTF-16 code units, not bytes and not characters. Notes
/// are full of non-ASCII -- arrows, em dashes, `&nbsp;` -- so getting this wrong
/// misplaces every diagnostic in the buffer.
pub struct LineIndex {
    /// Byte offset of the start of each line.
    starts: Vec<usize>,
}

impl LineIndex {
    pub fn new(text: &str) -> Self {
        let mut starts = vec![0];
        for (i, byte) in text.bytes().enumerate() {
            if byte == b'\n' {
                starts.push(i + 1);
            }
        }
        Self { starts }
    }

    /// `(line, character)` for a byte offset, both zero-based.
    pub fn position(&self, text: &str, offset: usize) -> (u32, u32) {
        let offset = offset.min(text.len());
        let line = match self.starts.binary_search(&offset) {
            Ok(exact) => exact,
            Err(next) => next - 1,
        };
        let column = text[self.starts[line]..offset]
            .chars()
            .map(char::len_utf16)
            .sum::<usize>();
        (line as u32, column as u32)
    }

    /// Byte offset for a zero-based `(line, character)` position.
    pub fn offset(&self, text: &str, line: u32, character: u32) -> usize {
        let Some(&start) = self.starts.get(line as usize) else {
            return text.len();
        };
        let rest = &text[start..];
        let mut remaining = character as usize;
        let mut offset = start;
        for ch in rest.chars() {
            if remaining == 0 || ch == '\n' {
                break;
            }
            remaining = remaining.saturating_sub(ch.len_utf16());
            offset += ch.len_utf8();
        }
        offset
    }
}

/// The `[[` prefix being typed immediately before `offset`, if any.
///
/// Returns the byte offset of the opening `[[` and the text typed since.
pub fn completion_prefix(text: &str, offset: usize) -> Option<(usize, &str)> {
    let before = &text[..offset.min(text.len())];
    let open = before.rfind("[[")?;
    let typed = &before[open + 2..];
    // Once the link is closed or a line has ended, this is no longer an
    // in-progress reference.
    if typed.contains(']') || typed.contains('\n') {
        return None;
    }
    Some((open, typed))
}

/// The `@` prefix being typed immediately before `offset`, if any.
///
/// Only fires at the start of a line or after whitespace, so email addresses
/// and the like never trigger it. Returns the byte offset of the `@` and the
/// text typed since.
pub fn at_prefix(text: &str, offset: usize) -> Option<(usize, &str)> {
    let before = &text[..offset.min(text.len())];
    let at = before.rfind('@')?;
    let preceded_by_word_boundary = match before[..at].chars().next_back() {
        None => true,
        Some(c) => c.is_whitespace(),
    };
    if !preceded_by_word_boundary {
        return None;
    }
    let typed = &before[at + 1..];
    if typed.chars().any(|c| c.is_whitespace()) {
        return None;
    }
    Some((at, typed))
}

/// Where a cursor sits in the metadata pop-out's YAML, for completion.
/// Every shape `render` emits for a name or a value is recognised: a bare
/// `name: value`, a multivalued name's `    - item` list entries (`name`
/// comes from the owning header line, found by `owner_of`), and an inline
/// `{value: X, inheritable: true}` mapping's own `X`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MetaContext {
    /// Under `labels:`/`relations:`, typing a name: nothing but indentation
    /// precedes the cursor on this line.
    Name {
        kind: Kind,
        typed: String,
        start: usize,
        end: usize,
    },
    /// Typing a name's scalar value -- a bare `name: value`, a `- item` in
    /// a multivalued name's list, or the `X` in `{value: X, ...}`.
    Value {
        kind: Kind,
        name: String,
        typed: String,
        start: usize,
        end: usize,
    },
}

/// The `labels:`/`relations:` section a line at `line_start` falls under,
/// together with the name of the nearest 2-space-indented `name:` line
/// above it -- the owning header for a multivalued name's `    - item`
/// list entries. Found by scanning upward for the nearest unindented
/// header; any other unindented, non-blank line means the search has left
/// the section (walked past it into `title:`/`noteId:`/`type:`, or past
/// the other section).
fn owner_of(text: &str, line_start: usize) -> Option<(Kind, Option<String>)> {
    let mut owner = None;
    for prior in text[..line_start].lines().rev() {
        match prior {
            "labels:" => return Some((Kind::Label, owner)),
            "relations:" => return Some((Kind::Relation, owner)),
            _ if !prior.starts_with(' ') && !prior.is_empty() => return None,
            _ => {
                if owner.is_none()
                    && let Some(rest) = prior.strip_prefix("  ")
                    && !rest.starts_with(' ')
                    && let Some(colon) = rest.find(':')
                {
                    owner = Some(rest[..colon].trim().to_string());
                }
            }
        }
    }
    None
}

/// Byte offset of the first non-space character in `line` at or after
/// `from`.
fn skip_spaces(line: &str, from: usize) -> usize {
    let rest = &line[from..];
    from + (rest.len() - rest.trim_start().len())
}

/// The byte range of `X` in a `{value: X, inheritable: ...}` inline
/// mapping opening at `brace` within `line`, if it opens with exactly the
/// shape `render_value` emits. `X` runs up to the first unquoted `,` or
/// `}` -- `render_value` only ever quotes with `"`, so a single toggle is
/// enough to skip a comma inside a quoted value.
fn inline_value_range(line: &str, brace: usize) -> Option<(usize, usize)> {
    let key_start = brace + 1;
    if !line[key_start..].starts_with("value:") {
        return None;
    }
    let value_start = skip_spaces(line, key_start + "value:".len());
    let mut quoted = false;
    let mut escaped = false;
    for (i, ch) in line[value_start..].char_indices() {
        if escaped {
            escaped = false;
            continue;
        }
        match ch {
            '\\' if quoted => escaped = true,
            '"' => quoted = !quoted,
            ',' | '}' if !quoted => return Some((value_start, value_start + i)),
            _ => {}
        }
    }
    None
}

/// A bare, single-valued `name: value` line the cursor at `offset` sits on
/// -- not a multivalued name's own `- item` line, and not the inline
/// `{value: ..., inheritable: true}` mapping form, both of which are
/// already what "convert to list" would turn it into. Exists for that code
/// action, so a note can grow a second value for a name without the user
/// hand-restructuring its YAML themselves.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConvertibleValue {
    pub name: String,
    pub value: String,
}

pub fn convertible_value_at(text: &str, offset: usize) -> Option<ConvertibleValue> {
    let offset = offset.min(text.len());
    let line_start = text[..offset].rfind('\n').map_or(0, |i| i + 1);
    let line_end = text[line_start..]
        .find('\n')
        .map_or(text.len(), |i| line_start + i);
    let line = &text[line_start..line_end];

    owner_of(text, line_start)?;
    let indented = line.strip_prefix("  ")?;
    if indented.starts_with(' ') {
        return None;
    }
    let colon = indented.find(':')?;
    let name = indented[..colon].trim().to_string();
    if name.is_empty() {
        return None;
    }
    let value_start = skip_spaces(line, 2 + colon + 1);
    if line[value_start..].starts_with('{') {
        return None;
    }
    let value = line[value_start..].trim().to_string();
    if value.is_empty() {
        return None;
    }
    Some(ConvertibleValue { name, value })
}

/// Classify `offset` in the pop-out's `text` for completion. `None` outside
/// a `labels:`/`relations:` section, or in a shape `render` never produces
/// (see `MetaContext`).
pub fn meta_context(text: &str, offset: usize) -> Option<MetaContext> {
    let offset = offset.min(text.len());
    let line_start = text[..offset].rfind('\n').map_or(0, |i| i + 1);
    let line_end = text[line_start..]
        .find('\n')
        .map_or(text.len(), |i| line_start + i);
    let line = &text[line_start..line_end];
    let col = offset - line_start;

    let (kind, owner) = owner_of(text, line_start)?;

    let indented = line.strip_prefix("  ")?;
    if indented.starts_with(' ') {
        // A multivalued name's own `    - item` line: complete the item,
        // using the owning name found scanning upward. Anything else at
        // this depth (an inline mapping's own field) is not handled.
        indented.strip_prefix("  - ")?;
        let name = owner?;
        let value_start = 6;
        if col < value_start {
            return None;
        }
        return Some(MetaContext::Value {
            kind,
            name,
            typed: line[value_start..col].to_string(),
            start: line_start + value_start,
            end: line_start + line.len(),
        });
    }

    match indented.find(':') {
        None => {
            if col < 2 {
                return None;
            }
            Some(MetaContext::Name {
                kind,
                typed: line[2..col].to_string(),
                start: line_start + 2,
                end: line_start + line.len(),
            })
        }
        Some(rel_colon) => {
            let colon = 2 + rel_colon;
            if col <= colon {
                return None;
            }
            let name = line[2..colon].trim().to_string();
            let value_start = skip_spaces(line, colon + 1);
            if col < value_start {
                return None;
            }
            if line[value_start..].starts_with('{') {
                let (start, end) = inline_value_range(line, value_start)?;
                if col < start || col > end {
                    return None;
                }
                return Some(MetaContext::Value {
                    kind,
                    name,
                    typed: line[start..col].to_string(),
                    start: line_start + start,
                    end: line_start + end,
                });
            }
            Some(MetaContext::Value {
                kind,
                name,
                typed: line[value_start..col].to_string(),
                start: line_start + value_start,
                end: line_start + line.len(),
            })
        }
    }
}

/// A rendered label or relation the cursor is somewhere on, for hover.
/// Unlike `MetaContext`, this looks at the whole line rather than the text
/// typed up to the cursor, since hover asks "what is under the cursor",
/// not "what is being typed here" -- the name always resolves as a whole
/// regardless of where in it the cursor lands.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MetaToken {
    /// The cursor is on the name itself, at or before its `:`.
    Name { kind: Kind, name: String },
    /// The cursor is past the `:`, on the value -- a bare `name: value`,
    /// any `- item` in a multivalued name's list (`name` is the owning
    /// header, found by `owner_of`), or the `X` in `{value: X, ...}`.
    Value {
        kind: Kind,
        name: String,
        value: String,
    },
}

/// The label or relation the cursor at `offset` is on, if any.
pub fn meta_token_at(text: &str, offset: usize) -> Option<MetaToken> {
    let offset = offset.min(text.len());
    let line_start = text[..offset].rfind('\n').map_or(0, |i| i + 1);
    let line_end = text[line_start..]
        .find('\n')
        .map_or(text.len(), |i| line_start + i);
    let line = &text[line_start..line_end];

    let (kind, owner) = owner_of(text, line_start)?;
    let indented = line.strip_prefix("  ")?;

    if indented.starts_with(' ') {
        let item = indented.strip_prefix("  - ")?;
        let name = owner?;
        return Some(MetaToken::Value {
            kind,
            name,
            value: item.trim().to_string(),
        });
    }

    let col = offset - line_start;
    let colon = indented.find(':')?;
    let name = indented[..colon].trim().to_string();
    if name.is_empty() {
        return None;
    }
    let name_end = 2 + colon;
    if col <= name_end {
        return Some(MetaToken::Name { kind, name });
    }
    let value_start = skip_spaces(line, name_end + 1);
    if line[value_start..].starts_with('{') {
        let value = inline_value_range(line, value_start)
            .map(|(start, end)| line[start..end].trim().to_string())
            .unwrap_or_default();
        return Some(MetaToken::Value { kind, name, value });
    }
    let value = line[value_start..].trim().to_string();
    Some(MetaToken::Value { kind, name, value })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_wiki_links_with_and_without_titles() {
        let links = wiki_links("see [[abc123|Some Note]] and [[def456]] here");
        assert_eq!(links.len(), 2);
        assert_eq!(links[0].note_id, "abc123");
        assert_eq!(links[0].title, "Some Note");
        assert_eq!(
            &"see [[abc123|Some Note]] and [[def456]] here"[links[0].start..links[0].end],
            "[[abc123|Some Note]]"
        );
        assert_eq!(links[1].note_id, "def456");
    }

    #[test]
    fn ignores_brackets_spanning_lines() {
        assert!(wiki_links("[[not\na link]]").is_empty());
    }

    #[test]
    fn ignores_ordinary_markdown_links() {
        assert!(wiki_links("[text](http://example.com)").is_empty());
    }

    #[test]
    fn link_at_finds_the_enclosing_reference() {
        let text = "a [[abc|T]] b";
        assert_eq!(link_at(text, 5).unwrap().note_id, "abc");
        assert!(link_at(text, 0).is_none());
    }

    #[test]
    fn note_id_of_path_takes_the_last_segment() {
        assert_eq!(note_id_of_path("abc123"), "abc123");
        assert_eq!(note_id_of_path("a/b/c"), "c");
        assert_eq!(note_id_of_path("a/b/"), "b");
        assert_eq!(note_id_of_path(""), "");
        assert_eq!(note_id_of_path("/"), "/");
    }

    #[test]
    fn a_wiki_link_with_a_note_path_resolves_to_its_tail_but_keeps_the_full_path() {
        let links = wiki_links("[[a/b/c|Some Note]]");
        assert_eq!(links[0].note_id, "c");
        assert_eq!(links[0].path, "a/b/c");
        assert_eq!(links[0].title, "Some Note");
    }

    #[test]
    fn a_bare_wiki_link_has_an_identical_note_id_and_path() {
        let links = wiki_links("[[abc123|Some Note]]");
        assert_eq!(links[0].note_id, "abc123");
        assert_eq!(links[0].path, "abc123");
    }

    /// LSP columns are UTF-16 code units. An em dash is one unit but three
    /// bytes, and an emoji is two units but four bytes.
    #[test]
    fn positions_are_counted_in_utf16_units() {
        let text = "a\nem — dash\n";
        let index = LineIndex::new(text);
        let offset = text.find("dash").unwrap();
        assert_eq!(index.position(text, offset), (1, 5));
    }

    #[test]
    fn positions_round_trip_through_offsets() {
        let text = "one\ntwo — three\nfour";
        let index = LineIndex::new(text);
        for offset in text.char_indices().map(|(i, _)| i) {
            let (line, character) = index.position(text, offset);
            assert_eq!(index.offset(text, line, character), offset, "at {offset}");
        }
    }

    #[test]
    fn detects_a_reference_being_typed() {
        let text = "see [[Keyb";
        assert_eq!(completion_prefix(text, text.len()), Some((4, "Keyb")));
    }

    #[test]
    fn ignores_a_reference_already_closed() {
        let text = "see [[abc]] more";
        assert_eq!(completion_prefix(text, text.len()), None);
    }

    #[test]
    fn detects_an_at_keyword_at_start_of_line() {
        let text = "@tod";
        assert_eq!(at_prefix(text, text.len()), Some((0, "tod")));
    }

    #[test]
    fn detects_an_at_keyword_after_whitespace() {
        let text = "see @tod";
        assert_eq!(at_prefix(text, text.len()), Some((4, "tod")));
    }

    #[test]
    fn ignores_an_email_address() {
        let text = "mail me at foo@bar";
        assert_eq!(at_prefix(text, text.len()), None);
    }

    #[test]
    fn ignores_an_at_keyword_that_has_a_space_after_it() {
        let text = "@today ";
        assert_eq!(at_prefix(text, text.len()), None);
    }

    #[test]
    fn meta_context_detects_a_label_name_being_typed() {
        let text = "title: x\nnoteId: a\ntype: text\n\nlabels:\n  gen\n";
        let offset = text.rfind("gen").unwrap() + 3;
        assert_eq!(
            meta_context(text, offset),
            Some(MetaContext::Name {
                kind: Kind::Label,
                typed: "gen".into(),
                start: text.find("  gen").unwrap() + 2,
                end: text.rfind("gen").unwrap() + 3,
            })
        );
    }

    #[test]
    fn meta_context_detects_a_relation_name_being_typed() {
        let text = "title: x\nnoteId: a\ntype: text\n\nrelations:\n  tem\n";
        let offset = text.rfind("tem").unwrap() + 3;
        assert_eq!(
            meta_context(text, offset).map(|c| matches!(
                c,
                MetaContext::Name {
                    kind: Kind::Relation,
                    ..
                }
            )),
            Some(true)
        );
    }

    #[test]
    fn meta_context_detects_a_value_being_typed_after_a_name() {
        let text = "title: x\nnoteId: a\ntype: text\n\nlabels:\n  priority: hi\n";
        let offset = text.rfind("hi").unwrap() + 2;
        assert_eq!(
            meta_context(text, offset),
            Some(MetaContext::Value {
                kind: Kind::Label,
                name: "priority".into(),
                typed: "hi".into(),
                start: text.rfind("hi").unwrap(),
                end: text.rfind("hi").unwrap() + 2,
            })
        );
    }

    #[test]
    fn meta_context_is_none_outside_a_section() {
        let text = "title: x\nnoteId: a\ntype: te\n";
        let offset = text.rfind("te").unwrap() + 2;
        assert_eq!(meta_context(text, offset), None);
    }

    #[test]
    fn meta_context_resolves_under_an_empty_labels_section_past_a_leading_comment() {
        // The shape `meta::render` actually produces for a note with no
        // labels or relations yet: a guide comment above `title:`, and both
        // section headers present with nothing under them. Neither should
        // stop the upward scan from reaching `labels:`.
        let text =
            "# :w apply | q close | g? help\ntitle: x\nnoteId: a\ntype: text\n\nlabels:\n  gen";
        let offset = text.len();
        assert_eq!(
            meta_context(text, offset),
            Some(MetaContext::Name {
                kind: Kind::Label,
                typed: "gen".into(),
                start: text.rfind("gen").unwrap(),
                end: text.len(),
            })
        );
    }

    #[test]
    fn meta_context_completes_a_multivalued_list_item() {
        let text = "title: x\nnoteId: a\ntype: text\n\nlabels:\n  genre:\n    - sci\n";
        let item_start = text.rfind("- sci").unwrap() + 2;
        let offset = item_start + 3;
        assert_eq!(
            meta_context(text, offset),
            Some(MetaContext::Value {
                kind: Kind::Label,
                name: "genre".into(),
                typed: "sci".into(),
                start: item_start,
                end: text.len() - 1,
            })
        );
    }

    #[test]
    fn meta_context_is_none_on_a_deeper_multivalued_list_item() {
        // A second-level nesting (a list item's own inline mapping) is
        // one indent past what `render` ever produces for a list item --
        // not handled, same as before.
        let text = "title: x\nnoteId: a\ntype: text\n\nlabels:\n  genre:\n      - sci\n";
        let offset = text.rfind("sci").unwrap();
        assert_eq!(meta_context(text, offset), None);
    }

    #[test]
    fn meta_context_completes_an_inline_mapping_value() {
        let text =
            "title: x\nnoteId: a\ntype: text\n\nlabels:\n  shared: {value: x, inheritable: true}\n";
        let value_start = text.rfind("value: x").unwrap() + "value: ".len();
        let offset = value_start + 1;
        assert_eq!(
            meta_context(text, offset),
            Some(MetaContext::Value {
                kind: Kind::Label,
                name: "shared".into(),
                typed: "x".into(),
                start: value_start,
                end: value_start + 1,
            })
        );
    }

    #[test]
    fn meta_context_is_none_on_the_keys_of_an_inline_mapping() {
        let text =
            "title: x\nnoteId: a\ntype: text\n\nlabels:\n  shared: {value: x, inheritable: true}\n";
        let offset = text.rfind("{value").unwrap() + 1;
        assert_eq!(meta_context(text, offset), None);
    }

    #[test]
    fn meta_token_at_resolves_a_name_from_anywhere_within_it() {
        let text = "title: x\nnoteId: a\ntype: text\n\nlabels:\n  priority: 1\n";
        let name_start = text.find("priority").unwrap();
        assert_eq!(
            meta_token_at(text, name_start + 2),
            Some(MetaToken::Name {
                kind: Kind::Label,
                name: "priority".into(),
            })
        );
    }

    #[test]
    fn meta_token_at_resolves_a_value_regardless_of_cursor_position_within_it() {
        let text = "title: x\nnoteId: a\ntype: text\n\nrelations:\n  template: tpl1\n";
        let value_start = text.rfind("tpl1").unwrap();
        assert_eq!(
            meta_token_at(text, value_start + 1),
            Some(MetaToken::Value {
                kind: Kind::Relation,
                name: "template".into(),
                value: "tpl1".into(),
            })
        );
    }

    #[test]
    fn meta_token_at_is_a_name_with_an_empty_value_for_a_bare_label() {
        let text = "title: x\nnoteId: a\ntype: text\n\nlabels:\n  todo:\n";
        let colon = text.rfind("todo:").unwrap() + 5;
        assert_eq!(
            meta_token_at(text, colon),
            Some(MetaToken::Value {
                kind: Kind::Label,
                name: "todo".into(),
                value: "".into(),
            })
        );
    }

    #[test]
    fn meta_token_at_resolves_a_multivalued_list_item_to_its_owning_name() {
        let text = "title: x\nnoteId: a\ntype: text\n\nlabels:\n  genre:\n    - sci-fi\n";
        let offset = text.rfind("sci-fi").unwrap() + 2;
        assert_eq!(
            meta_token_at(text, offset),
            Some(MetaToken::Value {
                kind: Kind::Label,
                name: "genre".into(),
                value: "sci-fi".into(),
            })
        );
    }

    #[test]
    fn meta_token_at_resolves_an_inline_mapping_to_just_its_value() {
        let text = "title: x\nnoteId: a\ntype: text\n\nrelations:\n  mentor: {value: abc123, inheritable: true}\n";
        let offset = text.rfind("abc123").unwrap();
        assert_eq!(
            meta_token_at(text, offset),
            Some(MetaToken::Value {
                kind: Kind::Relation,
                name: "mentor".into(),
                value: "abc123".into(),
            })
        );
    }

    #[test]
    fn convertible_value_at_resolves_a_bare_name_value_line() {
        let text = "title: x\nnoteId: a\ntype: text\n\nlabels:\n  genre: sci-fi\n";
        let offset = text.find("sci-fi").unwrap();
        assert_eq!(
            convertible_value_at(text, offset),
            Some(ConvertibleValue {
                name: "genre".into(),
                value: "sci-fi".into(),
            })
        );
    }

    #[test]
    fn convertible_value_at_is_none_on_a_list_item() {
        let text = "title: x\nnoteId: a\ntype: text\n\nlabels:\n  genre:\n    - sci-fi\n";
        let offset = text.find("sci-fi").unwrap();
        assert_eq!(convertible_value_at(text, offset), None);
    }

    #[test]
    fn convertible_value_at_is_none_on_an_inline_mapping() {
        let text = "title: x\nnoteId: a\ntype: text\n\nrelations:\n  mentor: {value: abc123, inheritable: true}\n";
        let offset = text.find("mentor").unwrap();
        assert_eq!(convertible_value_at(text, offset), None);
    }

    #[test]
    fn convertible_value_at_is_none_on_a_value_less_label() {
        let text = "title: x\nnoteId: a\ntype: text\n\nlabels:\n  todo:\n";
        let offset = text.find("todo").unwrap();
        assert_eq!(convertible_value_at(text, offset), None);
    }
}
