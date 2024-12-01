use axum::{response::IntoResponse, extract::Form};
use serde::Deserialize;
use crate::HtmlTemplate;

pub async fn hidden() -> impl IntoResponse {
   let template = HiddenTemplate {};
   HtmlTemplate(template)
}

#[derive(askama::Template)]
#[template(path = "hidden.html")]
pub struct HiddenTemplate {}
