//! Canonical DOM used for parsing, serialising and -- critically -- comparing HTML.
//!
//! The whole safety model of rhizome rests on being able to answer "is this
//! reconstructed HTML equivalent to the original?" for a single block. That
//! question must be answered by a real HTML parser operating on the *document*,
//! never by a Markdown-oriented AST.
//!
//! The reason is empirical. Pandoc's HTML reader silently drops wrappers it has
//! no AST node for: `<aside class="admonition important"><p>hi</p></aside>` and
//! a plain `<p>hi</p>` read to a byte-identical pandoc AST. Any verifier built
//! on that AST reports "no loss" at the exact moment it is destroying an
//! admonition. So we keep our own tree and compare that.

use std::collections::BTreeMap;
use std::fmt::Write as _;

use html5ever::tendril::TendrilSink;
use html5ever::{ParseOpts, QualName, local_name, ns, parse_fragment};
use markup5ever_rcdom::{Handle, NodeData, RcDom};

/// Elements that never have children and serialise without a closing tag.
const VOID: &[&str] = &[
    "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source",
    "track", "wbr",
];

/// Elements whose text content is significant down to the whitespace.
const PRESERVE_WHITESPACE: &[&str] = &["pre", "textarea", "script", "style"];

/// Elements whose children are raw text and must not be entity-escaped.
const RAW_TEXT: &[&str] = &["script", "style"];

/// Elements that generate a block box.
///
/// Whitespace between two of these is layout, not content: HTML collapses it
/// away and no renderer shows it. Knowing which tags these are is what lets
/// `normalize` drop indentation without touching whitespace that separates
/// inline elements, where it *is* content.
const BLOCK_LEVEL: &[&str] = &[
    "address",
    "article",
    "aside",
    "blockquote",
    "body",
    "caption",
    "col",
    "colgroup",
    "dd",
    "details",
    "dialog",
    "div",
    "dl",
    "dt",
    "fieldset",
    "figcaption",
    "figure",
    "footer",
    "form",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6",
    "head",
    "header",
    "hgroup",
    "hr",
    "html",
    "legend",
    "li",
    "main",
    "nav",
    "ol",
    "optgroup",
    "option",
    "p",
    "pre",
    "section",
    "summary",
    "table",
    "tbody",
    "td",
    "tfoot",
    "th",
    "thead",
    "tr",
    "ul",
];

pub fn is_void(name: &str) -> bool {
    VOID.contains(&name)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Node {
    Element(Element),
    Text(String),
    Comment(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Element {
    pub name: String,
    /// Sorted by construction, so attribute order can never affect comparison.
    pub attrs: BTreeMap<String, String>,
    pub children: Vec<Node>,
}

impl Element {
    pub fn attr(&self, key: &str) -> Option<&str> {
        self.attrs.get(key).map(String::as_str)
    }

    /// Whitespace-split `class` tokens, in document order.
    pub fn classes(&self) -> Vec<&str> {
        self.attr("class")
            .map(|c| c.split_whitespace().collect())
            .unwrap_or_default()
    }

    pub fn has_class(&self, want: &str) -> bool {
        self.classes().contains(&want)
    }
}

impl Node {
    pub fn element(&self) -> Option<&Element> {
        match self {
            Node::Element(e) => Some(e),
            _ => None,
        }
    }

    pub fn text(&self) -> Option<&str> {
        match self {
            Node::Text(t) => Some(t),
            _ => None,
        }
    }
}

/// Parse an HTML fragment into the direct children of `<body>`.
///
/// Trilium note content is always a fragment, never a full document.
pub fn parse(html: &str) -> Vec<Node> {
    let dom = parse_fragment(
        RcDom::default(),
        ParseOpts::default(),
        QualName::new(None, ns!(html), local_name!("body")),
        vec![],
        false,
    )
    .one(html);

    // parse_fragment wraps everything in a synthetic <html> element.
    let mut out = Vec::new();
    for child in dom.document.children.borrow().iter() {
        collect_fragment_roots(child, &mut out);
    }
    out
}

fn collect_fragment_roots(handle: &Handle, out: &mut Vec<Node>) {
    if let NodeData::Element { name, .. } = &handle.data
        && name.local.as_ref() == "html"
    {
        for child in handle.children.borrow().iter() {
            if let Some(node) = convert(child) {
                out.push(node);
            }
        }
        return;
    }
    if let Some(node) = convert(handle) {
        out.push(node);
    }
}

fn convert(handle: &Handle) -> Option<Node> {
    match &handle.data {
        NodeData::Text { contents } => Some(Node::Text(contents.borrow().to_string())),
        NodeData::Comment { contents } => Some(Node::Comment(contents.to_string())),
        NodeData::Element { name, attrs, .. } => {
            let mut map = BTreeMap::new();
            for attr in attrs.borrow().iter() {
                map.insert(attr.name.local.to_string(), attr.value.to_string());
            }
            let children = handle
                .children
                .borrow()
                .iter()
                .filter_map(convert)
                .collect();
            Some(Node::Element(Element {
                name: name.local.to_string(),
                attrs: map,
                children,
            }))
        }
        _ => None,
    }
}

// ---------------------------------------------------------------------------
// Serialisation
// ---------------------------------------------------------------------------

pub fn serialize(nodes: &[Node]) -> String {
    let mut out = String::new();
    for node in nodes {
        write_node(node, &mut out, false);
    }
    out
}

fn write_node(node: &Node, out: &mut String, raw_text: bool) {
    match node {
        Node::Text(t) => {
            if raw_text {
                out.push_str(t);
            } else {
                escape_text(t, out);
            }
        }
        Node::Comment(c) => {
            let _ = write!(out, "<!--{c}-->");
        }
        Node::Element(e) => {
            let _ = write!(out, "<{}", e.name);
            for (k, v) in &e.attrs {
                out.push(' ');
                out.push_str(k);
                out.push_str("=\"");
                escape_attr(v, out);
                out.push('"');
            }
            out.push('>');
            if is_void(&e.name) {
                return;
            }
            let child_raw = RAW_TEXT.contains(&e.name.as_str());
            for child in &e.children {
                write_node(child, out, child_raw);
            }
            let _ = write!(out, "</{}>", e.name);
        }
    }
}

fn escape_text(s: &str, out: &mut String) {
    for ch in s.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '\u{a0}' => out.push_str("&nbsp;"),
            c => out.push(c),
        }
    }
}

fn escape_attr(s: &str, out: &mut String) {
    for ch in s.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '"' => out.push_str("&quot;"),
            '\u{a0}' => out.push_str("&nbsp;"),
            c => out.push(c),
        }
    }
}

