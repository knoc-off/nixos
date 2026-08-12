//! Block-renderer registry.
//!
//! Wraps a `HashMap<&'static str, Box<dyn Renderer>>` keyed by the block
//! token (e.g. `"map"`). The registry is built once at startup, handed to
//! the parser (which uses [`Registry::external_langs`] to know which fenced
//! blocks to defer) and to the diff engine (which uses [`Registry::dispatch`]
//! to render each deferred block).

use marki_render::{Fragment, Input, RenderCtx, RenderError, Renderer};
use std::collections::HashMap;
use std::path::Path;

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
}
