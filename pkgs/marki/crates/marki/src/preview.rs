//! Offline card preview: turn a [`RenderedNote`] into the cards Anki would
//! show, without touching a collection.

use marki_anki::notetype::cloze_ords;
use regex::{Captures, Regex};
use std::sync::LazyLock;

use crate::sync::RenderedNote;

#[derive(Debug, Clone, serde::Serialize)]
pub struct CardPreview {
    pub name: String,
    pub ord: u32,
    pub front: String,
    pub back: String,
}

/// Every card the note generates, in ord order. Mirrors the templates marki
/// writes: `{{<Card>Front}}` / `{{<Card>Back}}` per card type (a card with an
/// empty front is not generated), or Anki's stock Cloze with one card per
/// `{{cN::}}` number.
pub fn cards(r: &RenderedNote) -> Vec<CardPreview> {
    if r.spec.cloze {
        let text = r.field("Text");
        let extra = r.field("Back Extra");
        return cloze_ords(text)
            .into_iter()
            .map(|ord| CardPreview {
                name: format!("Cloze {}", ord + 1),
                ord,
                front: cloze(text, ord + 1, false),
                back: format!("{}<br>\n{extra}", cloze(text, ord + 1, true)),
            })
            .collect();
    }
    r.spec
        .card_names
        .iter()
        .enumerate()
        .filter_map(|(ord, name)| {
            let front = r.field(&format!("{name}Front"));
            (!front.trim().is_empty()).then(|| CardPreview {
                name: name.clone(),
                ord: ord as u32,
                front: front.to_string(),
                back: r.field(&format!("{name}Back")).to_string(),
            })
        })
        .collect()
}

// ponytail: no nested clozes ({{c1::a {{c2::b}}}}); Anki supports them, add
// a real parser if cards start using them.
static CLOZE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\{\{c(\d+)::(.*?)(?:::(.*?))?\}\}").unwrap());

/// Anki's cloze filter for card `n`: the active deletion becomes `[...]`
/// (or `[hint]`) on the front and the highlighted answer on the back; every
/// other deletion shows its text.
fn cloze(text: &str, n: u32, reveal: bool) -> String {
    CLOZE
        .replace_all(text, |c: &Captures| {
            let answer = &c[2];
            if c[1].parse::<u32>().ok() != Some(n) {
                return answer.to_string();
            }
            let shown = if reveal {
                answer.to_string()
            } else {
                format!("[{}]", c.get(3).map_or("...", |h| h.as_str()))
            };
            format!("<span class=\"cloze\">{shown}</span>")
        })
        .into_owned()
}

/// A standalone HTML page showing every card front and back with the model
/// CSS applied, the way Anki wraps them (`.card`).
pub fn html_page(title: &str, css: &str, cards: &[CardPreview], errors: &[String]) -> String {
    let mut out = format!(
        "<!doctype html><meta charset=\"utf-8\"><title>{title}</title>\
         <style>{css}\nbody{{margin:0}}.marki-card{{border-bottom:2px dashed #888}}\
         .marki-label{{font:12px monospace;color:#888;padding:4px}}</style>\
         <script>MathJax={{tex:{{inlineMath:[['\\\\(','\\\\)']]}}}}</script>\
         <script async src=\"https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js\"></script>"
    );
    for e in errors {
        out.push_str(&format!("<pre style=\"color:red\">{}</pre>", marki_render::escape_html(e)));
    }
    for c in cards {
        for (side, html) in [("front", &c.front), ("back", &c.back)] {
            out.push_str(&format!(
                "<div class=\"marki-card\"><div class=\"marki-label\">{} ({side})</div>\
                 <div class=\"card\">{html}</div></div>",
                c.name
            ));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cloze_front_back_and_hint() {
        let t = "{{c1::Paris}} and {{c2::Rome::city}}";
        assert_eq!(cloze(t, 1, false), "<span class=\"cloze\">[...]</span> and Rome");
        assert_eq!(cloze(t, 2, false), "Paris and <span class=\"cloze\">[city]</span>");
        assert_eq!(cloze(t, 2, true), "Paris and <span class=\"cloze\">Rome</span>");
    }
}
