// src/llm_processor.rs
use annotated_text_parser::Correction;
use annotated_text_parser::parse_xml_corrections;
use openai_api_rs::v1::api::OpenAIClient;
use openai_api_rs::v1::chat_completion::{self, ChatCompletionRequest, Content, MessageRole};
use sqlx::SqlitePool;
use std::collections::HashMap;
use std::env;
use std::error::Error;
use std::sync::Arc;
use std::time::Duration;
use tokio::time::sleep;

// Use the tracing from axum_login instead
use axum_login::tracing::{debug, error, info, trace};

// Define a custom error type that implements Send + Sync
#[derive(Debug)]
pub struct ProcessorError(String);

impl std::fmt::Display for ProcessorError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl Error for ProcessorError {}

pub struct LlmProcessor {
    db: SqlitePool,
    client: Arc<OpenAIClient>,
}

impl LlmProcessor {
    pub fn new(db: SqlitePool) -> Result<Self, ProcessorError> {
        // Get API key from environment variable
        let api_key = env::var("OPENROUTER_API_KEY")
            .map_err(|e| ProcessorError(format!("Failed to get API key: {}", e)))?;

        // Create OpenRouter client
        let client = OpenAIClient::builder()
            .with_endpoint("https://openrouter.ai/api/v1")
            .with_api_key(api_key)
            .build()
            .map_err(|e| ProcessorError(format!("Failed to create OpenAI client: {}", e)))?;

        Ok(Self {
            db,
            client: Arc::new(client),
        })
    }

    pub async fn process_pending_submissions(&self) -> Result<(), ProcessorError> {
        info!("Checking for pending submissions...");
        // Fetch pending submissions (those without corrected_text) and include the prompt topic
        let submissions = sqlx::query!(
            r#"
            SELECT
                s.id, s.user_id, s.prompt_id, s.original_text, p.topic
            FROM
                essay_submissions s
            JOIN
                essay_prompts p ON s.prompt_id = p.id
            WHERE
                s.corrected_text IS NULL OR s.annotated_text IS NULL OR s.annotated_text = ''
            LIMIT 5
            "#
        )
        .fetch_all(&self.db)
        .await
        .map_err(|e| ProcessorError(format!("Database error: {}", e)))?;

        info!("Found {} pending submissions to process", submissions.len());

        for submission in submissions {
            info!("Processing submission ID: {}", submission.id);

            // Process each submission with the prompt topic using the new multi-step approach
            match self
                .process_submission(submission.id, &submission.original_text, &submission.topic)
                .await
            {
                Ok((corrected_text, annotated_text, prompt_relevance)) => {
                    // Update the database with the corrected text and annotated text
                    let word_count = submission.original_text.split_whitespace().count();
                    let (total_errors, _) = count_corrections(&annotated_text);
                    let language_score =
                        calculate_language_score(&submission.original_text, &annotated_text);

                    // Calculate final score with word count consideration
                    let final_score =
                        calculate_final_score(language_score, prompt_relevance, word_count);

                    info!(
                        "Updating submission ID: {}. Language Score: {}, Prompt Relevance: {}, Final Score: {}, Errors: {}",
                        submission.id, language_score, prompt_relevance, final_score, total_errors
                    );

                    sqlx::query!(
                        r#"
                        UPDATE essay_submissions
                        SET
                            corrected_text = ?,
                            annotated_text = ?,
                            score = ?,
                            error_count = ?,
                            prompt_relevance = ?
                        WHERE id = ?
                        "#,
                        corrected_text,
                        annotated_text,
                        final_score,
                        total_errors,
                        prompt_relevance,
                        submission.id
                    )
                    .execute(&self.db)
                    .await
                    .map_err(|e| ProcessorError(format!("Failed to update database: {}", e)))?;
                }
                Err(e) => {
                    error!("Error processing submission {}: {}", submission.id, e);
                }
            }

            // Add a small delay between submissions to avoid rate limiting
            sleep(Duration::from_secs(2)).await;
        }

        Ok(())
    }

