//! HTML -> Markdown, as an explicit whitelist of rules.
//!
//! Every rule returns `Option`: `None` means "no rule claims this", and the
//! caller keeps the block opaque. Silence is never an option -- a construct we
//! do not understand must not be quietly flattened into prose.
//!
//! Correctness here is not load-bearing on its own. Whatever this module
//! produces is re-rendered and compared against the original DOM before it is
//! ever shown as editable prose (see `segment`). A wrong rule costs a block its
//! transparency; it cannot cost the user their content.

use crate::dom::{Element, Node, is_ignorable_attr};

/// How much of the Markdown syntax surface to defend against by escaping it.
///
/// `Bare` is not "safe" on its own and is not meant to be: `segment::classify`
/// renders a block with `Bare`, proves it against the original DOM, and falls
/// back to `Full` only when that proof fails. Being wrong here costs a second
/// conversion pass, never a block's transparency -- which is what lets `Bare`
/// leave ordinary prose (`snake_case`, `512 > 256`, `[Branch]`) unescaped
/// instead of paying for characters that were never actually ambiguous in
/// context.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Escaping {
    /// Escape only `\` itself, since an unescaped backslash would change the
    /// meaning of whatever character follows it (including one this pass
    /// left alone on purpose).
    Bare,
    /// Escape every Markdown-active character `escape_markdown` knows about.
    /// Always round-trips; the price is a backslash in front of ordinary
    /// prose that happens to contain one of those characters.
    Full,
}

/// CKEditor admonition classes <-> GitHub alert keywords.
/// Mirrors `ADMONITION_TYPE_MAPPINGS` in Trilium's `markdown_renderer.ts`.
pub const ADMONITIONS: &[(&str, &str)] = &[
    ("note", "NOTE"),
    ("tip", "TIP"),
    ("important", "IMPORTANT"),
    ("caution", "CAUTION"),
    ("warning", "WARNING"),
];

/// Inline elements that may be carried through as raw HTML when no rule can
/// represent them. Trilium's own exporter does the same (`instance.keep([...])`).
///
/// Deliberately a closed list of tags that are inline in HTML's content model.
/// Anything outside it -- in particular an unrecognised block element sitting
/// inside a paragraph -- makes the whole block opaque instead, which is the
/// safe direction to fail in.
const INLINE_VERBATIM: &[&str] = &[
    "a", "abbr", "b", "bdi", "bdo", "big", "br", "cite", "code", "data", "del", "dfn", "em", "i",
    "img", "kbd", "mark", "q", "rp", "rt", "ruby", "s", "samp", "small", "span", "strike",
    "strong", "sub", "sup", "time", "tt", "u", "var", "wbr",
];

pub fn block_to_markdown(node: &Node, mode: Escaping) -> Option<String> {
    match node {
        // Stray whitespace between block elements is layout, not content.
        Node::Text(t) if t.trim().is_empty() => Some(String::new()),
        Node::Text(_) | Node::Comment(_) => None,
        Node::Element(e) => element_to_markdown(e, mode),
    }
}

fn element_to_markdown(e: &Element, mode: Escaping) -> Option<String> {
    match e.name.as_str() {
        "h1" | "h2" | "h3" | "h4" | "h5" | "h6" => {
            let level = e.name[1..].parse::<usize>().ok()?;
            let text = inline_to_markdown(&e.children, mode)?;
            Some(format!("{} {}", "#".repeat(level), trim_layout(&text)))
        }
        "p" => {
            if !e.attrs.is_empty() {
                return None;
            }
            let text = inline_to_markdown(&e.children, mode)?;
            Some(escape_block_start(trim_layout(&text)))
        }
        "hr" => Some("---".into()),
        "ul" if e.has_class("todo-list") => todo_list_to_markdown(e, mode),
        "ul" | "ol" => list_to_markdown(e, mode),
        "pre" => pre_to_markdown(e),
        "blockquote" => {
            if !e.attrs.is_empty() {
                return None;
            }
            let inner = blocks_to_markdown(&e.children, mode)?;
            Some(prefix_lines(&inner, "> "))
        }
        "aside" => admonition_to_markdown(e, mode),
        "figure" => figure_to_markdown(e, mode),
        "table" => table_to_markdown(e, mode),
        _ => None,
    }
}

