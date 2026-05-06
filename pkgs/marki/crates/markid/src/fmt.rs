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
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use crate::scan::scan_dir_v2;
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

    let scanned = scan_dir_v2(root)?;

    // Collect IDs seen before formatting so we can detect duplicates
    // without a second scan pass.
    let mut seen_ids = HashMap::<String, PathBuf>::new();

    for sn in &scanned {
        let had_id = sn.note.id.is_some();
        let minted_id = mint_id();

        // Read the current bytes so we can detect whether the formatter
        // actually changed anything.
        let before = match fs::read_to_string(&sn.path) {
            Ok(s) => s,
            Err(e) => {
                outcome
                    .errors
                    .push(format!("{}: read: {e}", sn.path.display()));
                continue;
            }
        };

        match write_back(&sn.path, &minted_id) {
            Ok(()) => {
                let after = fs::read_to_string(&sn.path).unwrap_or_default();
                if after == before {
                    outcome.unchanged += 1;
                } else {
                    outcome.formatted += 1;
                    if !had_id {
                        outcome.minted += 1;
                    }
                }

                // Record the final ID for duplicate detection.
                // If the file already had one, use that; otherwise use the minted one.
                let final_id = if had_id {
                    sn.note.id.clone().unwrap()
                } else {
                    minted_id
                };
                if let Some(other) = seen_ids.insert(final_id.clone(), sn.path.clone()) {
                    outcome.errors.push(format!(
                        "duplicate #id({final_id}) in {} and {}",
                        other.display(),
                        sn.path.display()
                    ));
                }
            }
            Err(e) => {
                outcome
                    .errors
                    .push(format!("{}: writeback: {e}", sn.path.display()));
            }
        }
    }

    Ok(outcome)
}
