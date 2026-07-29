//! Markdown -> HTML, shaped to match CKEditor's conventions.
//!
//! Plain CommonMark output is not enough: Trilium wraps tables in
//! `<figure class="table">`, marks internal links with `class="reference-link"`,
//! and renders admonitions as `<aside class="admonition ...">`. Those are applied
//! as DOM fixups after rendering, so this stays the exact inverse of `to_md`.

use pulldown_cmark::{Options, Parser, html};

use crate::convert::to_md::ADMONITIONS;
use crate::dom::{self, Element, Node};
use std::collections::BTreeMap;

pub fn markdown_to_html(md: &str) -> String {
    markdown_to_html_reporting(md).0
}

/// Same as [`markdown_to_html`], but also reports whether
/// `demote_stray_checkboxes` had to degrade a checkbox to literal text --
/// i.e. whether this Markdown described a todo-list shape CKEditor cannot
/// represent (a mixed bullet/checkbox list, an ordered task list, or anything
/// else `todo_list`/`todo_item` do not recognise). Split out from the plain
/// function so callers that only want the HTML are not forced to look at the
/// bool; the LSP's degradation warning is the one caller that needs it.
pub fn markdown_to_html_reporting(md: &str) -> (String, bool) {
    let mut options = Options::empty();
    options.insert(Options::ENABLE_TABLES);
    options.insert(Options::ENABLE_STRIKETHROUGH);
    options.insert(Options::ENABLE_TASKLISTS);

    let mut raw = String::new();
    html::push_html(&mut raw, Parser::new_ext(md, options));

    let mut nodes = dom::parse(&raw);
    split_mixed_task_lists(&mut nodes);
    fixup_all(&mut nodes, false);
    let degraded = demote_stray_checkboxes(&mut nodes);
    // Markdown renderers end every block with a newline; CKEditor blocks carry
    // no trailing whitespace of their own.
    (dom::serialize(&nodes).trim_end().to_string(), degraded)
}

/// The last line of defence against writing markup CKEditor's schema rejects.
///
/// Every other fixup in this module is safe to fail: bailing out just leaves
/// plainer HTML than CKEditor would have produced. `todo_list` cannot fail that
/// safely -- when it declines a shape (a mixed bullet/checkbox list, an ordered
/// task list, or anything else it does not recognise), what is left behind is
/// pulldown-cmark's raw `<input type="checkbox">`, which is not a construct
/// CKEditor's schema accepts. Left alone, that either gets silently dropped on
/// the next edit in the web UI, or normalised in a way the user did not ask for.
///
/// This walks every `<li>` and turns any checkbox `<input>` still sitting
/// inside one back into the literal `[ ]`/`[x]` text it came from, so the note
/// always holds valid HTML even for shapes the rest of this module cannot
/// represent. A `<label class="todo-list__label">` subtree is left untouched --
/// `todo_list`/`todo_item` already validated it, and its checkbox is meant to
/// be there. Read-back stays honest: `escape_markdown`'s `Escaping::Full` path
/// escapes `[`/`]`, so `- \[x\] done` still proves transparent. Returns whether
/// anything was actually demoted.
fn demote_stray_checkboxes(nodes: &mut [Node]) -> bool {
    let mut degraded = false;
    for node in nodes.iter_mut() {
        if let Node::Element(e) = node {
            if e.name == "li" {
                degraded |= demote_checkboxes_in(&mut e.children);
            } else {
                degraded |= demote_stray_checkboxes(&mut e.children);
            }
        }
    }
    degraded
}

fn demote_checkboxes_in(nodes: &mut Vec<Node>) -> bool {
    let mut degraded = false;
    let mut out = Vec::with_capacity(nodes.len());
    let mut iter = std::mem::take(nodes).into_iter().peekable();
    while let Some(node) = iter.next() {
        match &node {
            Node::Element(e) if e.name == "label" && e.has_class("todo-list__label") => {
                out.push(node);
            }
            Node::Element(e) if e.name == "input" && e.attr("type") == Some("checkbox") => {
                degraded = true;
                let mark = if e.attrs.contains_key("checked") {
                    "[x] "
                } else {
                    "[ ] "
                };
                out.push(Node::Text(mark.to_string()));
                // pulldown-cmark wraps the marker onto its own line; that
                // leading newline is its own layout, not content the source
                // ever had.
                if let Some(Node::Text(t)) = iter.peek_mut() {
                    *t = t.trim_start_matches('\n').to_string();
                }
            }
            Node::Element(e) => {
                let mut inner = e.clone();
                degraded |= demote_checkboxes_in(&mut inner.children);
                out.push(Node::Element(inner));
            }
            _ => out.push(node),
        }
    }
    *nodes = out;
    degraded
}

