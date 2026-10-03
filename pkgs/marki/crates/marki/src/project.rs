//! A loaded marki project: config plus the renderer registry and Lua engine
//! built from it. Shared by the CLI and the MCP server so both drive the
//! same pipeline.
//!
//! marki owns a local collection that is a sync client of the `[sync]`
//! server, like any other Anki device. Reads use the local copy as last
//! synced; [`Project::simulate`] and [`Project::push`] pull first, and push
//! syncs its writes back up (see `sync::client`).

use anyhow::{Context, Result, ensure};
use marki_anki::Collection;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use crate::config::Config;
use crate::preview::{self, CardPreview};
use crate::render::Registry;
use crate::scan::ScannedNote;
use crate::scan::scan_dir_v2;
use crate::scripting::context::NoteIndex;
use crate::scripting::engine::ScriptEngine;
use crate::sync::client::{self, Mode};
use crate::sync::{Outcome, RenderedNote, media, reconcile, render_note};

pub struct Project {
    pub cfg: Config,
    pub registry: Arc<Registry>,
    pub engine: ScriptEngine,
}

/// Where the collection and its media folder live.
pub struct Store {
    pub collection: PathBuf,
    pub media_dir: PathBuf,
}

/// The local collection for reading (see [`Project::read_view`]).
pub struct View {
    pub col: Collection,
}

/// Outcome of one push step.
#[derive(Debug, Clone, serde::Serialize)]
pub struct Step {
    pub name: &'static str,
    /// `ok`, `error` or `skipped`.
    pub status: &'static str,
    pub detail: String,
}

impl Step {
    pub fn ok(name: &'static str, detail: impl Into<String>) -> Self {
        Self { name, status: "ok", detail: detail.into() }
    }
    pub fn error(name: &'static str, e: &anyhow::Error) -> Self {
        Self { name, status: "error", detail: format!("{e:#}") }
    }
    pub fn skipped(name: &'static str, why: impl Into<String>) -> Self {
        Self { name, status: "skipped", detail: why.into() }
    }
    fn is_ok(&self) -> bool {
        self.status == "ok"
    }
}

/// A push that ran: the plan it executed and what each step did.
pub struct Pushed {
    pub outcome: Outcome,
    pub plan_hash: String,
    pub steps: Vec<Step>,
    /// `col.scm` moved during the write: every client must full-sync.
    /// Measured, not predicted from the plan.
    pub schema_changed: bool,
}

impl Pushed {
    /// No step failed or was skipped because of a failure, and no note
    /// failed to render. A step skipped by configuration (no `[sync]`)
    /// is fine.
    pub fn ok(&self) -> bool {
        self.steps.iter().all(|s| s.status != "error")
            && self.collection_written()
            && self.outcome.errors.is_empty()
    }
    /// The collection was written (so the cards repo should be committed).
    pub fn collection_written(&self) -> bool {
        self.steps.iter().any(|s| s.name == "collection" && s.is_ok())
    }
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

    pub fn store(&self) -> Result<Store> {
        let collection = self
            .cfg
            .resolved_collection()
            .context("no collection path: set `collection` in .marki/config.toml (no state dir found)")?;
        Ok(Store { media_dir: media_dir_for(&collection), collection })
    }

    /// Open the local collection (for writing too).
    pub fn open_collection(&self) -> Result<Collection> {
        let path = self.store()?.collection;
        Collection::open(&path).with_context(|| format!("open collection {}", path.display()))
    }

    /// The local collection as of its last sync. Never contacts the server.
    pub fn read_view(&self) -> Result<View> {
        Ok(View { col: self.open_collection()? })
    }

    /// Bring the local copy up to date with the server, if one is
    /// configured. `None` without `[sync]`.
    pub fn pull(&self) -> Result<Option<String>> {
        let Some(sync) = &self.cfg.sync else { return Ok(None) };
        let s = self.store()?;
        client::sync(sync, &s.collection, Mode::Pull).map(Some)
    }

