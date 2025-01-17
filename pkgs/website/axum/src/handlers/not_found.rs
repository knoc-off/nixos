use axum::response::IntoResponse;

use crate::HtmlTemplate;

pub async fn not_found() -> impl IntoResponse {
    let template = NotFound {};
    HtmlTemplate(template)
}

#[derive(askama::Template)]
#[template(path = "404.html")]
pub struct NotFound {}
