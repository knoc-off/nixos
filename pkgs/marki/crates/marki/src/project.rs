//! A loaded marki project: config plus the renderer registry and Lua engine
//! built from it. Shared by the CLI and the MCP server so both drive the
//! same pipeline.
//!
//! Collection access has two modes, because anki-sync-server (and Anki
//! desktop) hold the collection and `media.db` with an exclusive SQLite lock
//! for as long as they run:
//! - reads ([`Project::read_view`]) use the live files when they are free and
//!   a file-level snapshot when they are locked, so they never disturb the
//!   server;
//! - writes ([`Project::push`]) pause the server with the configured
//!   `[server]` stop/start commands, then write media, then the collection,
//!   stopping at the first failure, and always restart it.

use anyhow::{Context, Result, bail, ensure};
use marki_anki::Collection;
use marki_anki::media::MediaDatabase;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::config::{Config, ServerConfig};
use crate::preview::{self, CardPreview};
use crate::render::Registry;
use crate::scan::ScannedNote;
use crate::scan::scan_dir_v2;
use crate::scripting::engine::ScriptEngine;
use crate::sync::{Outcome, RenderedNote, media, reconcile, render_note};

pub struct Project {
    pub cfg: Config,
    pub registry: Arc<Registry>,
    pub engine: ScriptEngine,
}

/// Where the collection and its media store live.
pub struct Store {
    pub collection: PathBuf,
    pub media_dir: PathBuf,
    pub media_db: PathBuf,
}

