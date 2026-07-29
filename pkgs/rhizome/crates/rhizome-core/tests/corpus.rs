//! Corpus regression tests.
//!
//! These run against a directory of real Trilium note HTML, given by
//! `RHIZOME_CORPUS`. They are skipped when it is unset so the normal test run
//! stays hermetic, but they are the tests that actually matter: unit tests
//! prove the rules do what I think, this proves they do it to real CKEditor
//! output.
//!
//! The reference corpus is Trilium's own User Guide, which ships as note HTML
//! in the server assets:
//!
//! ```text
//! RHIZOME_CORPUS=…/apps/server/src/assets/doc_notes/en cargo test -p rhizome-core
//! ```

use std::collections::BTreeMap;
use std::path::PathBuf;

use rhizome_core::{buffer, segment, splice};

fn corpus() -> Option<Vec<PathBuf>> {
    let root = std::env::var("RHIZOME_CORPUS").ok()?;
    let mut files = Vec::new();
    let mut stack = vec![PathBuf::from(root)];
    while let Some(dir) = stack.pop() {
        for entry in std::fs::read_dir(&dir).ok()? {
            let path = entry.ok()?.path();
            if path.is_dir() {
                stack.push(path);
            } else if path.extension().is_some_and(|e| e == "html") {
                files.push(path);
            }
        }
    }
    files.sort();
    Some(files)
}

/// The property the entire write path rests on: opening a note and saving it
/// without editing must not change a single byte.
#[test]
fn every_note_splices_back_byte_identical() {
    let Some(files) = corpus() else {
        eprintln!("RHIZOME_CORPUS unset; skipping");
        return;
    };
    assert!(!files.is_empty(), "corpus is empty");

    let mut failures = Vec::new();
    for file in &files {
        let html = std::fs::read_to_string(file).unwrap();
        let segments = segment(&html);
        if splice(&segments, &BTreeMap::new()) != html {
            failures.push(file.clone());
        }
    }
    assert!(
        failures.is_empty(),
        "{} of {} notes did not splice back byte-identically: {:?}",
        failures.len(),
        files.len(),
        &failures[..failures.len().min(5)]
    );
}

/// Rendering a buffer and parsing it straight back, with no edits, must
/// reproduce the note exactly.
///
/// This is the same guarantee as `every_note_splices_back_byte_identical`, but
/// asserted about the function the client actually calls. It used to be checked
/// only against `splice`, which the save path never invokes -- `buffer::parse`
/// re-joined blocks with a fixed `"\n"` and quietly reformatted every note's
/// layout on save. Comparing trimmed blocks rather than bytes is what hid it.
#[test]
fn every_note_survives_a_buffer_round_trip() {
    let Some(files) = corpus() else {
        eprintln!("RHIZOME_CORPUS unset; skipping");
        return;
    };

    let mut failures = Vec::new();
    for file in &files {
        let html = std::fs::read_to_string(file).unwrap();
        let segments = segment(&html);
        let text = buffer::render(&segments);
        if buffer::parse(&text, &segments) != html {
            failures.push(file.clone());
        }
    }
    assert!(
        failures.is_empty(),
        "{} of {} notes changed across a buffer round trip: {:?}",
        failures.len(),
        files.len(),
        &failures[..failures.len().min(5)]
    );
}

/// Guards against a rule regression quietly pushing content back into the
/// opaque bucket. The measured figure on the reference corpus is 96.2%.
#[test]
fn transparency_does_not_regress() {
    let Some(files) = corpus() else {
        eprintln!("RHIZOME_CORPUS unset; skipping");
        return;
    };

    let (mut total, mut transparent) = (0usize, 0usize);
    for file in &files {
        let html = std::fs::read_to_string(file).unwrap();
        let stats = segment(&html).stats();
        total += stats.total;
        transparent += stats.transparent;
    }

    let ratio = transparent as f64 / total as f64;
    assert!(
        ratio >= 0.96,
        "transparency regressed to {:.1}% ({transparent}/{total})",
        ratio * 100.0
    );
}

/// Whether a block is editable must depend on what it *means*, never on how it
/// happens to be indented.
///
/// This is the test that matters most, because the comparator failed it
/// silently for a long time: it collapsed layout whitespace to a single space
/// but never dropped it, so equivalence only held when the source was formatted
/// exactly the way the Markdown renderer emits. Reformatting this corpus --
/// without altering one character of content -- moved transparency from 93.6%
/// to 82.0%. Trilium's docs ship pretty-printed; a live CKEditor vault does
/// not, so the headline figure was measuring the corpus as much as the engine.
#[test]
fn transparency_is_invariant_under_reformatting() {
    let Some(files) = corpus() else {
        eprintln!("RHIZOME_CORPUS unset; skipping");
        return;
    };

    let mut failures = Vec::new();
    for file in &files {
        let html = std::fs::read_to_string(file).unwrap();
        // Round-tripping through the canonical DOM reformats the markup --
        // indentation gone, attributes and entities canonical -- while
        // preserving content, including inside `pre`.
        let reformatted = rhizome_core::serialize(&rhizome_core::parse(&html));

        let before = segment(&html).stats();
        let after = segment(&reformatted).stats();
        if before.transparent != after.transparent || before.total != after.total {
            failures.push(format!(
                "{}: {}/{} -> {}/{}",
                file.display(),
                before.transparent,
                before.total,
                after.transparent,
                after.total
            ));
        }
    }
    assert!(
        failures.is_empty(),
        "{} of {} notes changed transparency under reformatting:\n{}",
        failures.len(),
        files.len(),
        failures[..failures.len().min(5)].join("\n")
    );
}
