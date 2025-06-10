// src/utils/not_found.rs

use crate::utils::html::HtmlTemplate; // Use our utility wrapper
use askama::Template;
use axum::{http::StatusCode, response::IntoResponse};

/// The Askama template for our 404 page.
#[derive(Template)]
#[template(path = "not_found.html")]
struct NotFoundTemplate {}

/// The handler for all requests that don't match any other route.
///
/// It returns a `404 NOT FOUND` status code along with a rendered HTML page.
pub async fn handler() -> impl IntoResponse {
    let template = NotFoundTemplate {};
    (StatusCode::NOT_FOUND, HtmlTemplate(template))
}