    async fn process_submission(
        &self,
        id: i64,
        text: &str,
        prompt_topic: &str,
    ) -> Result<(String, String, i64), ProcessorError> {
        debug!("Processing submission {} using multi-step approach", id);

        // STEP 1: Generate a corrected version of the essay
        let corrected_text = self.generate_corrected_text(id, text, prompt_topic).await?;

        debug!("Generated corrected text for submission {}", id);

        // STEP 2: Generate annotated version using the sequential approach
        let annotated_text = self
            .generate_sequential_annotations(id, text, &corrected_text)
            .await?;

        debug!("Generated annotated text for submission {}", id);

        // STEP 3: Evaluate prompt relevance
        let prompt_relevance = self
            .evaluate_prompt_relevance(id, text, prompt_topic)
            .await?;

        debug!(
            "Evaluated prompt relevance for submission {}: {}",
            id, prompt_relevance
        );

        Ok((corrected_text, annotated_text, prompt_relevance))
    }

    async fn generate_corrected_text(
        &self,
        id: i64,
        text: &str,
        prompt_topic: &str,
    ) -> Result<String, ProcessorError> {
        info!("Step 1: Generating corrected text for submission {}", id);

        // Create the prompt for the LLM to generate a corrected version
        let correction_prompt = format!(
            "You are an expert language tutor. Your task is to correct the following essay.\n\n
            The essay was written in response to this prompt: \"{}\"\n\n
            Here is the essay to correct:\n\n{}\n\n
            Please provide a fully corrected version of the essay. Fix all grammar, spelling,
            punctuation, word choice, and very small style/structural issues. Make the essay as good as it can be
            while preserving the original meaning and intent.\n\n

            Do not take creative liberty with the corrected essay, it should adhear quite closely to the original.
            Only provide the corrected essay text with no explanations, annotations, or additional comments.\n
            Respond in the same language as the essay is written!",
            prompt_topic, text
        );

        // Create the request for corrections
        let correction_req = ChatCompletionRequest::new(
            "openai/gpt-4o-2024-11-20".to_string(),
            vec![chat_completion::ChatCompletionMessage {
                role: MessageRole::user,
                content: Content::Text(correction_prompt),
                name: None,
                tool_calls: None,
                tool_call_id: None,
            }],
        );

        // Send the request to the LLM
        let correction_result = self
            .client
            .chat_completion(correction_req)
            .await
            .map_err(|e| ProcessorError(format!("LLM API error for corrections: {}", e)))?;

        // Extract the corrected text from the response
        let corrected_text = match &correction_result.choices[0].message.content {
            Some(content) => content.clone(),
            None => {
                return Err(ProcessorError(
                    "No content returned from LLM for corrections".to_string(),
                ))
            }
        };

        Ok(corrected_text)
    }

    // Helper function to extract XML content from potentially markdown-wrapped response
    fn extract_xml_content(response: &str) -> Result<String, ProcessorError> {
        // Check if the response contains a document tag
        if let Some(start_idx) = response.find("<document>") {
            if let Some(end_idx) = response.rfind("</document>") {
                // Return the content between the first <document> and the last </document> tag
                return Ok(response[start_idx..=end_idx + 10].trim().to_string());
            }
        }

        // If we can't find document tags, check for markdown code blocks
        if response.contains("```xml") || response.contains("```") {
            // Try to extract content from markdown code blocks
            let lines: Vec<&str> = response.lines().collect();
            let mut in_code_block = false;
            let mut xml_content = String::new();

            for line in lines {
                if line.trim().starts_with("```") {
                    in_code_block = !in_code_block;
                    continue;
                }

                if in_code_block && line.contains("<document>") {
                    // We found the start of our XML content
                    xml_content.push_str(line);
                    xml_content.push('\n');
                } else if in_code_block {
                    xml_content.push_str(line);
                    xml_content.push('\n');
                }
            }

            if !xml_content.is_empty() {
                return Ok(xml_content.trim().to_string());
            }
        }

        // If we couldn't extract XML content, return the original response
        // This is a fallback, but you might want to handle this differently
        Err(ProcessorError(
            "Could not extract valid XML content from LLM response".to_string(),
        ))
    }