fn admonition_to_markdown(e: &Element, mode: Escaping) -> Option<String> {
    if !e.has_class("admonition") {
        return None;
    }
    // Exactly `admonition` plus one recognised type keyword; anything else
    // (custom styling classes, unknown types) stays opaque.
    let classes = e.classes();
    if classes.len() != 2 {
        return None;
    }
    let kind = classes.iter().find(|c| **c != "admonition")?;
    let keyword = ADMONITIONS
        .iter()
        .find(|(css, _)| css == kind)
        .map(|(_, kw)| *kw)?;

    let inner = blocks_to_markdown(&e.children, mode)?;
    let body = prefix_lines(&inner, "> ");
    // The blank quote line keeps the marker in its own paragraph; without it
    // lazy continuation would fuse it into the first body paragraph.
    Some(format!("> [!{keyword}]\n>\n{body}"))
}

fn figure_to_markdown(e: &Element, mode: Escaping) -> Option<String> {
    // `<figure class="table"><table>...</table></figure>` is how CKEditor wraps
    // every table. Unwrap to the table and let the table rule decide.
    if e.has_class("table") && e.classes().len() == 1 {
        let table = e
            .children
            .iter()
            .filter_map(Node::element)
            .find(|c| c.name == "table")?;
        // Reject anything else in the figure (captions have no GFM form).
        if e.children.iter().filter(|c| c.element().is_some()).count() != 1 {
            return None;
        }
        return table_to_markdown(table, mode);
    }
    None
}

fn pre_to_markdown(e: &Element) -> Option<String> {
    if !e.attrs.is_empty() {
        return None;
    }
    let code = e
        .children
        .iter()
        .filter_map(Node::element)
        .find(|c| c.name == "code")?;
    if e.children.iter().filter(|c| c.element().is_some()).count() != 1 {
        return None;
    }

    let lang = match code.attr("class") {
        Some(class) => {
            let mut tokens = class.split_whitespace();
            let first = tokens.next()?;
            if tokens.next().is_some() {
                return None;
            }
            first.strip_prefix("language-")?.to_string()
        }
        None => String::new(),
    };
    // Only a `class` attribute is tolerated on the <code>.
    if code.attrs.len() > usize::from(code.attr("class").is_some()) {
        return None;
    }

    let mut text = String::new();
    for child in &code.children {
        text.push_str(child.text()?);
    }

    // A fence must be longer than any backtick run inside it, or that run
    // reads as the closing delimiter. Three is the Markdown minimum; a
    // sample that itself contains a fence-length backtick run used to force
    // this whole block opaque instead of just widening the fence.
    let fence = "`".repeat(code_fence_length(&text));
    // A Markdown fence always contributes a newline before its closing
    // delimiter, which the HTML direction strips back off. Appending one
    // unconditionally -- rather than normalising the existing trailing
    // newlines away -- keeps the pair a true inverse, so a block that really
    // does end in a newline survives instead of failing verification.
    Some(format!("{fence}{lang}\n{text}\n{fence}"))
}

