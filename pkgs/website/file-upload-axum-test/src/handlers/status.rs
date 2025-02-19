// src/handlers/status.rs
use askama::Template;
use axum::{
    extract::{Path, State},
    response::IntoResponse,
};
use crate::{
    models::AppState,
    utils::templates::HtmlTemplate,
};

#[derive(Template)]
#[template(path = "result.html")]
struct ResultTemplate {
    items: Vec<crate::models::TextItem>,
    process_id: String,
}

pub async fn check_status(
    State(state): State<AppState>,
    Path(process_id): Path<String>,
) -> impl IntoResponse {
    let items = state.results_store.get(&process_id).await.unwrap_or_default();
    HtmlTemplate(ResultTemplate { items, process_id })
}
