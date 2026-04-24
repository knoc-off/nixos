//! Canonical file formatter.
//!
//! Enforces a single shape on every `.md` card in the tree:
//!
//! ```text
//! <body, with all tag tokens excised>
//!
//! #id(<hex>) <tag1> <tag2> ...
//! ```
//!
//! Rules:
//!
//! * Every `#keyword` and `#keyword(args)` token in normal prose is
//!   removed from the body and re-emitted on the trailing tag line.
//! * Tokens inside code blocks (fenced or indented) and inline code
//!   spans are left alone.
//! * `#id(...)` lives first on the tag line. If the source already has
//!   one it wins; otherwise the caller-supplied minted id is used.
//! * Source order: tags appear on the final line in the order they
//!   appeared in the original text, deduplicated by first occurrence.
//! * Body whitespace is normalised: runs of ≥2 blank lines collapse to
//!   a single blank line, leading/trailing blank lines are trimmed,
//!   trailing whitespace on each line is stripped, file ends in a
//!   single `\n`.
//!
//! Idempotent: running the formatter twice on the same file yields
//! byte-identical output.

use crate::tag::NoteId;
use pulldown_cmark::{CodeBlockKind, Event, Parser, Tag, TagEnd};
use regex::Regex;
use std::ops::Range;
use std::sync::LazyLock;

/// Same tag shape as the parser: `#word` or `#word(args)`, where the word
/// starts with an ASCII letter and may contain letters, digits, `_`, `-`,
/// `:` (for Anki's `::` hierarchy).
static TAG_REGEX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"#([A-Za-z][\w:\-]*(?:\([^)]*\))?)").expect("tag regex compiles")
});

/// Format a single `.md` file to the canonical shape.
///
/// If the source already contains an `#id(...)`, that value is kept;
/// otherwise `minted_id` is used. The formatter produces a complete
/// replacement file body.
pub fn format_card(source: &str, minted_id: &NoteId) -> String {
    // Find byte ranges that are "code" — fenced/indented code blocks
    // plus inline `code` spans. Tags inside these ranges are left alone.
    let code_ranges = find_code_ranges(source);

    // Find every tag token outside code ranges.
    let tag_hits: Vec<TagHit> = TAG_REGEX
        .find_iter(source)
        .filter(|m| !is_in_any_range(m.range(), &code_ranges))
        .map(|m| TagHit {
            range: m.range(),
            token: m.as_str().to_string(),
        })
        .collect();

    // Excise tag tokens from the body, preserving everything else.
    let body_stripped = excise_ranges(source, tag_hits.iter().map(|h| h.range.clone()));

    // Normalise whitespace.
    let body_clean = normalise_whitespace(&body_stripped);

    // Prefer an existing `#id(...)` over the caller-supplied minted id.
    let existing_id = tag_hits.iter().find_map(|h| {
        let inner = h.token.strip_prefix('#')?;
        let (kw, args) = split_keyword(inner)?;
        if kw == "id" { args.map(|a| a.to_string()) } else { None }
    });
    let final_id = existing_id.unwrap_or_else(|| minted_id.clone());

    // Build tag line: id first, then other tags in source order,
    // deduplicated by whole-token equality.
    let id_token = format!("#id({final_id})");
    let mut seen = std::collections::HashSet::new();
    seen.insert(id_token.clone());

    let mut tag_line_parts: Vec<String> = Vec::with_capacity(tag_hits.len() + 1);
    tag_line_parts.push(id_token);

    for h in &tag_hits {
        // Skip any `#id(...)` we already handled.
        if let Some(inner) = h.token.strip_prefix('#') {
            if let Some((kw, _)) = split_keyword(inner) {
                if kw == "id" {
                    continue;
                }
            }
        }
        if seen.insert(h.token.clone()) {
            tag_line_parts.push(h.token.clone());
        }
    }

    let tag_line = tag_line_parts.join(" ");
    if body_clean.is_empty() {
        format!("{tag_line}\n")
    } else {
        format!("{body_clean}\n\n{tag_line}\n")
    }
}

struct TagHit {
    range: Range<usize>,
    token: String,
}

/// Split a tag keyword from its arguments. Input is the token without the
/// leading `#`. Returns `None` if the token is syntactically malformed.
fn split_keyword(token: &str) -> Option<(&str, Option<&str>)> {
    match token.find('(') {
        Some(open) => {
            if !token.ends_with(')') {
                return None;
            }
            Some((&token[..open], Some(&token[open + 1..token.len() - 1])))
        }
        None => Some((token, None)),
    }
}

/// Byte ranges covering every fenced / indented code block and every
/// inline code span.
fn find_code_ranges(source: &str) -> Vec<Range<usize>> {
    let mut ranges = Vec::new();
    let parser = Parser::new(source).into_offset_iter();
    let mut code_start: Option<usize> = None;
    for (event, range) in parser {
        match event {
            Event::Start(Tag::CodeBlock(CodeBlockKind::Fenced(_) | CodeBlockKind::Indented)) => {
                code_start = Some(range.start);
            }
            Event::End(TagEnd::CodeBlock) => {
                if let Some(start) = code_start.take() {
                    ranges.push(start..range.end);
                }
            }
            Event::Code(_) => {
                ranges.push(range);
            }
            _ => {}
        }
    }
    ranges
}

