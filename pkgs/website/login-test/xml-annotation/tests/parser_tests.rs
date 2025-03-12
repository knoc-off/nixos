// tests/parser_tests.rs

use std::error::Error;
use xml_annotation::CorrectionDocument;

#[test]
fn test_basic_parsing() -> Result<(), Box<dyn Error>> {
    let xml = r#"
    <document xmlns:cor="https://example.com/correction-system">
      <cor:content>
        My
        <cor:fix explanation="Non-standard superlative">
          <cor:original>favoritest</cor:original>
          <cor:corrected>favorite</cor:corrected>
        </cor:fix> book
      </cor:content>
    </document>
    "#;

    let doc = CorrectionDocument::parse(xml)?;

    assert_eq!(doc.reconstruct_original(), "My favoritest book");
    assert_eq!(doc.reconstruct_corrected(), "My favorite book");

    Ok(())
}

#[test]
fn test_nested_corrections() -> Result<(), Box<dyn Error>> {
    let xml = r#"
    <document xmlns:cor="https://example.com/correction-system">
      <cor:content>
        <cor:fix explanation="Sentence structure">
          <cor:original>The man quickly ran to the store.</cor:original>
          <cor:corrected>
            The man
            <cor:fix explanation="More precise verb">
              <cor:original>quickly ran</cor:original>
              <cor:corrected>sprinted</cor:corrected>
            </cor:fix>
            to the
            <cor:fix explanation="Specific location">
              <cor:original>store</cor:original>
              <cor:corrected>supermarket</cor:corrected>
            </cor:fix>.
          </cor:corrected>
        </cor:fix>
      </cor:content>
    </document>
    "#;

    let doc = CorrectionDocument::parse(xml)?;

    assert_eq!(doc.reconstruct_original(), "The man quickly ran to the store.");
    assert_eq!(doc.reconstruct_corrected(), "The man sprinted to the supermarket.");

    Ok(())
}

#[test]
fn test_revision_with_segments() -> Result<(), Box<dyn Error>> {
    let xml = r#"
    <document xmlns:cor="https://example.com/correction-system">
      <cor:content>
        <cor:revision explanation="Paragraph restructuring">
          <cor:original>
            The book was good. I liked the characters. The plot was interesting.
          </cor:original>
          <cor:corrected>
            <cor:segment>
              The book was
              <cor:fix explanation="More descriptive">
                <cor:original>good</cor:original>
                <cor:corrected>captivating</cor:corrected>
              </cor:fix>.
            </cor:segment>
            <cor:segment>
              The well-developed characters and intriguing plot contributed to its appeal.
            </cor:segment>
          </cor:corrected>
        </cor:revision>
      </cor:content>
    </document>
    "#;

    let doc = CorrectionDocument::parse(xml)?;

    assert_eq!(doc.reconstruct_original().trim(),
               "The book was good. I liked the characters. The plot was interesting.");
    assert_eq!(doc.reconstruct_corrected().trim(),
               "The book was captivating. The well-developed characters and intriguing plot contributed to its appeal.");

    Ok(())
}

#[test]
fn test_missing_original() {
    let xml = r#"
    <document xmlns:cor="https://example.com/correction-system">
      <cor:content>
        <cor:fix explanation="Missing original">
          <cor:corrected>fixed</cor:corrected>
        </cor:fix>
      </cor:content>
    </document>
    "#;

    let result = CorrectionDocument::parse(xml);
    assert!(result.is_err());

    match result {
        Err(e) => {
            let error_msg = e.to_string();
            assert!(error_msg.contains("Missing original"));
        },
        _ => panic!("Expected error for missing original element"),
    }
}

#[test]
fn test_missing_corrected() {
    let xml = r#"
    <document xmlns:cor="https://example.com/correction-system">
      <cor:content>
        <cor:fix explanation="Missing corrected">
          <cor:original>broken</cor:original>
        </cor:fix>
      </cor:content>
    </document>
    "#;

    let result = CorrectionDocument::parse(xml);
    assert!(result.is_err());

    match result {
        Err(e) => {
            let error_msg = e.to_string();
            assert!(error_msg.contains("Missing corrected"));
        },
        _ => panic!("Expected error for missing corrected element"),
    }
}