fn fixup_all(nodes: &mut Vec<Node>, in_pre: bool) {
    for node in nodes.iter_mut() {
        if let Node::Element(e) = node {
            let nested = in_pre || e.name == "pre";
            fixup_all(&mut e.children, nested);
            // Code spans are literal; a `[[...]]` inside one is not a link.
            if !nested && e.name != "code" {
                expand_wikilinks(&mut e.children);
            }
        }
    }
    if !in_pre {
        expand_wikilinks(nodes);
    }
    for node in nodes.iter_mut() {
        if let Some(replacement) = fixup(node, in_pre) {
            *node = replacement;
        }
    }
}

/// Splits every attribute-less `<ul>` whose items mix task-list shape
/// (`<input type="checkbox">`, tight or `Options::ENABLE_TASKLISTS`-wrapped
/// loose) with plain items into consecutive same-flavour `<ul>`s, at every
/// nesting depth. CKEditor has no construct for a single mixed list, but
/// adjacent lists of each flavour represent the same content losslessly, so
/// this runs before `fixup_all` and `todo_list` keeps its simple
/// all-or-nothing contract, converting each pure run independently.
fn split_mixed_task_lists(nodes: &mut Vec<Node>) {
    for node in nodes.iter_mut() {
        if let Node::Element(e) = node {
            split_mixed_task_lists(&mut e.children);
        }
    }
    let mut out = Vec::with_capacity(nodes.len());
    for node in nodes.drain(..) {
        match node {
            Node::Element(e) if e.name == "ul" && e.attrs.is_empty() => out.extend(split_ul(e)),
            other => out.push(other),
        }
    }
    *nodes = out;
}

/// Groups a `<ul>`'s children into consecutive same-flavour runs and rebuilds
/// one `<ul>` per run; whitespace-only text nodes travel with whichever run
/// follows them. When there is only one run (nothing was actually mixed),
/// the original list comes back completely unchanged -- important because a
/// genuinely loose plain list (see `unwrap_solitary_paragraphs`) must not be
/// touched by a pass that exists only to fix an artifact of splitting.
fn split_ul(e: Element) -> Vec<Node> {
    let Element { name, children, .. } = e;
    let mut runs: Vec<(bool, Vec<Node>)> = Vec::new();
    let mut current_flavour: Option<bool> = None;
    let mut pending_whitespace: Vec<Node> = Vec::new();

    for child in children {
        if matches!(&child, Node::Text(t) if t.trim().is_empty()) {
            pending_whitespace.push(child);
            continue;
        }
        let is_task =
            matches!(&child, Node::Element(li) if li.name == "li" && li_starts_with_checkbox(li));
        if current_flavour != Some(is_task) {
            runs.push((is_task, Vec::new()));
            current_flavour = Some(is_task);
        }
        let (_, run) = runs.last_mut().expect("just pushed a run");
        run.append(&mut pending_whitespace);
        run.push(child);
    }
    match runs.last_mut() {
        Some((_, run)) => run.extend(pending_whitespace),
        None => runs.push((false, pending_whitespace)),
    }

    // A single run means nothing was actually mixed -- leave the list
    // completely untouched (no per-item unwrapping either) rather than risk
    // normalising a genuinely loose plain list that had nothing to do with
    // splitting at all.
    if runs.len() <= 1 {
        let children = runs.into_iter().next().map_or(Vec::new(), |(_, c)| c);
        return vec![Node::Element(Element {
            name,
            attrs: BTreeMap::new(),
            children,
        })];
    }

    runs.into_iter()
        .map(|(is_task, run_children)| {
            // Only the plain runs need this: a loose-wrapped task item
            // already collapses to the same output as a tight one in
            // `todo_item`, but a plain `<li>` does not get that treatment,
            // and the `<p>` wrapping here is solely an artifact of the
            // *other* flavour's items being interspersed in the original
            // loose list -- not something CKEditor's own list plugin would
            // ever produce for a single-paragraph item.
            let run_children = if is_task {
                run_children
            } else {
                unwrap_solitary_paragraphs(run_children)
            };
            Node::Element(Element {
                name: name.clone(),
                attrs: BTreeMap::new(),
                children: run_children,
            })
        })
        .collect()
}

