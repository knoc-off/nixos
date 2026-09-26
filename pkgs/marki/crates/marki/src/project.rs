//! A loaded marki project: config plus the renderer registry and Lua engine
//! built from it. Shared by the CLI and the MCP server so both drive the
//! same pipeline.

use anyhow::{Context, Result};
use marki_anki::Collection;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use crate::config::Config;
use crate::render::Registry;
use crate::scan::scan_dir_v2;
use crate::scripting::engine::ScriptEngine;
use crate::preview::{self, CardPreview};
use crate::scan::ScannedNote;
use crate::sync::{Outcome, RenderedNote, reconcile, render_note};

pub struct Project {
    pub cfg: Config,
    pub registry: Arc<Registry>,
    pub engine: ScriptEngine,
}

impl Project {
    /// Discover the nearest `.marki/` from `cwd` (or use `config`) and load it
    /// without building anything. Callers may tweak the config before
    /// [`Project::new`].
    pub fn discover_config(cwd: &Path, config: Option<&Path>) -> Result<Config> {
        let disc = Config::discover(cwd, config);
        Config::load(&disc)
    }

    pub fn new(mut cfg: Config) -> Self {
        cfg.cards_dir = cfg.resolved_cards_dir();
        let registry = Arc::new(build_registry(&cfg));
        let engine = build_script_engine(&cfg);
        Self { cfg, registry, engine }
    }

    /// Open the configured Anki collection file, or fail with guidance when
    /// the `collection` key is unset.
    pub fn open_collection(&self) -> Result<Collection> {
        let path = self.cfg.resolved_collection().context(
            "no collection configured; set `collection` in .marki/config.toml or pass --collection",
        )?;
        Collection::open(&path).with_context(|| format!("open collection {}", path.display()))
    }

    /// One scan -> reconcile -> (optionally) write cycle against `col`.
    pub fn cycle(&mut self, col: &mut Collection, dry_run: bool, prune: bool) -> Result<Outcome> {
        let media_dir = self.cfg.media_dir().context("derive media dir from collection")?;
        let media_db = self.cfg.media_db_path().context("derive media db path from collection")?;
        self.run(col, Some((&media_dir, &media_db)), dry_run, prune)
    }

    fn run(
        &mut self,
        col: &mut Collection,
        media: Option<(&Path, &Path)>,
        dry_run: bool,
        prune: bool,
    ) -> Result<Outcome> {
        // Model scripts are cached and reloaded on mtime change (see
        // ScriptEngine::load_model), so no blanket invalidation per cycle.
        let notes = scan_dir_v2(&self.cfg.cards_dir)?;
        reconcile(
            col,
            &self.cfg.cards_dir,
            &notes,
            &mut self.engine,
            &self.registry,
            &render_cache_dir(),
            &self.cfg.resolved_models_dir(),
            media,
            dry_run,
            prune,
        )
    }