// ---------------------------------------------------------------------------
// Normalisation + equivalence
// ---------------------------------------------------------------------------

/// Rewrite a tree into a canonical form so that cosmetic differences -- attribute
/// order, indentation, entity spelling, `<b>` vs `<strong>` -- do not register as
/// semantic differences.
///
/// Deliberately conservative: anything not explicitly known to be cosmetic is
/// left alone, so an unknown difference fails the comparison rather than being
/// normalised away. Failing closed keeps the block opaque, which is safe.
pub fn normalize(nodes: &[Node]) -> Vec<Node> {
    let mut out = Vec::new();
    for node in nodes {
        normalize_into(node, false, &mut out);
    }
    collapse_adjacent_text(&mut out);
    trim_edge_whitespace(&mut out);
    drop_layout_whitespace(&mut out);
    out
}

fn normalize_into(node: &Node, preserve_ws: bool, out: &mut Vec<Node>) {
    match node {
        Node::Comment(_) => {}
        Node::Text(t) => {
            let text = if preserve_ws {
                t.clone()
            } else {
                collapse_whitespace(t)
            };
            if !text.is_empty() {
                out.push(Node::Text(text));
            }
        }
        Node::Element(e) => {
            let name = canonical_tag(&e.name);
            let preserve = preserve_ws || PRESERVE_WHITESPACE.contains(&name.as_str());

            let mut children = Vec::new();
            for child in &e.children {
                normalize_into(child, preserve, &mut children);
            }
            collapse_adjacent_text(&mut children);
            if !preserve {
                trim_edge_whitespace(&mut children);
                drop_layout_whitespace(&mut children);
            }

            out.push(Node::Element(Element {
                name,
                attrs: canonical_attrs(e),
                children,
            }));
        }
    }
}

/// Presentational tags CKEditor and Markdown renderers disagree about, mapped
/// onto their semantic equivalents.
fn canonical_tag(name: &str) -> String {
    match name {
        "b" => "strong".into(),
        "i" => "em".into(),
        "strike" | "s" => "del".into(),
        other => other.to_ascii_lowercase(),
    }
}

/// Editor-only bookkeeping CKEditor's list feature stamps on every `<li>`
/// (45.1.1+): a stable id for round-tripping the flat list model within a
/// live editing session, regenerated on load and meaningless outside it.
/// Trilium strips it from every HTML/Markdown export
/// (`export/strip_list_item_ids.ts`); we drop it here for the same reason,
/// so an id alone never keeps a list from being shown as Markdown.
///
/// Scoped to `<li>` specifically -- that is the only element CKEditor's
/// downcast ever sets it on (`registerDowncastStrategy({ scope: 'item' })`),
/// and staying scoped keeps `data-trilium-task-state` (also `<li>`-borne, but
/// with no GFM form) correctly opaque rather than silently widening the
/// whitelist to cover it too.
pub(crate) fn is_ignorable_attr(tag: &str, key: &str) -> bool {
    tag.eq_ignore_ascii_case("li") && key == "data-list-item-id"
}

