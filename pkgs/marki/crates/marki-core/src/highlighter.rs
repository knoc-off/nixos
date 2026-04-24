//! Server-side syntax highlighting via `syntect`.
//!
//! Emits self-contained HTML with inline `style="..."` attributes on every
//! token span, so the output needs no external CSS. Cards render correctly
//! on stock Anki `Basic` / `Cloze` note types.

use std::sync::LazyLock;
use syntect::highlighting::{Theme, ThemeSet};
use syntect::html::highlighted_html_for_string;
use syntect::parsing::SyntaxSet;

static SYNTAX_SET: LazyLock<SyntaxSet> = LazyLock::new(SyntaxSet::load_defaults_newlines);

static THEME: LazyLock<Theme> = LazyLock::new(|| {
    let theme_set = ThemeSet::load_defaults();
    theme_set.themes["base16-ocean.dark"].clone()
});

/// Extra inline styles injected into every `<pre>` produced by syntect so
/// that code blocks use a slightly smaller font and wrap instead of
/// overflowing narrow Anki card viewports.
const CODE_BLOCK_EXTRA_STYLE: &str =
    "font-size:0.85em;white-space:pre-wrap;word-wrap:break-word;overflow-wrap:break-word;";

/// Highlight `code` in `language`. Returns a self-contained
/// `<pre style="...">…</pre>` with inline styles on every token span.
///
/// The returned `<pre>` carries additional styles for smaller text and
/// word-wrapping so code doesn't overflow the card boundaries.
pub fn highlight_code(code: &str, language: &str) -> String {
    let syntax = SYNTAX_SET
        .find_syntax_by_token(language)
        .unwrap_or_else(|| SYNTAX_SET.find_syntax_plain_text());

    let raw = highlighted_html_for_string(code, &SYNTAX_SET, syntax, &THEME)
        .unwrap_or_else(|_| {
            format!(
                "<pre style=\"{CODE_BLOCK_EXTRA_STYLE}\">{}</pre>",
                html_escape(code),
            )
        });

    // syntect emits `<pre style="background-color:#...;">`. Inject our
    // extra styles right after the opening `style="` so both the theme
    // background *and* our sizing/wrapping rules apply.
    if let Some(pos) = raw.find("<pre style=\"") {
        let insert_at = pos + "<pre style=\"".len();
        let mut patched = String::with_capacity(raw.len() + CODE_BLOCK_EXTRA_STYLE.len());
        patched.push_str(&raw[..insert_at]);
        patched.push_str(CODE_BLOCK_EXTRA_STYLE);
        patched.push_str(&raw[insert_at..]);
        patched
    } else {
        // Unexpected format — wrap in a styled <div> as fallback.
        format!("<div style=\"{CODE_BLOCK_EXTRA_STYLE}\">{raw}</div>")
    }
}

fn html_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '&' => out.push_str("&amp;"),
            '"' => out.push_str("&quot;"),
            c => out.push(c),
        }
    }
    out
}

