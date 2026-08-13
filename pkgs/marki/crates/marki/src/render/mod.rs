//! Block-renderer registry.
//!
//! Wraps a `HashMap<&'static str, Box<dyn Renderer>>` keyed by the block
//! token (e.g. `"map"`). The registry is built once at startup, handed to
//! the parser (which uses [`Registry::external_langs`] to know which fenced
//! blocks to defer) and to the diff engine (which uses [`Registry::dispatch`]
//! to render each deferred block).

use marki_render::{escape_html, Asset, Fragment, Input, RenderCtx, RenderError, Renderer};
use std::collections::HashMap;
use std::path::Path;

use crate::highlighter::highlight_code;
use crate::note::Block;

#[derive(Default)]
pub struct Registry {
    renderers: HashMap<&'static str, Box<dyn Renderer>>,
    /// Snapshot of the keyset as `&'static str` so callers can pass it
    /// to the parser without per-call allocation.
    langs: Vec<&'static str>,
}

impl Registry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a renderer. Panics on duplicate `lang()` to surface
    /// programmer errors at startup.
    pub fn register(&mut self, r: Box<dyn Renderer>) {
        let lang = r.lang();
        assert!(
            !self.renderers.contains_key(lang),
            "duplicate renderer for lang `{lang}`"
        );
        self.renderers.insert(lang, r);
        self.langs.push(lang);
    }

    /// Block tokens to hand to the parser's `external_langs` argument.
    pub fn external_langs(&self) -> &[&'static str] {
        &self.langs
    }

    /// True if some renderer handles `lang`.
    pub fn handles(&self, lang: &str) -> bool {
        self.renderers.contains_key(lang)
    }

    /// Render one block by looking up `lang` in the registry. Returns
    /// `Err(RenderError::Resolve)` if nothing is registered for it --
    /// shouldn't happen if the parser was given the matching
    /// `external_langs`, but the asymmetry is a real failure mode worth
    /// surfacing.
    pub fn dispatch(
        &self,
        lang: &str,
        input: Input<'_>,
        source_path: &Path,
        cache_dir: &Path,
    ) -> Result<Fragment, RenderError> {
        let r = self.renderers.get(lang).ok_or_else(|| {
            RenderError::Resolve(format!("no renderer registered for lang `{lang}`"))
        })?;
        let mut ctx = RenderCtx {
            source_path,
            cache_dir,
        };
        r.render(input, &mut ctx)
    }

    /// Render a run of blocks to HTML -- the single block-to-HTML path
    /// shared by the stock pipeline and the model-script convenience
    /// helpers (`section_html`, `body_html`).
    ///
    /// Code blocks whose lang has a registered renderer are dispatched
    /// through it; `math`/`latex` become MathJax display math; every
    /// other code block is syntax-highlighted; prose blocks are wrapped
    /// in their element. A renderer's `reveal` output is collected
    /// separately so the caller can place it on the card back.
    ///
    /// Routing every path through here is what stops a `map` block from
    /// being dumped as raw TOML when a script asks for a section's HTML.
    pub fn render_blocks(
        &self,
        blocks: &[Block],
        source_path: &Path,
        cache_dir: &Path,
    ) -> RenderedBlocks {
        let mut out = RenderedBlocks::default();

        for block in blocks {
            match block {
                Block::CodeBlock { lang: Some(lang), source } if self.handles(lang) => {
                    match self.dispatch(lang, Input::Raw(source), source_path, cache_dir) {
                        Ok(frag) => {
                            out.html.push_str(&frag.html);
                            if !frag.reveal.is_empty() {
                                if !out.reveal.is_empty() {
                                    out.reveal.push('\n');
                                }
                                out.reveal.push_str(&frag.reveal);
                            }
                            out.assets.extend(frag.assets);
                        }
                        Err(e) => {
                            out.errors.push(format!("{lang} block: {e}"));
                            out.html.push_str(&format!(
                                "<div style=\"color:#a00;border:1px solid #a00;\
                                 padding:0.5em;font-family:monospace;font-size:0.85em;\">\
                                 <strong>{lang} block failed:</strong> {}</div>",
                                escape_html(&e.to_string())
                            ));
                        }
                    }
                }
                Block::CodeBlock { lang: Some(lang), source }
                    if lang == "math" || lang == "latex" =>
                {
                    out.html.push_str("\\[");
                    out.html.push_str(source);
                    out.html.push_str("\\]");
                }
                Block::CodeBlock { lang: Some(lang), source } => {
                    // A leading `_` opts a fence out of external dispatch;
                    // strip it before choosing a highlighter grammar.
                    let effective = lang.strip_prefix('_').unwrap_or(lang);
                    out.html.push_str(&highlight_code(source, effective));
                }
                Block::CodeBlock { lang: None, source } => {
                    out.html.push_str(&highlight_code(source, "txt"));
                }
                Block::ThematicBreak => {}
                Block::Heading { html, level, .. } => {
                    out.html.push_str(&format!("<h{level}>{html}</h{level}>"));
                }
                Block::Paragraph { html, .. } => {
                    out.html.push_str(&format!("<p>{html}</p>"));
                }
                Block::List { html, .. } | Block::Table { html } => {
                    out.html.push_str(html);
                }
                Block::Blockquote { html, .. } => {
                    out.html.push_str(&format!("<blockquote>{html}</blockquote>"));
                }
            }
        }

        out
    }
}

