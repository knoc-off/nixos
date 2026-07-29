//! Turning a segment list into buffer text and back.
//!
//! Transparent blocks appear as plain Markdown. Opaque blocks appear as fenced
//! blocks tagged `=html` carrying their block id.
//!
//! Fences rather than extmarks: extmarks do not survive a buffer reload, do not
//! survive being yanked into another buffer, and leave the user looking at
//! content they cannot address. A visible fence is debuggable, survives a
//! crash, folds away, and doubles as the escape hatch for hand-editing the HTML.

use std::collections::HashMap;
use std::ops::Range;

use pulldown_cmark::{Event, Options, Parser};

use crate::convert::markdown_to_html;
use crate::convert::markdown_to_html_reporting;
use crate::segment::{Block, BlockKind, Resolved, Segments, splice_resolved};

const HTML_FENCE: &str = "=html";

/// How a blank-line paragraph is written in the buffer. A pilcrow rather than
/// nothing: Markdown has no way to represent an empty block, so *something*
/// has to occupy the line for the parser to see it as a distinct chunk at
/// all. Deleting that line removes the spacer on save; typing one inserts a
/// fresh `<p>&nbsp;</p>`.
const SPACER: &str = "\u{b6}";

/// Canonical HTML for a spacer with no original block to restore from.
const SPACER_HTML: &str = "<p>&nbsp;</p>";

/// Trim layout whitespace only.
///
/// `str::trim` is Unicode-aware and strips U+00A0, which CKEditor emits as
/// real content. Using it here silently deletes a trailing `&nbsp;` and the
/// block then fails to match its original source.
fn trim_layout(s: &str) -> &str {
    s.trim_matches(|c: char| c.is_ascii_whitespace())
}

fn trim_layout_end(s: &str) -> &str {
    s.trim_end_matches(|c: char| c.is_ascii_whitespace())
}

/// Render the buffer a user edits.
pub fn render(segments: &Segments) -> String {
    render_with_spans(segments).0
}

/// `render`, plus each block's byte range in the rendered text. A single
/// implementation shared with `render` -- kept together rather than as two
/// parallel walks so they cannot silently drift apart, the same reasoning
/// `parse` already applies by routing through `splice_resolved`.
fn render_with_spans(segments: &Segments) -> (String, Vec<Range<usize>>) {
    let mut out = String::new();
    let mut spans = Vec::new();
    for (i, block) in segments.blocks().enumerate() {
        if i > 0 {
            out.push_str("\n\n");
        }
        let start = out.len();
        match &block.kind {
            BlockKind::Transparent { markdown } => out.push_str(markdown),
            BlockKind::Spacer => out.push_str(SPACER),
            BlockKind::Opaque { .. } => {
                let body = trim_layout_end(&block.source);
                let fence = "`".repeat(fence_length(body));
                out.push_str(&fence);
                out.push_str(HTML_FENCE);
                out.push(' ');
                out.push_str(&block.id);
                out.push('\n');
                out.push_str(body);
                out.push('\n');
                out.push_str(&fence);
            }
        }
        spans.push(start..out.len());
    }
    (out, spans)
}

/// A fence must be longer than any run of backticks in the content it wraps,
/// or that run reads as the closing delimiter and truncates everything after
/// it. Three is the Markdown minimum.
fn fence_length(content: &str) -> usize {
    let mut longest = 0;
    let mut run = 0;
    for c in content.chars() {
        if c == '`' {
            run += 1;
            longest = longest.max(run);
        } else {
            run = 0;
        }
    }
    (longest + 1).max(3)
}

/// Rebuild note HTML from edited buffer text.
///
/// Goes through [`splice_resolved`] rather than joining blocks itself, so the
/// note's original inter-block whitespace survives. That matters more than it
/// looks: this is the function the save path actually calls, and for a long
/// time the byte-identity guarantee was only ever proven about `splice`, which
/// the client never invokes.
pub fn parse(text: &str, segments: &Segments) -> String {
    splice_resolved(segments, &resolve(text, segments))
}