    async fn generate_sequential_annotations(
        &self,
        id: i64,
        original_text: &str,
        corrected_text: &str,
    ) -> Result<String, ProcessorError> {
        info!("Step 2: Generating sequential annotations for submission {}", id);

        // Initialize conversation history
        let mut conversation = Vec::new();

        // Start with system message
        conversation.push(chat_completion::ChatCompletionMessage {
            role: MessageRole::system,
            content: Content::Text(
                "You are an expert essay editor who specializes in annotating essays with XML tags to indicate corrections.".to_string()
            ),
            name: None,
            tool_calls: None,
            tool_call_id: None,
        });

        // Stage 1: Initial Setup - Wrap the original text in document tags
        let initial_xml = format!("<document>\n   {}\n</document>", original_text);

        conversation.push(chat_completion::ChatCompletionMessage {
            role: MessageRole::user,
            content: Content::Text(format!(
                "Here is an essay that needs annotation. For now, just confirm the structure is correct:\n\n{}",
                initial_xml
            )),
            name: None,
            tool_calls: None,
            tool_call_id: None,
        });

        // Send Stage 1 request
        let stage1_req = ChatCompletionRequest::new(
            "openai/gpt-4o-2024-11-20".to_string(),
            conversation.clone(),
        );

        let stage1_result = self
            .client
            .chat_completion(stage1_req)
            .await
            .map_err(|e| ProcessorError(format!("LLM API error for Stage 1: {}", e)))?;

        let stage1_response = match &stage1_result.choices[0].message.content {
            Some(content) => content.clone(),
            None => return Err(ProcessorError("No content returned from LLM for Stage 1".to_string())),
        };

        info!("Completed Stage 1 for submission {}", id);

        // Add assistant response to conversation
        conversation.push(chat_completion::ChatCompletionMessage {
            role: MessageRole::assistant,
            content: Content::Text(stage1_response),
            name: None,
            tool_calls: None,
            tool_call_id: None,
        });

        // Stage 2: Word-Level and Grammar Corrections
        let stage2_prompt = r#"
        Now, analyze the text and insert corrections for word-level and grammar issues. Focus on:
        - Spelling errors
        - Grammatical errors (e.g., subject-verb agreement, verb tense)
        - Punctuation issues
        - Incorrect word forms
        - Singular/plural mismatches
        - Capitalization errors

        Rules:
        1. Use the following XML structure for corrections:
           <correction type="TYPE">
               <original>original text</original>
               <corrected>corrected text</corrected>
               <explanation>optional explanation</explanation>
           </correction>
        2. Preserve all unmodified text exactly as it appears in the original essay.
        3. Do not make stylistic or structural changes at this stage.
        4. Ensure valid XML formatting with proper nesting.

        Compare the original essay with this corrected version to identify these issues:

        CORRECTED ESSAY:
        ---
        "#.to_string() + corrected_text + r#"
        ---

        Return the complete XML document with these corrections.
        "#;

        conversation.push(chat_completion::ChatCompletionMessage {
            role: MessageRole::user,
            content: Content::Text(stage2_prompt),
            name: None,
            tool_calls: None,
            tool_call_id: None,
        });

        // Send Stage 2 request
        let stage2_req = ChatCompletionRequest::new(
            "openai/gpt-4o-2024-11-20".to_string(),
            conversation.clone(),
        );

        let stage2_result = self
            .client
            .chat_completion(stage2_req)
            .await
            .map_err(|e| ProcessorError(format!("LLM API error for Stage 2: {}", e)))?;

        let stage2_response = match &stage2_result.choices[0].message.content {
            Some(content) => content.clone(),
            None => return Err(ProcessorError("No content returned from LLM for Stage 2".to_string())),
        };

        // Extract XML content from Stage 2
        let stage2_xml = match Self::extract_xml_content(&stage2_response) {
            Ok(xml) => xml,
            Err(_) => {
                // If extraction fails, use a fallback approach
                debug!("Failed to extract XML from Stage 2 response, using fallback");
                format!("<document>\n   {}\n</document>", original_text)
            }
        };

        info!("Completed Stage 2 for submission {}", id);

        // Add assistant response to conversation
        conversation.push(chat_completion::ChatCompletionMessage {
            role: MessageRole::assistant,
            content: Content::Text(stage2_response),
            name: None,
            tool_calls: None,
            tool_call_id: None,
        });

        // Stage 3: Stylistic and Tonal Corrections
        let stage3_prompt = format!(
            r#"
            Now, analyze the text and insert corrections for stylistic and tonal issues. Focus on:
            - Wordiness or awkward phrasing
            - Passive voice
            - Inappropriate or imprecise word usage
            - Adjusting formality to match the intended audience
            - Fixing incorrect idiomatic expressions
            - Removing unnecessary repetition

            Rules:
            1. Use the following XML structure for corrections:
               <correction type="TYPE">
                   <original>original text</original>
                   <corrected>corrected text</corrected>
                   <explanation>optional explanation</explanation>
               </correction>
            2. Nest corrections if they overlap with word-level or grammar corrections from Stage 2.
            3. Preserve all unmodified text exactly as it appears in the original essay.
            4. Ensure valid XML formatting with proper nesting.

            Start with the current XML and add these new corrections:
            {}

            Compare with the corrected version:
            ---
            {}
            ---

            Return the complete XML document with these additional corrections.
            "#,
            stage2_xml,
            corrected_text
        );

        conversation.push(chat_completion::ChatCompletionMessage {
            role: MessageRole::user,
            content: Content::Text(stage3_prompt),
            name: None,
            tool_calls: None,
            tool_call_id: None,
        });

        // Send Stage 3 request
        let stage3_req = ChatCompletionRequest::new(
            "openai/gpt-4o-2024-11-20".to_string(),
            conversation.clone(),
        );

        let stage3_result = self
            .client
            .chat_completion(stage3_req)
            .await
            .map_err(|e| ProcessorError(format!("LLM API error for Stage 3: {}", e)))?;

        let stage3_response = match &stage3_result.choices[0].message.content {
            Some(content) => content.clone(),
            None => return Err(ProcessorError("No content returned from LLM for Stage 3".to_string())),
        };

        // Extract XML content from Stage 3
        let stage3_xml = match Self::extract_xml_content(&stage3_response) {
            Ok(xml) => xml,
            Err(_) => {
                // If extraction fails, use the previous stage's XML
                debug!("Failed to extract XML from Stage 3 response, using Stage 2 XML");
                stage2_xml
            }
        };

        info!("Completed Stage 3 for submission {}", id);

        // Add assistant response to conversation
        conversation.push(chat_completion::ChatCompletionMessage {
            role: MessageRole::assistant,
            content: Content::Text(stage3_response),
            name: None,
            tool_calls: None,
            tool_call_id: None,
        });

        // Stage 4: Structural and Logical Flow Corrections
        let stage4_prompt = format!(
            r#"
            Now, analyze the text and insert corrections for structural and logical flow issues. Focus on:
            - Reorganizing sentences or paragraphs for clarity
            - Improving logical flow and transitions
            - Ensuring parallel structure in lists or comparisons
            - Fixing misplaced or dangling modifiers
            - Completing incomplete sentences
            - Fixing run-on sentences or comma splices

            Rules:
            1. Use the following XML structure for corrections:
               <correction type="TYPE">
                   <original>original text</original>
                   <corrected>corrected text</corrected>
                   <explanation>optional explanation</explanation>
               </correction>
            2. Nest corrections if they overlap with word-level, grammar, or stylistic corrections from previous stages.
            3. Preserve all unmodified text exactly as it appears in the original essay.
            4. Ensure valid XML formatting with proper nesting.

            Start with the current XML and add these new corrections:
            {}

            Compare with the corrected version:
            ---
            {}
            ---

            Return the complete XML document with these additional corrections.
            "#,
            stage3_xml,
            corrected_text
        );

        conversation.push(chat_completion::ChatCompletionMessage {
            role: MessageRole::user,
            content: Content::Text(stage4_prompt),
            name: None,
            tool_calls: None,
            tool_call_id: None,
        });

        // Send Stage 4 request
        let stage4_req = ChatCompletionRequest::new(
            "openai/gpt-4o-2024-11-20".to_string(),
            conversation.clone(),
        );

        let stage4_result = self
            .client
            .chat_completion(stage4_req)
            .await
            .map_err(|e| ProcessorError(format!("LLM API error for Stage 4: {}", e)))?;

        let stage4_response = match &stage4_result.choices[0].message.content {
            Some(content) => content.clone(),
            None => return Err(ProcessorError("No content returned from LLM for Stage 4".to_string())),
        };

        // Extract XML content from Stage 4
        let stage4_xml = match Self::extract_xml_content(&stage4_response) {
            Ok(xml) => xml,
            Err(_) => {
                // If extraction fails, use the previous stage's XML
                debug!("Failed to extract XML from Stage 4 response, using Stage 3 XML");
                stage3_xml
            }
        };

        info!("Completed Stage 4 for submission {}", id);

        // Add assistant response to conversation
        conversation.push(chat_completion::ChatCompletionMessage {
            role: MessageRole::assistant,
            content: Content::Text(stage4_response),
            name: None,
            tool_calls: None,
            tool_call_id: None,
        });

        // Stage 5: Final Validation
        let stage5_prompt = format!(
            r#"
            Finally, validate the XML annotations against these requirements:
            1. All original text is preserved outside correction tags.
            2. No words are omitted, duplicated, or reordered.
            3. XML is well-formed (proper nesting/closing tags).
            4. Corrections are properly nested when overlapping.
            5. Explanations are included for non-obvious corrections.

            If any issues are found, fix them and return the corrected XML.
            If no issues are found, return the validated XML.

            Current XML:
            {}
            "#,
            stage4_xml
        );

        conversation.push(chat_completion::ChatCompletionMessage {
            role: MessageRole::user,
            content: Content::Text(stage5_prompt),
            name: None,
            tool_calls: None,
            tool_call_id: None,
        });

        // Send Stage 5 request
        let stage5_req = ChatCompletionRequest::new(
            "openai/gpt-4o-2024-11-20".to_string(),
            conversation,
        );

        let stage5_result = self
            .client
            .chat_completion(stage5_req)
            .await
            .map_err(|e| ProcessorError(format!("LLM API error for Stage 5: {}", e)))?;

        let stage5_response = match &stage5_result.choices[0].message.content {
            Some(content) => content.clone(),
            None => return Err(ProcessorError("No content returned from LLM for Stage 5".to_string())),
        };

        // Extract final XML content
        let final_xml = match Self::extract_xml_content(&stage5_response) {
            Ok(xml) => xml,
            Err(_) => {
                // If extraction fails, use the previous stage's XML
                debug!("Failed to extract XML from Stage 5 response, using Stage 4 XML");
                stage4_xml
            }
        };

        info!("Completed all annotation stages for submission {}", id);

        Ok(final_xml)
    }

