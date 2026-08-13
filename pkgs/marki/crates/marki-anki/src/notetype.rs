//! Building marki notetypes (notetype + fields + templates) as the exact
//! protobuf blobs Anki stores.
//!
//! A marki model `X` with card names `[A, B, ...]` becomes the notetype
//! `marki:X`. Each card contributes a Front/Back field pair, so card `i`
//! owns fields at ords `2*i` (front) and `2*i+1` (back), and its template
//! renders `{{<Card>Front}}` / `{{<Card>Back}}`. This mirrors a stock
//! "Basic" notetype (latex/font defaults, `original_stock_kind = Basic`)
//! cloned per marki model, which is what real marki collections contain.

use crate::proto::generic::UInt32;
use crate::proto::notetypes::Notetype;
use crate::proto::notetypes::notetype::config::CardRequirement;
use crate::proto::notetypes::notetype::config::card_requirement::Kind as ReqKind;
use crate::proto::notetypes::notetype::{Config, Field, Template, field, template};
use crate::proto::notetypes::stock_notetype::OriginalStockKind;

/// Anki's stock LaTeX preamble/closer (`rslib` stock Basic). Kept verbatim
/// so generated notetypes match Anki-authored ones and Check Database sees
/// nothing to "fix".
pub const LATEX_PRE: &str = "\\documentclass[12pt]{article}\n\\special{papersize=3in,5in}\n\\usepackage[utf8]{inputenc}\n\\usepackage{amssymb,amsmath}\n\\pagestyle{empty}\n\\setlength{\\parindent}{0in}\n\\begin{document}\n";
pub const LATEX_POST: &str = "\\end{document}";

const DEFAULT_FIELD_FONT: &str = "Arial";
const DEFAULT_FIELD_SIZE: u32 = 20;

/// A marki model to materialize as a notetype. `name` is the bare model name
/// (`geographic-location`); the notetype is stored as `marki:<name>`.
pub struct ModelSpec {
    pub name: String,
    pub css: String,
    pub card_names: Vec<String>,
}

impl ModelSpec {
    pub fn notetype_name(&self) -> String {
        format!("marki:{}", self.name)
    }

    /// Field names in ord order: `[A]Front, [A]Back, [B]Front, ...`.
    pub fn field_names(&self) -> Vec<String> {
        let mut out = Vec::with_capacity(self.card_names.len() * 2);
        for card in &self.card_names {
            out.push(format!("{card}Front"));
            out.push(format!("{card}Back"));
        }
        out
    }
}

/// FNV-1a over the bytes, used to derive stable field/template ids from
/// `(ntid, kind, ord)` so re-running marki does not churn ids.
fn fnv1a(seed: &[u8]) -> i64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in seed {
        h ^= *b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    h as i64
}

fn stable_id(ntid: i64, kind: u8, ord: u32) -> i64 {
    let mut buf = Vec::with_capacity(13);
    buf.extend_from_slice(&ntid.to_le_bytes());
    buf.push(kind);
    buf.extend_from_slice(&ord.to_le_bytes());
    fnv1a(&buf)
}

/// The `Notetype.Config` blob for `notetypes.config`. `reqs[i]` points card
/// `i` at its front field ord `2*i` (see module docs).
pub fn notetype_config(css: &str, card_count: usize) -> Config {
    let reqs = (0..card_count as u32)
        .map(|i| CardRequirement {
            card_ord: i,
            kind: ReqKind::Any as i32,
            field_ords: vec![2 * i],
        })
        .collect();
    Config {
        kind: 0, // Normal
        sort_field_idx: 0,
        css: css.to_string(),
        target_deck_id_unused: 0,
        latex_pre: LATEX_PRE.to_string(),
        latex_post: LATEX_POST.to_string(),
        latex_svg: false,
        reqs,
        original_stock_kind: OriginalStockKind::Basic as i32,
        original_id: None,
        other: Vec::new(),
    }
}

/// A `fields.config` blob (stock Basic field defaults).
pub fn field_config(id: i64) -> field::Config {
    field::Config {
        sticky: false,
        rtl: false,
        font_name: DEFAULT_FIELD_FONT.to_string(),
        font_size: DEFAULT_FIELD_SIZE,
        description: String::new(),
        plain_text: false,
        collapsed: false,
        exclude_from_search: false,
        id: Some(id),
        tag: None,
        prevent_deletion: false,
        other: Vec::new(),
    }
}

