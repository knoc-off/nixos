//! `markid` CLI + daemon entry point.

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use markid::anki::AnkiConnect;
use markid::anki::TemplateState;
use markid::config::Config;
use markid::fmt as fmt_mod;
use markid::render::Registry;
use markid::scan::scan_dir_v2;
use markid::scripting::engine::ScriptEngine;
use markid::sync::reconcile;
use markid::watch::{Tick, run as run_watch};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;
use tracing_subscriber::EnvFilter;

#[derive(Parser)]
#[command(
    name = "marki",
    version,
    about = "Sync a markdown card repo with Anki — a one-shot CLI (optional watch daemon).",
    long_about = "marki keeps a directory of markdown flashcards in sync with Anki via \
AnkiConnect.\n\nIt is repo-centric: run it from inside a flashcard repo and it discovers a \
hidden `.markid/` directory (git-style, walking up from the current directory) holding the \
config, models, libraries and media that define your cards. `marki init` scaffolds one.\n\n\
With no subcommand, marki runs a single `push` (scan → reconcile → push) and exits."
)]
struct Cli {
    /// Path to a config file. By default marki discovers the nearest
    /// `.markid/config.toml` (walking up from the current directory),
    /// then falls back to `$XDG_CONFIG_HOME/markid/config.toml`.
    #[arg(long, env = "MARKID_CONFIG", global = true)]
    config: Option<PathBuf>,

    /// Override the cards directory (default: the repo root).
    #[arg(long, global = true)]
    cards_dir: Option<PathBuf>,

    /// Override the AnkiConnect endpoint URL.
    #[arg(long, env = "MARKID_ANKICONNECT", global = true)]
    anki_endpoint: Option<String>,

    /// Override the directory containing media files used by ```media``` blocks.
    /// Adds a single unnamed source (searched last, after any [media_sources]
    /// configured in the config file).
    #[arg(long, env = "MARKID_MEDIA_DIR", global = true)]
    media_dir: Option<PathBuf>,

    /// Path to the `typst` CLI binary, used to render ```typst``` blocks.
    /// When unset, ```typst``` blocks fall through to syntax highlighting.
    #[arg(long, env = "MARKID_TYPST", global = true)]
    typst_binary: Option<PathBuf>,

    /// Increase log verbosity. Repeat for more detail: `-v` enables
    /// `debug`, `-vv` enables `trace`. Overridden by an explicit
    /// `RUST_LOG`/env filter when one is set.
    #[arg(short = 'v', long = "verbose", global = true, action = clap::ArgAction::Count)]
    verbose: u8,

    #[command(subcommand)]
    cmd: Option<Cmd>,
}

#[derive(Subcommand)]
enum Cmd {
    /// Scaffold a `.markid/` project (config, models/, lib/, media/) in
    /// the current directory. Idempotent — never overwrites existing
    /// files. Run this once to turn a folder of cards into a marki repo.
    Init,
    /// Mint `#id(...)` for any card that doesn't have one. Pure disk op;
    /// no Anki needed. Meant to be run in CI or as a pre-commit step.
    Fmt,
    /// Run a single reconcile cycle and exit. This is the default when
    /// no subcommand is given.
    Push {
        /// Wait (with capped backoff) for AnkiConnect to become
        /// reachable before running the cycle, instead of failing fast.
        /// Useful for one-shot invocations (cron, systemd oneshot) where
        /// Anki may still be starting up.
        #[arg(long, env = "MARKID_WAIT_FOR_ANKI")]
        wait_for_anki: bool,

        /// Hard-delete orphaned notes (Anki notes with no matching `.md`)
        /// instead of the default soft-delete (suspend + `marki::orphan`
        /// tag). Irreversible — destroys scheduling history. Even with this
        /// flag, nothing is pruned during a cycle that had render errors.
        #[arg(long)]
        prune: bool,
    },
    /// Long-running daemon: watch the cards directory and push on change.
    Watch,
    /// Read-only diff view (added / updated / moved / deleted / unformatted).
    Status,
    /// Permanently delete notes previously quarantined (soft-deleted):
    /// every note tagged `marki::orphan`. Run this once you've confirmed
    /// the suspended notes really should be gone.
    Prune {
        /// Show what would be deleted without touching Anki.
        #[arg(long)]
        dry_run: bool,
    },
    /// Render every external block in a single .md file to disk and
    /// print the resulting HTML on stdout. No Anki round-trip — useful
    /// for theme iteration.
    RenderMap {
        /// The card .md to render.
        file: PathBuf,
        /// Directory to write asset files into. Created if missing.
        #[arg(long, default_value = "out")]
        out: PathBuf,
        /// Dump rendered assets (SVGs etc.) to stdout instead of writing
        /// files. Logs still go to stderr, so `markid -v render-map
        /// card.md --stdout > map.svg` gives a clean SVG plus debug
        /// trace. With multiple assets each is prefixed by an
        /// `<!-- asset: NAME -->` comment.
        #[arg(long)]
        stdout: bool,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    // Verbosity: an explicit RUST_LOG/env filter always wins; otherwise
    // `-v` bumps the default level. Logs go to stderr so stdout stays
    // clean for `render-map --stdout`.
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| {
        let level = match cli.verbose {
            0 => "info",
            1 => "debug",
            _ => "trace",
        };
        EnvFilter::new(level)
    });
    tracing_subscriber::fmt()
        .with_env_filter(env_filter)
        .with_target(false)
        .with_writer(std::io::stderr)
        .init();

