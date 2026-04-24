//! `markid fmt` — walk a directory of `.md` cards and rewrite each in
//! canonical form (see `marki_core::render::format_card`).
//!
//! * Every file gets its tags collected onto a single trailing tag line.
//! * Files without an `#id(...)` get a freshly-minted UUID.
//! * Whitespace is normalised.
//! * Running `fmt` twice is a no-op.
//!
//! Pure disk operation — no network, no Anki, no daemon.

use anyhow::Result;
use marki_core::mint_id;
use std::fs;
use std::path::Path;

use crate::scan::scan_dir;
use crate::writeback::write_back;

#[derive(Default)]
pub struct FmtOutcome {
    /// Files already in canonical form. Untouched on disk.
    pub unchanged: usize,
    /// Files rewritten to canonical form (formatting and/or minting).
    pub formatted: usize,
    /// Files that had a freshly-minted id (subset of `formatted`).
    pub minted: usize,
    /// Files whose parse produced warnings. Non-fatal.
    pub errored: usize,
    /// Accumulated human-readable error / warning lines.
    pub errors: Vec<String>,
}

pub fn run(root: &Path) -> Result<FmtOutcome> {
    let mut outcome = FmtOutcome::default();

    let scanned = scan_dir(root)?;

    for sc in &scanned {
        // Surface any parse warnings but keep going.
        if !sc.parsed.errors.is_empty() {
            outcome.errored += 1;
            for e in &sc.parsed.errors {
                outcome
                    .errors
                    .push(format!("{}: {e}", sc.path.display()));
            }
        }

        let had_id = sc.parsed.card.id.is_some();
        let minted_id = mint_id();

        // Read the current bytes so we can detect whether the formatter
        // actually changed anything.
        let before = match fs::read_to_string(&sc.path) {
            Ok(s) => s,
            Err(e) => {
                outcome
                    .errors
                    .push(format!("{}: read: {e}", sc.path.display()));
                continue;
            }
        };

        match write_back(&sc.path, &minted_id) {
            Ok(()) => {
                let after = fs::read_to_string(&sc.path).unwrap_or_default();
                if after == before {
                    outcome.unchanged += 1;
                } else {
                    outcome.formatted += 1;
                    if !had_id {
                        outcome.minted += 1;
                    }
                }
            }
            Err(e) => {
                outcome
                    .errors
                    .push(format!("{}: writeback: {e}", sc.path.display()));
            }
        }
    }

    // Sanity: after the pass, no two files should claim the same id.
    let rescanned = scan_dir(root)?;
    let mut seen = std::collections::HashMap::<String, std::path::PathBuf>::new();
    for sc in rescanned {
        if let Some(id) = sc.parsed.card.id {
            if let Some(other) = seen.insert(id.clone(), sc.path.clone()) {
                outcome.errors.push(format!(
                    "duplicate #id({id}) in {} and {}",
                    other.display(),
                    sc.path.display()
                ));
            }
        }
    }

    Ok(outcome)
}