/// A readable collection plus the media database path to read alongside it.
/// Either the live files or a snapshot of them (see [`Project::read_view`]).
pub struct View {
    pub col: Collection,
    pub media_db: PathBuf,
    /// Read from a copy because the live files were locked. May lag the
    /// server's latest write by whatever it had not flushed to disk.
    pub snapshot: bool,
    // Declared last so the collection closes before its directory goes.
    _tmp: Option<TempDir>,
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
    /// failed to render. A step skipped by configuration (no `[server]`)
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
        let collection = self.cfg.resolved_collection().context(
            "no collection configured; set `collection` in .marki/config.toml or pass --collection",
        )?;
        let dir = collection.parent().context("collection path has no parent")?;
        Ok(Store { media_dir: dir.join("media"), media_db: dir.join("media.db"), collection })
    }

    /// Open the live collection for writing. Fails fast when another process
    /// holds it; use [`Project::push`] or [`Project::with_paused`] instead of
    /// calling this directly when a server may be running.
    pub fn open_collection(&self) -> Result<Collection> {
        let path = self.store()?.collection;
        Collection::open(&path).with_context(|| format!("open collection {}", path.display()))
    }

    /// The collection for reading, without disturbing a running server: the
    /// live files when nobody holds them, otherwise a copy of the collection
    /// and `media.db` (with their WAL files, which SQLite replays on open).
    pub fn read_view(&self) -> Result<View> {
        let s = self.store()?;
        if !marki_anki::is_locked(&s.collection) && !marki_anki::is_locked(&s.media_db) {
            let col = Collection::open(&s.collection)
                .with_context(|| format!("open collection {}", s.collection.display()))?;
            return Ok(View { col, media_db: s.media_db, snapshot: false, _tmp: None });
        }
        // ponytail: a plain file copy can tear if the server checkpoints
        // mid-copy; SQLite then either replays a consistent WAL prefix or
        // fails to open, and the next call retries. Fine for reads.
        let tmp = TempDir::new("view")?;
        let col_copy = tmp.path().join("collection.anki2");
        let media_copy = tmp.path().join("media.db");
        copy_db(&s.collection, &col_copy)?;
        copy_db(&s.media_db, &media_copy)?;
        let col = Collection::open(&col_copy).context("open collection snapshot")?;
        Ok(View { col, media_db: media_copy, snapshot: true, _tmp: Some(tmp) })
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

    /// The full plan against `col` and the media store: models, notes,
    /// orphans, then media files that are missing or unregistered.
    fn plan_on(&mut self, col: &mut Collection, media_db: &Path, prune: bool) -> Result<Outcome> {
        let mut o = self.cycle(col, true, prune)?;
        let media_dir = self.store()?.media_dir;
        o.changes.extend(media::plan(&o.assets, &media_dir, media_db)?);
        Ok(o)
    }

    /// What a push would change right now (read-only, no simulation).
    pub fn plan(&mut self, prune: bool) -> Result<(Outcome, bool)> {
        let mut v = self.read_view()?;
        let o = self.plan_on(&mut v.col, &v.media_db, prune)?;
        Ok((o, v.snapshot))
    }

    /// Run a real push against throwaway copies of the collection and
    /// `media.db`, then check the copies. Nothing live changes. Also checks
    /// what the real push needs beyond the data: that the server can be
    /// paused and the media directory is writable. `plan_hash` fingerprints
    /// the plan so a later confirmed push can refuse if anything moved on.
    pub fn simulate(&mut self, prune: bool) -> Result<Simulation> {
        let s = self.store()?;
        let mut view = self.read_view()?;
        let plan = self.plan_on(&mut view.col, &view.media_db, prune)?;
        let tmp = TempDir::new("sim")?;
        let col_copy = tmp.path().join("collection.anki2");
        let media_copy = tmp.path().join("media.db");
        view.col.backup(&col_copy).context("snapshot collection")?;
        if view.media_db.exists() {
            MediaDatabase::open_or_create(&view.media_db)?
                .backup(&media_copy)
                .context("snapshot media db")?;
        }
        drop(view);

        let mut problems = self.preflight(&s, &plan);
        let mut sim = Collection::open(&col_copy)?;
        if let Err(e) = media::register(&plan.assets, &media_copy) {
            problems.push(format!("media db: {e:#}"));
        }
        let applied = self.cycle(&mut sim, false, prune)?;
        problems.extend(applied.errors.iter().filter(|e| !plan.errors.contains(e)).cloned());
        problems.extend(sim.check().context("check simulated collection")?);
        Ok(Simulation { plan_hash: plan_hash(&plan), outcome: plan, problems })
    }

    /// Conditions the real push depends on that a data simulation can't see.
    fn preflight(&self, s: &Store, plan: &Outcome) -> Vec<String> {
        let mut out = Vec::new();
        let locked = marki_anki::is_locked(&s.collection) || marki_anki::is_locked(&s.media_db);
        if locked && !self.cfg.server.configured() {
            out.push(
                "the collection is locked by another process (anki-sync-server or Anki \
                 desktop) and no [server] stop/start commands are configured"
                    .into(),
            );
        }
        for argv in [&self.cfg.server.stop, &self.cfg.server.start] {
            if let Some(bin) = argv.first()
                && which(bin).is_none()
            {
                out.push(format!("[server] command not found: {bin}"));
            }
        }
        if !plan.assets.is_empty()
            && let Err(e) = writable_dir(&s.media_dir)
        {
            out.push(format!("media dir: {e:#}"));
        }
        out
    }

    /// Push the current cards: pause the server, re-plan against the live
    /// files, then write media, then the collection -- stopping at the first
    /// failure -- and always restart the server. With `expected`, refuse
    /// unless the plan still hashes to it (from [`Project::simulate`]).
    /// Returns `Err` only when nothing was written.
    pub fn push(&mut self, expected: Option<&str>, prune: bool) -> Result<Pushed> {
        let s = self.store()?;
        let mut pause = Pause::begin(&self.cfg.server, &s)?;
        let mut col = Collection::open(&s.collection)
            .with_context(|| format!("open collection {}", s.collection.display()))?;
        let plan = self.plan_on(&mut col, &s.media_db, prune)?;
        let hash = plan_hash(&plan);
        if let Some(expected) = expected {
            ensure!(
                hash == expected,
                "plan changed since the simulation (hash {hash}, expected {expected}); nothing \
                 was written, simulate again"
            );
        }

        let scm_before = col.scm()?;
        let mut steps = Vec::new();
        let media_ok = match media::push_all(&plan.assets, &s.media_dir, &s.media_db) {
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
                    Outcome { changes: plan.changes, ..o }
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
        steps.push(match pause.resume() {
            Ok(Some(())) => Step::ok("server", "restarted"),
            Ok(None) => Step::skipped("server", "no [server] configured"),
            Err(e) => Step::error("server", &e),
        });
        Ok(Pushed { outcome, plan_hash: hash, steps, schema_changed })
    }

    /// Run `f` on the live collection with the server paused.
    pub fn with_paused<T>(&self, f: impl FnOnce(&mut Collection) -> Result<T>) -> Result<T> {
        let s = self.store()?;
        let mut pause = Pause::begin(&self.cfg.server, &s)?;
        let out = {
            let mut col = Collection::open(&s.collection)?;
            f(&mut col)
        };
        pause.resume()?;
        out
    }
}

/// Stops the server on [`Pause::begin`] and starts it again on
/// [`Pause::resume`] or, as a fallback, on drop -- so an early `?` return
/// can't leave it stopped.
struct Pause {
    start: Vec<String>,
    active: bool,
}

impl Pause {
    fn begin(server: &ServerConfig, s: &Store) -> Result<Self> {
        let locked = || marki_anki::is_locked(&s.collection) || marki_anki::is_locked(&s.media_db);
        if !server.configured() {
            ensure!(
                !locked(),
                "{} is locked by another process; configure [server] stop/start commands so \
                 marki can pause anki-sync-server, or close Anki",
                s.collection.display()
            );
            return Ok(Self { start: vec![], active: false });
        }
        run(&server.stop).context("stop server")?;
        let mut p = Self { start: server.start.clone(), active: true };
        let deadline = Instant::now() + Duration::from_secs(10);
        while locked() {
            if Instant::now() > deadline {
                let _ = p.resume();
                bail!("server stopped but the collection is still locked after 10s");
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        Ok(p)
    }

    /// `Some` when a server was restarted, `None` when none is configured.
    fn resume(&mut self) -> Result<Option<()>> {
        if !self.active {
            return Ok(None);
        }
        self.active = false;
        run(&self.start).context("start server")?;
        Ok(Some(()))
    }
}

impl Drop for Pause {
    fn drop(&mut self) {
        if let Err(e) = self.resume() {
            tracing::error!("{e:#}");
        }
    }
}

fn run(argv: &[String]) -> Result<()> {
    let (bin, args) = argv.split_first().context("empty command")?;
    let out = std::process::Command::new(bin)
        .args(args)
        .output()
        .with_context(|| format!("run {}", argv.join(" ")))?;
    ensure!(
        out.status.success(),
        "`{}` failed ({}): {}",
        argv.join(" "),
        out.status,
        String::from_utf8_lossy(&out.stderr).trim()
    );
    Ok(())
}

fn which(bin: &str) -> Option<PathBuf> {
    if bin.contains('/') {
        return Path::new(bin).exists().then(|| PathBuf::from(bin));
    }
    std::env::split_paths(&std::env::var_os("PATH")?)
        .map(|d| d.join(bin))
        .find(|p| p.is_file())
}

fn writable_dir(dir: &Path) -> Result<()> {
    std::fs::create_dir_all(dir).with_context(|| format!("create {}", dir.display()))?;
    let probe = dir.join(format!(".marki-probe-{}", std::process::id()));
    std::fs::write(&probe, b"").with_context(|| format!("{} is not writable", dir.display()))?;
    let _ = std::fs::remove_file(&probe);
    Ok(())
}

/// Copy a SQLite file and its WAL (the WAL holds committed pages not yet
/// checkpointed). No `-shm`: exclusive-mode servers don't have one, and a
/// stale one would be wrong for the copy. A missing source is not an error.
fn copy_db(src: &Path, dst: &Path) -> Result<()> {
    if !src.exists() {
        return Ok(());
    }
    std::fs::copy(src, dst).with_context(|| format!("copy {}", src.display()))?;
    let wal = |p: &Path| PathBuf::from(format!("{}-wal", p.display()));
    if wal(src).exists() {
        std::fs::copy(wal(src), wal(dst)).with_context(|| format!("copy {}-wal", src.display()))?;
    }
    Ok(())
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

    #[test]
    fn pause_restarts_on_drop() {
        let tmp = TempDir::new("pause-test").unwrap();
        let log = tmp.path().join("log");
        let sh = |word: &str| vec!["sh".into(), "-c".into(), format!("echo {word} >> {}", log.display())];
        let server = ServerConfig { stop: sh("stop"), start: sh("start") };
        let store = Store {
            collection: tmp.path().join("none.anki2"),
            media_dir: tmp.path().join("media"),
            media_db: tmp.path().join("media.db"),
        };
        {
            let _p = Pause::begin(&server, &store).unwrap();
        }
        assert_eq!(std::fs::read_to_string(&log).unwrap(), "stop\nstart\n");
        let mut p = Pause::begin(&server, &store).unwrap();
        assert_eq!(p.resume().unwrap(), Some(()));
        drop(p);
        assert_eq!(std::fs::read_to_string(&log).unwrap(), "stop\nstart\nstop\nstart\n", "no double start");
    }
}