    /// Run a real push against a throwaway `VACUUM INTO` copy of the
    /// collection, then check the copy. Nothing on disk changes (media
    /// included). `plan_hash` fingerprints the planned changes so a later
    /// confirmed push can refuse if the cards moved on in between.
    pub fn simulate(&mut self, col: &Collection, prune: bool) -> Result<Simulation> {
        let dir = std::env::temp_dir().join(format!("marki-sim-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir)?;
        let result = (|| {
            let copy = dir.join("collection.anki2");
            col.backup(&copy).context("snapshot collection")?;
            let mut sim = Collection::open(&copy)?;
            let outcome = self.run(&mut sim, None, false, prune)?;
            let problems = sim.check().context("check simulated collection")?;
            Ok(Simulation { plan_hash: plan_hash(&outcome), outcome, problems })
        })();
        let _ = std::fs::remove_dir_all(&dir);
        result
    }

    /// Push only if the plan still hashes to `expected` (from a prior
    /// [`Project::simulate`]); otherwise bail without writing.
    pub fn push_confirmed(
        &mut self,
        col: &mut Collection,
        expected: &str,
        prune: bool,
    ) -> Result<Outcome> {
        let plan = self.cycle(col, true, prune)?;
        let now = plan_hash(&plan);
        anyhow::ensure!(
            now == expected,
            "plan changed since the simulation (hash {now}, expected {expected}); simulate again"
        );
        self.cycle(col, false, prune)
    }
}

pub struct Simulation {
    pub outcome: Outcome,
    /// Problems the post-push check found in the simulated collection.
    pub problems: Vec<String>,
    pub plan_hash: String,
}

impl Simulation {
    /// Safe to confirm: no render errors and a clean collection afterwards.
    pub fn ok(&self) -> bool {
        self.outcome.errors.is_empty() && self.problems.is_empty()
    }
}

/// Fingerprint of a plan: every change plus the errors, so a fixed error
/// also invalidates the confirmation.
fn plan_hash(o: &Outcome) -> String {
    let mut h = blake3::Hasher::new();
    for c in &o.changes {
        let kind: &str = (&c.kind).into();
        h.update(format!("{kind}\0{}\0{}\0{}\0", c.id, c.detail, c.content_hash).as_bytes());
    }
    for e in &o.errors {
        h.update(e.as_bytes());
        h.update(b"\0");
    }
    h.finalize().to_hex()[..16].to_string()
}

/// A note rendered for preview: its cards plus what sync would write.
pub struct Preview {
    pub note: RenderedNote,
    pub cards: Vec<CardPreview>,
}

impl Preview {
    pub fn html_page(&self, title: &str) -> String {
        preview::html_page(title, &self.note.spec.css, &self.cards, &self.note.errors)
    }
}

impl Project {
    /// Render card source (a file on disk or an unsaved draft) exactly as sync
    /// would, without touching a collection. `path` places the note in the
    /// tree for relative media lookups and deck naming.
    pub fn preview(&mut self, path: &Path, source: &str) -> Result<Preview> {
        let sn = ScannedNote {
            path: path.to_path_buf(),
            source: source.to_string(),
            note: crate::note_parser::parse_note(source, path.to_path_buf()),
        };
        let note = render_note(
            &sn,
            &mut self.engine,
            &self.registry,
            &render_cache_dir(),
            &self.cfg.resolved_models_dir(),
        )?;
        let cards = preview::cards(&note);
        Ok(Preview { note, cards })
    }
}

/// Build the external block-renderer registry. The media renderer is
/// registered when at least one media source exists -- the built-in
/// git-tracked `.marki/media/` directory (searched first) plus any
/// `[media_sources]` from config. Otherwise ```media``` blocks fall
/// through to plain code rendering. Likewise, the typst renderer is only
/// registered when a typst binary is configured.
pub fn build_registry(cfg: &Config) -> Registry {
    let mut reg = Registry::new();
    let map_renderer =
        match marki_map::MapRenderer::with_defaults(cfg.map.clone(), cfg.resolved_cards_dir()) {
            Ok(r) => r,
            Err(e) => {
                tracing::warn!("invalid [map] rule in config ({e}); ignoring map defaults");
                marki_map::MapRenderer::new()
            }
        };
    reg.register(Box::new(map_renderer));

    let mut sources: Vec<(String, PathBuf)> = Vec::new();
    let builtin = cfg.builtin_media_dir();
    if builtin.is_dir() {
        sources.push(("media".to_string(), builtin));
    }
    sources.extend(cfg.media_sources.iter().map(|(n, d)| (n.clone(), d.clone())));
    if !sources.is_empty() {
        reg.register(Box::new(marki_media::MediaRenderer::new(sources)));
    }

    if let Some(bin) = &cfg.typst_binary {
        reg.register(Box::new(marki_typst::TypstRenderer::new(bin.clone())));
    }
    reg
}

fn build_script_engine(cfg: &Config) -> ScriptEngine {
    let lib_dir = cfg.resolved_lib_dir();
    let lib = lib_dir.exists().then_some(lib_dir);
    ScriptEngine::new(cfg.resolved_models_dir(), lib)
}

/// Cache directory used by external block renderers:
/// `$XDG_CACHE_HOME/marki/`, falling back to `/tmp/marki-cache`.
pub fn render_cache_dir() -> PathBuf {
    dirs::cache_dir()
        .map(|d| d.join("marki"))
        .unwrap_or_else(|| PathBuf::from("/tmp/marki-cache"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sync::{Change, ChangeKind};

    fn plan(content: &str, errors: &[&str]) -> Outcome {
        Outcome {
            changes: vec![Change {
                kind: ChangeKind::Update,
                id: "a".into(),
                path: None,
                detail: String::new(),
                content_hash: content.into(),
            }],
            errors: errors.iter().map(|e| e.to_string()).collect(),
            ..Default::default()
        }
    }

    #[test]
    fn plan_hash_tracks_content_and_errors() {
        let base = plan_hash(&plan("h1", &[]));
        assert_eq!(base, plan_hash(&plan("h1", &[])));
        assert_ne!(base, plan_hash(&plan("h2", &[])), "edited card must invalidate");
        assert_ne!(base, plan_hash(&plan("h1", &["x"])), "new error must invalidate");
    }
}
