//! Canonical formatting of card files.
//!
//! Three layers, innermost first:
//!
//!   * [`format_card`] -- pure `String -> String` canonicaliser.
//!   * [`write_back`]  -- applies it to one file, atomically.
//!   * [`run`]         -- the `fmt` command: walks a tree and reports.
//!
//! Pure disk operation -- no network, no Anki, no daemon.
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
//! * Body whitespace is normalised: runs of >=2 blank lines collapse to
//!   a single blank line, leading/trailing blank lines are trimmed,
//!   trailing whitespace on each line is stripped, file ends in a
//!   single `\n`.
//!
//! Idempotent: running the formatter twice on the same file yields
//! byte-identical output.

use anyhow::{Context, Result};
use pulldown_cmark::{CodeBlockKind, Event, Options, Parser, Tag, TagEnd};
use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::ops::Range;
use std::path::{Path, PathBuf};

use crate::id::mint_id;
use crate::scan::scan_dir_v2;
use crate::tag::{NoteId, TAG_REGEX};

/// Format a single `.md` file to the canonical shape.
///
/// If the source already contains an `#id(...)`, that value is kept;
/// otherwise `minted_id` is used. The formatter produces a complete
/// replacement file body.
pub fn format_card(source: &str, minted_id: &NoteId) -> String {
    // Find byte ranges that are "code" -- fenced/indented code blocks
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
    let parser = Parser::new_ext(source, Options::ENABLE_TABLES | Options::ENABLE_STRIKETHROUGH).into_offset_iter();
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
/// - Collapse runs of >=2 blank lines to a single blank line.
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

/// Format `path` in place. If the file has no `#id(...)` yet, use
/// `minted_id`; otherwise keep the existing id.
///
/// Writes via tempfile + atomic rename on the same directory to avoid
/// torn writes. No-op if the file is already in canonical form.
pub fn write_back(path: &Path, minted_id: &NoteId) -> Result<()> {
    let source = fs::read_to_string(path)
        .with_context(|| format!("read {}", path.display()))?;
    let new_source = format_card(&source, minted_id);
    if new_source == source {
        return Ok(());
    }

    let dir = path
        .parent()
        .ok_or_else(|| anyhow::anyhow!("file has no parent: {}", path.display()))?;
    let file_name = path
        .file_name()
        .ok_or_else(|| anyhow::anyhow!("file has no name: {}", path.display()))?;
    let tmp_name = format!(".{}.marki.tmp", file_name.to_string_lossy());
    let tmp_path = dir.join(&tmp_name);

    {
        let mut f = fs::File::create(&tmp_path)
            .with_context(|| format!("create tempfile {}", tmp_path.display()))?;
        f.write_all(new_source.as_bytes())
            .with_context(|| format!("write tempfile {}", tmp_path.display()))?;
        f.sync_all().ok();
    }
    fs::rename(&tmp_path, path)
        .with_context(|| format!("rename {} -> {}", tmp_path.display(), path.display()))?;
    Ok(())
}

#[derive(Default)]
pub struct FmtOutcome {
    /// Files already in canonical form. Untouched on disk.
    pub unchanged: usize,
    /// Files rewritten to canonical form (formatting and/or minting).
    pub formatted: usize,
    /// Files that had a freshly-minted id (subset of `formatted`).
    pub minted: usize,
    /// Files whose parse produced warnings. Non-fatal.
    pub errored: usize,
    /// Accumulated human-readable error / warning lines.
    pub errors: Vec<String>,
}

pub fn run(root: &Path) -> Result<FmtOutcome> {
    let mut outcome = FmtOutcome::default();

    let scanned = scan_dir_v2(root)?;

    // Collect IDs seen before formatting so we can detect duplicates
    // without a second scan pass.
    let mut seen_ids = HashMap::<String, PathBuf>::new();

    for sn in &scanned {
        let had_id = sn.note.id.is_some();
        let minted_id = mint_id();

        // Read the current bytes so we can detect whether the formatter
        // actually changed anything.
        let before = match fs::read_to_string(&sn.path) {
            Ok(s) => s,
            Err(e) => {
                outcome
                    .errors
                    .push(format!("{}: read: {e}", sn.path.display()));
                continue;
            }
        };

        match write_back(&sn.path, &minted_id) {
            Ok(()) => {
                let after = fs::read_to_string(&sn.path).unwrap_or_default();
                if after == before {
                    outcome.unchanged += 1;
                } else {
                    outcome.formatted += 1;
                    if !had_id {
                        outcome.minted += 1;
                    }
                }

                // Record the final ID for duplicate detection.
                // If the file already had one, use that; otherwise use the minted one.
                let final_id = if had_id {
                    sn.note.id.clone().unwrap()
                } else {
                    minted_id
                };
                if let Some(other) = seen_ids.insert(final_id.clone(), sn.path.clone()) {
                    outcome.errors.push(format!(
                        "duplicate #id({final_id}) in {} and {}",
                        other.display(),
                        sn.path.display()
                    ));
                }
            }
            Err(e) => {
                outcome
                    .errors
                    .push(format!("{}: writeback: {e}", sn.path.display()));
            }
        }
    }

    Ok(outcome)
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

    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static N: AtomicU64 = AtomicU64::new(0);

    fn tempdir() -> std::path::PathBuf {
        let base = std::env::temp_dir().join(format!(
            "marki-test-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst),
        ));
        let _ = fs::remove_dir_all(&base);
        fs::create_dir_all(&base).unwrap();
        base
    }

    #[test]
    fn writes_id_line_into_unmarked_file() {
        let tmp = tempdir();
        let p = tmp.join("a.md");
        fs::write(&p, "front\n---\nback\n").unwrap();
        write_back(&p, &"abcd1234".to_string()).unwrap();
        let got = fs::read_to_string(&p).unwrap();
        assert!(got.trim_end().ends_with("#id(abcd1234)"));
    }

    #[test]
    fn idempotent_rewrite() {
        let tmp = tempdir();
        let p = tmp.join("b.md");
        fs::write(&p, "body\n").unwrap();
        write_back(&p, &"x".to_string()).unwrap();
        let first = fs::read_to_string(&p).unwrap();
        write_back(&p, &"x".to_string()).unwrap();
        let second = fs::read_to_string(&p).unwrap();
        assert_eq!(first, second);
    }

    #[test]
    fn collects_tags_to_end() {
        let tmp = tempdir();
        let p = tmp.join("c.md");
        fs::write(&p, "#cloze\n\nbody\n\n#foo\n").unwrap();
        write_back(&p, &"idX".to_string()).unwrap();
        let got = fs::read_to_string(&p).unwrap();
        assert_eq!(got, "body\n\n#id(idX) #cloze #foo\n");
    }
}
