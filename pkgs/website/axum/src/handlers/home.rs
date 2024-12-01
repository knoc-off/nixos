use axum::response::IntoResponse;

use crate::HtmlTemplate;

pub async fn home() -> impl IntoResponse {
    let template = HomeTemplate {};
    HtmlTemplate(template)
}

#[derive(askama::Template)]
#[template(path = "home.html")]
pub struct HomeTemplate {}

