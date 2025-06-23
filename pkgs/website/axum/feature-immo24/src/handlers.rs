// feature-immo24/src/handlers.rs

use crate::models::{
    AiInsights, GenerateMessagePayload, GeneratedMessageResponse,
    ImmoSettings, ListQueryParams, Listing, NewListing, ProcessingStatus,
    ReasoningContext, UpdateListingPayload,
};
use app_state::AppState;
use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::Json,
};
use serde::de::DeserializeOwned;
use serde::Deserialize;
use serde_json::{json, Value as JsonValue};
use std::time::Duration;

const MAX_LLM_RETRIES: u32 = 3;
const LLM_RETRY_DELAY: Duration = Duration::from_millis(500);

// --- HELPER FUNCTIONS (Unchanged) ---

async fn update_status(
    pool: &sqlx::SqlitePool,
    scout_id: &str,
    status: ProcessingStatus,
    error: Option<String>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE immo24_listings SET processing_status = ?, processing_error = ? WHERE scout_id = ?",
    )
    .bind(status)
    .bind(error)
    .bind(scout_id)
    .execute(pool)
    .await?;
    Ok(())
}

async fn call_structured_llm<T>(
    state: &AppState,
    model: &str,
    initial_prompt: String,
) -> Result<T, anyhow::Error>
where
    T: DeserializeOwned,
{
    let openrouter_api_key = state.settings.openrouter_api_key.clone();

    let mut last_error: Option<anyhow::Error> = None;
    let mut messages =
        vec![json!({"role": "user", "content": initial_prompt})];

    for attempt in 0..MAX_LLM_RETRIES {
        if attempt > 0 {
            tracing::warn!(
                "Retrying LLM call (attempt {}/{})",
                attempt + 1,
                MAX_LLM_RETRIES
            );
            tokio::time::sleep(LLM_RETRY_DELAY).await;
        }

        let request_body = json!({
            "model": model,
            "messages": messages,
            "response_format": { "type": "json_object" }
        });

        let response = match state
            .http_client
            .post("https://openrouter.ai/api/v1/chat/completions")
            .bearer_auth(&openrouter_api_key)
            .json(&request_body)
            .send()
            .await
        {
            Ok(res) => res,
            Err(e) => {
                last_error = Some(e.into());
                continue;
            }
        };

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            last_error = Some(anyhow::anyhow!(
                "API Error during extraction: {}",
                error_text
            ));
            continue;
        }

        let ai_response: JsonValue = match response.json().await {
            Ok(json) => json,
            Err(e) => {
                last_error = Some(e.into());
                continue;
            }
        };

        let content = match ai_response["choices"][0]["message"]["content"]
            .as_str()
        {
            Some(text) => text,
            None => {
                last_error = Some(anyhow::anyhow!(
                    "Failed to extract content string from AI response: {:?}",
                    ai_response
                ));
                continue;
            }
        };

        match serde_json::from_str::<T>(content) {
            Ok(structured_data) => return Ok(structured_data),
            Err(e) => {
                last_error = Some(e.into());
                let correction_prompt = json!({
                    "role": "user",
                    "content": format!(
                        "Your last response was not valid JSON that matched the required schema. \
                        Error: '{}'. \
                        Invalid response snippet: '{}'. \
                        Please correct your response and output ONLY the valid JSON object.",
                        last_error.as_ref().unwrap(),
                        content
                    )
                });
                messages.push(json!({"role": "assistant", "content": content}));
                messages.push(correction_prompt);
            }
        }
    }

    Err(last_error.unwrap_or_else(|| {
        anyhow::anyhow!("LLM call failed after {} retries", MAX_LLM_RETRIES)
    }))
}

// --- BACKGROUND PROCESSING (Unchanged) ---

