//! Rhai-accessible render context.
//!
//! Provides `ctx.render(lang, source)` which dispatches to the
//! appropriate `Renderer` and returns a Rhai-friendly object
//! with `.front_html`, `.back_html`, and `.assets`.

use marki_render::{Asset, Input};
use rhai::{Dynamic, Engine, ImmutableString};
use std::path::PathBuf;
use std::sync::Arc;

use crate::render::Registry;

/// A rendered block result exposed to Rhai scripts. Wraps the
/// `Fragment` from the block renderer with convenient accessors.
#[derive(Debug, Clone)]
pub struct RhaiRenderedBlock {
    pub front_html: String,
    pub back_html: String,
    pub assets: Vec<String>,
}

/// The context object passed to model scripts as `ctx`. Provides
/// `ctx.render(lang, source)` to invoke block renderers.
#[derive(Clone)]
pub struct RenderContext {
    registry: Arc<Registry>,
    source_path: PathBuf,
    cache_dir: PathBuf,
    /// Assets accumulated during script execution. The caller
    /// collects these after `generate()` returns to push to Anki.
    accumulated_assets: Arc<std::sync::Mutex<Vec<Asset>>>,
}

impl RenderContext {
    pub fn new(
        registry: Arc<Registry>,
        source_path: PathBuf,
        cache_dir: PathBuf,
    ) -> Self {
        Self {
            registry,
            source_path,
            cache_dir,
            accumulated_assets: Arc::new(std::sync::Mutex::new(Vec::new())),
        }
    }

    /// Render a code block by lang. Called from Rhai as `ctx.render("map", source)`.
    pub fn render_block(&mut self, lang: &str, source: &str) -> Result<RhaiRenderedBlock, Box<rhai::EvalAltResult>> {
        let result = self.registry
            .dispatch(lang, Input::Raw(source), &self.source_path, &self.cache_dir)
            .map_err(|e| format!("render({lang}): {e}"))?;

        // Collect assets for later media push.
        let asset_names: Vec<String> = result.assets.iter()
            .map(|a| a.filename.clone())
            .collect();
        {
            let mut acc = self.accumulated_assets.lock().unwrap();
            acc.extend(result.assets);
        }

        Ok(RhaiRenderedBlock {
            front_html: result.html,
            back_html: result.reveal,
            assets: asset_names,
        })
    }

    /// Drain all accumulated assets (called after script execution).
    pub fn take_assets(&self) -> Vec<Asset> {
        let mut acc = self.accumulated_assets.lock().unwrap();
        std::mem::take(&mut *acc)
    }
}

/// Register the RenderContext and RhaiRenderedBlock types into Rhai.
pub fn register_context_types(engine: &mut Engine) {
    // ---- RenderContext ----
    engine.register_type_with_name::<RenderContext>("Context");
    engine.register_fn("render", RenderContext::render_block);

    // ---- RhaiRenderedBlock ----
    engine.register_type_with_name::<RhaiRenderedBlock>("RenderedBlock")
        .register_get("front_html", rendered_front_html)
        .register_get("back_html", rendered_back_html)
        .register_get("assets", rendered_assets);
}

fn rendered_front_html(rb: &mut RhaiRenderedBlock) -> ImmutableString {
    rb.front_html.clone().into()
}

fn rendered_back_html(rb: &mut RhaiRenderedBlock) -> ImmutableString {
    rb.back_html.clone().into()
}

fn rendered_assets(rb: &mut RhaiRenderedBlock) -> rhai::Array {
    rb.assets.iter().map(|a| Dynamic::from(a.clone())).collect()
}

