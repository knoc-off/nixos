//! Low-resolution PNG snapshots of the SVG figures on a card side, so an
//! agent can look at what it made without a browser.
//!
//! Only SVG assets are drawn (maps, typst). A map's layers are stacked
//! like the card shows them: `data-reveal="fade"` layers only on the back.

use marki_render::Asset;
use regex::Regex;
use resvg::{tiny_skia, usvg};
use std::sync::LazyLock;

/// One rasterized figure: the stacked SVG files and the PNG bytes.
pub struct Figure {
    pub layers: Vec<String>,
    pub png: Vec<u8>,
}

static IMG: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"<img\b[^>]*>"#).unwrap());
static SRC: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"\bsrc="([^"]+)""#).unwrap());
static MAP_LAYER: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^(marki-map-[0-9a-f]+)-").unwrap());

/// The SVG figures in `html`, in document order, each at most `max_px` on
/// its long side. `back` shows reveal layers. A figure that appears twice
/// (the back repeating the front) is drawn once.
pub fn figures(html: &str, assets: &[Asset], back: bool, max_px: u32) -> Vec<Result<Figure, String>> {
    // Group consecutive layers of one map; every other SVG is its own figure.
    let mut stacks: Vec<(Option<String>, Vec<String>)> = Vec::new();
    for tag in IMG.find_iter(html).map(|m| m.as_str()) {
        let Some(src) = SRC.captures(tag).map(|c| c[1].to_string()) else { continue };
        if !src.ends_with(".svg") || (!back && tag.contains(r#"data-reveal="fade""#)) {
            continue;
        }
        let map = MAP_LAYER.captures(&src).map(|c| c[1].to_string());
        match stacks.last_mut() {
            // A repeated layer means the same map again (front copied onto the back).
            Some((Some(m), layers)) if map.as_ref() == Some(m) && !layers.contains(&src) => layers.push(src),
            _ => stacks.push((map, vec![src])),
        }
    }
    let mut seen = std::collections::HashSet::new();
    stacks
        .into_iter()
        .filter(|(_, layers)| seen.insert(layers.clone()))
        .map(|(_, layers)| {
            let svgs = layers
                .iter()
                .map(|l| {
                    assets
                        .iter()
                        .find(|a| &a.filename == l)
                        .map(|a| a.bytes.as_slice())
                        .ok_or_else(|| format!("{l}: not rendered by this card"))
                })
                .collect::<Result<Vec<_>, _>>()?;
            Ok(Figure { png: stack_png(&svgs, max_px)?, layers })
        })
        .collect()
}

/// Parse options with one embedded font standing in for every family, so
/// map labels (`<text font-family="sans-serif">`) show up in previews.
/// Anki renders the real SVG with the browser's own fonts.
static OPTS: LazyLock<usvg::Options<'static>> = LazyLock::new(|| {
    let mut opts = usvg::Options::default();
    let db = opts.fontdb_mut();
    db.load_font_data(include_bytes!(env!("MARKI_FONT")).to_vec());
    let family = db.faces().next().and_then(|f| f.families.first()).map(|(n, _)| n.clone());
    if let Some(family) = family {
        db.set_sans_serif_family(&family);
        db.set_serif_family(&family);
        db.set_monospace_family(&family);
        opts.font_family = family;
    }
    opts
});

/// Draw `svgs` on top of each other (sized by the first) into one PNG.
pub fn stack_png(svgs: &[&[u8]], max_px: u32) -> Result<Vec<u8>, String> {
    let opts = &*OPTS;
    let trees = svgs
        .iter()
        .map(|b| usvg::Tree::from_data(b, opts).map_err(|e| format!("svg: {e}")))
        .collect::<Result<Vec<_>, _>>()?;
    let size = trees.first().ok_or("no svg")?.size();
    let scale = (max_px as f32 / size.width().max(size.height())).min(1.0);
    let (w, h) = ((size.width() * scale).ceil() as u32, (size.height() * scale).ceil() as u32);
    let mut pixmap = tiny_skia::Pixmap::new(w.max(1), h.max(1)).ok_or("empty image")?;
    // White under transparent layers, as on a default Anki card.
    pixmap.fill(tiny_skia::Color::WHITE);
    for t in &trees {
        resvg::render(t, tiny_skia::Transform::from_scale(scale, scale), &mut pixmap.as_mut());
    }
    pixmap.encode_png().map_err(|e| format!("png: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use marki_render::AssetMime;

    fn svg(name: &str, body: &str) -> Asset {
        Asset {
            filename: name.into(),
            bytes: format!(r#"<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100">{body}</svg>"#).into_bytes(),
            mime: AssetMime::SvgXml,
        }
    }

    fn pixel(png: &[u8], x: u32, y: u32) -> [u8; 4] {
        let p = tiny_skia::Pixmap::decode_png(png).unwrap();
        let c = p.pixel(x, y).unwrap();
        [c.red(), c.green(), c.blue(), c.alpha()]
    }

    #[test]
    fn map_layers_stack_and_fade_only_on_the_back() {
        let assets = [
            svg("marki-map-ab12-base.svg", r##"<rect width="200" height="100" fill="#00f"/>"##),
            svg("marki-map-ab12-answer.svg", r##"<rect width="100" height="100" fill="#f00"/>"##),
        ];
        let html = r#"<div class="marki-map"><img data-reveal="none" src="marki-map-ab12-base.svg"><img data-reveal="fade" src="marki-map-ab12-answer.svg"></div>"#;

        let front = figures(html, &assets, false, 512);
        let f = front[0].as_ref().unwrap();
        assert_eq!(f.layers, ["marki-map-ab12-base.svg"]);
        assert_eq!(pixel(&f.png, 10, 10), [0, 0, 255, 255]);

        // The back repeats the front map: still one figure, now with the answer.
        let back = figures(&format!("{html}<hr>{html}"), &assets, true, 100);
        assert_eq!(back.len(), 1);
        let b = back[0].as_ref().unwrap();
        assert_eq!(b.layers.len(), 2);
        assert_eq!(pixel(&b.png, 10, 10), [255, 0, 0, 255]);
        assert_eq!(pixel(&b.png, 90, 10), [0, 0, 255, 255], "scaled to 100x50");
    }

    #[test]
    fn missing_asset_is_an_error_not_a_panic() {
        let figs = figures(r#"<img src="x.svg"><img src="photo.png">"#, &[], true, 512);
        assert_eq!(figs.len(), 1);
        assert!(figs[0].as_ref().err().unwrap().contains("x.svg"));
    }

    #[test]
    fn text_is_drawn_with_the_embedded_font() {
        let a = svg("t.svg", r##"<text x="10" y="60" font-size="60" font-family="sans-serif" fill="#000">MMMM</text>"##);
        let png = stack_png(&[&a.bytes], 200).unwrap();
        let p = tiny_skia::Pixmap::decode_png(&png).unwrap();
        let dark = p.pixels().iter().filter(|c| c.red() < 100).count();
        assert!(dark > 500, "label glyphs should rasterize, got {dark} dark pixels");
    }
}
