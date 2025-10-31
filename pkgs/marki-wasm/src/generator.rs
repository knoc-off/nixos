use crate::card::{Card, NoteType};
use anyhow::{Context, Result};
use genanki_rs::{Deck, Field, Model, ModelType, Note, Package, Template};
use std::collections::HashMap;
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::Path;

// Embed WASM files at compile time
const WASM_JS: &[u8] = include_bytes!("../pkg/marki.js");
const WASM_BG: &[u8] = include_bytes!("../pkg/marki_bg.wasm");

fn generate_id(name: &str) -> i64 {
    let mut hasher = DefaultHasher::new();
    name.hash(&mut hasher);
    (hasher.finish() & 0x7FFFFFFF) as i64
}

fn generate_card_guid(file_path: &str) -> String {
    let path = Path::new(file_path);

    let filename = path.file_name().and_then(|n| n.to_str()).unwrap(); // should never happen

    let parent_dir = path
        .parent()
        .and_then(|p| p.file_name())
        .and_then(|n| n.to_str())
        .unwrap_or("default");

    let combined = format!("{}/{}", parent_dir, filename);

    let mut hasher = DefaultHasher::new();
    combined.hash(&mut hasher);
    let hash = hasher.finish();

    // Anki GUID, hex-string
    format!("{:016x}", hash)
}

fn create_basic_model() -> Model {
    dbg!("Creating basic card model");

    let css = r#"
.card {
    font-family: Arial, sans-serif;
    font-size: 20px;
    text-align: left;
    color: black;
    background-color: white;
}

.code {
    background-color: #2b303b;
    color: #c0c5ce;
    padding: 10px;
    border-radius: 5px;
    overflow-x: auto;
}
"#;

    let qfmt = r#"<pre id="marki-front-data" style="display:none;">{{Front}}</pre>
<div id="marki-front"></div>
<script>
const MARKI_DEBUG = true; // Set to false to disable debug logging
function renderMarkdown() {
    if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] renderMarkdown called');
    const dataEl = document.getElementById('marki-front-data');
    const markdown = dataEl.textContent;
    if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Front markdown:', markdown);

    const html = wasm_bindgen.render_markdown(markdown, false);
    if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Rendered HTML:', html);
    document.getElementById('marki-front').innerHTML = html;
    if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Front render complete');
}
if (!window.wasm_bindgen) {
    if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Loading WASM for the first time');
    const script = document.createElement('script');
    script.src = '_marki.js';
    script.onload = async function() {
        if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] WASM JS loaded, initializing...');
        await wasm_bindgen('_marki_bg.wasm');
        wasm_bindgen.init_panic_hook();
        window.markiInit = true;
        if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] WASM initialized');
        renderMarkdown();
    };
    document.head.appendChild(script);
} else {
    if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] WASM already loaded');
    (async function() {
        if (!window.markiInit) {
            if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Initializing WASM');
            await wasm_bindgen('_marki_bg.wasm');
            wasm_bindgen.init_panic_hook();
            window.markiInit = true;
            if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] WASM initialized');
        }
        renderMarkdown();
    })();
}
</script>"#;

    let afmt = r#"{{FrontSide}}<hr id="answer">
<pre id="marki-back-data" style="display:none;">{{Back}}</pre>
<div id="marki-back"></div>
<script>
(async function() {
    const MARKI_DEBUG = true;
    if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Rendering back side');

    const backData = document.getElementById('marki-back-data');
    if (!backData) {
        if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] No back data found');
        return;
    }

    const markdown = backData.textContent;
    if (markdown.trim()) {
        if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Back markdown:', markdown);
        const html = wasm_bindgen.render_markdown(markdown, false);
        if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Back HTML:', html);
        document.getElementById('marki-back').innerHTML = html;
        if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Back render complete');
    } else {
        if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] No back content to render');
    }
})();
</script>"#;

    Model::new(
        generate_id("marki-wasm-basic"),
        "Marki WASM Basic",
        vec![Field::new("Front"), Field::new("Back")],
        vec![Template::new("Card 1").qfmt(qfmt).afmt(afmt)],
    )
    .css(&css)
}