    // RenderMap doesn't need a working AnkiConnect — but it does want
    // the same renderer registry the daemon uses, which in turn wants
    // config (for media sources). Load the config the same way as below.
    if let Some(Cmd::RenderMap { file, out, stdout }) = &cli.cmd {
        let cfg = load_config_for_render(&cli)?;
        let registry = build_registry(&cfg);
        return cmd_render_map(file, out, *stdout, &registry);
    }

    // `init` only scaffolds the current directory; no config load needed.
    if let Some(Cmd::Init) = &cli.cmd {
        return cmd_init();
    }

    let cfg = load_config(&cli)?;

    // No subcommand → run a single push (one-shot first).
    let cmd = cli.cmd.unwrap_or(Cmd::Push { wait_for_anki: false, prune: false });

    match cmd {
        Cmd::Init => unreachable!("handled above"),
        Cmd::Fmt => cmd_fmt(&cfg),
        Cmd::Push { wait_for_anki, prune } => {
            let anki = AnkiConnect::new(&cfg.anki_endpoint).context("init AnkiConnect client")?;
            let registry = Arc::new(build_registry(&cfg));
            let mut script_engine = build_script_engine(&cfg);
            let mut template_state = load_template_state(&cfg);
            cmd_push(
                &anki,
                &cfg,
                &registry,
                &mut script_engine,
                &mut template_state,
                wait_for_anki,
                prune,
            )
        }
        Cmd::Status => {
            let anki = AnkiConnect::new(&cfg.anki_endpoint).context("init AnkiConnect client")?;
            let registry = Arc::new(build_registry(&cfg));
            let mut script_engine = build_script_engine(&cfg);
            let mut template_state = load_template_state(&cfg);
            cmd_status(&anki, &cfg, &registry, &mut script_engine, &mut template_state)
        }
        Cmd::Prune { dry_run } => {
            let anki = AnkiConnect::new(&cfg.anki_endpoint).context("init AnkiConnect client")?;
            cmd_prune(&anki, dry_run)
        }
        Cmd::Watch => {
            let anki = AnkiConnect::new(&cfg.anki_endpoint).context("init AnkiConnect client")?;
            let registry = Arc::new(build_registry(&cfg));
            let mut script_engine = build_script_engine(&cfg);
            let mut template_state = load_template_state(&cfg);
            cmd_watch(&anki, &cfg, &registry, &mut script_engine, &mut template_state)
        }
        Cmd::RenderMap { .. } => unreachable!("handled above"),
    }
}