    async fn evaluate_prompt_relevance(
        &self,
        id: i64,
        text: &str,
        prompt_topic: &str,
    ) -> Result<i64, ProcessorError> {
        info!("Step 3: Evaluating prompt relevance for submission {}", id);
        // Create the prompt for the LLM to evaluate prompt relevance
        let relevance_prompt = format!(
            "You are an essay evaluator. Your task is to evaluate how well the following essay addresses the given prompt.\n\n
            Prompt: \"{}\"\n\n
            Essay:\n{}\n\n
            On a scale of 0 to 100, where:\n
            - 0-20: Completely off-topic, doesn't address the prompt at all\n
            - 21-40: Barely addresses the prompt, mostly irrelevant\n
            - 41-60: Partially addresses the prompt, but with significant gaps\n
            - 61-80: Adequately addresses the prompt with minor gaps\n
            - 81-100: Fully addresses the prompt with depth and insight\n\n
            Provide only a single number as your response, representing your score for prompt relevance.",
            prompt_topic, text
        );

        // Create the request for prompt relevance
        let relevance_req = ChatCompletionRequest::new(
            "openai/chatgpt-4o-latest".to_string(),
            vec![chat_completion::ChatCompletionMessage {
                role: MessageRole::user,
                content: Content::Text(relevance_prompt),
                name: None,
                tool_calls: None,
                tool_call_id: None,
            }],
        );

        // Send the request to the LLM
        let relevance_result = self
            .client
            .chat_completion(relevance_req)
            .await
            .map_err(|e| ProcessorError(format!("LLM API error for relevance: {}", e)))?;

        // Extract the relevance score from the response
        let relevance_text = match &relevance_result.choices[0].message.content {
            Some(content) => content.clone(),
            None => {
                return Err(ProcessorError(
                    "No content returned from LLM for relevance".to_string(),
                ))
            }
        };

        // Parse the relevance score
        let relevance_score = parse_relevance_score(&relevance_text)
            .map_err(|e| ProcessorError(format!("Failed to parse relevance score: {}", e)))?;

        Ok(relevance_score)
    }
}