fn canonical_attrs(e: &Element) -> BTreeMap<String, String> {
    let mut attrs = BTreeMap::new();
    for (k, v) in &e.attrs {
        let key = k.to_ascii_lowercase();
        if is_ignorable_attr(&e.name, &key) {
            continue;
        }
        let value = match key.as_str() {
            // Class order is not semantic; sort so `a b` == `b a`.
            "class" => {
                let mut tokens: Vec<&str> = v.split_whitespace().collect();
                tokens.sort_unstable();
                tokens.join(" ")
            }
            // Inline styles differ only by spacing and trailing semicolons.
            "style" => {
                let mut decls: Vec<String> = v
                    .split(';')
                    .map(str::trim)
                    .filter(|d| !d.is_empty())
                    .map(|d| {
                        let mut parts = d.splitn(2, ':');
                        let prop = parts.next().unwrap_or("").trim().to_ascii_lowercase();
                        let val = parts.next().unwrap_or("").trim().to_string();
                        format!("{prop}:{val}")
                    })
                    .collect();
                decls.sort();
                decls.join(";")
            }
            _ => v.clone(),
        };
        if key == "class" && value.is_empty() {
            continue;
        }
        attrs.insert(key, value);
    }
    attrs
}

/// Collapse runs of ASCII whitespace to a single space.
///
/// U+00A0 is intentionally excluded: `&nbsp;` is meaningful content in CKEditor
/// output, not layout whitespace.
fn collapse_whitespace(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut in_ws = false;
    for ch in s.chars() {
        if ch.is_ascii_whitespace() {
            if !in_ws {
                out.push(' ');
                in_ws = true;
            }
        } else {
            out.push(ch);
            in_ws = false;
        }
    }
    out
}

fn collapse_adjacent_text(nodes: &mut Vec<Node>) {
    let mut i = 0;
    while i + 1 < nodes.len() {
        let merge = matches!((&nodes[i], &nodes[i + 1]), (Node::Text(_), Node::Text(_)));
        if merge {
            let Node::Text(next) = nodes.remove(i + 1) else {
                unreachable!()
            };
            let Node::Text(cur) = &mut nodes[i] else {
                unreachable!()
            };
            cur.push_str(&next);
        } else {
            i += 1;
        }
    }
}

/// Leading/trailing whitespace inside an element is layout, not content.
fn trim_edge_whitespace(nodes: &mut Vec<Node>) {
    if let Some(Node::Text(first)) = nodes.first_mut() {
        let trimmed = first.trim_start_matches(' ').to_string();
        *first = trimmed;
    }
    if let Some(Node::Text(last)) = nodes.last_mut() {
        let trimmed = last.trim_end_matches(' ').to_string();
        *last = trimmed;
    }
    nodes.retain(|n| !matches!(n, Node::Text(t) if t.is_empty()));
}

/// Drop whitespace-only text nodes that only ever separated block boxes.
///
/// Without this the comparison is not really a comparison: it only succeeds
/// when the source happens to be indented exactly the way the Markdown renderer
/// emits. Measured on the Trilium corpus, reformatting the HTML without
/// changing a character of content moved transparency from 93.6% to 82.0% --
/// the same documents, judged differently purely on layout.
///
/// The guard is what makes this safe. Whitespace is only dropped where it
/// touches a block box, so `<ul>\n<li>` loses its newline while
/// `<em>a</em> <em>b</em>` and `<p>text <img> more</p>` keep their spaces --
/// there the whitespace separates words and is content.
///
/// U+00A0 is never touched: CKEditor emits `&nbsp;` as real text, and only
/// ASCII spaces are trimmed here.
fn drop_layout_whitespace(nodes: &mut Vec<Node>) {
    let is_block =
        |n: &Node| matches!(n, Node::Element(e) if BLOCK_LEVEL.contains(&e.name.as_str()));

    for i in 0..nodes.len() {
        let follows_block = i > 0 && is_block(&nodes[i - 1]);
        let precedes_block = i + 1 < nodes.len() && is_block(&nodes[i + 1]);
        if let Node::Text(t) = &mut nodes[i] {
            if follows_block {
                *t = t.trim_start_matches(' ').to_string();
            }
            if precedes_block {
                *t = t.trim_end_matches(' ').to_string();
            }
        }
    }
    nodes.retain(|n| !matches!(n, Node::Text(t) if t.is_empty()));
}

