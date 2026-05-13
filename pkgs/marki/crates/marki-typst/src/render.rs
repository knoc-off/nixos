//! Compilation pipeline: source → cache check → temp dir → subprocess →
//! cached SVG → embedded HTML + emitted asset.
//!
//! The cache layout mirrors `marki-map`'s — `<cache_dir>/typst/<key>/`
//! holds `output.svg` plus a `.ready` marker. The marker is written
//! last, so a crash mid-write is observed as a cache miss on the next
//! run rather than a partial hit.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;

use marki_core::{AssetMime, EmittedAsset, RenderCtx, RenderedBlock};

use crate::error::TypstError;
use crate::version::RENDER_VERSION_TYPST;

/// Preamble prepended to every user source before compilation.
///
/// `width: auto, height: auto` shrinks the page to fit the rendered
/// content (no A4 whitespace). `margin: 0pt` removes Typst's default
/// 2.5cm margins. `fill: none` lets Anki's card background show
/// through. The user can override any of these by re-`set`ing the
/// page after the preamble — Typst's last-wins semantics apply
/// per property.
const PREAMBLE: &str = "#set page(width: auto, height: auto, margin: 0pt, fill: none)\n";

/// Marker file that signals "this directory's contents are complete".
const READY_MARKER: &str = ".ready";

/// File name written inside the cache dir.
const SVG_NAME: &str = "output.svg";

/// End-to-end render: returns the [`RenderedBlock`] the daemon
/// splices into the card.
pub fn run(
    binary: &Path,
    src: &str,
    ctx: &mut RenderCtx<'_>,
) -> Result<RenderedBlock, TypstError> {
    let key = cache_key(src);
    let dir = cache_dir(ctx.cache_dir, &key);

    let svg_bytes = if is_ready(&dir) {
        fs::read(dir.join(SVG_NAME))?
    } else {
        let bytes = compile(binary, src, ctx.source_path)?;
        write_atomic(&dir, &bytes)?;
        bytes
    };

    Ok(build_block(svg_bytes))
}

/// Compute `blake3(RENDER_VERSION_TYPST ∥ source)`, truncated to 16
/// hex chars. Same width as `marki-map`'s render keys.
fn cache_key(src: &str) -> String {
    let mut hasher = blake3::Hasher::new();
    hasher.update(&RENDER_VERSION_TYPST.to_le_bytes());
    hasher.update(PREAMBLE.as_bytes());
    hasher.update(src.as_bytes());
    let hex = hasher.finalize().to_hex();
    hex.as_str()[..16].to_string()
}

fn cache_dir(cache_root: &Path, key: &str) -> PathBuf {
    cache_root.join("typst").join(key)
}

fn is_ready(dir: &Path) -> bool {
    dir.join(READY_MARKER).exists()
}

/// Run `typst compile --format svg` against `src` and return the
/// SVG bytes. The Typst project root is set to the directory of the
/// markdown source so `#image("foo.png")` resolves relative to the
/// card.
fn compile(binary: &Path, src: &str, source_path: &Path) -> Result<Vec<u8>, TypstError> {
    // Build the on-disk source: preamble + user body. We isolate this
    // in a per-invocation temp dir so `typst compile` doesn't pollute
    // the cwd or the cache dir.
    // Create the temp dir inside the card's parent directory so that
    // the input file is contained within `--root` (required by Typst
    // ≥ 0.12) while still allowing `#image("foo.png")` to resolve
    // relative to the card.
    let root = source_path.parent().unwrap_or(Path::new("."));
    let work = mktempdir_in(root)?;
    let input = work.join("input.typ");
    {
        let mut h = fs::File::create(&input)?;
        h.write_all(PREAMBLE.as_bytes())?;
        h.write_all(src.as_bytes())?;
        // Trailing newline — harmless if the user already added one,
        // and keeps Typst happy when they didn't.
        if !src.ends_with('\n') {
            h.write_all(b"\n")?;
        }
    }
    let output = work.join("output.svg");

    let mut cmd = Command::new(binary);
    cmd.arg("compile")
        .arg("--format")
        .arg("svg")
        .arg("--root")
        .arg(root)
        .arg(&input)
        .arg(&output);

    let result = cmd.output();
    let outcome = match result {
        Ok(o) => o,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            let _ = fs::remove_dir_all(&work);
            return Err(TypstError::BinaryNotFound(binary.to_path_buf()));
        }
        Err(e) => {
            let _ = fs::remove_dir_all(&work);
            return Err(TypstError::Io(e));
        }
    };

    if !outcome.status.success() {
        let _ = fs::remove_dir_all(&work);
        let stderr = String::from_utf8_lossy(&outcome.stderr).into_owned();
        let stdout = String::from_utf8_lossy(&outcome.stdout).into_owned();
        // Typst writes diagnostics to stderr; stdout is usually empty
        // but include both so we don't lose anything.
        let combined = if stdout.trim().is_empty() {
            stderr
        } else {
            format!("{stderr}\n{stdout}")
        };
        return Err(TypstError::Compile(combined));
    }

    let bytes = fs::read(&output).map_err(|e| {
        TypstError::Compile(format!(
            "typst exited 0 but output.svg is unreadable: {e}"
        ))
    })?;

    let _ = fs::remove_dir_all(&work);
    Ok(bytes)
}

