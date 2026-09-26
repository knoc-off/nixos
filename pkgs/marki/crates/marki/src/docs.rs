//! Authoring docs served to agents (`marki_docs` tool, `marki://docs/*`
//! resources). They are the repo's own READMEs, embedded at build time, so
//! there is no second copy to drift.

use anyhow::{Result, bail};

const README: &str = include_str!("../../../README.md");
const MAP: &str = include_str!("../../marki-map/README.md");
const MEDIA: &str = include_str!("../../marki-media/README.md");
const TYPST: &str = include_str!("../../marki-typst/README.md");

/// Topic names with a one-line summary, in reading order.
pub const TOPICS: &[(&str, &str)] = &[
    ("cards", "card file format: sections, tags, cloze, decks, code blocks, math"),
    ("map", "```map blocks: highlight countries/regions/OSM features on an SVG map"),
    ("media", "```media blocks: images and audio from .marki/media or media sources"),
    ("typst", "```typst blocks: typeset diagrams/formulas compiled to SVG"),
    ("models", "Lua card models (custom card types)"),
];

/// Fence languages that have a doc topic of the same name.
pub const BLOCK_TOPICS: &[&str] = &["map", "media", "typst"];

pub fn doc(topic: &str) -> Result<String> {
    Ok(match topic {
        "cards" => format!(
            "{}\nBlock syntax: marki_docs(\"map\"), marki_docs(\"media\"), marki_docs(\"typst\"). \
             Custom card types: marki_docs(\"models\").\n",
            // Repo-relative links mean nothing over MCP; point at the topics.
            section(README, "## Writing cards", "## Formatting rules")
                .replace("[models/](models/README.md)", "marki_docs(\"models\")")
                .replace("[marki-map](crates/marki-map/README.md)", "marki_docs(\"map\")")
                .replace("[marki-media](crates/marki-media/README.md)", "marki_docs(\"media\")")
                .replace("[marki-typst](crates/marki-typst/README.md)", "marki_docs(\"typst\")")
        ),
        "map" => MAP.into(),
        "media" => MEDIA.into(),
        "typst" => TYPST.into(),
        "models" => crate::scripting::MODEL_API.into(),
        _ => bail!(
            "unknown topic {topic:?}; topics: {}",
            TOPICS.iter().map(|(t, _)| *t).collect::<Vec<_>>().join(", ")
        ),
    })
}

/// Doc topics for the renderer blocks a card source uses (```map etc.).
pub fn block_topics(source: &str) -> Vec<&'static str> {
    BLOCK_TOPICS
        .iter()
        .copied()
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

    #[test]
    fn every_topic_has_text() {
        for (t, _) in TOPICS {
            assert!(doc(t).unwrap().len() > 500, "{t} doc is empty");
        }
        let cards = doc("cards").unwrap();
        assert!(cards.contains("### Cloze") && !cards.contains("## Config"), "cards cut moved");
        assert!(!cards.contains("README.md"), "unrewritten repo link in cards doc");
        assert!(doc("nope").unwrap_err().to_string().contains("map"));
    }

    #[test]
    fn finds_block_topics() {
        assert_eq!(block_topics("Q\n\n```map\nx\n```\n\n```media\n```"), ["map", "media"]);
        assert!(block_topics("```_map\n```").is_empty());
    }
}
