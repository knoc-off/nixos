//! Whole-card PNG previews through a headless Chromium (`browser_binary`),
//! so an agent sees a card the way Anki's webview draws it: text, cloze,
//! tables, highlighted code, images and maps together, with the model CSS.
//!
//! Each card side is written to a scratch dir with its assets and
//! screenshotted by one `chromium --headless --screenshot` run; the sides of
//! a note render in parallel. The page loads MathJax from its CDN, so math
//! only typesets when the browser can reach it (otherwise it shows as TeX).

use anyhow::{Context, Result, bail, ensure};
use marki_render::Asset;
use resvg::tiny_skia;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

/// Viewport width in CSS px: about a phone held upright, where most
/// reviewing happens.
const WIDTH: u32 = 480;
/// Tallest side rendered; anything below is cut off.
const MAX_HEIGHT: u32 = 2000;
const TIMEOUT: Duration = Duration::from_secs(30);

/// One page per card side, `(label, html)`, screenshotted with `css` and
/// `assets`. Results are in input order; a failed side is an `Err` line.
pub fn screenshots(
    bin: &Path,
    css: &str,
    sides: &[(String, String)],
    assets: &[Asset],
) -> Result<Vec<Result<Vec<u8>, String>>> {
    let dir = crate::project::TempDir::new("shot")?;
    for a in assets {
        std::fs::write(dir.path().join(&a.filename), &a.bytes)
            .with_context(|| format!("write {}", a.filename))?;
    }
    Ok(std::thread::scope(|s| {
        let jobs: Vec<_> = sides
            .iter()
            .enumerate()
            .map(|(i, (_, html))| {
                let dir = dir.path();
                s.spawn(move || shot(bin, dir, i, &page(css, html)).map_err(|e| format!("{e:#}")))
            })
            .collect();
        jobs.into_iter().map(|j| j.join().unwrap_or_else(|_| Err("screenshot thread panicked".into()))).collect()
    }))
}

/// A card side as Anki shows it: the model CSS, the HTML inside `.card`.
fn page(css: &str, html: &str) -> String {
    format!(
        "<!doctype html><meta charset=\"utf-8\"><style>{css}\nhtml,body{{margin:0}}</style>\
         <script>MathJax={{tex:{{inlineMath:[['\\\\(','\\\\)']]}}}}</script>\
         <script async src=\"https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js\"></script>\
         <div class=\"card\">{html}</div>"
    )
}

fn shot(bin: &Path, dir: &Path, i: usize, html: &str) -> Result<Vec<u8>> {
    let page = dir.join(format!("side-{i}.html"));
    let png = dir.join(format!("side-{i}.png"));
    std::fs::write(&page, html)?;
    // --no-sandbox: Chromium's sandbox needs user namespaces, which the
    // hardened service (RestrictNamespaces) doesn't allow. The page is the
    // agent's own card, rendered in a throwaway profile.
    // --no-zygote: under the service's syscall filter the zygote's forked
    // children never answer, so the GPU process "fails to launch" and
    // Chromium aborts, --disable-gpu notwithstanding.
    let mut child = Command::new(bin)
        .args([
            "--headless",
            "--no-sandbox",
            "--no-zygote",
            "--disable-gpu",
            "--disable-dev-shm-usage",
            "--hide-scrollbars",
            "--no-first-run",
            "--virtual-time-budget=5000",
            &format!("--window-size={WIDTH},{MAX_HEIGHT}"),
        ])
        .arg(format!("--user-data-dir={}", dir.join(format!("profile-{i}")).display()))
        .arg(format!("--screenshot={}", png.display()))
        .arg(format!("file://{}", page.display()))
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .with_context(|| format!("run browser_binary {}", bin.display()))?;
    let start = Instant::now();
    let status = loop {
        if let Some(s) = child.try_wait()? {
            break s;
        }
        if start.elapsed() > TIMEOUT {
            let _ = child.kill();
            bail!("browser timed out after {}s", TIMEOUT.as_secs());
        }
        std::thread::sleep(Duration::from_millis(50));
    };
    let bytes = std::fs::read(&png).ok();
    let Some(bytes) = bytes.filter(|_| status.success()) else {
        let mut err = String::new();
        if let Some(mut e) = child.stderr.take() {
            use std::io::Read;
            let _ = e.read_to_string(&mut err);
        }
        let tail: Vec<&str> = err.lines().rev().take(5).collect();
        bail!("browser failed ({status}): {}", tail.into_iter().rev().collect::<Vec<_>>().join("\n"));
    };
    crop_bottom(&bytes)
}

/// Cut the empty viewport below the card: every bottom row that is one
/// colour, the background's, down to a small margin.
fn crop_bottom(png: &[u8]) -> Result<Vec<u8>> {
    let p = tiny_skia::Pixmap::decode_png(png).context("decode screenshot")?;
    let (w, h) = (p.width() as usize, p.height() as usize);
    let px = p.pixels();
    let bg = px[(h - 1) * w];
    let blank = |y: usize| px[y * w..(y + 1) * w].iter().all(|c| *c == bg);
    let mut last = h;
    while last > 1 && blank(last - 1) {
        last -= 1;
    }
    let keep = (last + 16).min(h) as u32;
    ensure!(keep > 0, "empty screenshot");
    let cut = p
        .clone_rect(tiny_skia::IntRect::from_xywh(0, 0, w as u32, keep).context("crop")?)
        .context("crop")?;
    cut.encode_png().map_err(|e| anyhow::anyhow!("png: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crop_keeps_content_plus_margin() {
        let mut p = tiny_skia::Pixmap::new(10, 200).unwrap();
        p.fill(tiny_skia::Color::WHITE);
        let mut paint = tiny_skia::Paint::default();
        paint.set_color_rgba8(0, 0, 0, 255);
        p.fill_rect(tiny_skia::Rect::from_xywh(0.0, 30.0, 10.0, 10.0).unwrap(), &paint, tiny_skia::Transform::identity(), None);
        let out = tiny_skia::Pixmap::decode_png(&crop_bottom(&p.encode_png().unwrap()).unwrap()).unwrap();
        assert_eq!((out.width(), out.height()), (10, 56));
    }

    /// Needs a real browser: MARKI_TEST_BROWSER=/path/to/chromium.
    #[test]
    fn screenshots_a_card_side() {
        let Some(bin) = std::env::var_os("MARKI_TEST_BROWSER") else {
            eprintln!("skip: MARKI_TEST_BROWSER not set");
            return;
        };
        let sides = [("front".to_string(), "<h1 style=\"color:red\">Hello</h1>".to_string())];
        let out = screenshots(Path::new(&bin), "", &sides, &[]).unwrap();
        let png = out[0].as_ref().unwrap();
        let p = tiny_skia::Pixmap::decode_png(png).unwrap();
        assert_eq!(p.width(), WIDTH);
        assert!(p.height() < 300, "cropped, got {}", p.height());
        assert!(p.pixels().iter().any(|c| c.red() > 200 && c.green() < 80), "red heading drawn");
    }
}