/// Match each buffer chunk against the blocks the note started with.
///
/// Matching is by content, not position, so inserting or reordering blocks does
/// not force the untouched ones to be rewritten.
pub fn resolve(text: &str, segments: &Segments) -> Vec<Resolved> {
    resolve_spans(text, segments)
        .into_iter()
        .map(|(resolved, _)| resolved)
        .collect()
}

/// Same as [`resolve`], but paired with the byte range in `text` each chunk
/// came from. That range is what a "which lines are unsaved" indicator needs
/// and [`resolve`] otherwise throws away; kept as one function rather than two
/// parallel implementations so they cannot drift.
pub fn resolve_spans(text: &str, segments: &Segments) -> Vec<(Resolved, Range<usize>)> {
    let blocks: Vec<&Block> = segments.blocks().collect();

    // Fast path: a buffer byte-identical to a fresh render is definitionally
    // unedited. Skip the chunk-matching heuristics below entirely and replay
    // every block as `Original` -- this is what keeps "open and immediately
    // save" safe no matter what ambiguity those heuristics might otherwise
    // trip over (two blocks whose Markdown happens to re-parse as one chunk,
    // for instance).
    let (rendered, spans) = render_with_spans(segments);
    if text == rendered {
        return (0..blocks.len())
            .map(|i| (Resolved::Original(i), spans[i].clone()))
            .collect();
    }

    let mut by_markdown: HashMap<&str, Vec<usize>> = HashMap::new();
    let mut by_id: HashMap<&str, usize> = HashMap::new();
    let mut spacers: Vec<usize> = Vec::new();
    for (i, block) in blocks.iter().enumerate() {
        match &block.kind {
            BlockKind::Transparent { markdown } => {
                by_markdown.entry(markdown.as_str()).or_default().push(i)
            }
            BlockKind::Opaque { .. } => {
                by_id.insert(block.id.as_str(), i);
            }
            BlockKind::Spacer => spacers.push(i),
        }
    }

    let chunks = split_blocks_with_ranges(text);
    // With the block count unchanged, an unmatched chunk is an edit of the
    // block in that position, and saying so keeps the whitespace around it.
    // Once blocks have been added or removed that inference is unsound -- it
    // would consume the wrong block and rewrite an untouched one -- so it is
    // dropped entirely rather than guessed at.
    let positional = chunks.len() == blocks.len();

    let mut used = vec![false; blocks.len()];
    let mut cursor = 0usize;
    let mut out = Vec::with_capacity(chunks.len());

    for (chunk, span) in chunks {
        if let Some((id, html)) = parse_html_fence(&chunk) {
            match by_id.get(id) {
                Some(&i) if !used[i] => {
                    used[i] = true;
                    cursor = i + 1;
                    if trim_layout(&html) == trim_layout(&blocks[i].source) {
                        out.push((Resolved::Original(i), span));
                    } else {
                        out.push((Resolved::Replaced(i, html), span));
                    }
                }
                // A fence whose id is unknown, or already claimed by an earlier
                // chunk, is taken at face value.
                _ => out.push((Resolved::New(html), span)),
            }
            continue;
        }

        if chunk == SPACER {
            // Any remaining spacer will do -- they are interchangeable, so
            // whichever restores this one's original bytes is as good as any
            // other. A brand new pilcrow with nothing left to claim becomes a
            // freshly authored blank line.
            let claimed = spacers
                .iter()
                .copied()
                .find(|&i| !used[i] && i >= cursor)
                .or_else(|| spacers.iter().copied().find(|&i| !used[i]));
            match claimed {
                Some(i) => {
                    used[i] = true;
                    cursor = i + 1;
                    out.push((Resolved::Original(i), span));
                }
                None => out.push((Resolved::New(SPACER_HTML.to_string()), span)),
            }
            continue;
        }

        // Prefer a match at or after the cursor so that repeated identical
        // paragraphs keep their original positions.
        let matched = by_markdown.get(chunk.as_str()).and_then(|indices| {
            indices
                .iter()
                .copied()
                .find(|&i| !used[i] && i >= cursor)
                .or_else(|| indices.iter().copied().find(|&i| !used[i]))
        });

        match matched {
            Some(i) => {
                used[i] = true;
                cursor = i + 1;
                out.push((Resolved::Original(i), span));
            }
            None => {
                let html = markdown_to_html(&chunk);
                if positional && cursor < blocks.len() && !used[cursor] {
                    used[cursor] = true;
                    out.push((Resolved::Replaced(cursor, html), span));
                    cursor += 1;
                } else {
                    out.push((Resolved::New(html), span));
                }
            }
        }
    }
    out
}

