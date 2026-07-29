//! The segment list: a note as an ordered sequence of blocks, each either
//! editable prose or verbatim HTML.
//!
//! The rule that makes this safe is **transparent by proof**. A block is only
//! offered as Markdown when the engine can demonstrate, for that specific
//! block, that converting to Markdown and back reproduces an equivalent DOM.
//! Everything else stays opaque.
//!
//! This inverts the usual arrangement, where a converter tries its best and
//! damage is discovered later (or never). Here losslessness is a checked
//! invariant on every block, on every open. An incomplete rule set costs
//! transparency, never content.

use std::collections::BTreeMap;

use crate::convert::to_md::Escaping;
use crate::convert::{markdown_to_html, to_md};
use crate::dom::{self, Node};
use crate::source::{Span, split_top_level};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OpaqueReason {
    /// No rule claimed this construct.
    NoRule,
    /// A rule produced Markdown, but re-rendering it did not reproduce the
    /// original DOM. The rule is wrong for this input; its output is discarded.
    VerificationFailed,
    /// The note as a whole could not be scanned into top-level blocks.
    Unparseable,
    /// This block would render as a Markdown list directly adjacent to
    /// another transparent block that renders as the same kind of list
    /// (`ul`/`ul` or `ol`/`ol`). Two such lists concatenate into a single
    /// chunk when the buffer is re-split, so the pair can never be told apart
    /// again -- shown here as HTML instead of silently merging them on save.
    Ambiguous,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BlockKind {
    Transparent {
        markdown: String,
    },
    /// A paragraph that carries no content of its own -- CKEditor's
    /// representation of a blank line (`<p>&nbsp;</p>`, `<p><br></p>`, or an
    /// empty `<p></p>`). Kept distinct from `Opaque` because it is not a
    /// construct anyone needs to read as raw HTML; it is rendered as a single
    /// pilcrow in the buffer instead of a fence.
    Spacer,
    Opaque {
        reason: OpaqueReason,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Block {
    /// Stable within a note: position plus a hash of the original source.
    pub id: String,
    /// The exact bytes this block occupied in the note. Splicing an untouched
    /// block re-emits this unchanged.
    pub source: String,
    pub kind: BlockKind,
}

impl Block {
    pub fn is_transparent(&self) -> bool {
        matches!(self.kind, BlockKind::Transparent { .. })
    }

    pub fn is_spacer(&self) -> bool {
        matches!(self.kind, BlockKind::Spacer)
    }

    pub fn markdown(&self) -> Option<&str> {
        match &self.kind {
            BlockKind::Transparent { markdown } => Some(markdown),
            BlockKind::Spacer | BlockKind::Opaque { .. } => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Segment {
    Whitespace(String),
    Block(Block),
}

#[derive(Debug, Clone, Default)]
pub struct Segments {
    pub segments: Vec<Segment>,
}

impl Segments {
    pub fn blocks(&self) -> impl Iterator<Item = &Block> {
        self.segments.iter().filter_map(|s| match s {
            Segment::Block(b) => Some(b),
            Segment::Whitespace(_) => None,
        })
    }

    pub fn stats(&self) -> Stats {
        let mut stats = Stats::default();
        for block in self.blocks() {
            stats.total += 1;
            match &block.kind {
                BlockKind::Transparent { .. } => stats.transparent += 1,
                BlockKind::Spacer => stats.spacer += 1,
                BlockKind::Opaque {
                    reason: OpaqueReason::NoRule,
                } => stats.no_rule += 1,
                BlockKind::Opaque {
                    reason: OpaqueReason::VerificationFailed,
                } => stats.verification_failed += 1,
                BlockKind::Opaque {
                    reason: OpaqueReason::Unparseable,
                } => stats.unparseable += 1,
                BlockKind::Opaque {
                    reason: OpaqueReason::Ambiguous,
                } => stats.ambiguous += 1,
            }
        }
        stats
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Stats {
    pub total: usize,
    pub transparent: usize,
    /// Blank-line paragraphs. Counted separately from `opaque`: they carry no
    /// content, so they should not read as "raw HTML you have to deal with".
    pub spacer: usize,
    pub no_rule: usize,
    pub verification_failed: usize,
    pub unparseable: usize,
    pub ambiguous: usize,
}

impl Stats {
    pub fn opaque(&self) -> usize {
        self.no_rule + self.verification_failed + self.unparseable + self.ambiguous
    }

    /// Fraction of the note's *content* blocks that are editable Markdown.
    ///
    /// Spacers are excluded from both sides of the ratio: they are not
    /// content, so counting them (the way they were counted as `Opaque`
    /// before this type existed) only dilutes what the number is meant to
    /// measure.
    pub fn transparent_ratio(&self) -> f64 {
        let counted = self.total - self.spacer;
        if counted == 0 {
            return 1.0;
        }
        self.transparent as f64 / counted as f64
    }
}

/// Build the segment list for a note's HTML content.
pub fn segment(html: &str) -> Segments {
    let Some(spans) = split_top_level(html) else {
        // Cannot scan the note; treat the whole thing as one opaque block
        // rather than guessing at boundaries.
        return Segments {
            segments: vec![Segment::Block(Block {
                id: block_id(0, html),
                source: html.to_string(),
                kind: BlockKind::Opaque {
                    reason: OpaqueReason::Unparseable,
                },
            })],
        };
    };

    let mut segments = Vec::with_capacity(spans.len());
    let mut index = 0;
    for span in spans {
        match span {
            Span::Whitespace(ws) => segments.push(Segment::Whitespace(ws)),
            Span::Node(source) => {
                let kind = classify(&source);
                segments.push(Segment::Block(Block {
                    id: block_id(index, &source),
                    source,
                    kind,
                }));
                index += 1;
            }
        }
    }
    distinguish_adjacent_list_markers(&mut segments);
    Segments { segments }
}

/// Two transparent blocks that render as the same *tag* of Markdown list
/// (`ul`/`ul` -- a plain `<ul>` and a `<ul class="todo-list">` both count,
/// since both write their marker as `-` -- or `ol`/`ol`) with nothing
/// between them concatenate into a single chunk when the buffer is
/// re-split. `resolve_spans` would then see one chunk where it expects two
/// blocks: an *unedited* save is still safe (its whole-buffer fast path
/// never runs the chunk matcher at all), but the moment *any other* part of
/// the note is edited, that fast path is skipped and the matcher has to
/// place this merged chunk against two separate blocks' worth of markdown.
/// Neither matches it, so both blocks come back freshly regenerated by
/// `to_html` instead of the untouched one being left alone -- losslessly
/// correct HTML (`split_mixed_task_lists` recovers both flavours), but a
/// wider rewrite and a false-dirty indicator on content nobody touched.
///
/// Rather than accept that, the second list's top-level marker is swapped
/// to an alternate that CommonMark never treats as a continuation of the
/// first (`-` -> `+` for `ul`, `.` -> `)` for `ol`'s delimiter) -- verified
/// the same way every transparent block is proved transparent, so a block
/// where that swap somehow does not round-trip falls back to the opaque
/// demotion this replaced, rather than risking a merge.
///
/// Processed left to right, consulting each block's own tag (stable
/// regardless of which marker it currently renders with): a run of three or
/// more same-tag adjacent lists alternates every other one, since two
/// blocks sharing the same alternate marker would just recreate the
/// problem this is solving.
fn distinguish_adjacent_list_markers(segments: &mut [Segment]) {
    let block_indices: Vec<usize> = segments
        .iter()
        .enumerate()
        .filter_map(|(i, s)| matches!(s, Segment::Block(_)).then_some(i))
        .collect();

    let mut prev_tag: Option<&'static str> = None;
    let mut alt = false;
    for &i in &block_indices {
        let Some(tag) = list_tag(&segments[i]) else {
            prev_tag = None;
            alt = false;
            continue;
        };
        alt = prev_tag == Some(tag) && !alt;
        prev_tag = Some(tag);
        if !alt {
            continue;
        }
        let Segment::Block(block) = &mut segments[i] else {
            unreachable!("index came from a Block filter")
        };
        let BlockKind::Transparent { markdown } = &block.kind else {
            unreachable!("list_tag only returns Some for a transparent block")
        };
        let alternated = alternate_top_level_marker(markdown, tag == "ol");
        if dom::equivalent(&block.source, &markdown_to_html(&alternated)) {
            block.kind = BlockKind::Transparent {
                markdown: alternated,
            };
        } else {
            block.kind = BlockKind::Opaque {
                reason: OpaqueReason::Ambiguous,
            };
            prev_tag = None;
            alt = false;
        }
    }
}

/// Rewrite every column-0 list marker in a transparent list block's
/// Markdown to the family's alternate form. Only a block's top-level item
/// lines ever start at column 0 -- `render_list_item` indents every
/// continuation and nested line under the marker -- so this cannot touch
/// anything but the marker itself: not a nested sub-list (which shares no
/// adjacency risk with a sibling top-level block anyway) and not user text,
/// which `escape_block_start` already keeps off column 0.
fn alternate_top_level_marker(markdown: &str, ordered: bool) -> String {
    markdown
        .lines()
        .map(|line| {
            if ordered {
                match line.find(". ") {
                    Some(dot) if line[..dot].bytes().all(|b| b.is_ascii_digit()) && dot > 0 => {
                        format!("{}){}", &line[..dot], &line[dot + 1..])
                    }
                    _ => line.to_string(),
                }
            } else {
                match line.strip_prefix("- ") {
                    Some(rest) => format!("+ {rest}"),
                    None => line.to_string(),
                }
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

/// A list's tag if `segment` is a *transparent* block whose source is
/// rooted at that single element, else `None`. Only transparent blocks are
/// at risk: an opaque block renders as an `=html` fence, which always
/// splits cleanly regardless of what it contains. Deliberately ignores
/// whether a `<ul>` is a todo-list -- both write their marker as `-`, so
/// both belong to the same adjacency family.
fn list_tag(segment: &Segment) -> Option<&'static str> {
    let Segment::Block(block) = segment else {
        return None;
    };
    if !block.is_transparent() {
        return None;
    }
    let nodes = dom::parse(&block.source);
    let mut elements = nodes.iter().filter_map(Node::element);
    let root = elements.next()?;
    if elements.next().is_some() {
        return None;
    }
    match root.name.as_str() {
        "ul" => Some("ul"),
        "ol" => Some("ol"),
        _ => None,
    }
}

/// Decide whether a block can be safely shown as Markdown.
///
/// Tries the least-escaped rendering first and lets the proof below decide
/// whether it was too optimistic. Being wrong here costs a second conversion
/// pass, not the block's transparency, which is what lets `Escaping::Bare`
/// leave ordinary prose (`snake_case`, `512 > 256`, `[Branch]`) unescaped
/// instead of defending against Markdown syntax that was never actually
/// ambiguous in this block's context.
fn classify(source: &str) -> BlockKind {
    let nodes = dom::parse(source);
    if is_spacer_paragraph(&nodes) {
        return BlockKind::Spacer;
    }

    let no_rule = BlockKind::Opaque {
        reason: OpaqueReason::NoRule,
    };
    let Some(bare) = to_md::blocks_to_markdown(&nodes, Escaping::Bare) else {
        return no_rule;
    };
    if bare.trim().is_empty() {
        return no_rule;
    }
    if dom::equivalent(source, &markdown_to_html(&bare)) {
        return BlockKind::Transparent { markdown: bare };
    }

    // `Bare` guessed wrong for this block; fall back to escaping everything
    // Markdown could possibly read as syntax. `full == bare` exactly when
    // the block had nothing for the wider escape set to touch, in which case
    // it already failed the proof above and a second, identical attempt
    // would only fail again.
    let Some(full) = to_md::blocks_to_markdown(&nodes, Escaping::Full) else {
        return no_rule;
    };
    if full != bare && dom::equivalent(source, &markdown_to_html(&full)) {
        return BlockKind::Transparent { markdown: full };
    }

    BlockKind::Opaque {
        reason: OpaqueReason::VerificationFailed,
    }
}

/// A `<p>` that carries no content: only ASCII/nbsp whitespace and bare
/// `<br>`s. This is how CKEditor represents a blank line -- there is no
/// Markdown construct for "nothing", so it is not routed through the
/// Markdown proof at all; it is recognised structurally instead.
fn is_spacer_paragraph(nodes: &[Node]) -> bool {
    let [Node::Element(p)] = nodes else {
        return false;
    };
    if p.name != "p" || !p.attrs.is_empty() {
        return false;
    }
    p.children.iter().all(|child| match child {
        Node::Text(t) => t.chars().all(|c| c.is_ascii_whitespace() || c == '\u{a0}'),
        Node::Element(e) => e.name == "br" && e.attrs.is_empty() && e.children.is_empty(),
        Node::Comment(_) => false,
    })
}

fn block_id(index: usize, source: &str) -> String {
    let hash = blake3::hash(source.as_bytes());
    format!("b{index}-{}", &hash.to_hex()[..8])
}

/// How one chunk of edited buffer text maps back onto the original note.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Resolved {
    /// Unchanged. Re-emit block `index` from its original bytes.
    Original(usize),
    /// Block `index`, rewritten. Its position -- and so the whitespace around
    /// it -- is still known.
    Replaced(usize, String),
    /// Content with no counterpart in the original note.
    New(String),
}

impl Resolved {
    fn index(&self) -> Option<usize> {
        match self {
            Resolved::Original(i) | Resolved::Replaced(i, _) => Some(*i),
            Resolved::New(_) => None,
        }
    }
}

/// Why a rebuilt note was refused.
#[derive(Debug, Clone, thiserror::Error, PartialEq, Eq)]
pub enum RebuildError {
    #[error(
        "the rebuilt note does not scan as HTML -- an edited block probably has an unclosed tag"
    )]
    DoesNotScan,
    #[error("the rebuilt note lost all content, but the note was not empty")]
    LostEverything,
}

/// Check a rebuilt note before it is written back to Trilium.
///
/// Opaque blocks are handed to the user as raw HTML and taken back verbatim, so
/// a mistyped tag in one of them can swallow every block that follows it. The
/// splitter already refuses to scan that, and honouring the refusal here turns
/// what would be a silently truncated note into a save that simply does not
/// happen. ETAPI has no transactions and no `If-Match`, so a bad write cannot
/// be taken back.
pub fn verify_rebuild(html: &str, original: &Segments) -> Result<(), RebuildError> {
    if split_top_level(html).is_none() {
        return Err(RebuildError::DoesNotScan);
    }
    if html.trim().is_empty() && original.blocks().next().is_some() {
        return Err(RebuildError::LostEverything);
    }
    Ok(())
}

/// Re-render a note from resolved chunks, preserving the original inter-block
/// whitespace wherever the document's ordering survived.
///
/// Preserving that whitespace is what makes a no-op save a genuine no-op.
/// Re-joining blocks with a fixed separator instead would rewrite the layout of
/// every note merely by opening and saving it, turning every sync diff into
/// noise -- the exact failure the byte-exact splitter exists to avoid.
pub fn splice_resolved(segments: &Segments, resolved: &[Resolved]) -> String {
    let layout = Layout::of(segments);
    let mut out = String::new();
    out.push_str(&layout.leading);

    let mut previous: Option<usize> = None;
    for (n, item) in resolved.iter().enumerate() {
        if n > 0 {
            // The original separator only applies if these two blocks were
            // genuinely adjacent in the source; otherwise fall back to a
            // newline rather than inventing a relationship.
            let separator = match (previous, item.index()) {
                (Some(p), Some(i)) if i == p + 1 => layout.separators[i].as_str(),
                _ => "\n",
            };
            out.push_str(separator);
        }
        match item {
            Resolved::Original(i) => out.push_str(&layout.sources[*i]),
            Resolved::Replaced(_, html) | Resolved::New(html) => out.push_str(html),
        }
        previous = item.index();
    }

    out.push_str(&layout.trailing);
    out
}

/// The whitespace skeleton of a note: what sat before, between and after its
/// blocks.
struct Layout {
    leading: String,
    trailing: String,
    /// `separators[i]` is the whitespace immediately preceding block `i`.
    separators: Vec<String>,
    sources: Vec<String>,
}

impl Layout {
    fn of(segments: &Segments) -> Self {
        let mut leading = String::new();
        let mut separators = Vec::new();
        let mut sources = Vec::new();
        let mut pending = String::new();
        let mut seen_block = false;

        for segment in &segments.segments {
            match segment {
                Segment::Whitespace(ws) => {
                    if seen_block {
                        pending.push_str(ws);
                    } else {
                        leading.push_str(ws);
                    }
                }
                Segment::Block(block) => {
                    separators.push(std::mem::take(&mut pending));
                    sources.push(block.source.clone());
                    seen_block = true;
                }
            }
        }

        Self {
            leading,
            trailing: pending,
            separators,
            sources,
        }
    }
}

/// Re-render a note, substituting only the blocks the user actually changed.
///
/// Blocks absent from `edits` are emitted from their original source, so they
/// are byte-identical to what Trilium already holds. This is what keeps a
/// no-op open-and-save a genuine no-op.
pub fn splice(segments: &Segments, edits: &BTreeMap<String, String>) -> String {
    let resolved: Vec<Resolved> = segments
        .blocks()
        .enumerate()
        .map(|(i, block)| match edits.get(&block.id) {
            None => Resolved::Original(i),
            Some(edited) => match &block.kind {
                // Unchanged prose re-emits the original bytes rather than a
                // freshly rendered equivalent.
                BlockKind::Transparent { markdown } if markdown == edited => Resolved::Original(i),
                BlockKind::Transparent { .. } => Resolved::Replaced(i, markdown_to_html(edited)),
                // Opaque and spacer blocks are edited as raw HTML and used
                // verbatim.
                BlockKind::Opaque { .. } | BlockKind::Spacer => {
                    Resolved::Replaced(i, edited.clone())
                }
            },
        })
        .collect();
    splice_resolved(segments, &resolved)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kinds(html: &str) -> Vec<BlockKind> {
        segment(html).blocks().map(|b| b.kind.clone()).collect()
    }

    #[test]
    fn simple_prose_is_transparent() {
        let seg = segment("<h2>Title</h2>\n<p>Body text.</p>");
        assert_eq!(seg.stats().transparent, 2);
        assert_eq!(seg.stats().opaque(), 0);
    }

    /// Ordinary prose that happens to contain a Markdown-active character
    /// must not come back with a backslash in front of it -- the `Bare`
    /// pass should prove itself without ever needing `Full`.
    #[test]
    fn ordinary_punctuation_is_not_escaped() {
        let seg = segment("<p>512 &gt; 256 &gt; 128, snake_case, [Branch], a | b, ~5 items</p>");
        let block = seg.blocks().next().unwrap();
        assert_eq!(
            block.markdown().unwrap(),
            "512 > 256 > 128, snake_case, [Branch], a | b, ~5 items"
        );
    }

    /// The case `Bare` cannot handle: a literal, unpaired `*` reads as
    /// emphasis on reparse, so the proof must fail it and fall back to
    /// `Full` -- which is what actually keeps the block transparent instead
    /// of losing it to `VerificationFailed`.
    #[test]
    fn a_character_bare_gets_wrong_still_ends_up_transparent_via_full() {
        let seg = segment("<p>a *b* c</p>");
        let block = seg.blocks().next().unwrap();
        assert!(
            block.is_transparent(),
            "expected the Full fallback to save this block, got {:?}",
            block.kind
        );
        assert_eq!(block.markdown().unwrap(), "a \\*b\\* c");
    }

    /// A paragraph starting `1.`/`N)` used to render `\1.` -- a literal
    /// backslash-then-digit, which does not suppress CommonMark's ordered-
    /// list marker at all, so the block failed its own proof and went
    /// opaque. The escape belongs on the punctuation, not the digit.
    #[test]
    fn a_paragraph_starting_with_a_digit_marker_is_transparent() {
        for html in [
            "<p>1. not a list</p>",
            "<p>2024. What a year</p>",
            "<p>1) also not a list</p>",
        ] {
            let seg = segment(html);
            let block = seg.blocks().next().unwrap();
            assert!(
                block.is_transparent(),
                "{html}: expected transparent, got {:?}",
                block.kind
            );
        }
    }

    #[test]
    fn admonitions_round_trip() {
        let html = r#"<aside class="admonition important"><p>Careful.</p></aside>"#;
        let seg = segment(html);
        let block = seg.blocks().next().unwrap();
        assert!(
            block.is_transparent(),
            "admonition should be transparent, got {:?}",
            block.kind
        );
        assert_eq!(block.markdown().unwrap(), "> [!IMPORTANT]\n>\n> Careful.");
    }

    /// The construct pandoc destroys silently must survive us completely.
    #[test]
    fn admonition_survives_splice() {
        let html = r#"<aside class="admonition important"><p>Careful.</p></aside>"#;
        let seg = segment(html);
        let id = seg.blocks().next().unwrap().id.clone();
        let mut edits = BTreeMap::new();
        edits.insert(id, "> [!IMPORTANT]\n>\n> Rewritten.".to_string());
        let out = splice(&seg, &edits);
        assert!(out.contains(r#"class="admonition important""#), "got {out}");
        assert!(out.contains("Rewritten"));
    }

    /// CKEditor writes multi-paragraph list items as blocks inside the `<li>`.
    /// These are loose lists and are perfectly representable.
    #[test]
    fn multi_paragraph_list_items_round_trip() {
        let html = "<ul><li><p>one</p><p>more</p></li><li><p>two</p></li></ul>";
        let seg = segment(html);
        let block = seg.blocks().next().unwrap();
        assert!(block.is_transparent(), "{:?}", block.kind);
        assert_eq!(splice(&seg, &BTreeMap::new()), html);
    }

    /// Looseness is a property of the whole list, so a list that mixes the two
    /// item shapes has no Markdown form and must not be guessed at.
    #[test]
    fn lists_mixing_tight_and_loose_items_stay_opaque() {
        let html = "<ul><li>tight</li><li><p>loose</p><p>again</p></li></ul>";
        assert!(!segment(html).blocks().next().unwrap().is_transparent());
    }

    /// CKEditor 45.1.1+ stamps every `<li>` with a per-session bookkeeping id
    /// (see `dom::is_ignorable_attr`), regenerated on load. It must not be
    /// the one thing standing between a list and being shown as Markdown.
    #[test]
    fn list_items_carrying_the_ckeditor_id_are_transparent() {
        let html = concat!(
            "<ul>",
            "<li data-list-item-id=\"e1c224\">one",
            "<ul><li data-list-item-id=\"e2426\">nested</li></ul>",
            "</li>",
            "<li data-list-item-id=\"e5b18\">two</li>",
            "</ul>"
        );
        let seg = segment(html);
        let block = seg.blocks().next().unwrap();
        assert!(block.is_transparent(), "{:?}", block.kind);
        // Untouched, it replays the original bytes -- ids and all.
        assert_eq!(splice(&seg, &BTreeMap::new()), html);
    }

    /// A `<li>` attribute that is *not* CKEditor's list-item id has no known
    /// Markdown form and must keep the list opaque -- in particular
    /// `data-trilium-task-state`, which multistate todo lists use and GFM
    /// cannot express.
    #[test]
    fn list_items_carrying_an_unrecognised_attribute_stay_opaque() {
        let html = r#"<ul><li data-trilium-task-state="doing">one</li></ul>"#;
        assert!(!segment(html).blocks().next().unwrap().is_transparent());
    }

    /// CKEditor's two-state todo list has a direct GFM form.
    #[test]
    fn a_two_state_todo_list_is_transparent() {
        let html = concat!(
            r#"<ul class="todo-list">"#,
            r#"<li><label class="todo-list__label"><input type="checkbox" disabled="disabled">"#,
            r#"<span class="todo-list__label__description">unchecked</span></label></li>"#,
            r#"<li><label class="todo-list__label"><input type="checkbox" checked="checked" disabled="disabled">"#,
            r#"<span class="todo-list__label__description">checked</span></label></li>"#,
            r#"</ul>"#,
        );
        let seg = segment(html);
        let block = seg.blocks().next().unwrap();
        assert!(block.is_transparent(), "{:?}", block.kind);
        assert_eq!(splice(&seg, &BTreeMap::new()), html);
    }

    /// Trilium's multistate todo plugin has no two-state GFM form; the item
    /// carrying it must not be silently rounded to the nearest checkbox
    /// state, so the whole list stays opaque.
    #[test]
    fn a_multistate_todo_item_keeps_the_list_opaque() {
        let html = concat!(
            r#"<ul class="todo-list">"#,
            r#"<li data-trilium-task-state="doing" title="Doing">"#,
            r#"<label class="todo-list__label"><input type="checkbox" disabled="disabled">"#,
            r#"<span class="todo-list__label__description">doing</span></label></li>"#,
            r#"</ul>"#,
        );
        assert!(!segment(html).blocks().next().unwrap().is_transparent());
    }

    /// Every `<li>` CKEditor 45.1.1+ emits carries `data-list-item-id`
    /// (`dom::is_ignorable_attr`) -- so did every one of these, taken directly
    /// from a real note. Phase 2 originally shipped tested only against
    /// hand-written fixtures without it, and so never actually worked on a
    /// real note; these pin the fix against real output instead.
    #[test]
    fn a_todo_list_carrying_the_ckeditor_id_is_transparent() {
        let html = concat!(
            r#"<ul class="todo-list">"#,
            r#"<li data-list-item-id="e9a57d315d73cd207acfb38a5f9914cd3"><label class="todo-list__label">"#,
            r#"<input type="checkbox" disabled="disabled"><span class="todo-list__label__description">state unchecked</span></label></li>"#,
            r#"<li data-list-item-id="e205a63cfffba5e31aefb87203864e69c"><label class="todo-list__label">"#,
            r#"<input type="checkbox" checked="checked" disabled="disabled"><span class="todo-list__label__description">state 2</span></label></li>"#,
            r#"</ul>"#,
        );
        let seg = segment(html);
        let block = seg.blocks().next().unwrap();
        assert!(block.is_transparent(), "{:?}", block.kind);
        assert_eq!(splice(&seg, &BTreeMap::new()), html);
    }

    /// A checkbox item nested inside another: the inner list sits as a
    /// sibling of the outer item's `<label>`, not inside its description.
    #[test]
    fn a_nested_todo_list_is_transparent() {
        let html = concat!(
            r#"<ul class="todo-list"><li data-list-item-id="ebd249ed3d1e4c8a737139f312fc92771">"#,
            r#"<label class="todo-list__label"><input type="checkbox" disabled="disabled">"#,
            r#"<span class="todo-list__label__description">check 1</span></label>"#,
            r#"<ul class="todo-list"><li data-list-item-id="ef019ca540d1d1547bdd652821f937402">"#,
            r#"<label class="todo-list__label"><input type="checkbox" disabled="disabled">"#,
            r#"<span class="todo-list__label__description">sub check</span></label></li></ul>"#,
            r#"</li></ul>"#,
        );
        let seg = segment(html);
        let block = seg.blocks().next().unwrap();
        assert!(block.is_transparent(), "{:?}", block.kind);
        assert_eq!(splice(&seg, &BTreeMap::new()), html);
    }

    /// A checkbox item can carry further paragraphs after its description --
    /// CKEditor puts them as `<p>` siblings of `<label>`, not inside it.
    #[test]
    fn a_todo_item_with_a_continuation_paragraph_is_transparent() {
        let html = concat!(
            r#"<ul class="todo-list"><li data-list-item-id="e5f7eb9d59e110cda6139e035711c5a44">"#,
            r#"<label class="todo-list__label"><input type="checkbox" disabled="disabled">"#,
            r#"<span class="todo-list__label__description">first line</span></label>"#,
            r#"<p>second line</p>"#,
            r#"<p>third line</p>"#,
            r#"</li></ul>"#,
        );
        let seg = segment(html);
        let block = seg.blocks().next().unwrap();
        assert!(block.is_transparent(), "{:?}", block.kind);
        assert_eq!(splice(&seg, &BTreeMap::new()), html);
    }

    /// CKEditor refuses to create a list mixing plain bullets and checkboxes,
    /// so writing Trilium's own "any task item makes the whole `<ul>`
    /// todo-list" form back would get silently normalised on the next visit
    /// to the web editor. `split_mixed_task_lists` splits the source
    /// `<ul>` into consecutive same-flavour lists instead -- lossless, and
    /// each pure run converts (and later re-segments) independently.
    #[test]
    fn a_mixed_bullet_and_checkbox_list_splits_into_two_lists() {
        let html = "- [x] a\n- b";
        let out = markdown_to_html(html);
        assert_eq!(
            out,
            concat!(
                r#"<ul class="todo-list"><li><label class="todo-list__label">"#,
                r#"<input checked="checked" disabled="disabled" type="checkbox">"#,
                r#"<span class="todo-list__label__description">a</span></label></li></ul>"#,
                "<ul>\n<li>b</li>\n</ul>",
            ),
            "{out}"
        );
        let blocks: Vec<_> = segment(&out).blocks().cloned().collect();
        assert_eq!(blocks.len(), 2);
        assert!(blocks[0].is_transparent(), "{:?}", blocks[0].kind);
        assert!(blocks[1].is_transparent(), "{:?}", blocks[1].kind);
    }

    /// `listType` in CKEditor's model is `bulleted | numbered | todo` --
    /// mutually exclusive, so there is no numbered todo list to write.
    #[test]
    fn an_ordered_task_list_degrades_the_checkbox_to_text() {
        let html = markdown_to_html("1. [ ] a");
        assert!(!html.contains("<input"), "{html}");
        assert!(html.contains("[ ] a"), "{html}");
    }

    /// Two transparent lists of the same tag, directly adjacent, would
    /// concatenate into one chunk when the buffer is re-split -- an edit
    /// elsewhere in the note could then merge them. The second is rewritten
    /// to the alternate marker instead, so both stay transparent.
    #[test]
    fn adjacent_same_tag_lists_alternate_the_second_ones_marker() {
        let html = "<ul><li>a</li></ul><ul><li>bullet nearby</li></ul>";
        let seg = segment(html);
        let blocks: Vec<_> = seg.blocks().collect();
        assert_eq!(blocks.len(), 2);
        assert_eq!(
            blocks[0].kind,
            BlockKind::Transparent {
                markdown: "- a".to_string()
            }
        );
        assert_eq!(
            blocks[1].kind,
            BlockKind::Transparent {
                markdown: "+ bullet nearby".to_string()
            }
        );
        assert_eq!(splice(&seg, &BTreeMap::new()), html);
    }

    /// A plain `<ul>` and a `<ul class="todo-list">` share the same tag (and
    /// so the same marker family, `-`) as far as adjacency risk goes, even
    /// though `to_html::split_mixed_task_lists` would also recover a merged
    /// chunk losslessly -- the marker swap applies uniformly regardless.
    /// This is the real-note shape that motivated the whole mechanism.
    #[test]
    fn adjacent_bullet_and_todo_lists_both_stay_transparent() {
        let html = concat!(
            r#"<ul><li>bullet nearby</li></ul>"#,
            r#"<ul class="todo-list"><li data-list-item-id="e5f7eb9d59e110cda6139e035711c5a44">"#,
            r#"<label class="todo-list__label"><input type="checkbox" disabled="disabled">"#,
            r#"<span class="todo-list__label__description">a</span></label></li></ul>"#,
        );
        let seg = segment(html);
        let blocks: Vec<_> = seg.blocks().collect();
        assert_eq!(blocks.len(), 2);
        assert!(blocks[0].is_transparent(), "{:?}", blocks[0].kind);
        assert!(blocks[1].is_transparent(), "{:?}", blocks[1].kind);
        assert_eq!(splice(&seg, &BTreeMap::new()), html);
    }

    /// A `<ul>`/`<ol>` pair never merges (different markers), so neither
    /// needs demoting.
    #[test]
    fn adjacent_lists_of_different_kinds_both_stay_transparent() {
        let html = "<ul><li>a</li></ul><ol><li>b</li></ol>";
        let seg = segment(html);
        let blocks: Vec<_> = seg.blocks().collect();
        assert_eq!(blocks.len(), 2);
        assert!(blocks[0].is_transparent(), "{:?}", blocks[0].kind);
        assert!(blocks[1].is_transparent(), "{:?}", blocks[1].kind);
    }

    /// A run of three same-kind lists alternates every other one's marker:
    /// once the middle block is on the alternate marker, its own text no
    /// longer merges with either neighbour, so all three stay transparent.
    #[test]
    fn a_run_of_three_same_kind_lists_alternates_every_other_ones_marker() {
        let html = "<ul><li>a</li></ul><ul><li>b</li></ul><ul><li>c</li></ul>";
        let seg = segment(html);
        let blocks: Vec<_> = seg.blocks().collect();
        assert_eq!(blocks.len(), 3);
        assert!(blocks[0].is_transparent(), "{:?}", blocks[0].kind);
        assert!(blocks[1].is_transparent(), "{:?}", blocks[1].kind);
        assert!(blocks[2].is_transparent(), "{:?}", blocks[2].kind);
        assert_eq!(
            blocks[0].kind,
            BlockKind::Transparent {
                markdown: "- a".to_string()
            }
        );
        assert_eq!(
            blocks[1].kind,
            BlockKind::Transparent {
                markdown: "+ b".to_string()
            }
        );
        assert_eq!(
            blocks[2].kind,
            BlockKind::Transparent {
                markdown: "- c".to_string()
            }
        );
        assert_eq!(splice(&seg, &BTreeMap::new()), html);
    }

    /// A hand-edited opaque block with an unclosed tag would swallow whatever
    /// follows it. ETAPI writes cannot be rolled back, so this is refused.
    #[test]
    fn a_rebuild_that_does_not_scan_is_refused() {
        let original = segment("<p>a</p>");
        assert_eq!(
            verify_rebuild("<div><p>a</p>", &original),
            Err(RebuildError::DoesNotScan)
        );
    }

    #[test]
    fn emptying_a_note_that_had_content_is_refused() {
        let original = segment("<p>a</p>");
        assert_eq!(
            verify_rebuild("  \n", &original),
            Err(RebuildError::LostEverything)
        );
    }

    #[test]
    fn a_well_formed_rebuild_is_accepted() {
        let original = segment("<p>a</p>");
        assert_eq!(verify_rebuild("<p>b</p>\n<p>c</p>", &original), Ok(()));
    }

    #[test]
    fn unknown_constructs_stay_opaque() {
        assert_eq!(
            kinds(r#"<div class="mermaid-widget">x</div>"#),
            vec![BlockKind::Opaque {
                reason: OpaqueReason::NoRule
            }]
        );
    }

    #[test]
    fn untouched_note_splices_byte_identical() {
        let html =
            "<h2>T</h2>\n<p>a</p>\n<div data-x=\"1\">opaque</div>\n<ul>\n  <li>one</li>\n</ul>";
        let seg = segment(html);
        assert_eq!(splice(&seg, &BTreeMap::new()), html);
    }

    #[test]
    fn editing_one_block_leaves_others_untouched() {
        let html = "<p>first</p>\n<p>second</p>";
        let seg = segment(html);
        let second = seg.blocks().nth(1).unwrap().id.clone();
        let mut edits = BTreeMap::new();
        edits.insert(second, "changed".to_string());
        assert_eq!(splice(&seg, &edits), "<p>first</p>\n<p>changed</p>");
    }

    #[test]
    fn resubmitting_identical_markdown_is_a_no_op() {
        let html = "<p>Body\n   with odd   spacing</p>";
        let seg = segment(html);
        let block = seg.blocks().next().unwrap();
        let mut edits = BTreeMap::new();
        edits.insert(block.id.clone(), block.markdown().unwrap().to_string());
        assert_eq!(splice(&seg, &edits), html);
    }

    #[test]
    fn code_blocks_round_trip() {
        let html = r#"<pre><code class="language-rust">fn main() {}</code></pre>"#;
        let seg = segment(html);
        assert!(seg.blocks().next().unwrap().is_transparent());
    }

    /// A fence contributes exactly one newline before its closing delimiter and
    /// the HTML direction removes exactly one, so content that genuinely ends
    /// in a newline is preserved rather than being normalised away.
    #[test]
    fn code_with_trailing_newline_round_trips() {
        let html = "<pre><code class=\"language-rust\">fn main() {}\n</code></pre>";
        let seg = segment(html);
        let block = seg.blocks().next().unwrap();
        assert!(block.is_transparent(), "{:?}", block.kind);
        assert_eq!(splice(&seg, &BTreeMap::new()), html);
    }

    #[test]
    fn reference_links_round_trip() {
        let html = r##"<p>See <a class="reference-link" href="#root/abc123">Other</a>.</p>"##;
        let seg = segment(html);
        assert!(
            seg.blocks().next().unwrap().is_transparent(),
            "{:?}",
            seg.blocks().next().unwrap()
        );
    }

    #[test]
    fn styled_images_stay_opaque_rather_than_losing_attributes() {
        let html = r#"<figure class="image"><img style="aspect-ratio:959/547;" src="x.png" width="959" height="547"></figure>"#;
        let seg = segment(html);
        assert!(!seg.blocks().next().unwrap().is_transparent());
    }

    /// One unrepresentable inline atom must not cost the whole paragraph. The
    /// prose stays editable and the `img` rides along as raw HTML.
    #[test]
    fn prose_around_an_unrepresentable_inline_image_stays_editable() {
        let html = r#"<p>Press the <img src="a.png" width="29" height="31">button now.</p>"#;
        let seg = segment(html);
        let block = seg.blocks().next().unwrap();
        assert!(block.is_transparent(), "{:?}", block.kind);
        let md = block.markdown().unwrap();
        assert!(md.contains("Press the"), "{md}");
        assert!(md.contains(r#"width="29""#), "{md}");
    }

    #[test]
    fn inline_math_spans_ride_along_as_html() {
        let html = r#"<p>we have <span class="math-tex">\(62^{12}\)</span> unique IDs</p>"#;
        let block = segment(html).blocks().next().unwrap().clone();
        assert!(block.is_transparent(), "{:?}", block.kind);
        assert!(block.markdown().unwrap().contains("math-tex"));
    }

    /// The limit of the escape hatch: an unknown *block* element is not inline,
    /// so the block goes opaque rather than being silently mangled.
    #[test]
    fn unknown_block_elements_inside_prose_stay_opaque() {
        let html = r#"<p>text <div class="widget">x</div> more</p>"#;
        assert!(!segment(html).blocks().next().unwrap().is_transparent());
    }

    /// CKEditor's representation of a blank line, all three variants.
    #[test]
    fn blank_line_paragraphs_are_spacers() {
        for html in ["<p>&nbsp;</p>", "<p><br></p>", "<p></p>"] {
            let seg = segment(html);
            let block = seg.blocks().next().unwrap();
            assert!(block.is_spacer(), "{html}: {:?}", block.kind);
            assert!(!block.is_transparent());
            assert_eq!(block.markdown(), None);
        }
    }

    #[test]
    fn a_paragraph_with_real_content_is_not_a_spacer() {
        let seg = segment("<p>&nbsp;hello</p>");
        assert!(!seg.blocks().next().unwrap().is_spacer());
    }

    /// A styled or attributed blank paragraph might carry meaning (e.g. a
    /// deliberately empty but formatted cell); only the bare case is safe to
    /// treat as pure layout.
    #[test]
    fn a_styled_blank_paragraph_is_not_a_spacer() {
        let seg = segment(r#"<p class="align-center">&nbsp;</p>"#);
        assert!(!seg.blocks().next().unwrap().is_spacer());
    }

    /// Spacers are not content, so they should not drag down the ratio the
    /// way being counted as opaque used to.
    #[test]
    fn spacers_do_not_count_as_opaque_or_dilute_transparency() {
        let seg = segment("<h2>Title</h2>\n<p>&nbsp;</p>\n<p>Body.</p>");
        let stats = seg.stats();
        assert_eq!(stats.spacer, 1);
        assert_eq!(stats.opaque(), 0);
        assert_eq!(stats.transparent_ratio(), 1.0);
    }

    /// A note that is nothing but a blank line is vacuously fully transparent
    /// -- there is no content to have failed on.
    #[test]
    fn a_note_of_only_spacers_has_full_ratio() {
        let seg = segment("<p>&nbsp;</p>");
        assert_eq!(seg.stats().transparent_ratio(), 1.0);
    }

    /// A backtick run inside a code sample used to force the whole block
    /// opaque. It should now just widen the fence enough to contain it.
    #[test]
    fn code_containing_a_backtick_fence_stays_transparent() {
        let html = r#"<pre><code class="language-markdown">```rust
fn main() {}
```</code></pre>"#;
        let seg = segment(html);
        let block = seg.blocks().next().unwrap();
        assert!(block.is_transparent(), "{:?}", block.kind);
        assert_eq!(splice(&seg, &BTreeMap::new()), html);
    }
}