fn code_fence_length(content: &str) -> usize {
    let mut longest = 0usize;
    let mut run = 0usize;
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

fn table_to_markdown(e: &Element, mode: Escaping) -> Option<String> {
    if !e.attrs.is_empty() {
        return None;
    }
    let mut thead = None;
    let mut tbody = None;
    for child in e.children.iter().filter_map(Node::element) {
        match child.name.as_str() {
            "thead" if thead.is_none() => thead = Some(child),
            "tbody" if tbody.is_none() => tbody = Some(child),
            // colgroup/caption/tfoot have no GFM representation.
            _ => return None,
        }
    }
    // GFM tables require a header row. A headerless table can only be
    // represented by inventing a phantom empty header, which would not
    // round-trip, so it stays opaque.
    let thead = thead?;

    let header = single_row(thead)?;
    let headers = row_cells(header, "th", mode)?;
    let width = headers.len();
    if width == 0 {
        return None;
    }

    let mut out = String::new();
    out.push_str(&format!("| {} |\n", headers.join(" | ")));
    out.push_str(&format!("|{}\n", " --- |".repeat(width)));

    if let Some(tbody) = tbody {
        for row in tbody.children.iter().filter_map(Node::element) {
            if row.name != "tr" {
                return None;
            }
            let cells = row_cells(row, "td", mode)?;
            if cells.len() != width {
                return None;
            }
            out.push_str(&format!("| {} |\n", cells.join(" | ")));
        }
    }
    Some(out.trim_end().to_string())
}

fn single_row(section: &Element) -> Option<&Element> {
    let rows: Vec<&Element> = section
        .children
        .iter()
        .filter_map(Node::element)
        .filter(|c| c.name == "tr")
        .collect();
    if rows.len() != 1 || section.children.iter().filter_map(Node::element).count() != 1 {
        return None;
    }
    Some(rows[0])
}

fn row_cells(row: &Element, cell_tag: &str, mode: Escaping) -> Option<Vec<String>> {
    if !row.attrs.is_empty() {
        return None;
    }
    let mut cells = Vec::new();
    for cell in row.children.iter().filter_map(Node::element) {
        if cell.name != cell_tag || !cell.attrs.is_empty() {
            return None;
        }
        let text = inline_to_markdown_ctx(&cell.children, mode, true)?;
        // A literal pipe would break the row structure.
        if text.contains('|') {
            return None;
        }
        cells.push(trim_layout(&text).to_string());
    }
    Some(cells)
}
fn list_to_markdown(e: &Element, mode: Escaping) -> Option<String> {
    if !e.attrs.is_empty() {
        return None;
    }
    let ordered = e.name == "ol";
    let mut items: Vec<String> = Vec::new();
    let mut loose: Option<bool> = None;
    let mut index = 1;

    for child in &e.children {
        match child {
            Node::Text(t) if t.trim().is_empty() => continue,
            Node::Element(li) if li.name == "li" => {
                if li.attrs.keys().any(|k| !is_ignorable_attr(&li.name, k)) {
                    return None;
                }
                let (content, item_loose) = list_item_content(li, mode)?;
                // CommonMark looseness is a property of the whole list: a loose
                // list wraps every item's text in `<p>`. A list that is loose in
                // one item and tight in another has no Markdown form.
                if *loose.get_or_insert(item_loose) != item_loose {
                    return None;
                }

                let marker = if ordered {
                    format!("{index}. ")
                } else {
                    "- ".to_string()
                };
                items.push(render_list_item(&marker, &content));
                index += 1;
            }
            _ => return None,
        }
    }

    if items.is_empty() {
        return None;
    }
    // Blank lines between items are what make the list loose on the way back.
    let separator = if loose.unwrap_or(false) { "\n\n" } else { "\n" };
    Some(items.join(separator))
}

/// Wraps a list item's already-rendered, unindented content with its marker,
/// indenting every continuation line to line up under it.
fn render_list_item(marker: &str, content: &str) -> String {
    let indent = " ".repeat(marker.len());
    let mut lines = content.lines();
    let mut rendered = String::new();
    rendered.push_str(marker);
    rendered.push_str(lines.next().unwrap_or(""));
    for line in lines {
        rendered.push('\n');
        if !line.is_empty() {
            rendered.push_str(&indent);
            rendered.push_str(line);
        }
    }
    rendered
}

/// `<ul class="todo-list">` -> GFM `- [ ]`/`- [x]` bullets.
fn todo_list_to_markdown(e: &Element, mode: Escaping) -> Option<String> {
    if e.attrs.len() != 1 || e.classes() != ["todo-list"] {
        return None;
    }
    let mut items = Vec::new();
    let mut any_loose = false;
    for child in &e.children {
        match child {
            Node::Text(t) if t.trim().is_empty() => continue,
            Node::Element(li) if li.name == "li" => {
                let (content, loose) = todo_item_to_markdown(li, mode)?;
                any_loose |= loose;
                items.push(content);
            }
            _ => return None,
        }
    }
    if items.is_empty() {
        return None;
    }
    let rendered: Vec<String> = items
        .iter()
        .map(|content| render_list_item("- ", content))
        .collect();
    // A continuation paragraph on any item forces the whole GFM list loose
    // (CommonMark looseness is list-wide); everything else stays tight. Unlike
    // a plain list, this never forces a block-vs-inline mismatch: `to_html`
    // collapses a loose-wrapped checkbox item to the exact same shape as a
    // tight one, so items are free to differ on whether they need it.
    let separator = if any_loose { "\n\n" } else { "\n" };
    Some(rendered.join(separator))
}

/// `<li [data-list-item-id]><label class="todo-list__label"><input
/// type="checkbox" [checked="checked"] disabled="disabled"><span
/// class="todo-list__label__description">...</span></label>
/// [<p>continuation</p>]* [<ul|ol>nested</ul|ol>]*</li>` -- the shape
/// CKEditor's two-state todo list emits, plus the multiple-nested-list shape
/// `split_mixed_task_lists` (in `to_html`) produces. Returns the item's
/// rendered content (unindented, marker not yet applied) and whether it
/// needed block-level separation from a continuation paragraph or a second
/// nested list.
fn todo_item_to_markdown(li: &Element, mode: Escaping) -> Option<(String, bool)> {
    // Trilium's multistate plugin stamps a non-ignorable `data-trilium-task-state`
    // on the `<li>` for any state beyond plain checked/unchecked. GFM has no form
    // for it, so it falls through here and the block stays opaque -- rather than
    // being lossily flattened to the nearest of two states.
    if li.attrs.keys().any(|k| !is_ignorable_attr(&li.name, k)) {
        return None;
    }
    let mut children = li
        .children
        .iter()
        .filter(|c| !matches!(c, Node::Text(t) if t.trim().is_empty()));

    let label = children.next()?.element().filter(|e| e.name == "label")?;
    if label.attrs.len() != 1 || label.classes() != ["todo-list__label"] {
        return None;
    }
    if label
        .children
        .iter()
        .any(|c| matches!(c, Node::Text(t) if !t.trim().is_empty()))
    {
        return None;
    }
    let elements: Vec<&Element> = label.children.iter().filter_map(Node::element).collect();
    let [input, span] = elements.as_slice() else {
        return None;
    };

    if input.name != "input" || input.attr("type") != Some("checkbox") {
        return None;
    }
    let allowed_input_attrs: &[&str] = &["type", "disabled", "checked"];
    if input
        .attrs
        .keys()
        .any(|k| !allowed_input_attrs.contains(&k.as_str()))
    {
        return None;
    }
    if input.attr("disabled") != Some("disabled") {
        return None;
    }
    let checked = match input.attr("checked") {
        None => false,
        Some("checked") => true,
        Some(_) => return None,
    };

    if span.name != "span"
        || span.attrs.len() != 1
        || span.classes() != ["todo-list__label__description"]
    {
        return None;
    }

    let marker = if checked { "[x]" } else { "[ ]" };
    let text = trim_layout(&inline_to_markdown(&span.children, mode)?).to_string();
    let mut parts = vec![format!("{marker} {text}")];

    let mut nested_started = false;
    let mut nested_count = 0u32;
    let mut loose = false;
    for child in children {
        let el = child.element()?;
        match el.name.as_str() {
            "p" if !nested_started => {
                if !el.attrs.is_empty() {
                    return None;
                }
                let ptext = trim_layout(&inline_to_markdown(&el.children, mode)?).to_string();
                parts.push(escape_block_start(&ptext));
                loose = true;
            }
            "ul" | "ol" => {
                parts.push(block_to_markdown(child, mode)?);
                nested_started = true;
                nested_count += 1;
            }
            _ => return None,
        }
    }
    // Two lists back to back are indistinguishable from one loose list unless
    // a blank line separates them -- the same ambiguity `split_mixed_task_lists`
    // resolves on the way back to HTML -- so a second nested list forces this
    // item loose too, same as a continuation paragraph does.
    if nested_count > 1 {
        loose = true;
    }

    let content = if loose {
        parts.join("\n\n")
    } else {
        // Tight: a nested list follows on the very next line, no blank line.
        let mut out = parts[0].clone();
        for part in &parts[1..] {
            out.push('\n');
            out.push_str(part);
        }
        out
    };
    Some((content, loose))
}

/// A list item is either inline content followed by nested lists (a tight
/// item), or a sequence of block children (a loose item). The bool reports
/// which, because the enclosing list has to be one or the other throughout.
fn list_item_content(li: &Element, mode: Escaping) -> Option<(String, bool)> {
    if li
        .children
        .iter()
        .filter_map(Node::element)
        .any(|el| el.name == "p")
    {
        return block_list_item(li, mode).map(|content| (content, true));
    }

    let mut inline: Vec<Node> = Vec::new();
    let mut blocks: Vec<&Node> = Vec::new();

    for child in &li.children {
        let is_block =
            matches!(child.element(), Some(el) if matches!(el.name.as_str(), "ul" | "ol"));
        if is_block {
            blocks.push(child);
        } else if blocks.is_empty() {
            inline.push(child.clone());
        } else {
            // Content after a nested list cannot be expressed positionally.
            if child.text().map(|t| t.trim().is_empty()) != Some(true) {
                return None;
            }
        }
    }

    let mut out = trim_layout(&inline_to_markdown(&inline, mode)?).to_string();
    for block in blocks {
        let nested = block_to_markdown(block, mode)?;
        out.push('\n');
        out.push_str(&nested);
    }
    Some((out, false))
}

/// An item whose children are blocks: `<li><p>a</p><p>b</p></li>`. Common in
/// CKEditor output and perfectly representable as a loose list item, which is
/// worth doing -- these accounted for a large share of the lists that were
/// being held opaque.
fn block_list_item(li: &Element, mode: Escaping) -> Option<String> {
    let mut parts = Vec::new();
    for child in &li.children {
        match child {
            Node::Text(t) if t.trim().is_empty() => continue,
            Node::Element(el) => match el.name.as_str() {
                "p" => {
                    if !el.attrs.is_empty() {
                        return None;
                    }
                    let text = trim_layout(&inline_to_markdown(&el.children, mode)?).to_string();
                    parts.push(escape_block_start(&text));
                }
                "ul" | "ol" => parts.push(list_to_markdown(el, mode)?),
                _ => return None,
            },
            _ => return None,
        }
    }
    if parts.is_empty() {
        return None;
    }
    Some(parts.join("\n\n"))
}

pub fn blocks_to_markdown(nodes: &[Node], mode: Escaping) -> Option<String> {
    let mut parts = Vec::new();
    for node in nodes {
        let md = block_to_markdown(node, mode)?;
        if !md.is_empty() {
            parts.push(md);
        }
    }
    Some(parts.join("\n\n"))
}

// ---------------------------------------------------------------------------
// Inline
// ---------------------------------------------------------------------------

pub fn inline_to_markdown(nodes: &[Node], mode: Escaping) -> Option<String> {
    inline_to_markdown_ctx(nodes, mode, false)
}

/// `literal_br`: whether `<br>` must stay `<br>` instead of becoming a
/// literal newline. True only inside a table cell (see `row_cells`), where a
/// newline would end the cell's line and break the table's row-based syntax;
/// propagated through every function on this recursive descent so a `<br>`
/// nested inside e.g. a `<span>` inside a cell still sees it.
fn inline_to_markdown_ctx(nodes: &[Node], mode: Escaping, literal_br: bool) -> Option<String> {
    let mut out = String::new();
    for node in nodes {
        match node {
            Node::Comment(_) => return None,
            Node::Text(t) => out.push_str(&escape_markdown(t, mode)),
            Node::Element(e) => out.push_str(&inline_element(e, mode, literal_br)?),
        }
    }
    Some(out)
}

fn inline_element(e: &Element, mode: Escaping, literal_br: bool) -> Option<String> {
    if let Some(md) = inline_rule(e, mode, literal_br) {
        return Some(md);
    }
    inline_verbatim(e, mode, literal_br)
}

/// Carry an inline element that has no Markdown form through as raw HTML.
///
/// Markdown renderers emit inline HTML unchanged, so this round-trips exactly
/// and the block stays verifiable. The point is to stop one unrepresentable
/// atom from costing a whole paragraph: CKEditor litters prose with
/// `<img width= height=>`, `<span class="math-tex">` and footnote `<sup>`
/// anchors, and without this a single icon made 31 otherwise-plain paragraphs
/// in the reference corpus entirely opaque.
///
/// Only the tags are literal. Children still go through the Markdown escaper,
/// because the text between raw tags is *not* raw -- it is parsed as Markdown
/// on the way back. Emitting `<span class="math-tex">\(62^{12}\)</span>`
/// verbatim silently ate the backslashes.
///
/// Restricted to known inline tags on purpose. An unrecognised *block* element
/// inside a paragraph must not be silently treated as inline -- that block goes
/// opaque instead, which is the safe direction to fail in.
fn inline_verbatim(e: &Element, mode: Escaping, literal_br: bool) -> Option<String> {
    if !INLINE_VERBATIM.contains(&e.name.as_str()) {
        return None;
    }
    let open = open_tag(e);
    // An unescaped pipe in an attribute would be read as a cell separator if
    // this lands inside a table. Text pipes are already escaped downstream.
    if open.contains('|') {
        return None;
    }
    if crate::dom::is_void(&e.name) {
        return Some(open);
    }
    let inner = inline_to_markdown_ctx(&e.children, mode, literal_br)?;
    Some(format!("{open}{inner}</{}>", e.name))
}

fn open_tag(e: &Element) -> String {
    let mut out = String::from("<");
    out.push_str(&e.name);
    for (key, value) in &e.attrs {
        out.push(' ');
        out.push_str(key);
        out.push_str("=\"");
        out.push_str(&value.replace('&', "&amp;").replace('"', "&quot;"));
        out.push('"');
    }
    out.push('>');
    out
}

fn inline_rule(e: &Element, mode: Escaping, literal_br: bool) -> Option<String> {
    match e.name.as_str() {
        "strong" | "b" => wrap(e, "**", mode, literal_br),
        "em" | "i" => wrap(e, "*", mode, literal_br),
        "del" | "s" | "strike" => wrap(e, "~~", mode, literal_br),
        "code" => {
            // CKEditor tags inline code with `spellcheck="false"` (1531 of 1560
            // occurrences in the reference corpus), so that is the canonical
            // form; anything else stays opaque.
            if !matches!(e.attr("spellcheck"), None | Some("false")) || e.attrs.len() > 1 {
                return None;
            }
            let mut text = String::new();
            for child in &e.children {
                text.push_str(child.text()?);
            }
            if text.contains('`') {
                return None;
            }
            Some(format!("`{text}`"))
        }
        "br" => {
            if !e.attrs.is_empty() {
                return None;
            }
            if literal_br {
                // Inside a table cell, a newline would end the cell's line
                // and break the row's syntax; kept as raw inline HTML.
                Some("<br>".into())
            } else {
                // A hard break, not a soft one: the buffer's own convention
                // is that every newline the user types is a `<br>`, so every
                // `<br>` must come back as a real newline, not fold away
                // into a space on the next round trip. `to_html` maps every
                // soft break onto a hard one to match.
                Some("\n".into())
            }
        }
        "a" => anchor(e, mode, literal_br),
        "img" => image(e, mode),
        _ => None,
    }
}

fn wrap(e: &Element, delim: &str, mode: Escaping, literal_br: bool) -> Option<String> {
    if !e.attrs.is_empty() {
        return None;
    }
    let inner = inline_to_markdown_ctx(&e.children, mode, literal_br)?;
    if inner.trim().is_empty() {
        return None;
    }
    Some(format!("{delim}{inner}{delim}"))
}

fn anchor(e: &Element, mode: Escaping, literal_br: bool) -> Option<String> {
    let href = e.attr("href")?;
    match e.attr("class") {
        // CKEditor's internal "reference" link renders the target's title.
        // Markdown link syntax cannot distinguish it from a plain link to the
        // same note, so it gets wiki-link syntax of its own. This is also the
        // form `[[` completion will produce.
        Some("reference-link") => {
            if e.attrs.len() != 2 {
                return None;
            }
            let id = href.strip_prefix("#root/")?;
            if !is_note_ref(id) {
                return None;
            }
            // The title must be literal text: anything with inline markup or
            // Markdown-active characters could not survive being re-parsed.
            let title = match e.children.as_slice() {
                [] => String::new(),
                [Node::Text(t)] => t.clone(),
                _ => return None,
            };
            if !is_plain_title(&title) {
                return None;
            }
            Some(format!("[[{id}|{title}]]"))
        }
        None => {
            if e.attrs.len() != 1 {
                return None;
            }
            let text = inline_to_markdown_ctx(&e.children, mode, literal_br)?;
            if text.contains(']') {
                return None;
            }
            Some(format!("[{text}]({})", escape_url(href)))
        }
        _ => None,
    }
}

/// Trilium note references: alphanumerics plus `_`, `-` and `/` for subpaths.
fn is_note_ref(s: &str) -> bool {
    !s.is_empty()
        && s.chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '/'))
}