// Parse the relevance score from the LLM response
fn parse_relevance_score(text: &str) -> Result<i64, String> {
    // Use regex to find a number in the text
    let re = regex::Regex::new(r"\b(\d{1,3})\b").unwrap();

    if let Some(captures) = re.captures(text) {
        if let Some(score_match) = captures.get(1) {
            let score_str = score_match.as_str();
            match score_str.parse::<i64>() {
                Ok(score) => {
                    // Ensure the score is between 0 and 100
                    return Ok(score.max(0).min(100));
                }
                Err(_) => return Err(format!("Failed to parse '{}' as a number", score_str)),
            }
        }
    }

    Err("No valid score found in the response".to_string())
}

// Count and categorize corrections using the parsed data structure
fn count_corrections(annotated_text: &str) -> (i64, HashMap<String, i64>) {
    // Parse the XML using your custom parser
    let parsed_result = match parse_xml_corrections(annotated_text) {
        Ok(parsed) => parsed,
        Err(e) => {
            eprintln!("Error parsing XML: {:?}", e);
            return (0, HashMap::new());
        }
    };

    // Initialize counters
    let mut total_errors = 0;
    let mut error_types = HashMap::new();

    // Count top-level corrections
    for correction in &parsed_result.corrections {
        total_errors += 1;
        *error_types
            .entry(correction.error_type.clone())
            .or_insert(0) += 1;

        // Recursively count nested corrections
        count_nested_corrections(correction, &mut error_types, &mut total_errors);
    }

    (total_errors, error_types)
}