/// Build the external block-renderer registry. The media renderer is
/// registered when at least one media source exists — the built-in
/// git-tracked `.markid/media/` directory (searched first) plus any
/// `[media_sources]` from config. Otherwise ```media``` blocks fall
/// through to plain code rendering. Likewise, the typst renderer is only
/// registered when a typst binary is configured.
fn build_registry(cfg: &Config) -> Registry {
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

    let mut sources: Vec<(String, std::path::PathBuf)> = Vec::new();
    // Built-in primary media dir, searched first when it exists.
    let builtin = cfg.builtin_media_dir();
    if builtin.is_dir() {
        sources.push(("media".to_string(), builtin));
    }
    sources.extend(
        cfg.media_sources
            .iter()
            .map(|(name, dir)| (name.clone(), dir.clone())),
    );

    if !sources.is_empty() {
        reg.register(Box::new(marki_media::MediaRenderer::new(sources)));
    }

    if let Some(bin) = &cfg.typst_binary {
        reg.register(Box::new(marki_typst::TypstRenderer::new(bin.clone())));
    }

    reg
}

/// Build the Rhai script engine with models_dir and lib_dir from config.
fn build_script_engine(cfg: &Config) -> ScriptEngine {
    let models_dir = cfg.resolved_models_dir();
    let lib_dir = cfg.resolved_lib_dir();
    let lib = if lib_dir.exists() { Some(lib_dir) } else { None };
    ScriptEngine::new(models_dir, lib)
}

/// Load template state from the project's `.markid/model_state.json`.
fn load_template_state(cfg: &Config) -> TemplateState {
    TemplateState::load(&cfg.state_path())
}

/// Cache directory used by external block renderers. We default to
/// `$XDG_CACHE_HOME/marki/` and fall back to `$HOME/.cache/marki/`.
fn render_cache_dir() -> PathBuf {
    if let Some(d) = dirs::cache_dir() {
        d.join("marki")
    } else {
        PathBuf::from("/tmp/marki-cache")
    }
}

fn load_config(cli: &Cli) -> Result<Config> {
    let cwd = std::env::current_dir().context("get current directory")?;
    let disc = Config::discover(&cwd, cli.config.as_deref());
    if let Some(p) = &disc.config_path {
        tracing::debug!(config = %p.display(), anchor = %disc.anchor_dir.display(), "loaded config");
    } else {
        tracing::debug!(anchor = %disc.anchor_dir.display(), "no config file; using defaults");
    }
    let mut cfg = Config::load(&disc)?;

    apply_cli_overrides(&mut cfg, cli)?;
    // Resolve cards_dir to an absolute path (project root by default).
    cfg.cards_dir = cfg.resolved_cards_dir();
    Ok(cfg)
}

/// Like [`load_config`] but tolerates a missing project — used by the
/// offline `render-map` subcommand which only needs the renderer
/// registry config (media sources, typst).
fn load_config_for_render(cli: &Cli) -> Result<Config> {
    let cwd = std::env::current_dir().context("get current directory")?;
    let disc = Config::discover(&cwd, cli.config.as_deref());
    let mut cfg = Config::load(&disc)?;
    apply_cli_overrides(&mut cfg, cli)?;
    Ok(cfg)
}

/// Apply `--cards-dir`, `--anki-endpoint`, `--media-dir`, `--typst-binary`
/// overrides on top of the loaded config. `--media-dir` adds a single
/// source searched after both the built-in media dir and config sources.
fn apply_cli_overrides(cfg: &mut Config, cli: &Cli) -> Result<()> {
    if let Some(p) = &cli.cards_dir {
        cfg.cards_dir = p.clone();
    }
    if let Some(e) = &cli.anki_endpoint {
        cfg.anki_endpoint = e.clone();
    }
    if let Some(p) = &cli.media_dir {
        cfg.media_sources
            .entry("_default".into())
            .or_insert_with(|| p.clone());
    }
    if let Some(p) = &cli.typst_binary {
        cfg.typst_binary = Some(p.clone());
    }
    Ok(())
}