/// Wiki-link titles are re-parsed as Markdown, so they may not contain
/// characters a Markdown parser would act on. `_` and `&` are safe: intraword
/// underscores do not open emphasis, and `&` round-trips as an entity.
fn is_plain_title(s: &str) -> bool {
    !s.chars()
        .any(|c| matches!(c, '[' | ']' | '|' | '*' | '`' | '\\' | '<' | '>'))
}

fn image(e: &Element, mode: Escaping) -> Option<String> {
    let src = e.attr("src")?;
    let alt = e.attr("alt").unwrap_or("");
    // Width/height/style/aspect-ratio are extremely common on CKEditor images
    // and have no Markdown form; those images stay opaque.
    let extra = e.attrs.len() - 1 - usize::from(e.attr("alt").is_some());
    if extra > 0 {
        return None;
    }
    Some(format!(
        "![{}]({})",
        escape_markdown(alt, mode),
        escape_url(src)
    ))
}

/// Escape characters that would otherwise be read as Markdown syntax, and
/// collapse source indentation.
///
/// Collapsing matters for correctness, not tidiness. CKEditor wraps and indents
/// its output, so a paragraph can contain a line beginning `- `; left alone,
/// re-parsing that Markdown would turn the tail of the paragraph into a list.
/// HTML already treats those newlines as a single space, so folding them here
/// loses nothing and removes the ambiguity.
///
/// `\` is escaped in every mode: left alone, an unescaped backslash changes
/// the meaning of whatever character follows it, including one `Bare` chose
/// to leave alone on purpose. Everything else is only escaped under `Full` --
/// see `Escaping`.
fn escape_markdown(s: &str, mode: Escaping) -> String {
    let mut out = String::with_capacity(s.len());
    let mut in_ws = false;
    for ch in s.chars() {
        if ch.is_ascii_whitespace() {
            if !in_ws {
                out.push(' ');
                in_ws = true;
            }
            continue;
        }
        in_ws = false;
        let escape = match ch {
            '\\' => true,
            '`' | '*' | '_' | '[' | ']' | '<' | '>' | '|' | '~' => mode == Escaping::Full,
            _ => false,
        };
        if escape {
            out.push('\\');
        }
        out.push(ch);
    }
    out
}

