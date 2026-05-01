//! Build the HTML wrapper that embeds rendered map layers in a card.
//!
//! Output layout (front side):
//!
//! ```html
//! <div class="marki-map"
//!      style="max-width:Wpx;width:100%;aspect-ratio:W/H;position:relative;display:block;margin:0 auto;">
//!   <style>
//!     .marki-map [data-reveal="fade"]{
//!       opacity:0; transition:opacity .5s ease;
//!     }
//!   </style>
//!   <img class="marki-map-layer"
//!        data-layer="base" data-reveal="none"
//!        src="<base.svg basename>"
//!        style="position:absolute;inset:0;width:100%;height:100%;">
//!   <img class="marki-map-layer"
//!        data-layer="answer" data-reveal="fade"
//!        src="<answer.svg basename>"
//!        style="position:absolute;inset:0;width:100%;height:100%;">
//! </div>
//! ```
//!
//! The container uses `max-width` + `aspect-ratio` instead of fixed
//! pixel dimensions, so the map scales down responsively on narrow
//! viewports (AnkiDroid, AnkiMobile) without horizontal scroll. SVGs
//! re-render crisply at any size. `margin:0 auto` centres the map
//! horizontally on wider viewports.
//!
//! The renderer also returns a `back_html_extras` `<style>` block that
//! Anki appends to the back side. That block overrides the front-side
//! rule to `opacity:1`, so on flip every `data-reveal="fade"` layer
//! fades into view.
//!
//! Pure CSS — no JavaScript — works on AnkiDroid, AnkiMobile, AnkiWeb.

use crate::dsl::{LayerSpec, RevealMode};
use indexmap::IndexMap;
use std::collections::BTreeMap;

/// One layer's emitted SVG, plus how it should reveal.
pub struct EmbedLayer<'a> {
    pub name: &'a str,
    /// Anki media filename (basename) the layer is stored under.
    pub media_filename: &'a str,
    pub reveal: RevealMode,
}

pub struct EmbedOutput {
    pub front_html: String,
    pub back_html_extras: String,
}

/// Build the HTML embed for a map.
///
/// The order of `layers` matters: earlier entries are drawn underneath
/// later ones. Convention is `base` first.
pub fn embed_layers(width: u32, height: u32, layers: &[EmbedLayer<'_>]) -> EmbedOutput {
    // Front-side: container, hide-on-front rule, then one <img> per layer.
    let mut front = String::with_capacity(512);
    front.push_str(&format!(
        "<div class=\"marki-map\" \
         style=\"max-width:{width}px;width:100%;aspect-ratio:{width}/{height};\
         position:relative;display:block;margin:0 auto;\">"
    ));
    // Inline <style> that hides every faded layer on the front.
    front.push_str(
        "<style>\
         .marki-map [data-reveal=\"fade\"]{\
         opacity:0;transition:opacity .5s ease;\
         }\
         </style>"
    );

    for l in layers {
        let reveal_attr = match l.reveal {
            RevealMode::None => "none",
            RevealMode::Fade => "fade",
        };
        front.push_str(&format!(
            "<img class=\"marki-map-layer\" \
             data-layer=\"{layer}\" data-reveal=\"{reveal}\" \
             src=\"{src}\" \
             style=\"position:absolute;inset:0;width:100%;height:100%;pointer-events:none;\" \
             alt=\"\">",
            layer = escape_attr(l.name),
            reveal = reveal_attr,
            src = escape_attr(l.media_filename),
        ));
    }

    front.push_str("</div>");

    // Back side: only emit a <style> block if at least one layer fades.
    let any_fade = layers
        .iter()
        .any(|l| matches!(l.reveal, RevealMode::Fade));
    let back = if any_fade {
        "<style>\
         .marki-map [data-reveal=\"fade\"]{\
         opacity:1;\
         }\
         </style>".to_string()
    } else {
        String::new()
    };

    EmbedOutput {
        front_html: front,
        back_html_extras: back,
    }
}

/// Compute the effective reveal mode for every layer, applying the
/// "base = none, others = fade" default rule. Returns a map keyed by
/// layer name.
pub fn resolve_reveals(
    layers: &IndexMap<String, LayerSpec>,
) -> BTreeMap<String, RevealMode> {
    layers
        .iter()
        .map(|(name, spec)| (name.clone(), spec.effective_reveal(name)))
        .collect()
}

fn escape_attr(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '&' => out.push_str("&amp;"),
            '"' => out.push_str("&quot;"),
            c => out.push(c),
        }
    }
    out
}


#[cfg(test)]
mod tests {
    use super::*;
    use crate::dsl::parse_map_spec;

    #[test]
    fn embed_with_one_fade_layer_yields_back_style() {
        let layers = vec![
            EmbedLayer {
                name: "base",
                media_filename: "base.svg",
                reveal: RevealMode::None,
            },
            EmbedLayer {
                name: "answer",
                media_filename: "answer.svg",
                reveal: RevealMode::Fade,
            },
        ];
        let out = embed_layers(600, 400, &layers);
        // Front contains both <img>s and the hide-rule.
        assert!(out.front_html.contains("marki-map"));
        assert!(out.front_html.contains("base.svg"));
        assert!(out.front_html.contains("answer.svg"));
        assert!(out.front_html.contains("opacity:0"));
        assert!(out.front_html.contains("data-reveal=\"none\""));
        assert!(out.front_html.contains("data-reveal=\"fade\""));
        // Responsive: max-width + aspect-ratio, centred.
        assert!(out.front_html.contains("max-width:600px"));
        assert!(out.front_html.contains("aspect-ratio:600/400"));
        assert!(out.front_html.contains("width:100%"));
        assert!(out.front_html.contains("margin:0 auto"));
        assert!(!out.front_html.contains("width:600px;height:400px"));
        // Back-side <style> overrides to opacity:1.
        assert!(out.back_html_extras.contains("opacity:1"));
    }

    #[test]
    fn embed_without_fade_skips_back_style() {
        let layers = vec![EmbedLayer {
            name: "base",
            media_filename: "base.svg",
            reveal: RevealMode::None,
        }];
        let out = embed_layers(100, 100, &layers);
        assert!(out.back_html_extras.is_empty());
    }

    #[test]
    fn reveal_resolution_matches_dsl_default() {
        let src = r#"
size = [600, 400]

[layers.base]
features = ["coastline"]

[layers.answer]
features = ["country/DEU"]
"#;
        let spec = parse_map_spec(src).unwrap();
        let r = resolve_reveals(&spec.layers);
        assert_eq!(r["base"], RevealMode::None);
        assert_eq!(r["answer"], RevealMode::Fade);
    }
}