/// True when two HTML fragments carry the same meaning.
///
/// This is the predicate the entire "transparent by proof" model depends on.
pub fn equivalent(a: &str, b: &str) -> bool {
    normalize(&parse(a)) == normalize(&parse(b))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrips_a_simple_paragraph() {
        let nodes = parse("<p>hello</p>");
        assert_eq!(serialize(&nodes), "<p>hello</p>");
    }

    #[test]
    fn attribute_order_is_not_semantic() {
        assert!(equivalent(
            r#"<img src="a.png" width="2">"#,
            r#"<img width="2" src="a.png">"#
        ));
    }

    #[test]
    fn indentation_is_not_semantic() {
        assert!(equivalent("<p>a\n   b</p>", "<p>a b</p>"));
    }

    #[test]
    fn class_order_is_not_semantic() {
        assert!(equivalent(
            r#"<aside class="admonition important">x</aside>"#,
            r#"<aside class="important admonition">x</aside>"#
        ));
    }

    #[test]
    fn presentational_tags_are_canonicalised() {
        assert!(equivalent("<p><b>x</b></p>", "<p><strong>x</strong></p>"));
    }

    /// The regression this whole module exists to prevent. Pandoc's AST cannot
    /// tell these apart; we must.
    #[test]
    fn dropping_an_admonition_wrapper_is_detected() {
        assert!(!equivalent(
            r#"<aside class="admonition important"><p>hello world</p></aside>"#,
            "<p>hello world</p>"
        ));
    }

    #[test]
    fn dropping_a_data_attribute_is_detected() {
        assert!(!equivalent(
            r#"<span data-note-id="abc">x</span>"#,
            "<span>x</span>"
        ));
    }

    /// CKEditor's per-item list bookkeeping is regenerated on load, so it is
    /// not semantic -- unlike an ordinary `data-*` attribute, which is.
    #[test]
    fn list_item_id_is_not_semantic() {
        assert!(equivalent(
            r#"<ul><li data-list-item-id="e0123">x</li></ul>"#,
            "<ul><li>x</li></ul>"
        ));
    }

    /// The same attribute name off an `<li>` is not CKEditor's bookkeeping and
    /// stays semantic -- the ignore rule is scoped to where it actually appears.
    #[test]
    fn list_item_id_off_an_li_is_still_semantic() {
        assert!(!equivalent(
            r#"<p data-list-item-id="e0123">x</p>"#,
            "<p>x</p>"
        ));
    }

    #[test]
    fn whitespace_inside_pre_is_significant() {
        assert!(!equivalent(
            "<pre><code>a\n    b</code></pre>",
            "<pre><code>a b</code></pre>"
        ));
    }

    #[test]
    fn nbsp_is_content_not_whitespace() {
        assert!(!equivalent("<p>a&nbsp;b</p>", "<p>a b</p>"));
    }

    /// Indentation between block boxes is layout. Comparing on it made the
    /// verdict depend on how the source happened to be formatted.
    #[test]
    fn compact_and_pretty_lists_are_equivalent() {
        assert!(equivalent(
            "<ul><li>a</li><li>b</li></ul>",
            "<ul>\n  <li>a</li>\n  <li>b</li>\n</ul>",
        ));
    }

    #[test]
    fn compact_and_pretty_tables_are_equivalent() {
        assert!(equivalent(
            "<table><thead><tr><th>A</th></tr></thead><tbody><tr><td>1</td></tr></tbody></table>",
            "<table>\n  <thead>\n    <tr>\n      <th>A</th>\n    </tr>\n  </thead>\n  <tbody>\n    <tr>\n      <td>1</td>\n    </tr>\n  </tbody>\n</table>",
        ));
    }

    #[test]
    fn compact_and_pretty_nested_lists_are_equivalent() {
        assert!(equivalent(
            "<ul><li>a<ul><li>b</li></ul></li></ul>",
            "<ul>\n  <li>a\n    <ul>\n      <li>b</li>\n    </ul>\n  </li>\n</ul>",
        ));
    }

    /// The other half of the rule. Whitespace separating inline elements is
    /// content, and dropping it would silently join words.
    #[test]
    fn whitespace_between_inline_elements_is_significant() {
        assert!(!equivalent(
            "<p><em>a</em> <em>b</em></p>",
            "<p><em>a</em><em>b</em></p>",
        ));
    }

    #[test]
    fn whitespace_adjacent_to_text_is_significant() {
        assert!(!equivalent(
            "<p>text <img src=\"a.png\"> more</p>",
            "<p>text <img src=\"a.png\">more</p>",
        ));
    }

    /// Whitespace next to a block box never renders either, even when it is
    /// attached to a text node rather than standing alone.
    #[test]
    fn whitespace_beside_a_block_sibling_is_layout() {
        assert!(equivalent(
            "<div>tail <p>a</p></div>",
            "<div>tail<p>a</p></div>",
        ));
    }
}