/// Escape a leading character that would make the line a block construct.
///
/// Independent of `Escaping`: `-`/`+`/`#`/`>`/an ordered-list marker at the
/// very start of a line is a block-structure hazard regardless of how the
/// inline text after it was escaped, so this always applies.
///
/// Applied line by line, not just to the string's first character: a `br`
/// now round-trips as a literal newline (see `inline_rule`), so a hazard can
/// start any line a hard break introduced, not only the block's first one.
fn escape_block_start(s: &str) -> String {
    s.lines()
        .map(escape_line_start)
        .collect::<Vec<_>>()
        .join("\n")
}

fn escape_line_start(s: &str) -> String {
    let mut chars = s.char_indices();
    let Some((_, first)) = chars.next() else {
        return s.to_string();
    };
    match first {
        '-' | '+' | '#' | '>' => format!("\\{s}"),
        '0'..='9' => {
            // Ordered-list marker: digits followed by `.` or `)`. The escape
            // must land on the punctuation, not the digit -- CommonMark only
            // honours a backslash before ASCII punctuation, so `\1.` is a
            // literal backslash followed by a still-live list marker. `1\.`
            // is the digit followed by an inert period, which is the intent.
            let digits = s.len() - s.trim_start_matches(|c: char| c.is_ascii_digit()).len();
            let rest = &s[digits..];
            if rest.starts_with(['.', ')']) {
                format!("{}\\{rest}", &s[..digits])
            } else {
                s.to_string()
            }
        }
        _ => s.to_string(),
    }
}

