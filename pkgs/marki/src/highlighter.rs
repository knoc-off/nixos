use std::sync::LazyLock;
use syntect::highlighting::{Theme, ThemeSet};
use syntect::html::{ClassStyle, ClassedHTMLGenerator};
use syntect::parsing::SyntaxSet;
use syntect::util::LinesWithEndings;

static SYNTAX_SET: LazyLock<SyntaxSet> = LazyLock::new(|| {
    dbg!("Loading syntax set");
    SyntaxSet::load_defaults_newlines()
});

static THEME: LazyLock<Theme> = LazyLock::new(|| {
    dbg!("Loading theme");
    let theme_set = ThemeSet::load_defaults();
    theme_set.themes["base16-ocean.dark"].clone()
});

/// Generate CSS for syntax highlighting (call once and include in card template)
pub fn generate_css() -> String {
    dbg!("Generating CSS for syntax highlighting");
    match syntect::html::css_for_theme_with_class_style(&THEME, ClassStyle::Spaced) {
        Ok(css) => css,
        Err(e) => {
            eprintln!("Error generating CSS: {}", e);
            String::new()
        }
    }
}

pub fn highlight_code(code: &str, language: &str) -> String {
    dbg!("Highlighting code block", language);

    let syntax = SYNTAX_SET
        .find_syntax_by_token(language)
        .unwrap_or_else(|| {
            dbg!("Language not found, using plain text", language);
            SYNTAX_SET.find_syntax_plain_text()
        });

    let mut html_generator =
        ClassedHTMLGenerator::new_with_class_style(syntax, &SYNTAX_SET, ClassStyle::Spaced);

    for line in LinesWithEndings::from(code) {
        if let Err(e) = html_generator.parse_html_for_line_which_includes_newline(line) {
            eprintln!("Error parsing line: {}", e);
        }
    }

    let html = html_generator.finalize();
    dbg!("Generated HTML length", html.len());
    html
}
