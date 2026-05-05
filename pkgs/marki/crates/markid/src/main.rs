//! `markid` CLI + daemon entry point.

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use markid::anki::AnkiConnect;
use markid::config::Config;
use markid::fmt as fmt_mod;
use markid::render::Registry;
use markid::scan::{deck_for, scan_dir};
use markid::sync::reconcile;
use markid::watch::{Tick, run as run_watch};
use std::path::{Path, PathBuf};
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
            let registry = build_registry(&cfg);
            cmd_push(&anki, &cfg, &registry)
        }
        Cmd::Status => {
            let anki = AnkiConnect::new(&cfg.anki_endpoint).context("init AnkiConnect client")?;
            let registry = build_registry(&cfg);
            cmd_status(&anki, &cfg, &registry)
        }
        Cmd::Watch => {
            let anki = AnkiConnect::new(&cfg.anki_endpoint).context("init AnkiConnect client")?;
            let registry = build_registry(&cfg);
            cmd_watch(&anki, &cfg, &registry)
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
        Config {
            cards_dir: PathBuf::new(),
            anki_endpoint: "http://127.0.0.1:8765".into(),
            sync_interval: Duration::from_secs(300),
            debounce_ms: 250,
            media_sources: Default::default(),
            typst_binary: None,
        }
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
        _ => Config {
            cards_dir: PathBuf::new(),
            anki_endpoint: "http://127.0.0.1:8765".into(),
            sync_interval: Duration::from_secs(300),
            debounce_ms: 250,
            media_sources: Default::default(),
            typst_binary: None,
        },
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
    registry: &Registry,
) -> Result<()> {
    // Stock `Basic` and `Cloze` note types come with every Anki install;
    // nothing to ensure.
    let scanned = scan_dir(&cfg.cards_dir, registry.external_langs())?;
    let cache_dir = render_cache_dir();
    let outcome = reconcile(anki, &cfg.cards_dir, &scanned, registry, &cache_dir)?;
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
    registry: &Registry,
) -> Result<()> {
    anki.ping().context("AnkiConnect ping")?;
    run_cycle(anki, cfg, registry)
}

fn cmd_status(anki: &AnkiConnect, cfg: &Config, registry: &Registry) -> Result<()> {
    anki.ping().context("AnkiConnect ping")?;
    let scanned = scan_dir(&cfg.cards_dir, registry.external_langs())?;
    let remote = anki.managed_notes()?;
    let remote_by_id: std::collections::HashMap<&str, &markid::anki::ManagedNote> =
        remote.iter().map(|n| (n.marki_id.as_str(), n)).collect();

    let cache_dir = render_cache_dir();
    let mut added = 0usize;
    let mut updated = 0usize;
    let mut moved = 0usize;
    let mut unformatted = 0usize;
    for sc in &scanned {
        let card = &sc.parsed.card;
        let deck = deck_for(&cfg.cards_dir, &sc.path);
        match &card.id {
            None => unformatted += 1,
            Some(id) => match remote_by_id.get(id.as_str()) {
                None => added += 1,
                Some(r) => {
                    // Dispatch blocks and recompute the hash over the
                    // final HTML, matching what the sync engine stores.
                    let html_hash = match markid::sync::dispatch_blocks(sc, registry, &cache_dir) {
                        Ok(resolved) => marki_core::content_hash_html(
                            &resolved.card.front_html,
                            &resolved.card.back_html,
                        ),
                        Err(_) => card.current_hash.clone(),
                    };
                    let content_diff = r.hash != html_hash;
                    let deck_diff = r.deck != deck;
                    if content_diff {
                        updated += 1;
                    } else if deck_diff {
                        moved += 1;
                    }
                }
            },
        }
    }
    let local_ids: std::collections::HashSet<String> = scanned
        .iter()
        .filter_map(|sc| sc.parsed.card.id.clone())
        .collect();
    let orphans = remote
        .iter()
        .filter(|r| !local_ids.contains(&r.marki_id))
        .count();

    println!(
        "scan: {} cards ({} unformatted)\nanki: {} managed notes\n+{} ~{} ->{} -{} orphans",
        scanned.len(),
        unformatted,
        remote.len(),
        added,
        updated,
        moved,
        orphans,
    );
    Ok(())
}

fn cmd_render_map(file: &Path, out: &Path, registry: &Registry) -> Result<()> {
    let source = std::fs::read_to_string(file)
        .with_context(|| format!("read {}", file.display()))?;
    let parsed = marki_core::parser::parse_with_externals(&source, registry.external_langs());
    if parsed.card.block_requests.is_empty() {
        println!("(no external blocks in {})", file.display());
    }
    std::fs::create_dir_all(out)
        .with_context(|| format!("create {}", out.display()))?;

    let cache = render_cache_dir();
    let mut front = parsed.card.front_html.clone();
    let mut back = parsed.card.back_html.clone();
    let mut total_assets = 0usize;
    for req in &parsed.card.block_requests {
        let placeholder = marki_core::placeholder_for(&req.id);
        let target = match req.side {
            marki_core::BlockSide::Front => &mut front,
            marki_core::BlockSide::Back => &mut back,
        };
        match registry.dispatch(req, file, &cache) {
            Ok(rb) => {
                *target = target.replacen(&placeholder, &rb.front_html, 1);
                if !rb.back_html_extras.is_empty() {
                    if !back.is_empty() {
                        back.push('\n');
                    }
                    back.push_str(&rb.back_html_extras);
                }
                for a in &rb.assets {
                    let asset_path = out.join(&a.filename);
                    std::fs::write(&asset_path, &a.bytes).with_context(|| {
                        format!("write asset {}", asset_path.display())
                    })?;
                    total_assets += 1;
                }
                println!("rendered {} block, id={}", req.lang, req.id);
            }
            Err(e) => {
                eprintln!("{} block {} failed: {e}", req.lang, req.id);
                let stub = format!(
                    "<div style=\"color:#a00;border:1px solid #a00;padding:0.5em;\
                     font-family:monospace;font-size:0.85em;\">\
                     <strong>{} block failed:</strong> {}</div>",
                    req.lang, e
                );
                *target = target.replacen(&placeholder, &stub, 1);
            }
        }
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

fn cmd_watch(anki: &AnkiConnect, cfg: &Config, registry: &Registry) -> Result<()> {
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
        if let Err(e) = run_cycle(anki, cfg, registry) {
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