// Helper function to recursively count nested corrections
fn count_nested_corrections(
    correction: &Correction,
    error_types: &mut HashMap<String, i64>,
    total_errors: &mut i64,
) {
    for child in &correction.children {
        *total_errors += 1;
        *error_types.entry(child.error_type.clone()).or_insert(0) += 1;

        // Recursively process children of this child
        count_nested_corrections(child, error_types, total_errors);
    }
}

// Calculate language score based on weighted error types and text length
fn calculate_language_score(original: &str, annotated: &str) -> i64 {
    // Get word count from original text
    let word_count = original.split_whitespace().count() as f64;

    // Count errors by type using our custom parser
    let (total_errors, error_types) = count_corrections(annotated);

    // Define weights for different error types (more severe errors have higher weights)
    let error_weights = HashMap::from([
        ("SPELLING".to_string(), 1.0),       // Minor
        ("PUNCTUATION".to_string(), 1.0),    // Minor
        ("CAPITALIZATION".to_string(), 1.0), // Minor
        ("WORD_CHOICE".to_string(), 1.5),    // Moderate
        ("GRAMMAR".to_string(), 2.0),        // Significant
        ("STYLE".to_string(), 1.5),          // Moderate
        ("REPETITION".to_string(), 1.2),     // Moderate
        ("STRUCTURAL".to_string(), 2.5),     // Major
        ("COHERENCE".to_string(), 2.5),      // Major
        ("FACTUAL".to_string(), 2.0),        // Significant
        ("FORMATTING".to_string(), 0.8),     // Minor
    ]);

    // Calculate weighted error score
    let mut weighted_error_sum = 0.0;

    for (error_type, count) in error_types {
        let weight = error_weights.get(&error_type).unwrap_or(&1.0);
        weighted_error_sum += *weight * count as f64;
    }

    // Base score of 100
    let base_score = 100.0;

    // Calculate error density (errors per 100 words)
    let error_density = if word_count > 0.0 {
        (weighted_error_sum / word_count) * 100.0
    } else {
        0.0
    };

    // Apply length-based normalization
    // For very short essays (<100 words), errors are more impactful
    // For longer essays (>500 words), we're slightly more forgiving
    let length_factor = if word_count < 100.0 {
        1.2 // Stricter for very short essays
    } else if word_count > 500.0 {
        0.9 // More lenient for longer essays
    } else {
        // Linear interpolation between 1.2 and 0.9 for essays between 100-500 words
        1.2 - (word_count - 100.0) * (0.3 / 400.0)
    };

    // Calculate penalty based on error density and length factor
    let error_penalty = error_density * length_factor;

    // Apply diminishing returns for very high error counts
    // (to avoid extremely low scores for essays with many errors)
    let adjusted_penalty = if error_penalty > 50.0 {
        50.0 + (error_penalty - 50.0) * 0.5
    } else {
        error_penalty
    };

    // Ensure score is between 0 and 100
    let score = (base_score - adjusted_penalty).max(0.0).min(100.0);

    score.round() as i64
}

