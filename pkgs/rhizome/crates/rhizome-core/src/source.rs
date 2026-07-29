//! Splitting note HTML into top-level blocks, at the level of the source bytes.
//!
//! Deliberately not done by re-serialising a parsed tree. The single most
//! important property of the write path is that a block the user never touched
//! goes back to Trilium byte-identical -- otherwise merely opening a note
//! rewrites it, every sync diff becomes noise, and the blast radius of a bad
//! conversion is the whole vault instead of the block being edited.
//!
//! So each block keeps the exact substring it came from, and splicing is string
//! concatenation.

/// A top-level span of the note source.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Span {
    /// Whitespace between blocks. Layout only, always preserved verbatim.
    Whitespace(String),
    /// A single top-level node, as it appeared in the source.
    Node(String),
}

impl Span {
    pub fn source(&self) -> &str {
        match self {
            Span::Whitespace(s) | Span::Node(s) => s,
        }
    }
}

/// Split an HTML fragment into top-level spans.
///
/// Returns `None` if the input cannot be scanned unambiguously (unbalanced
/// tags, truncated comment). Callers treat that as "the whole note is one
/// opaque block", which is always safe.
pub fn split_top_level(html: &str) -> Option<Vec<Span>> {
    let bytes = html.as_bytes();
    let mut spans = Vec::new();
    let mut pos = 0;

    while pos < bytes.len() {
        if bytes[pos].is_ascii_whitespace() {
            let start = pos;
            while pos < bytes.len() && bytes[pos].is_ascii_whitespace() {
                pos += 1;
            }
            spans.push(Span::Whitespace(html[start..pos].to_string()));
            continue;
        }

        if bytes[pos] == b'<' && is_markup_start(html, pos) {
            let end = scan_node(html, pos)?;
            spans.push(Span::Node(html[pos..end].to_string()));
            pos = end;
            continue;
        }

        // Bare text at the top level. CKEditor does not normally emit this, but
        // it is valid, so keep it as its own node rather than failing. A `<`
        // that does not begin markup is part of this text.
        let start = pos;
        pos += 1;
        while pos < bytes.len() && !(bytes[pos] == b'<' && is_markup_start(html, pos)) {
            pos += 1;
        }
        let text = &html[start..pos];
        if text.trim().is_empty() {
            spans.push(Span::Whitespace(text.to_string()));
        } else {
            spans.push(Span::Node(text.to_string()));
        }
    }

    Some(spans)
}

/// Whether the `<` at `pos` begins markup rather than literal text.
///
/// HTML only treats `<` as markup before an ASCII letter, `/`, `!` or `?`;
/// everywhere else it is data. Trilium notes rely on this -- a code sample
/// containing `for (i = 0; i < len; i++)` is real, and reading its `<` as a
/// tag made the scanner give up and mark the whole note unparseable.
fn is_markup_start(html: &str, pos: usize) -> bool {
    let rest = &html.as_bytes()[pos + 1..];
    match rest.first() {
        Some(b'!') | Some(b'?') => true,
        Some(b'/') => rest.get(1).is_some_and(u8::is_ascii_alphabetic),
        Some(c) => c.is_ascii_alphabetic(),
        None => false,
    }
}

/// Given `<` at `start`, return the byte index just past this node.
fn scan_node(html: &str, start: usize) -> Option<usize> {
    let bytes = html.as_bytes();

    if html[start..].starts_with("<!--") {
        return html[start..].find("-->").map(|i| start + i + 3);
    }
    if html[start..].starts_with("<!") || html[start..].starts_with("<?") {
        return html[start..].find('>').map(|i| start + i + 1);
    }

    let name = tag_name(html, start + 1)?;
    let open_end = scan_tag_end(html, start)?;

    if bytes[open_end - 2] == b'/' || crate::dom::is_void(&name) {
        return Some(open_end);
    }

    let mut depth = 1usize;
    let mut pos = open_end;
    while pos < bytes.len() {
        if bytes[pos] != b'<' || !is_markup_start(html, pos) {
            pos += 1;
            continue;
        }
        if html[pos..].starts_with("<!--") {
            pos = html[pos..].find("-->").map(|i| pos + i + 3)?;
            continue;
        }
        if html[pos..].starts_with("<!") || html[pos..].starts_with("<?") {
            pos = html[pos..].find('>').map(|i| pos + i + 1)?;
            continue;
        }
        if html[pos..].starts_with("</") {
            let close = tag_name(html, pos + 2)?;
            let end = html[pos..].find('>').map(|i| pos + i + 1)?;
            if close == name {
                depth -= 1;
                if depth == 0 {
                    return Some(end);
                }
            }
            pos = end;
            continue;
        }

        let inner = tag_name(html, pos + 1)?;
        let end = scan_tag_end(html, pos)?;
        if inner == name && bytes[end - 2] != b'/' && !crate::dom::is_void(&inner) {
            depth += 1;
        }
        pos = end;
    }
    None
}