/// Atomically populate the cache directory. The `.ready` marker is
/// written last; a crash mid-write leaves the directory in a never-
/// ready state that future readers treat as a miss.
fn write_atomic(dir: &Path, svg: &[u8]) -> Result<(), TypstError> {
    fs::create_dir_all(dir)?;

    let svg_tmp = dir.join(format!(".{SVG_NAME}.tmp"));
    {
        let mut h = fs::File::create(&svg_tmp)?;
        h.write_all(svg)?;
        h.sync_all().ok();
    }
    fs::rename(&svg_tmp, dir.join(SVG_NAME))?;

    let marker_tmp = dir.join(format!(".{READY_MARKER}.tmp"));
    fs::File::create(&marker_tmp)?.sync_all().ok();
    fs::rename(&marker_tmp, dir.join(READY_MARKER))?;

    Ok(())
}

/// Build the [`RenderedBlock`] from a cache key + SVG bytes.
///
/// Build the [`RenderedBlock`] from rendered SVG bytes.
///
/// The asset filename is content-addressed over the output bytes
/// (matching `marki-media`'s scheme): two blocks that compile to the
/// same SVG dedupe in Anki's media collection. The HTML wraps the
/// `<img>` in a centered, max-width container; final visual sizing
/// is the theme's responsibility.
fn build_block(svg: Vec<u8>) -> RenderedBlock {
    let hex = blake3::hash(&svg).to_hex();
    let short = &hex.as_str()[..8];
    let filename = format!("marki-typst-{short}.svg");
    let html = format!(
        "<div class=\"marki-typst\" style=\"max-width:100%;margin:0 auto;\">\
         <img src=\"{filename}\" \
         style=\"max-width:100%;height:auto;display:block;margin:0 auto;\" alt=\"\"></div>"
    );

    RenderedBlock {
        front_html: html,
        back_html_extras: String::new(),
        assets: vec![EmittedAsset {
            filename,
            bytes: svg,
            mime: AssetMime::SvgXml,
        }],
    }
}

/// Make a fresh per-invocation temp directory under `parent`.
/// Removed by the caller after the subprocess returns.
fn mktempdir_in(parent: &Path) -> Result<PathBuf, TypstError> {
    use std::sync::atomic::{AtomicU64, Ordering};
    static N: AtomicU64 = AtomicU64::new(0);

    let p = parent.join(format!(
        ".marki-typst-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::SeqCst)
    ));
    fs::create_dir_all(&p)?;
    Ok(p)
}