// Calculate final score as weighted average of language score and prompt relevance
// with additional considerations for essay length
fn calculate_final_score(language_score: i64, prompt_relevance: i64, word_count: usize) -> i64 {
    // Base weights: 60% language quality, 40% prompt relevance
    let mut language_weight = 0.6;
    let mut relevance_weight = 0.4;

    // Adjust weights based on essay length
    if word_count < 100 {
        // For very short essays, language mechanics are less important than addressing the prompt
        language_weight = 0.5;
        relevance_weight = 0.5;
    } else if word_count > 500 {
        // For longer essays, language mechanics become more important
        language_weight = 0.65;
        relevance_weight = 0.35;
    }

    // Apply length bonus/penalty for very short or very long essays
    let length_adjustment = if word_count < 50 {
        -5.0 // Penalty for extremely short essays
    } else if word_count < 100 {
        -2.0 // Small penalty for short essays
    } else if word_count > 1000 {
        3.0 // Bonus for very comprehensive essays
    } else if word_count > 700 {
        1.0 // Small bonus for longer essays
    } else {
        0.0 // No adjustment for medium-length essays
    };

    // Calculate weighted score
    let weighted_score = (language_score as f64 * language_weight)
        + (prompt_relevance as f64 * relevance_weight)
        + length_adjustment;

    // Ensure final score is between 0 and 100
    weighted_score.round().max(0.0).min(100.0) as i64
}

// Function to run the processor as a background task
pub async fn run_processor_loop() {
    // Get database connection
    let db_url = std::env::var("DATABASE_URL").unwrap_or_else(|_| "sqlite:app.db".to_string());

    // Connect to the database
    let db = match SqlitePool::connect(&db_url).await {
        Ok(db) => db,
        Err(e) => {
            error!("Failed to connect to database: {}", e);
            return;
        }
    };

    // Create processor
    let processor = match LlmProcessor::new(db) {
        Ok(p) => p,
        Err(e) => {
            error!("Failed to create LLM processor: {}", e);
            return;
        }
    };

    info!("Starting LLM processor background task");

    loop {
        if let Err(e) = processor.process_pending_submissions().await {
            error!("Error in processor loop: {}", e);
        }

        // Sleep for a while before checking for new submissions
        info!("Sleeping for 60 seconds before next check");
        sleep(Duration::from_secs(60)).await;
    }
}
