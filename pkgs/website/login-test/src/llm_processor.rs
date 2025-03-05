// src/llm_processor.rs
use openai_api_rs::v1::api::OpenAIClient;
use openai_api_rs::v1::chat_completion::{self, ChatCompletionRequest, Content, MessageRole};
use sqlx::SqlitePool;
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

            // Process each submission with the prompt topic using the new two-step approach
            match self
                .process_submission(submission.id, &submission.original_text, &submission.topic)
                .await
            {
                Ok((corrected_text, annotated_text, prompt_relevance)) => {
                    // Update the database with the corrected text and annotated text
                    // Also calculate a simple score and error count
                    let error_count = count_corrections(&annotated_text);
                    let language_score =
                        calculate_language_score(&submission.original_text, &annotated_text);

                    // Calculate final score as a weighted average of language score and prompt relevance
                    let final_score = calculate_final_score(language_score, prompt_relevance);

                    info!(
                        "Updating submission ID: {}. Language Score: {}, Prompt Relevance: {}, Final Score: {}, Errors: {}",
                        submission.id, language_score, prompt_relevance, final_score, error_count
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
                        error_count,
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
        debug!("Processing submission {} using two-step approach", id);

        // STEP 1: Generate a corrected version of the essay
        let corrected_text = self.generate_corrected_text(id, text, prompt_topic).await?;

        debug!("Generated corrected text for submission {}", id);

        // STEP 2: Generate annotated version showing the differences
        let annotated_text = self
            .generate_annotated_text(id, text, &corrected_text)
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

    async fn generate_annotated_text(
        &self,
        id: i64,
        original_text: &str,
        corrected_text: &str,
    ) -> Result<String, ProcessorError> {
        info!("Step 2: Generating annotated text for submission {}", id);

        // Create the prompt for the LLM to generate annotations in XML format
        let annotation_prompt = format!(
            "
                Analyze an original essay and its corrected version to create an annotated version of the ORIGINAL essay.

                **Annotation Format:** Use XML tags for corrections as follows:

                <correction type=\"TYPE\" explanation=\"optional explanation\">
                    <original>original text</original>
                    <corrected>corrected text</corrected>
                </correction>

                **Types:**
                - `TYPO`: Spelling errors
                - `GRAM`: Grammar errors
                - `PUNC`: Punctuation errors
                - `WORD`: Word choice issues
                - `STYL`: Stylistic issues (awkward phrasing, redundancy)
                - `STRUC`: Structural issues (organization, flow)

                **Guidelines:**
                - Choose the most appropriate error type
                - Provide concise explanations for non-obvious corrections
                - Nest corrections for multiple issues in the same text
                - Avoid overlapping corrections
                - Ensure proper XML formatting with opening and closing tags
                - Each word should appear only once in corrections

                **Example:** \"The students <correction type=\"GRAM\" explanation=\"Subject-verb agreement\"><original>is</original><corrected>are</corrected></correction> studying.\"

                ORIGINAL essay: {}

                CORRECTED essay: {}

                Your Final response should ONLY contain the annotated version of the original essay.
            ",
            original_text, corrected_text
        );

        // Create the request for annotations
        let annotation_req = ChatCompletionRequest::new(
            "deepseek/deepseek-r1-distill-llama-70b".to_string(),
            vec![chat_completion::ChatCompletionMessage {
                role: MessageRole::user,
                content: Content::Text(annotation_prompt),
                name: None,
                tool_calls: None,
                tool_call_id: None,
            }],
        );

        // Send the request to the LLM
        let annotation_result = self
            .client
            .chat_completion(annotation_req)
            .await
            .map_err(|e| ProcessorError(format!("LLM API error for annotations: {}", e)))?;

        // Extract the annotated text from the response
        let annotated_text = match &annotation_result.choices[0].message.content {
            Some(content) => content.clone(),
            None => {
                return Err(ProcessorError(
                    "No content returned from LLM for annotations".to_string(),
                ))
            }
        };

        Ok(annotated_text)
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

// Count the number of corrections in the text (updated for nested format)
fn count_corrections(text: &str) -> i64 {
    // Count all annotations of any type with the new nested format
    let re = regex::Regex::new(
        r"\[(TYPO|GRAM|PUNC|WORD|STYL|STRUC)\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\|[^|{}]*\|[^|{}]*\}]",
    )
    .unwrap();

    // This is a simplified approach - a proper recursive parser would be better
    // for accurately counting nested annotations
    re.find_iter(text).count() as i64
}

// Calculate language score based on the number of errors and text length
fn calculate_language_score(original: &str, annotated: &str) -> i64 {
    let word_count = original.split_whitespace().count() as f64;
    let error_count = count_corrections(annotated) as f64;

    // Base score of 100
    let base_score = 100.0;

    // Deduct points for errors (more impact for shorter essays)
    let error_penalty = if word_count > 0.0 {
        (error_count / word_count) * 100.0 * 2.0 // Multiply by 2 to make errors more impactful
    } else {
        0.0
    };

    // Ensure score is between 0 and 100
    let score = (base_score - error_penalty).max(0.0).min(100.0);

    score as i64
}

// Calculate final score as weighted average of language score and prompt relevance
fn calculate_final_score(language_score: i64, prompt_relevance: i64) -> i64 {
    // Weight: 60% language quality, 40% prompt relevance
    let weighted_score = (language_score as f64 * 0.6) + (prompt_relevance as f64 * 0.4);
    weighted_score.round() as i64
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
