// src/handlers/results.rs
use askama::Template;
use axum::{
    extract::{Extension, Path},
    response::IntoResponse,
};
use chrono::NaiveDateTime;
use sqlx::SqlitePool;
use crate::models::Analysis;
use crate::utils::templates::HtmlTemplate;

#[derive(Template)]
#[template(path = "result_fragment.html")]
struct ResultFragmentTemplate {
    pub analysis: Analysis,
}

/// GET /status/:uuid
pub async fn get_status(
    Path(uuid): Path<String>,
    Extension(pool): Extension<SqlitePool>,
) -> impl IntoResponse {
    let rec = sqlx::query_as!(
        Analysis,
        r#"
        SELECT
            id as "id!",
            uuid,
            original_text,
            annotated_text,
            score as "score!",
            created_at as "created_at!"
        FROM text_checks
        WHERE uuid = ?
        "#,
        uuid
    )
    .fetch_optional(&pool)
    .await;

    match rec {
        Ok(Some(analysis)) => {
            HtmlTemplate(ResultFragmentTemplate { analysis }).into_response()
        }
        _ => {
            // Return a simple loading fragment if not yet available.
            HtmlTemplate(LoadingTemplate {}).into_response()
        }
    }
}

#[derive(Template)]
#[template(path = "results.html")]
struct ResultsTemplate {
    pub analysis: Analysis,
}

/// GET /results/:uuid
pub async fn get_results_page(
    Path(uuid): Path<String>,
    Extension(pool): Extension<SqlitePool>,
) -> impl IntoResponse {
    let rec = sqlx::query_as!(
        Analysis,
        r#"
        SELECT
            id as "id!",
            uuid,
            original_text,
            annotated_text,
            score as "score!",
            created_at as "created_at!"
        FROM text_checks
        WHERE uuid = ?
        "#,
        uuid
    )
    .fetch_one(&pool)
    .await;

    match rec {
        Ok(analysis) => HtmlTemplate(ResultsTemplate { analysis }).into_response(),
        Err(e) => (
            axum::http::StatusCode::NOT_FOUND,
            format!("Result not found: {}", e),
        )
            .into_response(),
    }
}

#[derive(Template)]
#[template(source = "<div>Processing...</div>", ext = "html")]
struct LoadingTemplate;