/// Read an ASCII tag name starting at `pos`.
fn tag_name(html: &str, pos: usize) -> Option<String> {
    let bytes = html.as_bytes();
    let mut end = pos;
    while end < bytes.len() && (bytes[end].is_ascii_alphanumeric() || bytes[end] == b'-') {
        end += 1;
    }
    if end == pos {
        return None;
    }
    Some(html[pos..end].to_ascii_lowercase())
}

/// Find the index just past the `>` closing a tag, honouring quoted attribute
/// values so that `<img alt="a > b">` scans correctly.
fn scan_tag_end(html: &str, start: usize) -> Option<usize> {
    let bytes = html.as_bytes();
    let mut pos = start + 1;
    let mut quote: Option<u8> = None;

    while pos < bytes.len() {
        let byte = bytes[pos];
        match quote {
            Some(q) if byte == q => quote = None,
            Some(_) => {}
            None if byte == b'"' || byte == b'\'' => quote = Some(byte),
            None if byte == b'>' => return Some(pos + 1),
            None => {}
        }
        pos += 1;
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn nodes(html: &str) -> Vec<String> {
        split_top_level(html)
            .unwrap()
            .into_iter()
            .filter_map(|s| match s {
                Span::Node(n) => Some(n),
                Span::Whitespace(_) => None,
            })
            .collect()
    }

    #[test]
    fn splits_sibling_blocks() {
        assert_eq!(nodes("<p>a</p><p>b</p>"), vec!["<p>a</p>", "<p>b</p>"]);
    }

    #[test]
    fn preserves_source_exactly() {
        let html = "<p  class='x'   >a</p>";
        assert_eq!(nodes(html), vec![html]);
    }

    #[test]
    fn handles_nested_same_tag() {
        let html = "<div><div>inner</div></div>";
        assert_eq!(nodes(html), vec![html]);
    }

    #[test]
    fn handles_void_elements() {
        assert_eq!(
            nodes("<img src=a.png><p>x</p>"),
            vec!["<img src=a.png>", "<p>x</p>"]
        );
    }

    #[test]
    fn handles_gt_inside_attribute() {
        let html = r#"<img alt="a > b">"#;
        assert_eq!(nodes(html), vec![html]);
    }

    #[test]
    fn reassembly_is_byte_identical() {
        let html = "<h2>Title</h2>\n<p>Body\n  continues</p>\n<aside class=\"admonition note\">\n  <p>x</p>\n</aside>";
        let joined: String = split_top_level(html)
            .unwrap()
            .iter()
            .map(Span::source)
            .collect();
        assert_eq!(joined, html);
    }

    /// An implicitly-closed tag is not an error -- the scanner treats the
    /// explicit `</div>` as closing the outer element, matching how a browser
    /// would. Only genuinely truncated input is rejected.
    #[test]
    fn tolerates_implicit_closing() {
        assert_eq!(nodes("<div><p>oops</div>"), vec!["<div><p>oops</div>"]);
    }

    /// A `<` that does not begin a tag is data. Trilium notes contain code
    /// samples, and reading the `<` in `i < len` as markup made the scanner
    /// give up and mark the entire note unparseable.
    #[test]
    fn bare_less_than_in_text_is_not_markup() {
        let html = "<pre>for (i = 0; i < len; i++) {}</pre>";
        assert_eq!(nodes(html), vec![html]);
    }

    #[test]
    fn bare_less_than_at_top_level_is_text() {
        let spans = split_top_level("a < b <p>x</p>").unwrap();
        assert_eq!(spans.last().unwrap().source(), "<p>x</p>");
        assert_eq!(
            spans.iter().map(Span::source).collect::<String>(),
            "a < b <p>x</p>"
        );
    }

    #[test]
    fn rejects_truncated_input() {
        assert!(split_top_level("<div><p>oops").is_none());
    }
}