    /// Send local writes to the server. `allow_upload`: this process just
    /// changed the schema, so a full upload is expected (see `sync.py`).
    pub fn sync_up(&self, allow_upload: bool) -> Result<Option<String>> {
        let Some(sync) = &self.cfg.sync else { return Ok(None) };
        let s = self.store()?;
        client::sync(sync, &s.collection, Mode::Push { allow_upload }).map(Some)
    }

    /// One scan -> reconcile -> (optionally) write cycle against `col`.
    /// Collection only; media is the caller's (see [`Project::push`]).
    fn cycle(&mut self, col: &mut Collection, dry_run: bool, prune: bool) -> Result<Outcome> {
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
            dry_run,
            prune,
        )
    }

    /// The full plan against `col` and the media folder: models, notes,
    /// orphans, then media files that are missing or different, then
    /// (with `prune`) unused renderer files to delete. Without `prune`
    /// those are only counted in `media_orphans`. A cycle with render
    /// errors never plans deletions: a failed card's files look unused.
    fn plan_on(&mut self, col: &mut Collection, prune: bool) -> Result<Outcome> {
        let mut o = self.cycle(col, true, prune)?;
        let media_dir = self.store()?.media_dir;
        o.changes.extend(media::plan(&o.assets, &media_dir));
        if o.errors.is_empty() {
            let unused = media::unused(&o.media_refs, &media_dir)?;
            if prune {
                o.changes.extend(media::delete_changes(&unused));
            } else {
                o.media_orphans = unused.len();
            }
        }
        Ok(o)
    }

    /// What a push would change against the local copy as last synced
    /// (offline, no simulation), plus seconds since that sync (`None`:
    /// never synced).
    pub fn plan(&mut self, prune: bool) -> Result<(Outcome, Option<i64>)> {
        let mut v = self.read_view()?;
        let ls = v.col.last_sync_millis()?;
        let age = (ls > 0).then(|| {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_or(0, |d| d.as_millis() as i64);
            (now - ls).max(0) / 1000
        });
        Ok((self.plan_on(&mut v.col, prune)?, age))
    }

    /// Pull, then run a real push against a throwaway copy of the
    /// collection and check the copy. Nothing is uploaded; media files are
    /// not written (the plan already compared them). Also checks that the
    /// media folder is writable. `plan_hash` fingerprints the plan so a
    /// later confirmed push can refuse if anything moved on.
    pub fn simulate(&mut self, prune: bool) -> Result<Simulation> {
        let s = self.store()?;
        self.pull().context("pull")?;
        let mut view = self.read_view()?;
        let plan = self.plan_on(&mut view.col, prune)?;
        let tmp = TempDir::new("sim")?;
        let col_copy = tmp.path().join("collection.anki2");
        view.col.backup(&col_copy).context("snapshot collection")?;
        drop(view);

        let mut problems = preflight(&s, &plan);
        let mut sim = Collection::open(&col_copy)?;
        let applied = self.cycle(&mut sim, false, prune)?;
        problems.extend(applied.errors.iter().filter(|e| !plan.errors.contains(e)).cloned());
        problems.extend(sim.check().context("check simulated collection")?);
        Ok(Simulation { plan_hash: plan_hash(&plan), outcome: plan, problems })
    }

    /// Push the current cards: pull, re-plan against the fresh copy,
    /// write media, then the collection (stopping at the first failure),
    /// then sync the result up. With `expected`, refuse unless the plan
    /// still hashes to it (from [`Project::simulate`]). Returns `Err` only
    /// when nothing was written. A failed final sync leaves the writes
    /// pending in the local copy (`usn = -1`); the next push sends them.
    pub fn push(&mut self, expected: Option<&str>, prune: bool) -> Result<Pushed> {
        let s = self.store()?;
        let mut steps = Vec::new();
        match self.pull().context("pull")? {
            Some(action) => steps.push(Step::ok("pull", action)),
            None => steps.push(Step::skipped("pull", "no [sync] configured")),
        }
        let mut col = Collection::open(&s.collection)
            .with_context(|| format!("open collection {}", s.collection.display()))?;
        let plan = self.plan_on(&mut col, prune)?;
        let hash = plan_hash(&plan);
        if let Some(expected) = expected {
            ensure!(
                hash == expected,
                "plan changed since the simulation (hash {hash}, expected {expected}); nothing \
                 was written, simulate again"
            );
        }

        let scm_before = col.scm()?;
        let media_ok = match media::write_files(&plan.assets, &s.media_dir) {
            Ok(n) => {
                steps.push(Step::ok("media", format!("{} asset(s), {n} file(s) written", plan.assets.len())));
                true
            }
            Err(e) => {
                steps.push(Step::error("media", &e));
                false
            }
        };
        let outcome = if media_ok {
            match self.cycle(&mut col, false, prune) {
                Ok(o) => {
                    steps.push(Step::ok(
                        "collection",
                        format!("+{} ~{} ->{} orphaned {}", o.added, o.updated, o.moved, o.quarantined + o.deleted),
                    ));
                    // Only after the notes stopped naming them.
                    let deletes = plan.media_deletes();
                    if !deletes.is_empty() {
                        steps.push(match media::delete(&deletes, &s.media_dir) {
                            Ok(n) => Step::ok("media cleanup", format!("{n} unused file(s) deleted")),
                            Err(e) => Step::error("media cleanup", &e),
                        });
                    }
                    Outcome { changes: plan.changes, media_orphans: plan.media_orphans, ..o }
                }
                Err(e) => {
                    steps.push(Step::error("collection", &e));
                    plan
                }
            }
        } else {
            steps.push(Step::skipped("collection", "media failed; notes would reference missing files"));
            plan
        };
        let schema_changed = col.scm()? != scm_before;
        drop(col);
        steps.push(match self.sync_up(schema_changed) {
            Ok(Some(action)) => Step::ok("sync", action),
            Ok(None) => Step::skipped("sync", "no [sync] configured"),
            Err(e) => Step::error("sync", &e),
        });
        Ok(Pushed { outcome, plan_hash: hash, steps, schema_changed })
    }
}

