// src/handlers/api.rs
use axum::{
    extract::{Extension, Path},
    response::Json,
};
use serde::Serialize;
use sqlx::SqlitePool;
use crate::models::Analysis;

#[derive(Serialize)]
pub struct AnalysisResponse {
    pub id: i64,
    pub uuid: String,
    pub original_text: String,
    pub annotated_text: String,
    pub score: f64,
    pub created_at: String,
}

pub async fn get_status_json(
    Path(uuid): Path<String>,
    Extension(pool): Extension<SqlitePool>,
) -> Json<Option<AnalysisResponse>> {
    let rec = sqlx::query_as!(
        Analysis,
        r#"
        SELECT
            id as "id!",
            uuid,
            original_text,
            annotated_text,
            score as "score!",
            created_at as "created_at!",
            user_id as "user_id?"
        FROM text_checks
        WHERE uuid = ?
        "#,
        uuid
    )
    .fetch_optional(&pool)
    .await;

    if let Ok(Some(analysis)) = rec {
        let response = AnalysisResponse {
            id: analysis.id,
            uuid: analysis.uuid,
            original_text: analysis.original_text,
            annotated_text: analysis.annotated_text,
            score: analysis.score,
            created_at: analysis.created_at.to_string(),
        };
        Json(Some(response))
    } else {
        Json(None)
    }
}

