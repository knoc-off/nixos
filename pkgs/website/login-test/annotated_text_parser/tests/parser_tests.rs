#[cfg(test)]
mod tests {
    use annotated_text_parser::*;

    #[test]
    fn test_simple_correction() {
        let xml = r#"
        <document>
          <content>
            This has a <correction type="TYPO" explanation="Common spelling error">
              <original>mispeling</original>
              <corrected>misspelling</corrected>
            </correction> in it.
          </content>
        </document>
        "#;

        let result = parse_xml_corrections(xml).unwrap();

        assert_eq!(result.original_text, "This has a mispeling in it.");
        assert_eq!(result.corrected_text, "This has a misspelling in it.");
        assert_eq!(result.corrections.len(), 1);
        assert_eq!(result.corrections[0].error_type, "TYPO");
        assert_eq!(result.corrections[0].original, "mispeling");
        assert_eq!(result.corrections[0].correction, "misspelling");
        assert_eq!(
            result.corrections[0].explanation,
            Some("Common spelling error".to_string())
        );
    }

    #[test]
    fn test_multiple_corrections() {
        let xml = r#"
        <document>
          <content>
            The team <correction type="GRAM">
              <original>is</original>
              <corrected>are</corrected>
            </correction> <correction type="WORD">
              <original>leveraging</original>
              <corrected>using</corrected>
            </correction> their resources effectively.
          </content>
        </document>
        "#;

        let result = parse_xml_corrections(xml).unwrap();

        assert_eq!(
            result.original_text,
            "The team is leveraging their resources effectively."
        );
        assert_eq!(
            result.corrected_text,
            "The team are using their resources effectively."
        );
        assert_eq!(result.corrections.len(), 2);

        // Check first correction
        assert_eq!(result.corrections[0].error_type, "GRAM");
        assert_eq!(result.corrections[0].original, "is");
        assert_eq!(result.corrections[0].correction, "are");

        // Check second correction
        assert_eq!(result.corrections[1].error_type, "WORD");
        assert_eq!(result.corrections[1].original, "leveraging");
        assert_eq!(result.corrections[1].correction, "using");
    }

    #[test]
    fn test_nested_corrections() {
        let xml = r#"
        <document>
          <content>
            <correction type="STYL" explanation="Improved overall style">
              <original>
                This sentence has
                <correction type="GRAM">
                  <original>a error</original>
                  <corrected>an error</corrected>
                </correction>
                that needs fixing.
              </original>
              <corrected>This sentence has an error that needs fixing.</corrected>
            </correction>
          </content>
        </document>
        "#;

        let result = parse_xml_corrections(xml).unwrap();

        assert_eq!(result.corrections.len(), 1);
        assert_eq!(result.corrections[0].error_type, "STYL");
        assert_eq!(result.corrections[0].children.len(), 1);
        assert_eq!(result.corrections[0].children[0].error_type, "GRAM");
        assert_eq!(result.corrections[0].children[0].original, "a error");
        assert_eq!(result.corrections[0].children[0].correction, "an error");

        assert_eq!(
            result.original_text,
            "This sentence has a error that needs fixing."
        );
        assert_eq!(
            result.corrected_text,
            "This sentence has an error that needs fixing."
        );
    }

    #[test]
    fn test_with_suggestions() {
        let xml = r#"
        <document>
          <content>
            This is a simple text.
          </content>
          <suggestions>
            1. Consider using more specific examples.
            2. Try to vary your sentence structure more.
          </suggestions>
        </document>
        "#;

        let result = parse_xml_corrections(xml).unwrap();

        assert_eq!(result.original_text, "This is a simple text.");
        assert_eq!(result.corrected_text, "This is a simple text.");
        assert!(result.corrections.is_empty());
        assert_eq!(
            result.suggestions,
            Some(
                "1. Consider using more specific examples.\n            2. Try to vary your sentence structure more."
                    .to_string()
            )
        );
    }

    #[test]
    fn test_html_entity_decoding() {
        let xml = r#"
        <document>
          <content>
            This has &amp; special &lt;characters&gt; and a <correction type="TYPO">
              <original>mispeling &amp; stuff</original>
              <corrected>misspelling &amp; things</corrected>
            </correction> in it.
          </content>
        </document>
        "#;

        let result = parse_xml_corrections(xml).unwrap();

        assert_eq!(
            result.original_text,
            "This has & special <characters> and a mispeling & stuff in it."
        );
        assert_eq!(
            result.corrected_text,
            "This has & special <characters> and a misspelling & things in it."
        );
        assert_eq!(result.corrections[0].original, "mispeling & stuff");
        assert_eq!(result.corrections[0].correction, "misspelling & things");
    }

