use axum::{response::IntoResponse, extract::Query};
use serde::Deserialize;

use crate::HtmlTemplate;

#[derive(Deserialize)]
pub struct NotFoundParams {
    pub url: Option<String>,
}

pub async fn not_found(Query(params): Query<NotFoundParams>) -> impl IntoResponse {
    let attempted_url = params.url.unwrap_or_else(|| "Unknown".to_string());
    let template = NotFound { attempted_url };
    HtmlTemplate(template)
}

#[derive(askama::Template)]
#[template(path = "404.html")]
pub struct NotFound {
    pub attempted_url: String,
}