#[test]
fn test_complex_document() -> Result<(), Box<dyn Error>> {
    let xml = r#"
    <document xmlns:cor="https://example.com/correction-system">
      <cor:content>
        My
        <cor:fix explanation="Non-standard superlative">
          <cor:original>favoritest</cor:original>
          <cor:corrected>favorite</cor:corrected>
        </cor:fix> book is
        <cor:fix explanation="Title formatting">
          <cor:original>"The Great Gatsby"</cor:original>
          <cor:corrected>*The Great Gatsby*</cor:corrected>
          <cor:fix explanation="Punctuation replacement">
            <cor:original>"</cor:original>
            <cor:corrected>*</cor:corrected>
          </cor:fix>
        </cor:fix> by F. Scott Fitzgerald,
        <cor:revision explanation="Improved temporal reference">
          <cor:original>who wrote it back when people wore weird hats and drove old cars</cor:original>
          <cor:corrected>
            written during an era of
            <cor:fix explanation="More formal adjective">
              <cor:original>weird</cor:original>
              <cor:corrected>unusual</cor:corrected>
            </cor:fix> hats and
            <cor:fix explanation="Technical term">
              <cor:original>old cars</cor:original>
              <cor:corrected>vintage automobiles</cor:corrected>
            </cor:fix>
          </cor:corrected>
        </cor:revision>.
      </cor:content>
    </document>
    "#;

    let doc = CorrectionDocument::parse(xml)?;

    let original = doc.reconstruct_original();
    let corrected = doc.reconstruct_corrected();

    assert!(original.contains("favoritest"));
    assert!(original.contains("\"The Great Gatsby\""));
    assert!(original.contains("who wrote it back when people wore weird hats and drove old cars"));

    assert!(corrected.contains("favorite"));
    assert!(corrected.contains("*The Great Gatsby*"));
    assert!(corrected.contains("written during an era of unusual hats and vintage automobiles"));

    Ok(())
}

#[test]
fn test_whitespace_preservation() -> Result<(), Box<dyn Error>> {
    let xml = r#"
    <document xmlns:cor="https://example.com/correction-system">
      <cor:content>
        Line one.
        <cor:fix explanation="Spacing">
          <cor:original>  Extra spaces.  </cor:original>
          <cor:corrected> Single space. </cor:corrected>
        </cor:fix>
        Line three.
      </cor:content>
    </document>
    "#;

    let doc = CorrectionDocument::parse(xml)?;

    assert_eq!(doc.reconstruct_original(), "Line one.  Extra spaces.  Line three.");
    assert_eq!(doc.reconstruct_corrected(), "Line one. Single space. Line three.");

    Ok(())
}

#[test]
fn test_find_by_explanation() -> Result<(), Box<dyn Error>> {
    let xml = r#"
    <document xmlns:cor="https://example.com/correction-system">
      <cor:content>
        <cor:fix explanation="Spelling error">
          <cor:original>teh</cor:original>
          <cor:corrected>the</cor:corrected>
        </cor:fix> quick
        <cor:fix explanation="Grammar issue">
          <cor:original>brown fox jump</cor:original>
          <cor:corrected>brown fox jumps</cor:corrected>
        </cor:fix> over
        <cor:fix explanation="Spelling error">
          <cor:original>teh</cor:original>
          <cor:corrected>the</cor:corrected>
        </cor:fix> lazy dog.
      </cor:content>
    </document>
    "#;

    let doc = CorrectionDocument::parse(xml)?;

    let spelling_errors = doc.find_by_explanation("Spelling");
    assert_eq!(spelling_errors.len(), 2);

    let grammar_issues = doc.find_by_explanation("Grammar");
    assert_eq!(grammar_issues.len(), 1);

    Ok(())
}

#[test]
fn test_malformed_xml() {
    let xml = r#"
    <document xmlns:cor="https://example.com/correction-system">
      <cor:content>
        <cor:fix explanation="Unclosed tag">
          <cor:original>broken</cor:original>
          <cor:corrected>fixed
      </cor:content>
    </document>
    "#;

    let result = CorrectionDocument::parse(xml);
    assert!(result.is_err());

    match result {
        Err(e) => {
            let error_msg = e.to_string();
            assert!(error_msg.contains("XML error"));
        },
        _ => panic!("Expected error for malformed XML"),
    }
}

#[test]
fn test_to_json() -> Result<(), Box<dyn Error>> {
    let xml = r#"
    <document xmlns:cor="https://example.com/correction-system">
      <cor:content>
        <cor:fix explanation="Simple fix">
          <cor:original>wrong</cor:original>
          <cor:corrected>right</cor:corrected>
        </cor:fix>
      </cor:content>
    </document>
    "#;

    let doc = CorrectionDocument::parse(xml)?;
    let json = doc.to_json();

    // Basic validation of JSON structure
    assert!(json.is_object());
    assert!(json.as_object().unwrap().contains_key("root"));

    Ok(())
}

#[test]
fn test_empty_document() -> Result<(), Box<dyn Error>> {
    let xml = r#"
    <document xmlns:cor="https://example.com/correction-system">
      <cor:content></cor:content>
    </document>
    "#;

    let doc = CorrectionDocument::parse(xml)?;

    assert_eq!(doc.reconstruct_original(), "");
    assert_eq!(doc.reconstruct_corrected(), "");

    Ok(())
}