    #[test]
    fn test_correction_without_explicit_tags() {
        let xml = r#"
        <document>
          <content>
            This has a <correction type="TYPO">mispeling</correction> in it.
          </content>
        </document>
        "#;

        let result = parse_xml_corrections(xml).unwrap();

        assert_eq!(result.original_text, "This has a mispeling in it.");
        assert_eq!(result.corrected_text, "This has a mispeling in it.");
        assert_eq!(result.corrections.len(), 1);
        assert_eq!(result.corrections[0].original, "mispeling");
        assert_eq!(result.corrections[0].correction, "mispeling");
    }

    #[test]
    fn test_complex_document() {
        let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
    <document>
      <content>
        <correction type="STYL" explanation="This paragraph has been restructured for clarity">
          <original>
            The research team conducted a study on climate change effects. They collected data from
            <correction type="TYPO" explanation="Spelling error">
              <original>fourty</original>
              <corrected>forty</corrected>
            </correction>
            different locations across the globe. The data
            <correction type="GRAM">
              <original>was</original>
              <corrected>were</corrected>
            </correction>
            analyzed using advanced statistical methods.
          </original>
          <corrected>
            The research team conducted a comprehensive global study on climate change effects. They collected and analyzed data from forty different locations using advanced statistical methods.
          </corrected>
        </correction>

        This paragraph contains several common errors. The author
        <correction type="VERB" explanation="Incorrect verb tense">
          <original>use</original>
          <corrected>uses</corrected>
        </correction>
        incorrect verb forms and
        <correction type="PUNCT" explanation="Missing comma in compound sentence">
          <original>sometimes forgets punctuation</original>
          <corrected>sometimes forgets punctuation,</corrected>
        </correction>
        which makes the text harder to read.
      </content>

      <suggestions>
        1. Consider using more specific examples to illustrate your points.
        2. The introduction would benefit from a clearer thesis statement.
      </suggestions>
    </document>"#;

        let result = parse_xml_corrections(xml).unwrap();

        // Check that we have the right number of top-level corrections
        assert_eq!(result.corrections.len(), 3);

        // Check that the first correction has nested corrections
        assert_eq!(result.corrections[0].children.len(), 2);

        // Check that suggestions were parsed correctly
        assert!(result.suggestions.unwrap().contains("specific examples"));

        // Check that the original and corrected texts are different
        assert!(result.original_text.contains("fourty"));
        assert!(result.corrected_text.contains("forty"));
        assert!(result.original_text.contains("use"));
        assert!(result.corrected_text.contains("uses"));
    }

    #[test]
    fn test_error_handling() {
        // Test missing type attribute
        let xml = r#"
        <document>
          <content>
            This has a <correction>mispeling</correction> in it.
          </content>
        </document>
        "#;

        let result = parse_xml_corrections(xml);
        assert!(result.is_err());

        // Test malformed XML
        let xml = r#"
        <document>
          <content>
            This has a <correction type="TYPO">mispeling</content>
        </document>
        "#;

        let result = parse_xml_corrections(xml);
        assert!(result.is_err());
    }

    #[test]
    fn test_empty_document() {
        let xml = r#"
        <document>
          <content></content>
        </document>
        "#;

        let result = parse_xml_corrections(xml).unwrap();
        assert_eq!(result.original_text, "");
        assert_eq!(result.corrected_text, "");
        assert!(result.corrections.is_empty());
        assert_eq!(result.suggestions, None);
    }

    #[test]
    fn test_whitespace_handling() {
        let xml = r#"
        <document>
          <content>
            This text has   <correction type="SPACE" explanation="Extra spaces">
              <original>  too many   spaces  </original>
              <corrected> normal spacing </corrected>
            </correction> between words.
          </content>
        </document>
        "#;

        let result = parse_xml_corrections(xml).unwrap();

        assert_eq!(
            result.original_text,
            "This text has   too many   spaces   between words."
        );
        assert_eq!(
            result.corrected_text,
            "This text has   normal spacing  between words."
        );
        assert_eq!(result.corrections[0].original, "too many   spaces");
        assert_eq!(result.corrections[0].correction, "normal spacing");
    }

    #[test]
    fn test_buffer_size_configuration() {
        let xml = r#"
        <document>
          <content>
            This has a <correction type="TYPO" explanation="Common spelling error">
              <original>mispeling</original>
              <corrected>misspelling</corrected>
            </correction> in it.
          </content>
        </document>
        "#;

        // Test with a smaller buffer size
        let mut parser = XmlParser::new().with_buffer_size(64);
        let result = parser.parse(xml).unwrap();

        assert_eq!(result.original_text, "This has a mispeling in it.");
        assert_eq!(result.corrected_text, "This has a misspelling in it.");
    }
}