fn create_cloze_model() -> Model {
    dbg!("Creating cloze card model");

    let css = r#"
.card {
    font-family: Arial, sans-serif;
    font-size: 20px;
    text-align: left;
    color: black;
    background-color: white;
}

.cloze {
    font-weight: bold;
    color: blue;
}

.code {
    background-color: #2b303b;
    color: #c0c5ce;
    padding: 10px;
    border-radius: 5px;
    overflow-x: auto;
}
"#;

    let qfmt = r#"<pre id="marki-cloze-data" style="display:none;">{{Text}}</pre>
<div id="marki-cloze"></div>
<script>
const MARKI_DEBUG = true; // Set to false to disable debug logging
function renderClozeMarkdown() {
    if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] renderClozeMarkdown called');
    const dataEl = document.getElementById('marki-cloze-data');
    const markdown = dataEl.textContent;
    if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Cloze markdown:', markdown);

    const html = wasm_bindgen.render_markdown(markdown, true);
    if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Cloze HTML:', html);
    document.getElementById('marki-cloze').innerHTML = html;
    if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Cloze render complete');
}
if (!window.wasm_bindgen) {
    if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Loading WASM for cloze (first time)');
    const script = document.createElement('script');
    script.src = '_marki.js';
    script.onload = async function() {
        if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] WASM JS loaded for cloze, initializing...');
        await wasm_bindgen('_marki_bg.wasm');
        wasm_bindgen.init_panic_hook();
        window.markiInit = true;
        if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] WASM initialized for cloze');
        renderClozeMarkdown();
    };
    document.head.appendChild(script);
} else {
    if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] WASM already loaded for cloze');
    (async function() {
        if (!window.markiInit) {
            if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Initializing WASM for cloze');
            await wasm_bindgen('_marki_bg.wasm');
            wasm_bindgen.init_panic_hook();
            window.markiInit = true;
            if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] WASM initialized for cloze');
        }
        renderClozeMarkdown();
    })();
}
</script>"#;

    let afmt = r#"{{FrontSide}}<hr id="answer">
<pre id="marki-extra-data" style="display:none;">{{Extra}}</pre>
<div id="marki-extra"></div>
<script>
(async function() {
    const MARKI_DEBUG = true;
    if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Rendering cloze extra');

    const extraData = document.getElementById('marki-extra-data');
    if (!extraData) {
        if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] No extra data found');
        return;
    }

    const markdown = extraData.textContent;
    if (markdown.trim()) {
        if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Cloze extra markdown:', markdown);
        const html = wasm_bindgen.render_markdown(markdown, false);
        if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Cloze extra HTML:', html);
        document.getElementById('marki-extra').innerHTML = html;
        if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] Cloze extra render complete');
    } else {
        if (MARKI_DEBUG) console.log('[MARKI-JS DEBUG] No cloze extra content to render');
    }
})();
</script>"#;

    Model::new_with_options(
        generate_id("marki-wasm-cloze"),
        "Marki WASM Cloze",
        vec![Field::new("Text"), Field::new("Extra")],
        vec![Template::new("Cloze").qfmt(qfmt).afmt(afmt)],
        Some(&css),
        Some(ModelType::Cloze),
        None, // latex_pre
        None, // latex_post
        None, // sort_field_index
    )
}

pub fn generate_decks(
    decks_cards: HashMap<String, Vec<Card>>,
    output_path: &Path,
    mut media_files: Vec<String>,
) -> Result<()> {
    dbg!("Generating multiple decks", decks_cards.len());

    // Add embedded WASM renderer files to media
    // Write embedded files to temp directory with _ prefix for Anki
    println!("Bundling embedded WASM renderer...");

    let temp_dir = std::env::temp_dir();
    let wasm_js_dest = temp_dir.join("_marki.js");
    let wasm_bg_dest = temp_dir.join("_marki_bg.wasm");

    // Write WASM binary
    std::fs::write(&wasm_bg_dest, WASM_BG).context("Failed to write embedded WASM binary")?;

    // Write JS file with updated reference to _marki_bg.wasm
    let js_content =
        String::from_utf8(WASM_JS.to_vec()).context("Failed to decode embedded WASM JS")?;
    let js_content = js_content.replace("marki_bg.wasm", "_marki_bg.wasm");
    std::fs::write(&wasm_js_dest, js_content).context("Failed to write embedded WASM JS file")?;

    media_files.push(wasm_js_dest.to_string_lossy().to_string());
    media_files.push(wasm_bg_dest.to_string_lossy().to_string());

    let basic_model = create_basic_model();
    let cloze_model = create_cloze_model();

    let mut all_decks = Vec::new();

    for (deck_name, cards) in decks_cards {
        dbg!("Creating deck", &deck_name, cards.len());

        let deck_id = generate_id(&deck_name);
        let mut deck = Deck::new(deck_id, &deck_name, "Generated by marki");

        for (idx, card) in cards.iter().enumerate() {
            let guid = card
                .file_path
                .as_ref()
                .map(|p| generate_card_guid(p))
                .unwrap_or_else(|| format!("{:016x}", idx));

            let model = match card.note_type {
                NoteType::Cloze => {
                    dbg!("Creating cloze note", card.front.len(), card.back.len());
                    &cloze_model
                }
                NoteType::Basic => {
                    dbg!("Creating basic note", card.front.len(), card.back.len());
                    &basic_model
                }
            };

            let note = Note::new(model.clone(), vec![&card.front, &card.back])
                .context(format!("Failed to create note for card {}", idx))?
                .guid(&guid);

            deck.add_note(note);
        }

        all_decks.push(deck);
    }

    dbg!("Writing package to file", output_path, all_decks.len());

    let media_refs: Vec<&str> = media_files.iter().map(|s| s.as_str()).collect();
    let mut package = Package::new(all_decks, media_refs).context("Failed to create package")?;
    package
        .write_to_file(output_path.to_str().unwrap())
        .context("Failed to write package to file")?;

    dbg!("Successfully wrote package");
    Ok(())
}
