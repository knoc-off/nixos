//! Authoring docs served to agents (`marki_docs` tool, `marki://docs/*`
//! resources). `cards` and `models` live here; each block renderer ships
//! its own doc (`Renderer::docs`, its crate README), so a new block brings
//! its docs along. All are the repo's own markdown, embedded at build time.

use anyhow::{Result, bail};

use crate::render::Registry;

const README: &str = include_str!("../../../README.md");

/// One-line summaries for topic lists; a block without one gets a generic line.
const SUMMARIES: &[(&str, &str)] = &[
    ("cards", "card file format: sections, tags, cloze, decks, code blocks, math"),
    ("map", "```map blocks: highlight countries/regions/OSM features on an SVG map"),
    ("media", "```media blocks: images and audio from .marki/media or media sources"),
    ("typst", "```typst blocks: typeset diagrams/formulas compiled to SVG"),
    ("models", "Lua card models (custom card types)"),
];

/// `(topic, summary)` for every doc this server has: cards, the active
/// blocks, models.
pub fn topics(reg: &Registry) -> Vec<(String, String)> {
    let summary = |t: &str| {
        SUMMARIES
            .iter()
            .find(|(n, _)| *n == t)
            .map_or_else(|| format!("```{t} blocks"), |(_, s)| s.to_string())
    };
    std::iter::once("cards")
        .chain(block_langs(reg))
        .chain(std::iter::once("models"))
        .map(|t| (t.to_string(), summary(t)))
        .collect()
}

/// Active block languages that ship a doc.
pub fn block_langs(reg: &Registry) -> impl Iterator<Item = &'static str> + '_ {
    reg.external_langs().iter().copied().filter(|l| reg.docs(l).is_some())
}

pub fn doc(reg: &Registry, topic: &str) -> Result<String> {
    Ok(match topic {
        "cards" => {
            let blocks: Vec<String> = block_langs(reg).map(|l| format!("marki_docs(\"{l}\")")).collect();
            // Repo-relative links mean nothing over MCP; point at the topics.
            let mut body = section(README, "## Writing cards", "## Formatting rules")
                .replace("[models/](models/README.md)", "marki_docs(\"models\")");
            for l in ["map", "media", "typst"] {
                body = body.replace(&format!("[marki-{l}](crates/marki-{l}/README.md)"), &format!("marki_docs(\"{l}\")"));
            }
            format!(
                "{body}\nBlock syntax on this server: {}. Custom card types: marki_docs(\"models\").\n",
                if blocks.is_empty() { "none enabled".into() } else { blocks.join(", ") }
            )
        }
        "models" => crate::scripting::MODEL_API.into(),
        t => match reg.docs(t) {
            Some(d) => d.into(),
            None => bail!(
                "unknown topic {t:?}; topics: {}",
                topics(reg).into_iter().map(|(t, _)| t).collect::<Vec<_>>().join(", ")
            ),
        },
    })
}

/// Doc topics for the renderer blocks a card source uses (```map etc.).
pub fn block_topics(reg: &Registry, source: &str) -> Vec<&'static str> {
    block_langs(reg)
        .filter(|t| {
            source
                .lines()
                .any(|l| l.trim_start().strip_prefix("```").is_some_and(|lang| lang.trim() == *t))
        })
        .collect()
}

fn section<'a>(text: &'a str, start: &str, end: &str) -> &'a str {
    let from = text.find(start).unwrap_or(0);
    let to = text[from..].find(end).map_or(text.len(), |i| from + i);
    &text[from..to]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;

    fn registry() -> Registry {
        let mut cfg = Config::default();
        cfg.typst_binary = Some("typst".into());
        crate::project::build_registry(&cfg)
    }

    #[test]
    fn every_topic_has_text() {
        let reg = registry();
        let names: Vec<_> = topics(&reg).into_iter().map(|(t, _)| t).collect();
        assert_eq!(names, ["cards", "map", "typst", "models"], "media needs a source dir");
        for t in &names {
            assert!(doc(&reg, t).unwrap().len() > 500, "{t} doc is empty");
        }
        let cards = doc(&reg, "cards").unwrap();
        assert!(cards.contains("### Cloze") && !cards.contains("## Config"), "cards cut moved");
        assert!(!cards.contains("README.md"), "unrewritten repo link in cards doc");
        assert!(doc(&reg, "nope").unwrap_err().to_string().contains("map"));
    }

    #[test]
    fn finds_block_topics() {
        let reg = registry();
        assert_eq!(block_topics(&reg, "Q\n\n```map\nx\n```\n\n```typst\n```"), ["map", "typst"]);
        assert!(block_topics(&reg, "```_map\n```").is_empty());
    }
}
