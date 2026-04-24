//! `markid` CLI + daemon entry point.

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use markid::anki::AnkiConnect;
use markid::config::Config;
use markid::fmt as fmt_mod;
use markid::scan::{deck_for, scan_dir};
use markid::sync::reconcile;
use markid::watch::{Tick, run as run_watch};
use std::path::PathBuf;
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
}

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .with_target(false)
        .init();

    let cli = Cli::parse();
    let cfg = load_config(&cli)?;

    match cli.cmd {
        Cmd::Fmt => cmd_fmt(&cfg),
        Cmd::Push => {
            let anki = AnkiConnect::new(&cfg.anki_endpoint).context("init AnkiConnect client")?;
            cmd_push(&anki, &cfg, true)
        }
        Cmd::Status => {
            let anki = AnkiConnect::new(&cfg.anki_endpoint).context("init AnkiConnect client")?;
            cmd_status(&anki, &cfg)
        }
        Cmd::Watch => {
            let anki = AnkiConnect::new(&cfg.anki_endpoint).context("init AnkiConnect client")?;
            cmd_watch(&anki, &cfg)
        }
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
            ankiweb_sync: true,
        }
    };

    if let Some(p) = &cli.cards_dir {
        cfg.cards_dir = p.clone();
    }
    if let Some(e) = &cli.anki_endpoint {
        cfg.anki_endpoint = e.clone();
    }
    if cfg.cards_dir.as_os_str().is_empty() {
        anyhow::bail!("cards_dir is required (set in config or pass --cards-dir)");
    }
    Ok(cfg)
}

fn run_cycle(anki: &AnkiConnect, cfg: &Config, ankiweb_sync: bool) -> Result<()> {
    if ankiweb_sync {
        if let Err(e) = anki.sync() {
            tracing::warn!("pre-sync failed: {e}");
        }
    }
    // Stock `Basic` and `Cloze` note types come with every Anki install;
    // nothing to ensure.
    let scanned = scan_dir(&cfg.cards_dir)?;
    let outcome = reconcile(anki, &cfg.cards_dir, &scanned)?;
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
    if ankiweb_sync {
        if let Err(e) = anki.sync() {
            tracing::warn!("post-sync failed: {e}");
        }
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

fn cmd_push(anki: &AnkiConnect, cfg: &Config, ankiweb_sync: bool) -> Result<()> {
    anki.ping().context("AnkiConnect ping")?;
    run_cycle(anki, cfg, ankiweb_sync)
}

fn cmd_status(anki: &AnkiConnect, cfg: &Config) -> Result<()> {
    anki.ping().context("AnkiConnect ping")?;
    let scanned = scan_dir(&cfg.cards_dir)?;
    let remote = anki.managed_notes()?;
    let remote_by_id: std::collections::HashMap<&str, &markid::anki::ManagedNote> =
        remote.iter().map(|n| (n.marki_id.as_str(), n)).collect();

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
                    let content_diff = r.hash != card.current_hash;
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

fn cmd_watch(anki: &AnkiConnect, cfg: &Config) -> Result<()> {
    wait_for_anki(anki)?;

    let debounce = Duration::from_millis(cfg.debounce_ms);
    let heartbeat = cfg.sync_interval;
    let ankiweb_sync = cfg.ankiweb_sync;

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
        if let Err(e) = run_cycle(anki, cfg, ankiweb_sync) {
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
