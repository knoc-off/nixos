use pulldown_cmark::{CodeBlockKind, Event, HeadingLevel, Parser, Tag, TagEnd};
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
pub struct MarkdownRenderer {
    is_cloze: bool,
    cloze_counter: i32,
}

#[wasm_bindgen]
impl MarkdownRenderer {
    #[wasm_bindgen(constructor)]
    pub fn new(is_cloze: bool) -> MarkdownRenderer {
        MarkdownRenderer {
            is_cloze,
            cloze_counter: 0,
        }
    }

    #[wasm_bindgen]
    pub fn render(&mut self, markdown: &str) -> String {
        #[cfg(debug_assertions)]
        {
            console::log_1(&format!("[MARKI-WASM DEBUG] Starting render - is_cloze: {}, markdown length: {}",
                self.is_cloze, markdown.len()).into());
            console::log_1(&format!("[MARKI-WASM DEBUG] Input markdown:\n{}", markdown).into());
        }

        let mut output = String::new();
        let mut in_code_block = false;
        let mut code_buffer = String::new();
        let mut code_lang = String::new();

        let parser = Parser::new(markdown);

        for event in parser {
            #[cfg(debug_assertions)]
            console::log_1(&format!("[MARKI-WASM DEBUG] Processing event: {:?}", event).into());

            match event {
                Event::Start(Tag::Strong) => {
                    if self.is_cloze {
                        self.cloze_counter += 1;
                        output.push_str(&format!("{{{{c{}::", self.cloze_counter));
                    } else {
                        output.push_str("<strong>");
                    }
                }
                Event::End(TagEnd::Strong) => {
                    if self.is_cloze {
                        output.push_str("}}");
                    } else {
                        output.push_str("</strong>");
                    }
                }
                Event::Start(Tag::Emphasis) => {
                    if self.is_cloze {
                        self.cloze_counter += 1;
                        output.push_str(&format!("{{{{c{}::", self.cloze_counter));
                    } else {
                        output.push_str("<em>");
                    }
                }
                Event::End(TagEnd::Emphasis) => {
                    if self.is_cloze {
                        output.push_str("}}");
                    } else {
                        output.push_str("</em>");
                    }
                }
                Event::Start(Tag::CodeBlock(CodeBlockKind::Fenced(lang))) => {
                    in_code_block = true;
                    code_lang = lang.to_string();
                    code_buffer.clear();
                }
                Event::End(TagEnd::CodeBlock) => {
                    if in_code_block {
                        let escaped = html_escape(&code_buffer);
                        output.push_str(&format!(
                            "<pre class=\"code\"><code class=\"language-{}\">{}</code></pre>",
                            code_lang, escaped
                        ));
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
                    let tag = match level {
                        HeadingLevel::H1 => "h1",
                        HeadingLevel::H2 => "h2",
                        HeadingLevel::H3 => "h3",
                        HeadingLevel::H4 => "h4",
                        HeadingLevel::H5 => "h5",
                        HeadingLevel::H6 => "h6",
                    };
                    output.push_str(&format!("<{}>", tag));
                }
                Event::End(TagEnd::Heading(level)) => {
                    let tag = match level {
                        HeadingLevel::H1 => "h1",
                        HeadingLevel::H2 => "h2",
                        HeadingLevel::H3 => "h3",
                        HeadingLevel::H4 => "h4",
                        HeadingLevel::H5 => "h5",
                        HeadingLevel::H6 => "h6",
                    };
                    output.push_str(&format!("</{}>", tag));
                }
                Event::Start(Tag::List(None)) => output.push_str("<ul>"),
                Event::Start(Tag::List(Some(_))) => output.push_str("<ol>"),
                Event::End(TagEnd::List(false)) => output.push_str("</ul>"),
                Event::End(TagEnd::List(true)) => output.push_str("</ol>"),
                Event::Start(Tag::Item) => output.push_str("<li>"),
                Event::End(TagEnd::Item) => output.push_str("</li>"),
                Event::Start(Tag::BlockQuote(_)) => output.push_str("<blockquote>"),
                Event::End(TagEnd::BlockQuote(_)) => output.push_str("</blockquote>"),
                Event::Start(Tag::Link { dest_url, .. }) => {
                    output.push_str(&format!("<a href=\"{}\">", dest_url))
                }
                Event::End(TagEnd::Link) => output.push_str("</a>"),
                Event::Code(code) => output.push_str(&format!("<code>{}</code>", code)),
                Event::Rule => {} // Skip horizontal rules (used as front/back divider)
                _ => {}
            }
        }

        #[cfg(debug_assertions)]
        {
            console::log_1(&format!("[MARKI-WASM DEBUG] Render complete - output length: {}", output.len()).into());
            console::log_1(&format!("[MARKI-WASM DEBUG] Output HTML:\n{}", output).into());
        }

        output
    }
}

fn html_escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

// Simple render function for convenience
#[wasm_bindgen]
pub fn render_markdown(markdown: &str, is_cloze: bool) -> String {
    let mut renderer = MarkdownRenderer::new(is_cloze);
    renderer.render(markdown)
}