fn is_in_any_range(range: Range<usize>, ranges: &[Range<usize>]) -> bool {
    ranges
        .iter()
        .any(|r| range.start >= r.start && range.end <= r.end)
}

/// Delete the given byte ranges from `source`. Input ranges need not be
/// sorted; overlapping ranges are handled by skipping overlaps.
fn excise_ranges(source: &str, ranges: impl IntoIterator<Item = Range<usize>>) -> String {
    let mut sorted: Vec<_> = ranges.into_iter().collect();
    sorted.sort_by_key(|r| r.start);

    let mut out = String::with_capacity(source.len());
    let mut cursor = 0;
    for r in sorted {
        if r.start >= cursor {
            out.push_str(&source[cursor..r.start]);
            cursor = r.end;
        }
    }
    out.push_str(&source[cursor..]);
    out
}

/// Aggressive whitespace normalisation.
///
/// - Trim trailing whitespace from every line.
/// - Collapse runs of ≥2 blank lines to a single blank line.
/// - Trim leading and trailing blank lines from the whole file.
/// - Result has no trailing `\n` (caller adds one).
fn normalise_whitespace(source: &str) -> String {
    let normalised_eol = source.replace("\r\n", "\n");
    let trimmed_lines: Vec<&str> = normalised_eol
        .split('\n')
        .map(|line| line.trim_end())
        .collect();

    let mut out: Vec<&str> = Vec::with_capacity(trimmed_lines.len());
    let mut pending_blanks = 0usize;
    for line in &trimmed_lines {
        if line.is_empty() {
            pending_blanks += 1;
            continue;
        }
        if !out.is_empty() && pending_blanks > 0 {
            out.push("");
        }
        pending_blanks = 0;
        out.push(line);
    }
    out.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_input_yields_only_id_line() {
        let out = format_card("", &"abc123".to_string());
        assert_eq!(out, "#id(abc123)\n");
    }

    #[test]
    fn simple_untagged_card() {
        let src = "front\n---\nback\n";
        let out = format_card(src, &"x".to_string());
        assert_eq!(out, "front\n---\nback\n\n#id(x)\n");
    }

    #[test]
    fn existing_id_wins() {
        let src = "body\n\n#id(keepme)\n";
        let out = format_card(src, &"fresh".to_string());
        assert!(out.contains("#id(keepme)"));
        assert!(!out.contains("#id(fresh)"));
    }

    #[test]
    fn tags_collected_to_bottom_in_source_order() {
        let src = "#cloze\n\nThe capital of **France**.\n\n#geography\n";
        let out = format_card(src, &"x".to_string());
        assert_eq!(
            out,
            "The capital of **France**.\n\n#id(x) #cloze #geography\n"
        );
    }

    #[test]
    fn duplicate_tags_deduped() {
        let src = "body #foo #foo\n\n#foo\n";
        let out = format_card(src, &"x".to_string());
        assert!(out.contains("#id(x) #foo\n"));
        assert_eq!(out.matches("#foo").count(), 1);
    }

    #[test]
    fn tags_inside_fenced_code_preserved() {
        let src = "```rust\nlet x = 1; // #not_a_tag\n```\n\n#real\n";
        let out = format_card(src, &"x".to_string());
        assert!(out.contains("// #not_a_tag"));
        assert!(out.contains("#id(x) #real"));
    }

    #[test]
    fn tags_in_inline_code_preserved() {
        let src = "Use `grep #pattern` for searching.\n\n#search\n";
        let out = format_card(src, &"x".to_string());
        assert!(out.contains("`grep #pattern`"));
        assert!(out.contains("#id(x) #search"));
    }

    #[test]
    fn cloze_args_preserved() {
        let src = "#cloze(auto)\n\nThe capital of **France**.\n";
        let out = format_card(src, &"x".to_string());
        assert!(out.contains("#cloze(auto)"));
    }

    #[test]
    fn idempotent() {
        let src = "#cloze\n\nfoo **bar** #baz\n\n#qux\n";
        let first = format_card(src, &"id1".to_string());
        let second = format_card(&first, &"id2".to_string());
        assert_eq!(first, second, "second formatter pass should be a no-op");
    }

    #[test]
    fn leading_blank_lines_trimmed() {
        let src = "\n\n\nfront\n\n\n\nback\n\n\n";
        let out = format_card(src, &"x".to_string());
        assert_eq!(out, "front\n\nback\n\n#id(x)\n");
    }

    #[test]
    fn trailing_whitespace_stripped() {
        let src = "front   \nback\t\n";
        let out = format_card(src, &"x".to_string());
        assert_eq!(out, "front\nback\n\n#id(x)\n");
    }
}