fn run_cycle(
    anki: &AnkiConnect,
    cfg: &Config,
    registry: &Arc<Registry>,
    script_engine: &mut ScriptEngine,
    template_state: &mut TemplateState,
    dry_run: bool,
    prune: bool,
) -> Result<markid::sync::Outcome> {
    // Invalidate cached model scripts so edits to .rhai files are picked up.
    script_engine.invalidate_all();
    let notes = scan_dir_v2(&cfg.cards_dir)?;
    let cache_dir = render_cache_dir();
    let models_dir = cfg.resolved_models_dir();
    tracing::debug!(
        notes = notes.len(),
        cards_dir = %cfg.cards_dir.display(),
        cache_dir = %cache_dir.display(),
        dry_run,
        prune,
        "starting reconcile cycle"
    );
    let outcome = reconcile(
        anki,
        &cfg.cards_dir,
        &notes,
        script_engine,
        registry,
        template_state,
        &cache_dir,
        &models_dir,
        dry_run,
        prune,
    )?;
    tracing::info!(
        "cycle: +{} ~{} ->{} -{} (quarantined {}, skipped-prune {}, unformatted {}, {} errors)",
        outcome.added,
        outcome.updated,
        outcome.moved,
        outcome.deleted,
        outcome.quarantined,
        outcome.skipped_prune,
        outcome.unformatted,
        outcome.errors.len(),
    );
    for e in &outcome.errors {
        tracing::warn!("{e}");
    }
    // Persist template state after successful cycle.
    let state_path = cfg.state_path();
    if let Err(e) = template_state.save(&state_path) {
        tracing::warn!("save template state: {e}");
    }
    Ok(outcome)
}

/// Scaffold a `.markid/` project in the current directory.
fn cmd_init() -> Result<()> {
    let cwd = std::env::current_dir().context("get current directory")?;
    let anchor = markid::config::init_project(&cwd)?;
    println!("initialized marki project at {}", anchor.display());
    println!("  - edit {}/config.toml", anchor.display());
    println!("  - add models to {}/models/", anchor.display());
    println!("  - add committed media to {}/media/", anchor.display());
    println!("then run `marki` (or `marki push`) from this repo to sync.");
    Ok(())
}

fn cmd_fmt(cfg: &Config) -> Result<()> {
    let outcome = fmt_mod::run(&cfg.cards_dir)?;
    println!(
        "fmt: formatted {} (minted {}), unchanged {}, warnings {}",
        outcome.formatted, outcome.minted, outcome.unchanged, outcome.errored,
    );
    for e in &outcome.errors {
        eprintln!("warning: {e}");
    }
    Ok(())
}

fn cmd_push(
    anki: &AnkiConnect,
    cfg: &Config,
    registry: &Arc<Registry>,
    script_engine: &mut ScriptEngine,
    template_state: &mut TemplateState,
    wait_for_anki_first: bool,
    prune: bool,
) -> Result<()> {
    if wait_for_anki_first {
        wait_for_anki(anki)?;
    } else {
        anki.ping().context("AnkiConnect ping")?;
    }
    let outcome = run_cycle(anki, cfg, registry, script_engine, template_state, false, prune)?;
    // Surface failures with a non-zero exit so cron/systemd notices, instead
    // of silently "succeeding" while notes failed to render.
    if !outcome.errors.is_empty() {
        anyhow::bail!(
            "cycle completed with {} error(s); no orphans were pruned",
            outcome.errors.len()
        );
    }
    Ok(())
}

fn cmd_status(
    anki: &AnkiConnect,
    cfg: &Config,
    registry: &Arc<Registry>,
    script_engine: &mut ScriptEngine,
    template_state: &mut TemplateState,
) -> Result<()> {
    anki.ping().context("AnkiConnect ping")?;
    run_cycle(anki, cfg, registry, script_engine, template_state, true, false)?;
    Ok(())
}

/// Permanently delete every note quarantined by a prior soft-delete
/// (`tag:marki::orphan`). Separate, explicit, opt-in step.
fn cmd_prune(anki: &AnkiConnect, dry_run: bool) -> Result<()> {
    anki.ping().context("AnkiConnect ping")?;
    let query = format!("tag:{}", markid::anki::model::ORPHAN_TAG);
    let note_ids = anki.find_notes(&query).context("find quarantined notes")?;
    if note_ids.is_empty() {
        println!("prune: no quarantined notes (tag:{})", markid::anki::model::ORPHAN_TAG);
        return Ok(());
    }
    if dry_run {
        println!("prune (dry-run): would delete {} quarantined note(s)", note_ids.len());
        return Ok(());
    }
    anki.delete_notes(&note_ids).context("delete quarantined notes")?;
    println!("prune: deleted {} quarantined note(s)", note_ids.len());
    Ok(())
}