async fn run_extraction_step(
    state: &AppState,
    listing: &Listing,
) -> Result<AiInsights, anyhow::Error> {
    update_status(
        &state.pool,
        &listing.scout_id,
        ProcessingStatus::Extracting,
        None,
    )
    .await?;

    // --- REVISED PROMPT ---
    let prompt = format!(
        r#"
You are a highly precise data extraction engine. Your task is to analyze the German real estate listing text provided below and extract specific information into a structured JSON format.

**Rules:**
1.  Your response MUST be ONLY a single, valid JSON object.
2.  Ignore marketing talk. the posts will often try to sell the place like its gold. you should see through this.
3.  Do not include explanations, apologies, or any text outside of the JSON object.
4.  Do not use markdown formatting like ```json.
5.  If a piece of information is not present in the text, use `null` for optional fields (like `summary`) and an empty array `[]` for list fields (like `key_features`).
6.  All text in the output JSON should be in English.

**JSON Schema to follow:**
{{
  "summary": "string | null - A brief, one-paragraph summary of the property.",
  "key_features": "string[] - An array of positive features mentioned (e.g., 'Balcony', 'New Kitchen', 'Hardwood Floors').",
  "potential_cons": "string[] - An array of potential drawbacks mentioned (e.g., 'Noisy Street', 'No Elevator', 'Old Heating').",
  "floor_level": "string | null - The floor the apartment is on (e.g., '3rd floor', 'Ground floor', 'Top floor').",
  "pet_policy": "string | null - The policy on pets. Should be one of: 'Allowed', 'Not Allowed', 'On Request'.",
  "application_requirements": "Vec<(String, String)> - An array of tuples where the first element is the document (e.g., 'SCHUFA', 'Proof of income') and the second element is the exact sentence, from the text, in which the document is mentioned."
}}

--- GERMAN LISTING TEXT ---
{:?}
--- END OF TEXT ---
"#,
        listing.text_descriptions
    );

    // Use our new robust function to get guaranteed structured output
    let extracted_insights: AiInsights = call_structured_llm(
        state,
        "google/gemini-2.0-flash-001",
        prompt,
    )
    .await?;

    // Save the successfully extracted insights to the database
    sqlx::query(
        "UPDATE immo24_listings SET ai_insights = ? WHERE scout_id = ?",
    )
    .bind(json!(&extracted_insights))
    .bind(&listing.scout_id)
    .execute(&state.pool)
    .await?;

    Ok(extracted_insights)
}

async fn run_reasoning_step(
    state: &AppState,
    scout_id: &str,
    mut current_insights: AiInsights,
    context: &ReasoningContext,
) -> Result<AiInsights, anyhow::Error> {
    // ... function body is unchanged
    update_status(
        &state.pool,
        scout_id,
        ProcessingStatus::Reasoning,
        None,
    )
    .await?;

    // Define the struct for the reasoning response, as it's a subset of AiInsights
    #[derive(Deserialize)]
    struct ReasoningResponse {
        fitness_score: u8,
        fitness_verdict: String,
        fitness_notes: String,
    }

    // --- REVISED PROMPT ---
    let prompt = format!(
        r#"
You are a meticulous real estate evaluation agent. Your task is to analyze a property's structured data against a client's specific criteria and provide a reasoned evaluation.

**Your Thought Process (Follow these steps):**
1.  **Check for Deal-breakers:** First, review the property's `key_features` and `potential_cons`. If any of the client's `Deal-breakers` are present, the verdict MUST be "Reject" and the score MUST be 10 or less.
2.  **Evaluate Desired Features:** Next, count how many of the client's `Desired Features` are mentioned in the property's `key_features`.
3.  **Synthesize Score and Verdict:** Based on the presence of desired features and the absence of deal-breakers, determine a final score and verdict. A property with all desired features and no cons should be close to 100. A property with few desired features should be a "PoorMatch".
4.  **Formulate Notes:** Write a concise, bullet-point explanation for your decision, directly referencing which criteria were met or missed.

---
**Client's Criteria:**
- Desired Features: {:?}
- Deal-breakers (MUST NOT have): {:?}

---
**Property Data (from previous extraction step):**
{}

---
**Your Response:**
Your response MUST be ONLY a single, valid JSON object. Do not use markdown. Adhere strictly to this schema:
{{
  "fitness_score": "number - An integer from 0 to 100.",
  "fitness_verdict": "string - MUST be one of: 'Reject', 'PoorMatch', 'GoodMatch', 'ExcellentMatch'.",
  "fitness_notes": "string - A concise, bulleted explanation for the score and verdict."
}}
"#,
        context.desired_features,
        context.dealbreaker_features,
        serde_json::to_string_pretty(&current_insights)?
    );

    // For a complex reasoning task, a more powerful model might yield better results.
    // Gemini 2.5 Pro is a strong candidate for this.
    let reasoning_data: ReasoningResponse = call_structured_llm(
        state,
        "google/gemini-2.0-flash-001", // Switched to Pro for better reasoning
        prompt,
    )
    .await?;

    // Merge the reasoning results into our main insights struct
    current_insights.fitness_score = Some(reasoning_data.fitness_score);
    current_insights.fitness_verdict = Some(reasoning_data.fitness_verdict);
    current_insights.fitness_notes = Some(reasoning_data.fitness_notes);

    // Save the fully populated insights to the database
    sqlx::query(
        "UPDATE immo24_listings SET ai_insights = ? WHERE scout_id = ?",
    )
    .bind(json!(&current_insights))
    .bind(scout_id)
    .execute(&state.pool)
    .await?;

    Ok(current_insights)
}
async fn process_listing_insights(
    state: AppState,
    scout_id: String,
    context: ReasoningContext,
) {
    // ... function body is unchanged
    // 1. Fetch the initial listing data
    let listing = match sqlx::query_as::<_, Listing>(
        "SELECT * FROM immo24_listings WHERE scout_id = ?",
    )
    .bind(&scout_id)
    .fetch_one(&state.pool)
    .await
    {
        Ok(data) => data,
        Err(e) => {
            tracing::error!("Background task failed to fetch listing data: {}", e);
            // No need to update status here, as the listing doesn't exist.
            return;
        }
    };

    // --- RUN EXTRACTION STEP ---
    let extracted_insights = match run_extraction_step(&state, &listing).await {
        Ok(insights) => insights,
        Err(e) => {
            tracing::error!("Extraction failed for {}: {}", &scout_id, e);
            let _ = update_status(
                &state.pool,
                &scout_id,
                ProcessingStatus::ExtractionFailed,
                Some(e.to_string()),
            )
            .await;
            return;
        }
    };

    // --- RUN REASONING STEP ---
    match run_reasoning_step(&state, &scout_id, extracted_insights, &context)
        .await
    {
        Ok(_) => {
            // Final success status
            let _ = update_status(
                &state.pool,
                &scout_id,
                ProcessingStatus::Completed,
                None,
            )
            .await;
            tracing::info!("Successfully processed listing {}", &scout_id);
        }
        Err(e) => {
            tracing::error!("Reasoning failed for {}: {}", &scout_id, e);
            let _ = update_status(
                &state.pool,
                &scout_id,
                ProcessingStatus::ReasoningFailed,
                Some(e.to_string()),
            )
            .await;
        }
    }
}

// --- API HANDLERS ---

/// **MODIFIED: Now fetches settings to start background processing.**
pub async fn create_listing(
    State(state): State<AppState>,
    Json(payload): Json<NewListing>,
) -> Result<(StatusCode, Json<Listing>), (StatusCode, String)> {
    let insert_query = sqlx::query(
        "INSERT INTO immo24_listings (
            scout_id, status, total_rent, address, published_at, notes,
            property_details, source_stats, contact_person, text_descriptions, ai_insights
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&payload.scout_id)
    .bind(payload.status.unwrap_or_else(|| "new".to_string()))
    .bind(payload.total_rent)
    .bind(payload.address)
    .bind(payload.published_at)
    .bind(payload.notes)
    .bind(json!(payload.property_details))
    .bind(json!(payload.source_stats))
    .bind(json!(payload.contact_person))
    .bind(json!(payload.text_descriptions))
    .bind(json!(AiInsights::default()))
    .execute(&state.pool)
    .await;

    if let Err(err) = insert_query {
        tracing::error!("Failed to insert new listing: {}", err);
        if err.to_string().contains("UNIQUE constraint failed") {
            return Err((StatusCode::CONFLICT, err.to_string()));
        }
        return Err((StatusCode::INTERNAL_SERVER_ERROR, err.to_string()));
    }

    let initial_listing = sqlx::query_as::<_, Listing>(
        "SELECT * FROM immo24_listings WHERE scout_id = ?",
    )
    .bind(&payload.scout_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    // --- MODIFICATION: Fetch settings from DB ---
    let settings = get_settings(State(state.clone()))
        .await
        .map_err(|e| (e, "Failed to fetch settings for processing".to_string()))?;
    let reasoning_context = settings.0.reasoning_context; // .0 to get Json inner value

    // --- SPAWN THE BACKGROUND TASK ---
    let state_clone = state.clone();
    let scout_id_clone = initial_listing.scout_id.clone();
    tokio::spawn(async move {
        process_listing_insights(state_clone, scout_id_clone, reasoning_context)
            .await;
    });

    Ok((StatusCode::ACCEPTED, Json(initial_listing)))
}

// --- NEW: Settings Handlers ---

/// **NEW: Get the current application settings.**
pub async fn get_settings(
    State(state): State<AppState>,
) -> Result<Json<ImmoSettings>, StatusCode> {
    // Fetch the single row of settings from the database.
    // We use `fetch_optional` in case the table is empty, providing defaults.
    let row: Option<(String, String)> = sqlx::query_as(
        "SELECT reasoning_context, message_template FROM immo24_settings WHERE id = 1",
    )
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!("Failed to fetch settings: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    if let Some((context_json, template)) = row {
        let reasoning_context = serde_json::from_str(&context_json)
            .unwrap_or_else(|_| ReasoningContext::default());
        Ok(Json(ImmoSettings {
            reasoning_context,
            message_template: template,
        }))
    } else {
        // If no settings row exists, return a default configuration.
        Ok(Json(ImmoSettings {
            reasoning_context: ReasoningContext::default(),
            message_template: "".to_string(),
        }))
    }
}

/// **NEW: Update the application settings.**
pub async fn update_settings(
    State(state): State<AppState>,
    Json(payload): Json<ImmoSettings>,
) -> Result<Json<ImmoSettings>, StatusCode> {
    let context_json = serde_json::to_string(&payload.reasoning_context)
        .map_err(|_| StatusCode::BAD_REQUEST)?;

    // Use an "UPSERT" query to either insert the first row or update it if it exists.
    sqlx::query(
        "INSERT INTO immo24_settings (id, reasoning_context, message_template)
         VALUES (1, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
            reasoning_context = excluded.reasoning_context,
            message_template = excluded.message_template,
            updated_at = strftime('%Y-%m-%d %H:%M:%f', 'now')",
    )
    .bind(context_json)
    .bind(&payload.message_template)
    .execute(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!("Failed to update settings: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    Ok(Json(payload))
}

// --- NEW: Interactive "Bot" Handler ---

pub async fn generate_message_handler(
    State(state): State<AppState>,
    Path(scout_id): Path<String>,
    Json(payload): Json<GenerateMessagePayload>,
) -> Result<Json<GeneratedMessageResponse>, StatusCode> {
    // 1. Fetch the listing data
    let listing = sqlx::query_as::<_, Listing>(
        "SELECT * FROM immo24_listings WHERE scout_id = ?",
    )
    .bind(&scout_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|_| StatusCode::NOT_FOUND)?;

    // 2. Fetch the current settings
    let settings = get_settings(State(state.clone())).await?.0;

    // 3. Construct the prompt for the LLM
    let prompt = format!(
        r#"
You are a helpful assistant who personalizes a German-language application message for a real estate listing.

**Your Task:**
1.  Take the user's message template as a base.
2.  Analyze the provided "Property Data" and "User Criteria".
3.  dont make it too formal, keep the tone neutral, and you dont need to go out of your way to include any specifics of the property
4.  Subtly weave details from the property data into the template to make it sound personal and informed. For example, mention a specific feature you like that matches the user's criteria.
5.  If the user provides a "Refinement Instruction", apply that change to your generated message.
6.  Your final output must be ONLY the personalized message text inside a JSON object.
7.  Keep it short and to the point.

---
**User's Message Template:**
```
{}
```

---
**Property Data:**
```json
{}
```

---
**User Criteria, and Data:**
```json
{}
```

---
**Refinement Instruction (if any):**
{}

---
**Your Response (JSON only):**
Adhere strictly to this schema:
{{
  "message": "string - The final, personalized German message."
}}
"#,
        settings.message_template,
        serde_json::to_string_pretty(&listing).unwrap(),
        serde_json::to_string_pretty(&settings.reasoning_context).unwrap(),
        payload
            .refinement_prompt
            .unwrap_or_else(|| "No specific refinement instruction.".to_string())
    );

    #[derive(Deserialize)]
    struct MessageResponse {
        message: String,
    }

    // 4. Call the LLM
    let result: Result<MessageResponse, _> = call_structured_llm(
        &state,
        "google/gemini-2.5-pro-preview", // A powerful model is best for this creative task
        prompt,
    )
    .await;

    match result {
        Ok(response) => Ok(Json(GeneratedMessageResponse {
            message: response.message,
        })),
        Err(e) => {
            tracing::error!("Message generation failed: {}", e);
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

// --- Unchanged Handlers ---
pub async fn query_listings(
    State(state): State<AppState>,
    Query(params): Query<ListQueryParams>,
) -> Result<Json<Vec<Listing>>, StatusCode> {
    // ... function body is unchanged
    let mut query_builder = sqlx::QueryBuilder::new(
        "SELECT * FROM immo24_listings WHERE 1=1" // Start with a always-true condition
    );

    tracing::info!("Query params - status: {:?}", params.status);

    // Apply filters based on query parameters
    if let Some(status) = params.status {
        query_builder.push(" AND status = ");
        query_builder.push_bind(status);
    }

    // if let Some(min_rent) = params.min_rent {
    //     query_builder.push(" AND total_rent >= ");
    //     query_builder.push_bind(min_rent);
    // }

    query_builder.push(" ORDER BY published_at DESC, created_at DESC");

    // Apply limit and offset for pagination
    if let Some(limit) = params.limit {
        query_builder.push(" LIMIT ");
        query_builder.push_bind(limit);
    } else {
        // Default limit if not provided
        query_builder.push(" LIMIT 20");
    }

    if let Some(offset) = params.offset {
        query_builder.push(" OFFSET ");
        query_builder.push_bind(offset);
    }

    let sql = query_builder.sql();
    tracing::info!("Executing query: {}", sql);


    // Build and execute the query
    let result = query_builder
        .build_query_as::<Listing>()
        .fetch_all(&state.pool)
        .await;

    match result {
        Ok(listings) => Ok(Json(listings)),
        Err(err) => {
            tracing::error!("Failed to list listings: {}", err);
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}


pub async fn get_listing(
    State(state): State<AppState>,
    Path(scout_id): Path<String>,
) -> Result<Json<Listing>, StatusCode> {
    // First, ensure the listing exists. If not, return 404.
    let current_listing = sqlx::query_as::<_, Listing>("SELECT * FROM immo24_listings WHERE scout_id = ?")
        .bind(&scout_id)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| {
            if matches!(e, sqlx::Error::RowNotFound) {
                StatusCode::NOT_FOUND
            } else {
                tracing::error!("Failed to fetch listing for update: {}", e);
                StatusCode::INTERNAL_SERVER_ERROR
            }
        })?;

    Ok(Json(current_listing))
}


pub async fn update_listing(
    State(state): State<AppState>,
    Path(scout_id): Path<String>,
    Json(payload): Json<UpdateListingPayload>,
) -> Result<Json<Listing>, StatusCode> {
    // First, ensure the listing exists. If not, return 404.
    let current_listing = sqlx::query_as::<_, Listing>("SELECT * FROM immo24_listings WHERE scout_id = ?")
        .bind(&scout_id)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| {
            if matches!(e, sqlx::Error::RowNotFound) {
                StatusCode::NOT_FOUND
            } else {
                tracing::error!("Failed to fetch listing for update: {}", e);
                StatusCode::INTERNAL_SERVER_ERROR
            }
        })?;

    // Start building the dynamic UPDATE query
    let mut builder: sqlx::QueryBuilder<sqlx::Sqlite> = sqlx::QueryBuilder::new("UPDATE immo24_listings SET ");
    let mut separator = builder.separated(", ");
    let mut has_updates = false;

    // --- Handle all simple column updates ---
    if let Some(status) = payload.status {
        separator.push("status = ");
        separator.push_bind_unseparated(status);
        has_updates = true;
    }
    if let Some(notes) = payload.notes {
        separator.push("notes = ");
        separator.push_bind_unseparated(notes);
        has_updates = true;
    }
    if let Some(total_rent) = payload.total_rent {
        separator.push("total_rent = ");
        separator.push_bind_unseparated(total_rent);
        has_updates = true;
    }
    if let Some(address) = payload.address {
        separator.push("address = ");
        separator.push_bind_unseparated(address);
        has_updates = true;
    }
    if let Some(published_at) = payload.published_at {
        separator.push("published_at = ");
        separator.push_bind_unseparated(published_at);
        has_updates = true;
    }

    // Helper function for JSON merging
    fn merge(target: &mut JsonValue, patch: &JsonValue) {
        if let JsonValue::Object(target_map) = target {
            if let JsonValue::Object(patch_map) = patch {
                for (key, value) in patch_map {
                    if let Some(target_value) = target_map.get_mut(key) {
                        merge(target_value, value);
                    } else {
                        target_map.insert(key.clone(), value.clone());
                    }
                }
                return;
            }
        }
        *target = patch.clone();
    }

    // --- Handle JSON column updates ---
    if let Some(patch) = payload.property_details {
        let mut current_json = json!(current_listing.property_details);
        merge(&mut current_json, &patch);
        separator.push("property_details = ");
        separator.push_bind_unseparated(current_json.to_string());
        has_updates = true;
    }
    if let Some(patch) = payload.source_stats {
        let mut current_json = json!(current_listing.source_stats);
        merge(&mut current_json, &patch);
        separator.push("source_stats = ");
        separator.push_bind_unseparated(current_json.to_string());
        has_updates = true;
    }
    if let Some(patch) = payload.contact_person {
        let mut current_json = json!(current_listing.contact_person);
        merge(&mut current_json, &patch);
        separator.push("contact_person = ");
        separator.push_bind_unseparated(current_json.to_string());
        has_updates = true;
    }
    if let Some(patch) = payload.text_descriptions {
        let mut current_json = json!(current_listing.text_descriptions);
        merge(&mut current_json, &patch);
        separator.push("text_descriptions = ");
        separator.push_bind_unseparated(current_json.to_string());
        has_updates = true;
    }
    if let Some(patch) = payload.ai_insights {
        let mut current_json = json!(current_listing.ai_insights);
        merge(&mut current_json, &patch);
        separator.push("ai_insights = ");
        separator.push_bind_unseparated(current_json.to_string());
        has_updates = true;
    }

    // If no fields were provided for update, return the current listing
    if !has_updates {
        return Ok(Json(current_listing));
    }

    // Add updated_at timestamp
    separator.push("updated_at = strftime('%Y-%m-%d %H:%M:%f', 'now')");

    // Add the WHERE clause to update the correct row
    builder.push(" WHERE scout_id = ");
    builder.push_bind(scout_id.clone());

    // Execute the built query
    let update_result = builder.build().execute(&state.pool).await;
    if let Err(e) = update_result {
        tracing::error!("Failed to update listing {}: {}", scout_id, e);
        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    }

    // Fetch and return the fully updated listing to the client
    let updated_listing = sqlx::query_as::<_, Listing>("SELECT * FROM immo24_listings WHERE scout_id = ?")
        .bind(&scout_id)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!("Failed to fetch updated listing {}: {}", scout_id, e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(updated_listing))
}