/// HTML produced by [`Registry::render_blocks`], split into the front
/// `html`, the `reveal` extras destined for the card back, the emitted
/// `assets`, and any non-fatal render `errors`.
#[derive(Debug, Default)]
pub struct RenderedBlocks {
    pub html: String,
    pub reveal: String,
    pub assets: Vec<Asset>,
    pub errors: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    struct Plain;
    impl Renderer for Plain {
        fn lang(&self) -> &'static str {
            "plain"
        }
        fn render(
            &self,
            input: Input<'_>,
            _ctx: &mut RenderCtx<'_>,
        ) -> Result<Fragment, RenderError> {
            Ok(Fragment {
                html: format!("<pre>{}</pre>", input.as_source()?.trim_end()),
                ..Default::default()
            })
        }
    }

    fn paths() -> (PathBuf, PathBuf) {
        (PathBuf::from("/tmp/x.md"), PathBuf::from("/tmp/c"))
    }

    #[test]
    fn registry_dispatches() {
        let mut reg = Registry::new();
        reg.register(Box::new(Plain));
        assert_eq!(reg.external_langs(), &["plain"]);
        assert!(reg.handles("plain"));

        let (src, cache) = paths();
        let out = reg
            .dispatch("plain", Input::Raw("hello\n"), &src, &cache)
            .unwrap();
        assert_eq!(out.html, "<pre>hello</pre>");
    }

    #[test]
    fn unknown_lang_resolves_to_error() {
        let reg = Registry::new();
        let (src, cache) = paths();
        let err = reg
            .dispatch("map", Input::Raw(""), &src, &cache)
            .unwrap_err();
        assert!(matches!(err, RenderError::Resolve(_)));
        assert!(!reg.handles("map"));
    }

    #[test]
    fn spec_route_reaches_the_renderer() {
        let mut reg = Registry::new();
        reg.register(Box::new(Plain));

        let mut t = toml::Table::new();
        t.insert("source".into(), toml::Value::String("hi".into()));

        let (src, cache) = paths();
        let out = reg
            .dispatch("plain", Input::Spec(toml::Value::Table(t)), &src, &cache)
            .unwrap();
        assert_eq!(out.html, "<pre>hi</pre>");
    }

    #[test]
    fn render_blocks_dispatches_registered_code_block() {
        // The raw-TOML bug: a code block whose lang has a renderer must
        // be dispatched, not emitted verbatim as <pre><code>...source...>.
        let mut reg = Registry::new();
        reg.register(Box::new(Plain));

        let blocks = vec![Block::CodeBlock {
            lang: Some("plain".into()),
            source: "payload\n".into(),
        }];
        let (src, cache) = paths();
        let out = reg.render_blocks(&blocks, &src, &cache);

        assert_eq!(out.html, "<pre>payload</pre>");
        assert!(!out.html.contains("<code"), "must not fall back to raw code wrapping");
        assert!(out.errors.is_empty());
    }

    #[test]
    fn render_blocks_wraps_prose_and_highlights_unknown_code() {
        let reg = Registry::new();
        let blocks = vec![
            Block::Paragraph { text: "hi".into(), html: "hi".into() },
            Block::CodeBlock { lang: Some("rust".into()), source: "fn x(){}".into() },
        ];
        let (src, cache) = paths();
        let out = reg.render_blocks(&blocks, &src, &cache);

        assert!(out.html.contains("<p>hi</p>"));
        // Unknown-to-the-registry code is syntax-highlighted (inline styles),
        // not dispatched.
        assert!(out.html.contains("style="));
    }
}