/// Buffer spans where a fresh conversion would have to degrade a checkbox to
/// literal `[ ]`/`[x]` text, because the surrounding list has no CKEditor
/// todo-list form (a mixed bullet/checkbox list, an ordered task list, or
/// anything else `to_html`'s `todo_list`/`todo_item` do not recognise).
/// Diagnostic-only, and deliberately never blocks a save: `demote_stray_
/// checkboxes` already guarantees the note gets valid HTML either way, so
/// this is purely a warning that the checkbox did not take.
///
/// Mirrors [`resolve_spans`]'s chunk matching just far enough to know which
/// spans get freshly converted at all -- an already-matched chunk reuses its
/// block's proven-transparent Markdown and never touches `to_html`, so it
/// cannot degrade anything by definition.
pub fn task_list_degradations(text: &str, segments: &Segments) -> Vec<Range<usize>> {
    let blocks: Vec<&Block> = segments.blocks().collect();
    if text == render(segments) {
        return Vec::new();
    }

    let mut by_markdown: HashMap<&str, Vec<usize>> = HashMap::new();
    for (i, block) in blocks.iter().enumerate() {
        if let BlockKind::Transparent { markdown } = &block.kind {
            by_markdown.entry(markdown.as_str()).or_default().push(i);
        }
    }

    let mut used = vec![false; blocks.len()];
    let mut cursor = 0usize;
    let mut out = Vec::new();

    for (chunk, span) in split_blocks_with_ranges(text) {
        if chunk == SPACER || parse_html_fence(&chunk).is_some() {
            continue;
        }
        let matched = by_markdown.get(chunk.as_str()).and_then(|indices| {
            indices
                .iter()
                .copied()
                .find(|&i| !used[i] && i >= cursor)
                .or_else(|| indices.iter().copied().find(|&i| !used[i]))
        });
        match matched {
            Some(i) => {
                used[i] = true;
                cursor = i + 1;
            }
            None => {
                let (_, degraded) = markdown_to_html_reporting(&chunk);
                if degraded {
                    out.push(span);
                }
            }
        }
    }
    out
}

/// Split buffer text into top-level Markdown blocks, paired with each
/// chunk's byte range in `text`.
///
/// Uses the Markdown parser's own notion of a block rather than blank-line
/// splitting, because fenced code and admonitions legitimately span blank
/// lines.
fn split_blocks_with_ranges(text: &str) -> Vec<(String, Range<usize>)> {
    let mut options = Options::empty();
    options.insert(Options::ENABLE_TABLES);
    options.insert(Options::ENABLE_STRIKETHROUGH);
    options.insert(Options::ENABLE_TASKLISTS);

    let mut out = Vec::new();
    let mut depth = 0usize;
    for (event, range) in Parser::new_ext(text, options).into_offset_iter() {
        match event {
            Event::Start(_) => depth += 1,
            Event::End(_) => {
                depth -= 1;
                if depth == 0 {
                    let raw = &text[range.clone()];
                    let chunk = trim_layout_end(raw);
                    if !chunk.is_empty() {
                        // Only trailing whitespace was trimmed above, so the
                        // chunk still starts exactly where `range` did.
                        out.push((chunk.to_string(), range.start..range.start + chunk.len()));
                    }
                }
            }
            _ => {}
        }
    }
    out
}