fn escape_url(s: &str) -> String {
    if s.contains(' ') || s.contains('(') || s.contains(')') {
        format!("<{s}>")
    } else {
        s.to_string()
    }
}

/// Trim indentation without touching content.
///
/// `str::trim` removes *Unicode* whitespace, which includes U+00A0. CKEditor
/// emits `&nbsp;` as meaningful content all over the place, and trimming it
/// silently deletes characters the user typed.
fn trim_layout(s: &str) -> &str {
    s.trim_matches(|c: char| c.is_ascii_whitespace())
}

fn prefix_lines(s: &str, prefix: &str) -> String {
    s.lines()
        .map(|line| {
            if line.is_empty() {
                prefix.trim_end().to_string()
            } else {
                format!("{prefix}{line}")
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bare_leaves_ordinary_markdown_active_characters_alone() {
        for ch in ['`', '*', '_', '[', ']', '<', '>', '|', '~'] {
            let s = format!("a{ch}b");
            assert_eq!(escape_markdown(&s, Escaping::Bare), s, "char {ch:?}");
        }
    }

    #[test]
    fn bare_still_escapes_a_literal_backslash() {
        assert_eq!(escape_markdown("a\\b", Escaping::Bare), "a\\\\b");
    }

    #[test]
    fn full_escapes_every_markdown_active_character() {
        assert_eq!(
            escape_markdown("`*_[]<>|~\\", Escaping::Full),
            "\\`\\*\\_\\[\\]\\<\\>\\|\\~\\\\"
        );
    }

    #[test]
    fn escape_block_start_puts_the_backslash_on_the_punctuation_not_the_digit() {
        // `\1.` is a literal backslash followed by a still-live list marker;
        // `1\.` is the digit followed by an inert period.
        assert_eq!(escape_block_start("1. not a list"), "1\\. not a list");
        assert_eq!(
            escape_block_start("2024. what a year"),
            "2024\\. what a year"
        );
        assert_eq!(
            escape_block_start("1) also not a list"),
            "1\\) also not a list"
        );
    }

    #[test]
    fn escape_block_start_leaves_a_bare_number_alone() {
        assert_eq!(escape_block_start("42 things"), "42 things");
    }

    #[test]
    fn escape_block_start_still_escapes_list_and_heading_markers() {
        for (input, expected) in [
            ("- not a list", "\\- not a list"),
            ("+ not a list", "\\+ not a list"),
            ("# not a heading", "\\# not a heading"),
            ("> not a quote", "\\> not a quote"),
        ] {
            assert_eq!(escape_block_start(input), expected);
        }
    }

    #[test]
    fn a_br_in_prose_becomes_a_real_newline() {
        let nodes = crate::dom::parse("<p>a<br>b</p>");
        let md = block_to_markdown(&nodes[0], Escaping::Bare).unwrap();
        assert_eq!(md, "a\nb");
    }

    #[test]
    fn a_br_in_a_table_cell_stays_literal() {
        let nodes = crate::dom::parse(
            "<figure class=\"table\"><table><thead><tr><th>h</th></tr></thead><tbody><tr><td>a<br>b</td></tr></tbody></table></figure>",
        );
        let md = block_to_markdown(&nodes[0], Escaping::Bare).unwrap();
        assert!(
            md.contains("a<br>b"),
            "table cell br should stay literal, got: {md:?}"
        );
    }

    #[test]
    fn a_block_start_hazard_after_an_embedded_break_is_escaped() {
        // The line after a hard break becomes the start of a fresh Markdown
        // line; if it happens to look like a list marker or heading, it must
        // be escaped the same as any other block start.
        let nodes = crate::dom::parse("<p>a<br>- not a list</p>");
        let md = block_to_markdown(&nodes[0], Escaping::Bare).unwrap();
        assert_eq!(md, "a\n\\- not a list");
    }
}
