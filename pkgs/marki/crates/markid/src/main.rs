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
    name = "markid",
    version,
    about = "Sync a markdown directory with Anki via AnkiConnect"
)]
struct Cli {
    /// Path to a config file. Defaults to `$XDG_CONFIG_HOME/markid/config.toml`.
    #[arg(long, env = "MARKID_CONFIG", global = true)]
    config: Option<PathBuf>,

    /// Override the cards directory from the config file.
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

    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Mint `#id(...)` for any card that doesn't have one. Pure disk op;
    /// no Anki needed. Meant to be run in CI or as a pre-commit step.
    Fmt,
    /// Run a single reconcile cycle and exit.
    Push,
    /// Long-running daemon: watch the cards directory and push on change.
    Watch,
    /// Read-only diff view (added / updated / moved / deleted / unformatted).
    Status,
    /// Render every external block in a single .md file to disk and
    /// print the resulting HTML on stdout. No Anki round-trip — useful
    /// for theme iteration.
    RenderMap {
        /// The card .md to render.
        file: PathBuf,
        /// Directory to write asset files into. Created if missing.
        #[arg(long, default_value = "out")]
        out: PathBuf,
    },
}

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .with_target(false)
        .init();

    let cli = Cli::parse();

    // RenderMap doesn't need a working AnkiConnect — but it does want
    // the same renderer registry the daemon uses, which in turn wants
    // config (for `media_dir`). Load the config the same way as below.
    if let Cmd::RenderMap { file, out } = &cli.cmd {
        let cfg = load_config_for_render(&cli)?;
        let registry = build_registry(&cfg);
        return cmd_render_map(file, out, &registry);
    }

    let cfg = load_config(&cli)?;

    match cli.cmd {
        Cmd::Fmt => cmd_fmt(&cfg),
        Cmd::Push => {
            let anki = AnkiConnect::new(&cfg.anki_endpoint).context("init AnkiConnect client")?;
            let registry = Arc::new(build_registry(&cfg));
            let mut script_engine = build_script_engine(&cfg);
            let mut template_state = load_template_state();
            cmd_push(&anki, &cfg, &registry, &mut script_engine, &mut template_state)
        }
        Cmd::Status => {
            let anki = AnkiConnect::new(&cfg.anki_endpoint).context("init AnkiConnect client")?;
            let registry = Arc::new(build_registry(&cfg));
            let mut script_engine = build_script_engine(&cfg);
            let mut template_state = load_template_state();
            cmd_status(&anki, &cfg, &registry, &mut script_engine, &mut template_state)
        }
        Cmd::Watch => {
            let anki = AnkiConnect::new(&cfg.anki_endpoint).context("init AnkiConnect client")?;
            let registry = Arc::new(build_registry(&cfg));
            let mut script_engine = build_script_engine(&cfg);
            let mut template_state = load_template_state();
            cmd_watch(&anki, &cfg, &registry, &mut script_engine, &mut template_state)
        }
        Cmd::RenderMap { .. } => unreachable!("handled above"),
    }
}

