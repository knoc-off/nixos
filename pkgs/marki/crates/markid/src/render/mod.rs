//! External block-renderer registry.
//!
//! Wraps a `HashMap<&'static str, Box<dyn BlockRenderer>>` keyed by the
//! lang token (e.g. `"map"`). The registry is built once at startup,
//! handed to the parser (which uses [`Self::external_langs`] to know
//! which fenced blocks to defer) and to the diff engine (which uses
//! [`Self::dispatch`] to fulfil each [`marki_core::BlockRequest`]).

use marki_core::{BlockError, BlockRenderer, BlockRequest, RenderCtx, RenderedBlock};
use std::collections::HashMap;
use std::path::Path;

#[derive(Default)]
pub struct Registry {
    renderers: HashMap<&'static str, Box<dyn BlockRenderer>>,
    /// Snapshot of the keyset as `&'static str` so callers can pass it
    /// to the parser (`parse_with_externals`) without per-call allocation.
    langs: Vec<&'static str>,
}

impl Registry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a renderer. Panics on duplicate `lang()` to surface
    /// programmer errors at startup.
    pub fn register(&mut self, r: Box<dyn BlockRenderer>) {
        let lang = r.lang();
        assert!(
            !self.renderers.contains_key(lang),
            "duplicate renderer for lang `{lang}`"
        );
        self.renderers.insert(lang, r);
        self.langs.push(lang);
    }

    /// Lang tokens to hand to the parser's `external_langs` argument.
    pub fn external_langs(&self) -> &[&'static str] {
        &self.langs
    }

    /// Number of renderers registered. Mostly for diagnostics.
    pub fn len(&self) -> usize {
        self.renderers.len()
    }

    pub fn is_empty(&self) -> bool {
        self.renderers.is_empty()
    }

    /// Render one block by looking up its lang in the registry. Returns
    /// `Err(BlockError::Resolve)` if no renderer is registered for the
    /// block's lang — shouldn't happen if the parser was given the
    /// matching `external_langs`, but the asymmetry is a real failure
    /// mode worth surfacing.
    pub fn dispatch(
        &self,
        req: &BlockRequest,
        source_path: &Path,
        cache_dir: &Path,
    ) -> Result<RenderedBlock, BlockError> {
        let r = self.renderers.get(req.lang.as_str()).ok_or_else(|| {
            BlockError::Resolve(format!("no renderer registered for lang `{}`", req.lang))
        })?;
        let mut ctx = RenderCtx {
            source_path,
            cache_dir,
        };
        r.render(&req.source, &mut ctx)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use marki_core::{BlockSide, RenderedBlock};
    use std::path::PathBuf;

    struct Plain;
    impl BlockRenderer for Plain {
        fn lang(&self) -> &'static str {
            "plain"
        }
        fn render(
            &self,
            src: &str,
            _ctx: &mut RenderCtx<'_>,
        ) -> Result<RenderedBlock, BlockError> {
            Ok(RenderedBlock {
                front_html: format!("<pre>{}</pre>", src.trim_end()),
                back_html_extras: String::new(),
                assets: Vec::new(),
            })
        }
    }

    #[test]
    fn registry_dispatches() {
        let mut reg = Registry::new();
        reg.register(Box::new(Plain));
        assert_eq!(reg.external_langs(), &["plain"]);

        let req = BlockRequest {
            id: "abc".into(),
            lang: "plain".into(),
            source: "hello\n".into(),
            byte_offset: 0,
            side: BlockSide::Front,
        };
        let out = reg
            .dispatch(&req, &PathBuf::from("/tmp/x.md"), &PathBuf::from("/tmp/c"))
            .unwrap();
        assert_eq!(out.front_html, "<pre>hello</pre>");
    }

    #[test]
    fn unknown_lang_resolves_to_error() {
        let reg = Registry::new();
        let req = BlockRequest {
            id: "abc".into(),
            lang: "map".into(),
            source: String::new(),
            byte_offset: 0,
            side: BlockSide::Front,
        };
        let err = reg
            .dispatch(&req, &PathBuf::from("/tmp/x.md"), &PathBuf::from("/tmp/c"))
            .unwrap_err();
        assert!(matches!(err, BlockError::Resolve(_)));
    }
}