/// Recognise ```` ```=html <id> ```` fences and return the id plus raw HTML.
///
/// The opening fence's length is not fixed at three: [`render`] widens it
/// past any backtick run in the wrapped HTML, so the closer has to be
/// resolved the same way -- at least as long as the opener, not literally
/// three characters.
fn parse_html_fence(chunk: &str) -> Option<(&str, String)> {
    let mut lines = chunk.lines();
    let first = lines.next()?;
    let trimmed = first.trim_start();
    let marker = trimmed.chars().next().filter(|&c| c == '`' || c == '~')?;
    let opener_len = trimmed.chars().take_while(|&c| c == marker).count();
    if opener_len < 3 {
        return None;
    }
    let info = trimmed[opener_len..].trim();
    let id = info.strip_prefix(HTML_FENCE)?.trim();

    let body: Vec<&str> = lines.collect();
    let end = body.iter().rposition(|l| {
        let t = l.trim();
        !t.is_empty() && t.chars().all(|c| c == marker) && t.chars().count() >= opener_len
    })?;
    Some((id, body[..end].join("\n")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::segment::segment;

    #[test]
    fn opaque_blocks_render_as_tagged_fences() {
        let html = r#"<figure class="image"><img src="a.png" width="3"></figure>"#;
        let buffer = render(&segment(html));
        assert!(buffer.starts_with("```=html b0-"), "got {buffer}");
        assert!(buffer.contains(r#"<figure class="image">"#));
    }

    #[test]
    fn resolve_spans_covers_the_exact_edited_text() {
        let html = "<p>one</p>\n<p>two</p>";
        let segments = segment(html);
        let mut buffer = render(&segments);
        buffer = buffer.replace("two", "TWO");
        let spans = resolve_spans(&buffer, &segments);
        assert_eq!(spans.len(), 2);
        let (_, second) = &spans[1];
        assert_eq!(&buffer[second.clone()], "TWO");
    }

    #[test]
    fn resolve_spans_and_resolve_agree_on_classification() {
        let html = "<p>one</p>\n<p>two</p>";
        let segments = segment(html);
        let buffer = render(&segments);
        let plain: Vec<_> = resolve(&buffer, &segments);
        let spanned: Vec<_> = resolve_spans(&buffer, &segments)
            .into_iter()
            .map(|(r, _)| r)
            .collect();
        assert_eq!(plain, spanned);
    }

    #[test]
    fn round_trips_an_unedited_buffer_byte_identically() {
        let html = "<h2>Title</h2>\n<p>Some prose.</p>\n<div data-x=\"1\">opaque</div>";
        let segments = segment(html);
        let buffer = render(&segments);
        assert_eq!(parse(&buffer, &segments), html);
    }

    #[test]
    fn editing_prose_leaves_neighbours_untouched() {
        let html = "<p>first</p>\n<p>second</p>";
        let segments = segment(html);
        let edited = render(&segments).replace("second", "changed");
        assert_eq!(parse(&edited, &segments), "<p>first</p>\n<p>changed</p>");
    }

    /// A list carrying CKEditor's per-item ids round-trips untouched by
    /// default (`Resolved::Original`), and an edit to it rewrites the whole
    /// list without the ids -- CKEditor regenerates them on next load, so
    /// nothing is lost, but nothing is fabricated either.
    #[test]
    fn editing_a_list_item_drops_the_ckeditor_id_it_no_longer_has_a_claim_to() {
        let html = "<ul><li data-list-item-id=\"e0123\">one</li><li data-list-item-id=\"e4567\">two</li></ul>";
        let segments = segment(html);
        let buffer = render(&segments);
        assert_eq!(buffer, "- one\n- two", "got {buffer}");
        assert_eq!(parse(&buffer, &segments), html);

        let edited = buffer.replace("two", "TWO");
        assert_eq!(
            parse(&edited, &segments),
            "<ul>\n<li>one</li>\n<li>TWO</li>\n</ul>"
        );
    }

    /// A CKEditor todo list appears in the buffer as GFM task-list syntax,
    /// and an edit that checks an item off round-trips to the corresponding
    /// `checked="checked"` on the `<input>`.
    #[test]
    fn a_todo_list_edits_as_gfm_checkboxes() {
        let html = concat!(
            r#"<ul class="todo-list">"#,
            r#"<li><label class="todo-list__label"><input disabled="disabled" type="checkbox">"#,
            r#"<span class="todo-list__label__description">one</span></label></li>"#,
            r#"<li><label class="todo-list__label"><input disabled="disabled" type="checkbox">"#,
            r#"<span class="todo-list__label__description">two</span></label></li>"#,
            r#"</ul>"#,
        );
        let segments = segment(html);
        let buffer = render(&segments);
        assert_eq!(buffer, "- [ ] one\n- [ ] two", "got {buffer}");
        assert_eq!(parse(&buffer, &segments), html);

        let edited = buffer.replace("[ ] two", "[x] two");
        assert_eq!(
            parse(&edited, &segments),
            concat!(
                r#"<ul class="todo-list">"#,
                r#"<li><label class="todo-list__label"><input disabled="disabled" type="checkbox">"#,
                r#"<span class="todo-list__label__description">one</span></label></li>"#,
                r#"<li><label class="todo-list__label"><input checked="checked" disabled="disabled" type="checkbox">"#,
                r#"<span class="todo-list__label__description">two</span></label></li>"#,
                r#"</ul>"#,
            )
        );
    }

    /// A checkbox item with a continuation paragraph and a nested sub-item
    /// edits through the buffer exactly like any other list.
    #[test]
    fn a_todo_item_with_a_continuation_and_a_nested_item_edits_correctly() {
        let html = concat!(
            r#"<ul class="todo-list"><li><label class="todo-list__label">"#,
            r#"<input disabled="disabled" type="checkbox">"#,
            r#"<span class="todo-list__label__description">first</span></label>"#,
            r#"<p>more detail</p>"#,
            r#"<ul class="todo-list"><li><label class="todo-list__label">"#,
            r#"<input disabled="disabled" type="checkbox">"#,
            r#"<span class="todo-list__label__description">sub</span></label></li></ul>"#,
            r#"</li></ul>"#,
        );
        let segments = segment(html);
        let buffer = render(&segments);
        assert_eq!(
            buffer, "- [ ] first\n\n  more detail\n\n  - [ ] sub",
            "got {buffer}"
        );
        assert_eq!(parse(&buffer, &segments), html);

        let edited = buffer.replace("[ ] sub", "[x] sub");
        assert_eq!(
            parse(&edited, &segments),
            concat!(
                r#"<ul class="todo-list"><li><label class="todo-list__label">"#,
                r#"<input disabled="disabled" type="checkbox">"#,
                r#"<span class="todo-list__label__description">first</span></label>"#,
                r#"<p>more detail</p>"#,
                r#"<ul class="todo-list"><li><label class="todo-list__label">"#,
                r#"<input checked="checked" disabled="disabled" type="checkbox">"#,
                r#"<span class="todo-list__label__description">sub</span></label></li></ul>"#,
                r#"</li></ul>"#,
            )
        );
    }

    /// A plain bullet list directly followed by a todo list -- the shape that
    /// exposed the bug this test guards against: both blocks classify
    /// transparent, and editing the checkbox forces the two adjacent chunks
    /// to be re-split from raw buffer text, which is exactly where
    /// `to_html::split_mixed_task_lists` has to put them back as two
    /// separate `<ul>`s rather than merging them.
    #[test]
    fn a_bullet_list_next_to_a_todo_list_edits_correctly() {
        let html = concat!(
            r#"<ul><li>foo</li></ul>"#,
            r#"<ul class="todo-list"><li><label class="todo-list__label">"#,
            r#"<input disabled="disabled" type="checkbox">"#,
            r#"<span class="todo-list__label__description">fasf</span></label></li></ul>"#,
        );
        let segments = segment(html);
        let buffer = render(&segments);
        assert_eq!(buffer, "- foo\n\n+ [ ] fasf", "got {buffer}");
        assert_eq!(parse(&buffer, &segments), html);

        let edited = buffer.replace("[ ] fasf", "[x] fasf");
        assert_eq!(
            parse(&edited, &segments),
            concat!(
                // The untouched bullet list keeps its exact original bytes
                // -- no reformatting, no dropped/regenerated attributes --
                // because the marker swap on the todo-list keeps both as
                // separate chunks instead of one merged chunk that neither
                // block's own markdown matches.
                r#"<ul><li>foo</li></ul>"#,
                r#"<ul class="todo-list"><li><label class="todo-list__label">"#,
                r#"<input checked="checked" disabled="disabled" type="checkbox">"#,
                r#"<span class="todo-list__label__description">fasf</span></label></li></ul>"#,
            )
        );

        // The untouched list resolves as `Original`, not a fresh conversion
        // -- this is what keeps it out of `rhizome/dirty`'s span list too.
        let resolved = resolve(&edited, &segments);
        assert!(
            matches!(
                resolved.as_slice(),
                [Resolved::Original(0), Resolved::Replaced(1, _)]
            ),
            "{resolved:?}"
        );
    }

    /// A nested list that mixes a checkbox item with a plain item splits into
    /// two nested `<ul>`s on write; the plain one must come back tight, not
    /// wrapped in `<p>` the way a loose list leaves it, or the round-trip
    /// proof fails on the very next load.
    #[test]
    fn a_nested_mixed_list_round_trips_and_edits_correctly() {
        let md = "- [ ] first\n\n  - [ ] sub\n\n  - plain sub";
        let html = markdown_to_html(md);
        assert_eq!(
            html,
            concat!(
                r#"<ul class="todo-list"><li><label class="todo-list__label">"#,
                r#"<input disabled="disabled" type="checkbox">"#,
                r#"<span class="todo-list__label__description">first</span></label>"#,
                r#"<ul class="todo-list"><li><label class="todo-list__label">"#,
                r#"<input disabled="disabled" type="checkbox">"#,
                r#"<span class="todo-list__label__description">sub</span></label></li></ul>"#,
                "<ul>\n<li>plain sub</li>\n</ul></li></ul>",
            ),
            "{html}"
        );

        let segments = segment(&html);
        let buffer = render(&segments);
        assert_eq!(buffer, md, "got {buffer}");
        assert_eq!(parse(&buffer, &segments), html);

        let edited = buffer.replace("[ ] sub", "[x] sub");
        let out = parse(&edited, &segments);
        assert!(out.contains(r#"checked="checked""#), "{out}");
        assert!(out.contains("plain sub"), "{out}");
    }

    /// Two directly adjacent same-kind lists have the second held opaque by
    /// `segment` -- an unedited save must still restore both exactly, and the
    /// no-op fast path is what guarantees that regardless of how the ambiguous
    /// chunk-matching heuristics below it would have resolved a merged chunk.
    #[test]
    fn an_unedited_save_near_different_flavour_adjacent_lists_is_a_true_no_op() {
        let html = concat!(
            r#"<ul class="todo-list"><li><label class="todo-list__label">"#,
            r#"<input disabled="disabled" type="checkbox">"#,
            r#"<span class="todo-list__label__description">a</span></label>"#,
            r#"<p>continuation</p>"#,
            r#"</li></ul>"#,
            r#"<ul><li>bullet nearby</li></ul>"#,
        );
        let segments = segment(html);
        let buffer = render(&segments);
        assert_eq!(parse(&buffer, &segments), html);
    }

    #[test]
    fn an_unedited_save_near_same_flavour_adjacent_lists_is_a_true_no_op() {
        let html = "<ul><li>a</li></ul><ul><li>bullet nearby</li></ul>";
        let segments = segment(html);
        let buffer = render(&segments);
        assert_eq!(parse(&buffer, &segments), html);
    }

    /// Regression: editing one block of a plain-list-next-to-a-todo-list
    /// note must not mark the untouched list dirty. Before the marker-swap
    /// fix, the two lists rendered with the same `-` marker, re-split as one
    /// merged chunk, and any edit anywhere in the note (not just to this
    /// pair) made `resolve_spans` regenerate both instead of recognising the
    /// untouched one as `Original` -- which is exactly what fed a false
    /// positive into `rhizome/dirty`.
    #[test]
    fn editing_a_todo_item_does_not_dirty_an_adjacent_untouched_bullet_list() {
        let html = concat!(
            r#"<p>asfas</p>"#,
            r#"<ul><li>fas fasf</li><li>fasf as</li><li>fasfasf</li></ul>"#,
            r#"<ul class="todo-list"><li><label class="todo-list__label">"#,
            r#"<input disabled="disabled" type="checkbox">"#,
            r#"<span class="todo-list__label__description">fasf</span></label></li></ul>"#,
        );
        let segments = segment(html);
        let buffer = render(&segments);
        let edited = buffer.replace("[ ] fasf", "[x] fasf");
        let resolved = resolve(&edited, &segments);
        assert!(
            matches!(
                resolved.as_slice(),
                [
                    Resolved::Original(0),
                    Resolved::Original(1),
                    Resolved::Replaced(2, _)
                ]
            ),
            "{resolved:?}"
        );
    }

    #[test]
    fn task_list_degradations_is_empty_for_an_unedited_buffer() {
        let html = concat!(
            r#"<ul class="todo-list"><li><label class="todo-list__label">"#,
            r#"<input disabled="disabled" type="checkbox">"#,
            r#"<span class="todo-list__label__description">a</span></label></li></ul>"#,
        );
        let segments = segment(html);
        let buffer = render(&segments);
        assert!(task_list_degradations(&buffer, &segments).is_empty());
    }

    #[test]
    fn task_list_degradations_flags_a_freshly_typed_ordered_task_list() {
        let segments = segment("<p>placeholder</p>");
        let text = "1. [x] a";
        let degradations = task_list_degradations(text, &segments);
        assert_eq!(degradations.len(), 1);
        assert_eq!(&text[degradations[0].clone()], text);
    }

    #[test]
    fn task_list_degradations_ignores_an_edit_that_does_not_touch_a_checkbox() {
        let html = "<p>fine</p>";
        let segments = segment(html);
        let text = "totally different prose";
        assert!(task_list_degradations(text, &segments).is_empty());
    }

    #[test]
    fn opaque_html_survives_untouched() {
        let html = r#"<figure class="image"><img src="a.png" width="3"></figure>"#;
        let segments = segment(html);
        let buffer = render(&segments);
        assert_eq!(parse(&buffer, &segments), html);
    }

    #[test]
    fn hand_edited_opaque_html_is_taken_verbatim() {
        let html = r#"<figure class="image"><img src="a.png" width="3"></figure>"#;
        let segments = segment(html);
        let buffer = render(&segments).replace("a.png", "b.png");
        assert!(parse(&buffer, &segments).contains("b.png"));
    }

    #[test]
    fn code_blocks_spanning_blank_lines_stay_one_block() {
        let text = "```rust\nlet a = 1;\n\nlet b = 2;\n```";
        assert_eq!(split_blocks_with_ranges(text).len(), 1);
    }

    /// The layout of a note is content as far as its owner is concerned: a save
    /// that reflows it makes every sync diff unreadable.
    #[test]
    fn unusual_inter_block_whitespace_survives_a_no_op_save() {
        let html = "\n  <p>a</p>\n\n\n    <p>b</p>\n  ";
        let segments = segment(html);
        assert_eq!(parse(&render(&segments), &segments), html);
    }

    #[test]
    fn editing_one_block_preserves_the_whitespace_around_it() {
        let html = "<p>first</p>\n\n\n<p>second</p>";
        let segments = segment(html);
        let edited = render(&segments).replace("second", "changed");
        assert_eq!(
            parse(&edited, &segments),
            "<p>first</p>\n\n\n<p>changed</p>"
        );
    }

    #[test]
    fn repeated_identical_paragraphs_keep_their_positions() {
        let html = "<p>same</p>\n\n<p>same</p>";
        let segments = segment(html);
        assert_eq!(parse(&render(&segments), &segments), html);
    }

    #[test]
    fn inserting_a_block_does_not_rewrite_its_neighbours() {
        let html = "<p>first</p>\n<p>second</p>";
        let segments = segment(html);
        let edited = format!("{}\n\nadded", render(&segments));
        let out = parse(&edited, &segments);
        assert!(out.starts_with("<p>first</p>\n<p>second</p>"), "{out}");
        assert!(out.contains("<p>added</p>"), "{out}");
    }

    #[test]
    fn spacer_renders_as_a_pilcrow() {
        let html = "<p>a</p>\n<p>&nbsp;</p>\n<p>b</p>";
        let buffer = render(&segment(html));
        assert_eq!(buffer, "a\n\n\u{b6}\n\nb");
    }

    #[test]
    fn an_untouched_spacer_round_trips_byte_identically() {
        let html = "<p>a</p>\n<p>&nbsp;</p>\n<p>b</p>";
        let segments = segment(html);
        assert_eq!(parse(&render(&segments), &segments), html);
    }

    /// The whole point: a blank-line spacer can be removed just by deleting
    /// its line, the same as deleting any other line.
    #[test]
    fn deleting_the_pilcrow_line_removes_the_spacer() {
        let html = "<p>a</p>\n<p>&nbsp;</p>\n<p>b</p>";
        let segments = segment(html);
        let edited = "a\n\nb";
        assert_eq!(parse(edited, &segments), "<p>a</p>\n<p>b</p>");
    }

    #[test]
    fn typing_a_pilcrow_inserts_a_fresh_spacer() {
        let html = "<p>a</p>\n<p>b</p>";
        let segments = segment(html);
        let edited = "a\n\n\u{b6}\n\nb";
        assert_eq!(
            parse(edited, &segments),
            "<p>a</p>\n<p>&nbsp;</p>\n<p>b</p>"
        );
    }

    /// Two adjacent spacers with different original markup must each restore
    /// their own bytes, not be conflated into a single canonical form.
    #[test]
    fn consecutive_spacers_round_trip_byte_identically() {
        let html = "<p>a</p>\n<p>&nbsp;</p>\n<p><br></p>\n<p>b</p>";
        let segments = segment(html);
        assert_eq!(parse(&render(&segments), &segments), html);
    }

    #[test]
    fn an_opaque_block_containing_a_backtick_run_gets_a_wider_fence() {
        let html = "<div data-x=\"```\">text</div>";
        let segments = segment(html);
        let buffer = render(&segments);
        assert!(buffer.starts_with("````=html"), "got {buffer}");
        assert_eq!(parse(&buffer, &segments), html);
    }

    #[test]
    fn a_five_backtick_run_gets_a_six_backtick_fence() {
        let html = "<div data-x=\"`````\">text</div>";
        let segments = segment(html);
        let buffer = render(&segments);
        assert!(buffer.starts_with("``````=html"), "got {buffer}");
        assert_eq!(parse(&buffer, &segments), html);
    }

    #[test]
    fn parse_html_fence_requires_a_closer_at_least_as_long_as_the_opener() {
        let chunk = "````=html b0-aaaa\nsome <p>```</p> content\n````";
        let (id, html) = parse_html_fence(chunk).unwrap();
        assert_eq!(id, "b0-aaaa");
        assert_eq!(html, "some <p>```</p> content");
    }

    /// This is the truncation risk a fixed three-backtick fence had: a bare
    /// three-backtick line inside a wider fence's body used to read as that
    /// fence's own closer.
    #[test]
    fn a_bare_three_backtick_line_inside_a_wider_fence_does_not_truncate_it() {
        let chunk = "````=html b0-aaaa\nline one\n```\nline two\n````";
        let (_, html) = parse_html_fence(chunk).unwrap();
        assert_eq!(html, "line one\n```\nline two");
    }
}
