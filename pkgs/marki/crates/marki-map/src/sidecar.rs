//! JSON sidecar that ships alongside SVG layers.
//!
//! Per the RFC, "a JSON sidecar per map lists layers, dimensions,
//! projection, and any per-layer hints". The card-side JS doesn't yet
//! consume it (M1 is pure CSS), but the file is shipped to Anki media
//! anyway so a future card-side renderer can opt in.
//!
//! The sidecar is also re-read by the pipeline on a render-cache hit:
//! it carries the actual rendered `width`/`height` (which may differ
//! from the author's `requested_size` budget — see `pipeline::fit_canvas`).

use crate::dsl::RevealMode;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct Sidecar {
    /// Actual rendered canvas size (px). Always ≤ `requested_size`.
    pub width: u32,
    pub height: u32,
    /// The author's `size = [W, H]` budget. The renderer treats this
    /// as a max — the actual canvas is sized to match the projected
    /// aspect of the data.
    pub requested_size: [u32; 2],
    pub projection: String,
    pub layers: Vec<SidecarLayer>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SidecarLayer {
    pub name: String,
    pub filename: String,
    pub reveal: RevealMode,
}

pub fn render(sidecar: &Sidecar) -> serde_json::Result<Vec<u8>> {
    serde_json::to_vec_pretty(sidecar)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Sidecar {
        Sidecar {
            width: 600,
            height: 280,
            requested_size: [600, 400],
            projection: "mercator".into(),
            layers: vec![SidecarLayer {
                name: "base".into(),
                filename: "base.svg".into(),
                reveal: RevealMode::None,
            }],
        }
    }

    #[test]
    fn render_round_trips() {
        let bytes = render(&sample()).unwrap();
        let text = String::from_utf8(bytes).unwrap();
        assert!(text.contains("\"reveal\": \"none\""));
        assert!(text.contains("\"requested_size\""));
        assert!(text.contains("\"projection\": \"mercator\""));
    }

    #[test]
    fn round_trip_through_json() {
        let bytes = render(&sample()).unwrap();
        let parsed: Sidecar = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(parsed.width, 600);
        assert_eq!(parsed.height, 280);
        assert_eq!(parsed.requested_size, [600, 400]);
        assert_eq!(parsed.projection, "mercator");
        assert_eq!(parsed.layers.len(), 1);
        assert_eq!(parsed.layers[0].name, "base");
    }
}