/// Unwraps any `<li>` whose entire content is one bare `<p>` back to plain
/// inline content, so a plain run split out of a loose mixed list matches the
/// tight shape a genuinely plain list would have. Items with more than one
/// block child (a real continuation paragraph) are left alone.
fn unwrap_solitary_paragraphs(children: Vec<Node>) -> Vec<Node> {
    children
        .into_iter()
        .map(|child| {
            let Node::Element(mut li) = child else {
                return child;
            };
            if li.name != "li" {
                return Node::Element(li);
            }
            let real: Vec<usize> = li
                .children
                .iter()
                .enumerate()
                .filter(|(_, c)| !matches!(c, Node::Text(t) if t.trim().is_empty()))
                .map(|(i, _)| i)
                .collect();
            if let [only] = real.as_slice()
                && let Node::Element(p) = &li.children[*only]
                && p.name == "p"
                && p.attrs.is_empty()
            {
                li.children = p.children.clone();
            }
            Node::Element(li)
        })
        .collect()
}

/// Whether an `<li>`'s content begins with a checkbox `<input>`, either
/// directly (tight) or wrapped in a `<p>` (loose) -- the shape `split_ul`
/// groups on. `todo_item` fully validates the rest of the item afterwards.
fn li_starts_with_checkbox(li: &Element) -> bool {
    let first = li
        .children
        .iter()
        .find(|c| !matches!(c, Node::Text(t) if t.trim().is_empty()));
    let input = match first {
        Some(Node::Element(e)) if e.name == "input" => Some(e),
        Some(Node::Element(e)) if e.name == "p" && e.attrs.is_empty() => e
            .children
            .first()
            .and_then(Node::element)
            .filter(|i| i.name == "input"),
        _ => None,
    };
    input.is_some_and(|i| i.attr("type") == Some("checkbox"))
}

/// Turn `[[noteId|Title]]` text back into a CKEditor reference link.
fn expand_wikilinks(nodes: &mut Vec<Node>) {
    if !nodes
        .iter()
        .any(|n| matches!(n, Node::Text(t) if t.contains("[[")))
    {
        return;
    }
    let mut out = Vec::with_capacity(nodes.len());
    for node in nodes.drain(..) {
        match node {
            Node::Text(text) => out.extend(split_wikilinks(&text)),
            other => out.push(other),
        }
    }
    *nodes = out;
}

fn split_wikilinks(text: &str) -> Vec<Node> {
    let mut out = Vec::new();
    let mut rest = text;

    while let Some(open) = rest.find("[[") {
        let Some(close_rel) = rest[open + 2..].find("]]") else {
            break;
        };
        let body = &rest[open + 2..open + 2 + close_rel];
        let Some((id, title)) = body.split_once('|') else {
            break;
        };
        if id.is_empty() || id.contains('[') {
            break;
        }

        if !rest[..open].is_empty() {
            out.push(Node::Text(rest[..open].to_string()));
        }
        out.push(Node::Element(Element {
            name: "a".into(),
            attrs: [
                ("class".to_string(), "reference-link".to_string()),
                ("href".to_string(), format!("#root/{id}")),
            ]
            .into_iter()
            .collect(),
            children: if title.is_empty() {
                vec![]
            } else {
                vec![Node::Text(title.to_string())]
            },
        }));
        rest = &rest[open + 2 + close_rel + 2..];
    }

    if !rest.is_empty() {
        out.push(Node::Text(rest.to_string()));
    }
    out
}

fn fixup(node: &Node, in_pre: bool) -> Option<Node> {
    let e = node.element()?;
    match e.name.as_str() {
        "blockquote" => admonition(e),
        "table" => Some(Node::Element(Element {
            name: "figure".into(),
            attrs: [("class".to_string(), "table".to_string())]
                .into_iter()
                .collect(),
            children: vec![Node::Element(e.clone())],
        })),
        "ul" => todo_list(e),
        "img" => normalise_image(e),
        "pre" => trim_code_newline(e),
        // Inline code only: inside <pre> the language class is the marker and
        // CKEditor adds no spellcheck attribute.
        "code" if !in_pre => {
            let mut out = e.clone();
            out.attrs.insert("spellcheck".into(), "false".into());
            Some(Node::Element(out))
        }
        _ => None,
    }
}

