// app-main/src/utils/not_found.rs

use askama::Template;
use axum::{
    http::StatusCode,
    response::{Html, IntoResponse},
};

#[derive(Template)]
#[template(path = "not_found.html")] // This path is now relative to app-main/templates/
struct NotFoundTemplate {}

/// The handler for all requests that don't match any other route.
///
/// It explicitly returns a tuple of a status code and an HTML body.
pub async fn handler() -> impl IntoResponse {
    let template = NotFoundTemplate {};
    match template.render() {
        Ok(body) => (StatusCode::NOT_FOUND, Html(body)),
        // If the template fails to render, we should still send a response.
        Err(_) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Html("<h1>Internal Server Error</h1><p>Could not render error page.</p>".to_string()),
        ),
    }
}
