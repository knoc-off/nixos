use askama::Template;
use axum::{
    extract::{Extension, Form},
    response::IntoResponse,
};
use serde::Deserialize;
use sqlx::SqlitePool;
use tokio::time::{sleep, Duration};
use uuid::Uuid;
use crate::models::NewAnalysis;
use crate::utils::templates::HtmlTemplate;

#[derive(Template)]
#[template(path = "index.html")]
struct IndexTemplate {}

/// GET /
pub async fn index() -> impl IntoResponse {
    HtmlTemplate(IndexTemplate {})
}

#[derive(Deserialize)]
pub struct CheckForm {
    pub text: String,
}

/// POST /check
#[axum::debug_handler]
pub async fn handle_check(
    Extension(pool): Extension<SqlitePool>,
    Form(input): Form<CheckForm>,
) -> impl IntoResponse {
    // Simulate a processing delay
    sleep(Duration::from_secs(1)).await;

    // --- Simulated LLM Inline Markup ---
    // If the input text contains "teh", replace it inline with our markup.
    let annotated = if input.text.contains("teh") {
        input.text.replace("teh", "<<teh|the>>")
    } else {
        input.text.clone()
    };
    // You can add more inline markup rules here.
    let score = if annotated.contains("<<") { 0.8 } else { 1.0 };
    // --- End simulated LLM ---

    let new_uuid = Uuid::new_v4().to_string();
    let new_analysis = NewAnalysis {
        uuid: new_uuid.clone(),
        original_text: input.text,
        annotated_text: annotated,
        score,
    };

    if let Err(e) = new_analysis.save(&pool).await {
        tracing::error!("Failed to save analysis: {}", e);
        return (axum::http::StatusCode::INTERNAL_SERVER_ERROR, "DB error")
            .into_response();
    }

    // Return a processing page that polls /status/<uuid> via HTMX.
    HtmlTemplate(ProcessingTemplate { uuid: new_uuid }).into_response()
}

#[derive(Template)]
#[template(path = "processing.html")]
struct ProcessingTemplate {
    pub uuid: String,
}