/// Make a fresh per-invocation temp directory under
/// `$TMPDIR/marki-typst-{pid}-{counter}`. Removed by the caller after
/// the subprocess returns (success or failure).
fn mktempdir() -> Result<PathBuf, TypstError> {
    mktempdir_in(&std::env::temp_dir())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static N: AtomicU64 = AtomicU64::new(0);

    fn tempdir() -> PathBuf {
        let p = std::env::temp_dir().join(format!(
            "marki-typst-test-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = fs::remove_dir_all(&p);
        fs::create_dir_all(&p).unwrap();
        p
    }

    #[test]
    fn cache_key_is_stable() {
        let a = cache_key("= hello");
        let b = cache_key("= hello");
        assert_eq!(a, b);
        assert_eq!(a.len(), 16);
    }

    #[test]
    fn cache_key_changes_with_source() {
        assert_ne!(cache_key("= hello"), cache_key("= goodbye"));
    }

    #[test]
    fn write_atomic_marks_ready() {
        let root = tempdir();
        let dir = cache_dir(&root, "deadbeef00000000");
        write_atomic(&dir, b"<svg/>").unwrap();
        assert!(is_ready(&dir));
        let got = fs::read(dir.join(SVG_NAME)).unwrap();
        assert_eq!(got, b"<svg/>");
    }

    #[test]
    fn missing_marker_is_not_ready() {
        let root = tempdir();
        let dir = cache_dir(&root, "ffffffffffffffff");
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join(SVG_NAME), b"oops").unwrap();
        assert!(!is_ready(&dir));
    }

    #[test]
    fn build_block_emits_one_asset() {
        let block = build_block(b"<svg/>".to_vec());
        assert_eq!(block.assets.len(), 1);
        assert!(block.assets[0].filename.starts_with("marki-typst-"));
        assert!(block.assets[0].filename.ends_with(".svg"));
        assert_eq!(block.assets[0].mime, AssetMime::SvgXml);
        assert!(block.front_html.contains(&block.assets[0].filename));
        assert!(block.back_html_extras.is_empty());
    }

    #[test]
    fn build_block_filename_is_content_addressed() {
        let a = build_block(b"<svg>same</svg>".to_vec());
        let b = build_block(b"<svg>same</svg>".to_vec());
        let c = build_block(b"<svg>different</svg>".to_vec());
        assert_eq!(a.assets[0].filename, b.assets[0].filename);
        assert_ne!(a.assets[0].filename, c.assets[0].filename);
    }

    #[test]
    fn missing_binary_yields_binary_not_found() {
        let work = tempdir();
        let src_path = work.join("card.md");
        fs::write(&src_path, "").unwrap();
        let mut ctx = RenderCtx {
            source_path: &src_path,
            cache_dir: &work,
        };
        let r = run(
            Path::new("/definitely/does/not/exist/typst-binary"),
            "= hi",
            &mut ctx,
        );
        match r {
            Err(TypstError::BinaryNotFound(_)) => {}
            other => panic!("expected BinaryNotFound, got {other:?}"),
        }
    }

    /// End-to-end test using a fake `typst` shim that just writes a
    /// fixed SVG to the output path. We don't depend on the real
    /// Typst binary in the test harness — the subprocess contract
    /// (args, exit code, output path) is what we want to exercise.
    ///
    /// `#!/bin/sh` (and POSIX shell syntax) keeps this working in the
    /// Nix build sandbox, where `/usr/bin/env` is not present.
    #[test]
    fn fake_binary_round_trip() {
        let work = tempdir();
        let shim = work.join("typst-shim.sh");
        fs::write(
            &shim,
            // Last positional arg is the output path. POSIX shells
            // don't have ${@: -1}; use `eval` + `$#` instead.
            "#!/bin/sh\nset -e\neval \"out=\\${$#}\"\nprintf '%s' '<svg data-shim=\"yes\"/>' > \"$out\"\n",
        )
        .unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = fs::metadata(&shim).unwrap().permissions();
            perms.set_mode(0o755);
            fs::set_permissions(&shim, perms).unwrap();
        }

        let card = work.join("card.md");
        fs::write(&card, "").unwrap();
        let cache = work.join("cache");
        fs::create_dir_all(&cache).unwrap();

        let mut ctx = RenderCtx {
            source_path: &card,
            cache_dir: &cache,
        };
        let block = run(&shim, "= ignored", &mut ctx).unwrap();
        assert_eq!(block.assets.len(), 1);
        assert_eq!(block.assets[0].bytes, b"<svg data-shim=\"yes\"/>");

        // Second run: cache hit, even if the binary is removed.
        fs::remove_file(&shim).unwrap();
        let block2 = run(&shim, "= ignored", &mut ctx).unwrap();
        assert_eq!(block2.assets[0].bytes, b"<svg data-shim=\"yes\"/>");
        assert_eq!(block.assets[0].filename, block2.assets[0].filename);
    }

    #[test]
    fn fake_binary_failure_propagates_stderr() {
        let work = tempdir();
        let shim = work.join("typst-fail.sh");
        fs::write(
            &shim,
            "#!/bin/sh\necho 'error: bad syntax at line 4' 1>&2\nexit 1\n",
        )
        .unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = fs::metadata(&shim).unwrap().permissions();
            perms.set_mode(0o755);
            fs::set_permissions(&shim, perms).unwrap();
        }

        let card = work.join("card.md");
        fs::write(&card, "").unwrap();
        let cache = work.join("cache");
        fs::create_dir_all(&cache).unwrap();
        let mut ctx = RenderCtx {
            source_path: &card,
            cache_dir: &cache,
        };
        let err = run(&shim, "broken source", &mut ctx).unwrap_err();
        match err {
            TypstError::Compile(msg) => assert!(msg.contains("bad syntax")),
            other => panic!("expected Compile, got {other:?}"),
        }
    }
}