/// A `templates.config` blob rendering `{{<card>Front}}` / `{{<card>Back}}`.
pub fn template_config(card_name: &str, id: i64) -> template::Config {
    template::Config {
        q_format: format!("{{{{{card_name}Front}}}}"),
        a_format: format!("{{{{{card_name}Back}}}}"),
        q_format_browser: String::new(),
        a_format_browser: String::new(),
        target_deck_id: 0,
        browser_font_name: String::new(),
        browser_font_size: 0,
        id: Some(id),
        other: Vec::new(),
    }
}

/// The rows to write for one notetype: the notetype config plus every field
/// and template with its ord/name/blob. Ids are derived from `ntid` so the
/// output is deterministic.
pub struct BuiltNotetype {
    pub id: i64,
    pub name: String,
    pub config: Config,
    /// `(ord, name, config)` for `fields`.
    pub fields: Vec<(u32, String, field::Config)>,
    /// `(ord, name, config)` for `templates`.
    pub templates: Vec<(u32, String, template::Config)>,
}

/// Build every row for `spec` under the assigned `ntid`.
pub fn build(spec: &ModelSpec, ntid: i64) -> BuiltNotetype {
    let fields = spec
        .field_names()
        .into_iter()
        .enumerate()
        .map(|(i, name)| {
            let ord = i as u32;
            (ord, name, field_config(stable_id(ntid, b'F', ord)))
        })
        .collect();
    let templates = spec
        .card_names
        .iter()
        .enumerate()
        .map(|(i, card)| {
            let ord = i as u32;
            (ord, card.clone(), template_config(card, stable_id(ntid, b'T', ord)))
        })
        .collect();
    BuiltNotetype {
        id: ntid,
        name: spec.notetype_name(),
        config: notetype_config(&spec.css, spec.card_names.len()),
        fields,
        templates,
    }
}

/// The full nested `Notetype` message (used by sync/RPC, not stored on disk
/// as one blob). Handy for tests that want to see the assembled shape.
pub fn assemble(built: &BuiltNotetype, mtime_secs: i64, usn: i32) -> Notetype {
    Notetype {
        id: built.id,
        name: built.name.clone(),
        mtime_secs,
        usn,
        config: Some(built.config.clone()),
        fields: built
            .fields
            .iter()
            .map(|(ord, name, cfg)| Field {
                ord: Some(UInt32 { val: *ord }),
                name: name.clone(),
                config: Some(cfg.clone()),
            })
            .collect(),
        templates: built
            .templates
            .iter()
            .map(|(ord, name, cfg)| Template {
                ord: Some(UInt32 { val: *ord }),
                name: name.clone(),
                mtime_secs,
                usn,
                config: Some(cfg.clone()),
            })
            .collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn geo_spec() -> ModelSpec {
        ModelSpec {
            name: "geographic-location".into(),
            css: ".card{}".into(),
            card_names: vec![
                "Locate".into(),
                "Identify".into(),
                "FlagToCountry".into(),
                "CountryToFlag".into(),
            ],
        }
    }

    #[test]
    fn field_and_card_layout_matches_marki_convention() {
        let spec = geo_spec();
        assert_eq!(spec.notetype_name(), "marki:geographic-location");
        assert_eq!(
            spec.field_names(),
            vec![
                "LocateFront",
                "LocateBack",
                "IdentifyFront",
                "IdentifyBack",
                "FlagToCountryFront",
                "FlagToCountryBack",
                "CountryToFlagFront",
                "CountryToFlagBack",
            ]
        );
    }

    #[test]
    fn reqs_use_2i_stride() {
        let cfg = notetype_config(".card{}", 4);
        let ords: Vec<(u32, Vec<u32>)> = cfg
            .reqs
            .iter()
            .map(|r| (r.card_ord, r.field_ords.clone()))
            .collect();
        assert_eq!(
            ords,
            vec![(0, vec![0]), (1, vec![2]), (2, vec![4]), (3, vec![6])]
        );
        assert!(cfg.reqs.iter().all(|r| r.kind == ReqKind::Any as i32));
    }

    #[test]
    fn template_formats_reference_matching_fields() {
        let t = template_config("Locate", 1);
        assert_eq!(t.q_format, "{{LocateFront}}");
        assert_eq!(t.a_format, "{{LocateBack}}");
    }

    #[test]
    fn ids_are_stable_for_same_ntid() {
        let a = build(&geo_spec(), 999);
        let b = build(&geo_spec(), 999);
        assert_eq!(a.fields[0].2.id, b.fields[0].2.id);
        assert_eq!(a.templates[2].2.id, b.templates[2].2.id);
        // Distinct ords/kinds get distinct ids.
        assert_ne!(a.fields[0].2.id, a.fields[1].2.id);
        assert_ne!(a.fields[0].2.id, a.templates[0].2.id);
    }
}