/// Build the external block-renderer registry. The media renderer is
/// only registered when at least one media source is configured —
/// otherwise ```media``` blocks fall through to plain code rendering.
/// Likewise, the typst renderer is only registered when a typst binary
/// is configured.
fn build_registry(cfg: &Config) -> Registry {
    let mut reg = Registry::new();
    reg.register(Box::new(marki_map::MapRenderer::new()));

    let sources: Vec<(String, std::path::PathBuf)> = cfg
        .media_sources
        .iter()
        .map(|(name, dir)| (name.clone(), dir.clone()))
        .collect();

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

/// Load template state from the standard config location.
fn load_template_state() -> TemplateState {
    let path = TemplateState::default_path(
        &dirs::config_dir().unwrap_or_else(|| PathBuf::from(".")),
    );
    TemplateState::load(&path)
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
    let path = cli
        .config
        .clone()
        .or_else(Config::default_path)
        .ok_or_else(|| anyhow::anyhow!("no config path; pass --config or set XDG_CONFIG_HOME"))?;

    let mut cfg = if path.exists() {
        Config::load_from(&path).with_context(|| format!("read config {}", path.display()))?
    } else {
        Config::default()
    };

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
    if cfg.cards_dir.as_os_str().is_empty() {
        anyhow::bail!("cards_dir is required (set in config or pass --cards-dir)");
    }
    Ok(cfg)
}

/// Like [`load_config`] but doesn't require `cards_dir` — used by the
/// offline `render-map` subcommand which only needs the renderer
/// registry config (e.g. `media_dir`).
fn load_config_for_render(cli: &Cli) -> Result<Config> {
    let path = cli.config.clone().or_else(Config::default_path);

    let mut cfg = match path {
        Some(p) if p.exists() => {
            Config::load_from(&p).with_context(|| format!("read config {}", p.display()))?
        }
        _ => Config::default(),
    };

    if let Some(p) = &cli.media_dir {
        cfg.media_sources
            .entry("_default".into())
            .or_insert_with(|| p.clone());
    }
    if let Some(p) = &cli.typst_binary {
        cfg.typst_binary = Some(p.clone());
    }
    Ok(cfg)
}

fn run_cycle(
    anki: &AnkiConnect,
    cfg: &Config,
    registry: &Arc<Registry>,
    script_engine: &mut ScriptEngine,
    template_state: &mut TemplateState,
    dry_run: bool,
) -> Result<()> {
    // Invalidate cached model scripts so edits to .rhai files are picked up.
    script_engine.invalidate_all();
    let notes = scan_dir_v2(&cfg.cards_dir)?;
    let cache_dir = render_cache_dir();
    let models_dir = cfg.resolved_models_dir();
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
    )?;
    tracing::info!(
        "cycle: +{} ~{} ->{} -{} (unformatted {}, {} errors)",
        outcome.added,
        outcome.updated,
        outcome.moved,
        outcome.deleted,
        outcome.unformatted,
        outcome.errors.len(),
    );
    for e in &outcome.errors {
        tracing::warn!("{e}");
    }
    // Persist template state after successful cycle.
    let state_path = TemplateState::default_path(
        &dirs::config_dir().unwrap_or_else(|| PathBuf::from(".")),
    );
    if let Err(e) = template_state.save(&state_path) {
        tracing::warn!("save template state: {e}");
    }
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
) -> Result<()> {
    anki.ping().context("AnkiConnect ping")?;
    run_cycle(anki, cfg, registry, script_engine, template_state, false)
}

fn cmd_status(
    anki: &AnkiConnect,
    cfg: &Config,
    registry: &Arc<Registry>,
    script_engine: &mut ScriptEngine,
    template_state: &mut TemplateState,
) -> Result<()> {
    anki.ping().context("AnkiConnect ping")?;
    run_cycle(anki, cfg, registry, script_engine, template_state, true)
}

fn cmd_render_map(file: &Path, out: &Path, registry: &Registry) -> Result<()> {
    let source = std::fs::read_to_string(file)
        .with_context(|| format!("read {}", file.display()))?;
    let note = marki_core::note_parser::parse_note(&source, file.to_path_buf());

    std::fs::create_dir_all(out)
        .with_context(|| format!("create {}", out.display()))?;

    let cache = render_cache_dir();
    let result = markid::sync::stock_render::render_stock(&note, registry, file, &cache);

    // Extract front/back from fields.
    let front = result.fields.iter()
        .find(|(k, _)| k == "Front" || k == "Text")
        .map(|(_, v)| v.as_str())
        .unwrap_or("");
    let back = result.fields.iter()
        .find(|(k, _)| k == "Back" || k == "Back Extra")
        .map(|(_, v)| v.as_str())
        .unwrap_or("");

    for e in &result.errors {
        eprintln!("warning: {e}");
    }

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
        if let Err(e) = run_cycle(anki, cfg, registry, script_engine, template_state, false) {
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