/// A `<ul>` where every item is `pulldown-cmark`'s task-list shape
/// (`<li><input type="checkbox" [checked]/>text</li>`, from
/// `Options::ENABLE_TASKLISTS`) becomes CKEditor's two-state todo list. Any
/// item that isn't exactly that shape leaves the whole list untouched: it
/// then fails the round-trip proof in `segment::classify` and the block
/// stays opaque, the same safe fallback every other rule here relies on.
fn todo_list(e: &Element) -> Option<Node> {
    if !e.attrs.is_empty() {
        return None;
    }
    let mut items = Vec::new();
    for child in &e.children {
        match child {
            Node::Text(t) if t.trim().is_empty() => {}
            Node::Element(li) if li.name == "li" => items.push(li),
            _ => return None,
        }
    }
    if items.is_empty() {
        return None;
    }
    let mut children = Vec::with_capacity(items.len());
    for li in items {
        children.push(Node::Element(todo_item(li)?));
    }
    Some(Node::Element(Element {
        name: "ul".into(),
        attrs: [("class".to_string(), "todo-list".to_string())]
            .into_iter()
            .collect(),
        children,
    }))
}

/// `<li><input disabled="" type="checkbox" [checked=""]/>text</li>` (tight) or
/// `<li><p><input .../>text</p></li>` (loose, from `Options::ENABLE_TASKLISTS`
/// wrapping every item's content in `<p>`), optionally followed by continuation
/// `<p>` blocks and/or zero or more nested lists, becomes CKEditor's todo-list
/// item: `<li><label class="todo-list__label"><input type="checkbox"
/// [checked="checked"] disabled="disabled"><span
/// class="todo-list__label__description">text</span></label>
/// [<p>continuation</p>]* [<ul|ol>nested</ul|ol>]*</li>`. More than one
/// nested list only ever arises from `split_mixed_task_lists` splitting this
/// item's own nested list because it mixed flavours too.
fn todo_item(li: &Element) -> Option<Element> {
    if !li.attrs.is_empty() {
        return None;
    }
    let real: Vec<&Node> = li
        .children
        .iter()
        .filter(|c| !matches!(c, Node::Text(t) if t.trim().is_empty()))
        .collect();
    let (first, rest) = real.split_first()?;

    let (input, description, tail): (&Element, Vec<Node>, &[&Node]) = if let Some(p) = first
        .element()
        .filter(|e| e.name == "p" && e.attrs.is_empty())
    {
        let (input, description) = checkbox_and_description(&p.children)?;
        (input, description, rest)
    } else {
        let input = first.element().filter(|e| e.name == "input")?;
        // The tight description runs up to the first block sibling -- a
        // continuation `<p>` or a nested list.
        let desc_end = rest
            .iter()
            .position(|c| matches!(c.element(), Some(e) if e.name == "p" || e.name == "ul"))
            .unwrap_or(rest.len());
        let mut description: Vec<Node> = rest[..desc_end].iter().map(|n| (*n).clone()).collect();
        // pulldown-cmark wraps the marker onto its own line; that leading
        // newline is the parser's own layout, not content the source had.
        if let Some(Node::Text(t)) = description.first_mut() {
            *t = t.trim_start_matches('\n').to_string();
        }
        (input, description, &rest[desc_end..])
    };

    if input.attr("type") != Some("checkbox") {
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
    let checked = input.attrs.contains_key("checked");

    // Whatever is left is zero or more continuation paragraphs, then zero or
    // more nested lists (`split_mixed_task_lists` may have turned one mixed
    // nested list into several pure ones); no paragraph may follow a nested
    // list, and nothing else may appear at all.
    let mut continuations = Vec::new();
    let mut nested = Vec::new();
    for child in tail {
        match child.element() {
            Some(e) if e.name == "p" && nested.is_empty() => continuations.push((*child).clone()),
            Some(e) if e.name == "ul" || e.name == "ol" => nested.push((*child).clone()),
            _ => return None,
        }
    }

    let mut input_attrs = BTreeMap::new();
    input_attrs.insert("type".to_string(), "checkbox".to_string());
    if checked {
        input_attrs.insert("checked".to_string(), "checked".to_string());
    }
    input_attrs.insert("disabled".to_string(), "disabled".to_string());

    let mut children = vec![Node::Element(Element {
        name: "label".into(),
        attrs: [("class".to_string(), "todo-list__label".to_string())]
            .into_iter()
            .collect(),
        children: vec![
            Node::Element(Element {
                name: "input".into(),
                attrs: input_attrs,
                children: vec![],
            }),
            Node::Element(Element {
                name: "span".into(),
                attrs: [(
                    "class".to_string(),
                    "todo-list__label__description".to_string(),
                )]
                .into_iter()
                .collect(),
                children: description,
            }),
        ],
    })];
    children.extend(continuations);
    children.extend(nested);

    Some(Element {
        name: "li".into(),
        attrs: BTreeMap::new(),
        children,
    })
}

/// Splits a loose todo item's `<p>` body -- `<input .../>text` -- into the
/// checkbox and its description, mirroring the tight shape's own split.
fn checkbox_and_description(children: &[Node]) -> Option<(&Element, Vec<Node>)> {
    let (first, rest) = children.split_first()?;
    let input = first.element().filter(|e| e.name == "input")?;
    let mut description: Vec<Node> = rest.to_vec();
    if let Some(Node::Text(t)) = description.first_mut() {
        *t = t.trim_start_matches('\n').to_string();
    }
    Some((input, description))
}

/// `> [!NOTE]` blockquotes become CKEditor admonitions.
fn admonition(e: &Element) -> Option<Node> {
    let mut children = e.children.iter().filter(|n| n.element().is_some());
    let first = children.next()?.element()?;
    if first.name != "p" {
        return None;
    }
    let marker = match first.children.as_slice() {
        [Node::Text(t)] => t.trim().to_string(),
        _ => return None,
    };
    let keyword = marker.strip_prefix("[!")?.strip_suffix(']')?;
    let css = ADMONITIONS
        .iter()
        .find(|(_, kw)| *kw == keyword)
        .map(|(css, _)| *css)?;

    // Everything after the marker paragraph becomes the admonition body.
    let mut body = Vec::new();
    let mut seen_marker = false;
    for child in &e.children {
        if !seen_marker {
            if let Some(el) = child.element()
                && el.name == "p"
            {
                seen_marker = true;
            }
            continue;
        }
        body.push(child.clone());
    }

    Some(Node::Element(Element {
        name: "aside".into(),
        attrs: [("class".to_string(), format!("admonition {css}"))]
            .into_iter()
            .collect(),
        children: body,
    }))
}

/// Internal note links carry a marker class in CKEditor output.
/// Undo two cosmetic things Markdown renderers do to images: an `alt=""`
/// attribute that was never in the source, and percent-encoding of the URL.
///
/// Decoding is safe rather than lossy: a source that genuinely contained `%20`
/// will no longer match after decoding and simply stays opaque.
fn normalise_image(e: &Element) -> Option<Node> {
    let mut out = e.clone();
    let mut changed = false;

    if out.attrs.get("alt").is_some_and(String::is_empty) {
        out.attrs.remove("alt");
        changed = true;
    }
    if let Some(src) = out.attrs.get("src") {
        let decoded = percent_decode(src);
        if &decoded != src {
            out.attrs.insert("src".into(), decoded);
            changed = true;
        }
    }
    changed.then_some(Node::Element(out))
}

fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%'
            && i + 2 < bytes.len()
            && let Some(hi) = (bytes[i + 1] as char).to_digit(16)
            && let Some(lo) = (bytes[i + 2] as char).to_digit(16)
        {
            out.push((hi * 16 + lo) as u8);
            i += 3;
            continue;
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8(out).unwrap_or_else(|_| s.to_string())
}

/// A Markdown fence always emits a trailing newline inside `<code>`; CKEditor's
/// code blocks do not carry one. Strip it back off.
///
/// This is a compensation, not an inverse: a source block that genuinely ends
/// in a newline no longer matches and stays opaque. That is the minority case
/// in practice (13 of 195 in the reference corpus).
fn trim_code_newline(e: &Element) -> Option<Node> {
    let mut out = e.clone();
    let code = out.children.iter_mut().find_map(|c| match c {
        Node::Element(el) if el.name == "code" => Some(el),
        _ => None,
    })?;
    if let Some(Node::Text(text)) = code.children.last_mut()
        && text.ends_with('\n')
    {
        text.pop();
        return Some(Node::Element(out));
    }
    None
}