/// Conditions the real push depends on that a data simulation can't see.
fn preflight(s: &Store, plan: &Outcome) -> Vec<String> {
    let mut out = Vec::new();
    if !(plan.assets.is_empty() && plan.media_deletes().is_empty())
        && let Err(e) = writable_dir(&s.media_dir)
    {
        out.push(format!("media dir: {e:#}"));
    }
    out
}

fn writable_dir(dir: &Path) -> Result<()> {
    std::fs::create_dir_all(dir).with_context(|| format!("create {}", dir.display()))?;
    let probe = dir.join(format!(".marki-probe-{}", std::process::id()));
    std::fs::write(&probe, b"").with_context(|| format!("{} is not writable", dir.display()))?;
    let _ = std::fs::remove_file(&probe);
    Ok(())
}

/// Anki's media folder for a collection: `foo.anki2` -> `foo.media`.
pub fn media_dir_for(collection: &Path) -> PathBuf {
    collection.with_extension("media")
}

/// A scratch directory removed on drop.
pub struct TempDir(PathBuf);

impl TempDir {
    pub fn new(tag: &str) -> Result<Self> {
        use std::sync::atomic::{AtomicUsize, Ordering};
        static N: AtomicUsize = AtomicUsize::new(0);
        let n = N.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!("marki-{tag}-{}-{n}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).with_context(|| format!("create {}", dir.display()))?;
        Ok(Self(dir))
    }
    pub fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

pub struct Simulation {
    /// The plan (models, notes, orphans, media) that a push would execute.
    pub outcome: Outcome,
    /// Problems the simulated push, the post-push check or the preflight
    /// found.
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
        // ctx:notes sees the saved tree; the note itself (saved or draft)
        // is excluded by path.
        let index = scan_dir_v2(&self.cfg.cards_dir)
            .map(|notes| Arc::new(NoteIndex::new(&self.cfg.cards_dir, &notes)))
            .ok();
        let note = render_note(
            &sn,
            &mut self.engine,
            &self.registry,
            &render_cache_dir(),
            &self.cfg.resolved_models_dir(),
            index.as_ref(),
        )?;
        let cards = preview::cards(&note);
        Ok(Preview { note, cards })
    }

    /// Render every saved note of model `name` with draft `lua` in its place
    /// and return one line per failing note. Notes render on all cores, each
    /// thread with its own Lua engine (engines aren't `Send`): a model edit
    /// misses the render cache for every map, so this is the slow part of
    /// saving a model.
    pub fn check_model_draft(&self, name: &str, lua: &str) -> Result<Vec<String>> {
        let root = &self.cfg.cards_dir;
        let all = scan_dir_v2(root)?;
        let index = Arc::new(NoteIndex::new(root, &all));
        let notes: Vec<&ScannedNote> = all.iter().filter(|sn| sn.note.model == name).collect();
        let threads = std::thread::available_parallelism().map_or(4, |n| n.get()).min(notes.len().max(1));
        let next = std::sync::atomic::AtomicUsize::new(0);
        let (cache, models) = (render_cache_dir(), self.cfg.resolved_models_dir());
        // Borrow only what threads need: `self.engine` isn't `Sync`.
        let (cfg, registry) = (&self.cfg, &self.registry);
        let mut failures: Vec<(usize, String)> = std::thread::scope(|s| {
            let workers: Vec<_> = (0..threads)
                .map(|_| {
                    s.spawn(|| {
                        let mut engine = build_script_engine(cfg);
                        let mut out = Vec::new();
                        if let Err(e) = engine.set_draft(name, lua) {
                            out.push((0, format!("{e:#}")));
                            return out;
                        }
                        loop {
                            let i = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                            let Some(sn) = notes.get(i) else { break };
                            let rel = sn.path.strip_prefix(root).unwrap_or(&sn.path).display();
                            match render_note(sn, &mut engine, registry, &cache, &models, Some(&index)) {
                                Ok(r) if r.errors.is_empty() => {}
                                Ok(r) => out.push((i, format!("{rel}: {}", r.errors.join("; ")))),
                                Err(e) => out.push((i, format!("{rel}: {e:#}"))),
                            }
                        }
                        out
                    })
                })
                .collect();
            workers.into_iter().flat_map(|w| w.join().unwrap_or_default()).collect()
        });
        failures.sort();
        failures.dedup();
        Ok(failures.into_iter().map(|(_, f)| f).collect())
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
    reg.register(Box::new(map_renderer.with_geo_dir(cfg.anchor_dir.join("geo"))));

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

    fn plan(kind: ChangeKind, content: &str, errors: &[&str]) -> Outcome {
        Outcome {
            changes: vec![Change {
                kind,
                id: "a".into(),
                path: None,
                detail: String::new(),
                content_hash: content.into(),
                full_sync: false,
            }],
            errors: errors.iter().map(|e| e.to_string()).collect(),
            ..Default::default()
        }
    }

    #[test]
    fn plan_hash_tracks_content_and_errors() {
        let base = plan_hash(&plan(ChangeKind::Update, "h1", &[]));
        assert_eq!(base, plan_hash(&plan(ChangeKind::Update, "h1", &[])));
        assert_ne!(base, plan_hash(&plan(ChangeKind::Update, "h2", &[])), "edited card must invalidate");
        assert_ne!(base, plan_hash(&plan(ChangeKind::Update, "h1", &["x"])), "new error must invalidate");
        assert_ne!(base, plan_hash(&plan(ChangeKind::Media, "h1", &[])), "media is part of the plan");
    }
}
