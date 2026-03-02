use pulldown_cmark::{CodeBlockKind, Event, HeadingLevel, Options, Parser, Tag, TagEnd};
use wasm_bindgen::prelude::*;

#[cfg(debug_assertions)]
use web_sys::console;

#[cfg(target_arch = "wasm32")]
use wee_alloc::WeeAlloc;

#[cfg(target_arch = "wasm32")]
#[global_allocator]
static ALLOC: WeeAlloc = WeeAlloc::INIT;

#[wasm_bindgen]
pub fn init_panic_hook() {
    #[cfg(target_arch = "wasm32")]
    console_error_panic_hook::set_once();
}

#[wasm_bindgen]
pub fn version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

fn html_escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

fn heading_tag(level: HeadingLevel) -> &'static str {
    match level {
        HeadingLevel::H1 => "h1",
        HeadingLevel::H2 => "h2",
        HeadingLevel::H3 => "h3",
        HeadingLevel::H4 => "h4",
        HeadingLevel::H5 => "h5",
        HeadingLevel::H6 => "h6",
    }
}

/// Render markdown to HTML.
///
/// Inline HTML is passed through untouched so that Anki's cloze engine
/// (which injects `<span class="cloze">...</span>` before our JS runs)
/// survives the markdown rendering pass.
#[wasm_bindgen]
pub fn render_markdown(markdown: &str) -> String {
    #[cfg(debug_assertions)]
    console::log_1(&format!("[MARKI-WASM] render start, len={}", markdown.len()).into());

    let options = Options::ENABLE_STRIKETHROUGH | Options::ENABLE_TABLES;
    let parser = Parser::new_ext(markdown, options);

    let mut output = String::new();
    let mut in_code_block = false;
    let mut code_buffer = String::new();
    let mut code_lang = String::new();

    for event in parser {
        match event {
            // Inline HTML from Anki's cloze substitution — pass through as-is
            Event::Html(html) | Event::InlineHtml(html) => {
                output.push_str(&html);
            }

            Event::Start(Tag::CodeBlock(CodeBlockKind::Fenced(lang))) => {
                in_code_block = true;
                code_lang = lang.to_string();
                code_buffer.clear();
            }
            Event::Start(Tag::CodeBlock(CodeBlockKind::Indented)) => {
                in_code_block = true;
                code_lang.clear();
                code_buffer.clear();
            }
            Event::End(TagEnd::CodeBlock) => {
                if in_code_block {
                    let escaped = html_escape(&code_buffer);
                    if code_lang.is_empty() {
                        output.push_str(&format!(
                            "<pre class=\"code\"><code>{}</code></pre>",
                            escaped
                        ));
                    } else {
                        output.push_str(&format!(
                            "<pre class=\"code\"><code class=\"language-{}\">{}</code></pre>",
                            code_lang, escaped
                        ));
                    }
                    in_code_block = false;
                }
            }

            Event::Text(text) => {
                if in_code_block {
                    code_buffer.push_str(&text);
                } else {
                    output.push_str(&text);
                }
            }

            Event::SoftBreak | Event::HardBreak => {
                if in_code_block {
                    code_buffer.push('\n');
                } else {
                    output.push_str("<br>");
                }
            }

            Event::Start(Tag::Paragraph) => output.push_str("<p>"),
            Event::End(TagEnd::Paragraph) => output.push_str("</p>"),

            Event::Start(Tag::Heading { level, .. }) => {
                output.push_str(&format!("<{}>", heading_tag(level)));
            }
            Event::End(TagEnd::Heading(level)) => {
                output.push_str(&format!("</{}>", heading_tag(level)));
            }

            Event::Start(Tag::Strong) => output.push_str("<strong>"),
            Event::End(TagEnd::Strong) => output.push_str("</strong>"),
            Event::Start(Tag::Emphasis) => output.push_str("<em>"),
            Event::End(TagEnd::Emphasis) => output.push_str("</em>"),
            Event::Start(Tag::Strikethrough) => output.push_str("<del>"),
            Event::End(TagEnd::Strikethrough) => output.push_str("</del>"),

            Event::Start(Tag::List(None)) => output.push_str("<ul>"),
            Event::Start(Tag::List(Some(start))) => {
                if start == 1 {
                    output.push_str("<ol>");
                } else {
                    output.push_str(&format!("<ol start=\"{}\">", start));
                }
            }
            Event::End(TagEnd::List(false)) => output.push_str("</ul>"),
            Event::End(TagEnd::List(true)) => output.push_str("</ol>"),
            Event::Start(Tag::Item) => output.push_str("<li>"),
            Event::End(TagEnd::Item) => output.push_str("</li>"),

            Event::Start(Tag::BlockQuote(_)) => output.push_str("<blockquote>"),
            Event::End(TagEnd::BlockQuote(_)) => output.push_str("</blockquote>"),

            Event::Start(Tag::Link { dest_url, .. }) => {
                output.push_str(&format!("<a href=\"{}\">", dest_url));
            }
            Event::End(TagEnd::Link) => output.push_str("</a>"),

            Event::Start(Tag::Image {
                dest_url, title, ..
            }) => {
                output.push_str(&format!("<img src=\"{}\"", dest_url));
                if !title.is_empty() {
                    output.push_str(&format!(" title=\"{}\"", title));
                }
                // alt text comes as child Text events, but for <img> we close in End
                output.push_str(" alt=\"");
            }
            Event::End(TagEnd::Image) => output.push_str("\">"),

            // Tables
            Event::Start(Tag::Table(_)) => output.push_str("<table>"),
            Event::End(TagEnd::Table) => output.push_str("</table>"),
            Event::Start(Tag::TableHead) => output.push_str("<thead><tr>"),
            Event::End(TagEnd::TableHead) => output.push_str("</tr></thead>"),
            Event::Start(Tag::TableRow) => output.push_str("<tr>"),
            Event::End(TagEnd::TableRow) => output.push_str("</tr>"),
            Event::Start(Tag::TableCell) => output.push_str("<td>"),
            Event::End(TagEnd::TableCell) => output.push_str("</td>"),

            Event::Code(code) => {
                output.push_str(&format!("<code>{}</code>", html_escape(&code)));
            }

            Event::Rule => output.push_str("<hr>"),

            _ => {}
        }
    }

    // Version watermark for debugging — rendered into every card
    output.push_str(&format!(
        "<div class=\"marki-version\">marki v{}</div>",
        env!("CARGO_PKG_VERSION")
    ));

    #[cfg(debug_assertions)]
    console::log_1(&format!("[MARKI-WASM] render done, len={}", output.len()).into());

    output
}