fn cmd_render_map(file: &Path, out: &Path, to_stdout: bool, registry: &Registry) -> Result<()> {
    use std::io::Write;

    let source = std::fs::read_to_string(file)
        .with_context(|| format!("read {}", file.display()))?;
    let note = marki_core::note_parser::parse_note(&source, file.to_path_buf());

    let cache = render_cache_dir();
    let result = markid::sync::stock_render::render_stock(&note, registry, file, &cache);

    for e in &result.errors {
        eprintln!("warning: {e}");
    }

    // --stdout: dump each rendered asset to stdout (SVG XML etc.) and
    // skip file writing entirely. Logs and warnings already went to
    // stderr, so the stream stays clean.
    if to_stdout {
        let stdout = std::io::stdout();
        let mut w = stdout.lock();
        let multi = result.assets.len() > 1;
        for a in &result.assets {
            if multi {
                writeln!(w, "<!-- asset: {} -->", a.filename)?;
            }
            w.write_all(&a.bytes)?;
            if !a.bytes.ends_with(b"\n") {
                writeln!(w)?;
            }
        }
        tracing::info!(
            assets = result.assets.len(),
            "rendered {} to stdout",
            file.display()
        );
        return Ok(());
    }

    // Extract front/back from fields.
    let front = result.fields.iter()
        .find(|(k, _)| k == "Front" || k == "Text")
        .map(|(_, v)| v.as_str())
        .unwrap_or("");
    let back = result.fields.iter()
        .find(|(k, _)| k == "Back" || k == "Back Extra")
        .map(|(_, v)| v.as_str())
        .unwrap_or("");

    std::fs::create_dir_all(out)
        .with_context(|| format!("create {}", out.display()))?;

    // Write assets to output directory.
    let mut total_assets = 0usize;
    for a in &result.assets {
        let asset_path = out.join(&a.filename);
        std::fs::write(&asset_path, &a.bytes).with_context(|| {
            format!("write asset {}", asset_path.display())
        })?;
        total_assets += 1;
    }

    let html_path = out.join("preview.html");
    let document = format!(
        "<!doctype html><meta charset=\"utf-8\"><title>{name}</title>\
         <style>body{{font-family:system-ui,sans-serif;margin:2rem;max-width:800px;}}</style>\
         <h2>front</h2>{front}<hr><h2>back</h2>{back}",
        name = file.display(),
        front = front,
        back = back,
    );
    std::fs::write(&html_path, document.as_bytes())
        .with_context(|| format!("write {}", html_path.display()))?;
    println!(
        "wrote {} (preview) plus {} asset(s) to {}",
        html_path.display(),
        total_assets,
        out.display()
    );
    Ok(())
}

fn cmd_watch(
    anki: &AnkiConnect,
    cfg: &Config,
    registry: &Arc<Registry>,
    script_engine: &mut ScriptEngine,
    template_state: &mut TemplateState,
) -> Result<()> {
    wait_for_anki(anki)?;

    let debounce = Duration::from_millis(cfg.debounce_ms);
    let heartbeat = cfg.sync_interval;

    tracing::info!(
        "watching {} (debounce={:?} heartbeat={:?})",
        cfg.cards_dir.display(),
        debounce,
        heartbeat
    );

    run_watch(&cfg.cards_dir, debounce, heartbeat, |tick| {
        match tick {
            Tick::Filesystem => tracing::info!("cycle: triggered by filesystem change"),
            Tick::Heartbeat => tracing::info!("cycle: triggered by heartbeat"),
        }
        if let Err(e) = run_cycle(anki, cfg, registry, script_engine, template_state, false, false) {
            tracing::error!("cycle failed: {e:#}");
        }
        Ok(true)
    })
}

fn wait_for_anki(anki: &AnkiConnect) -> Result<()> {
    let mut backoff = Duration::from_millis(500);
    let cap = Duration::from_secs(30);
    loop {
        match anki.ping() {
            Ok(v) => {
                tracing::info!("AnkiConnect version {v}");
                return Ok(());
            }
            Err(e) => {
                tracing::warn!("AnkiConnect unreachable ({e}); retrying in {:?}", backoff);
                std::thread::sleep(backoff);
                backoff = (backoff * 2).min(cap);
            }
        }
    }
}
