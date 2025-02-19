// src/utils/templates.rs
use askama::Template;
use axum::response::{Html, IntoResponse};

pub struct HtmlTemplate<T>(pub T);

impl<T: Template> IntoResponse for HtmlTemplate<T> {
    fn into_response(self) -> axum::response::Response {
        match self.0.render() {
            Ok(html) => Html(html).into_response(),
            Err(err) => Html(format!(
                "<div class='error'>Template error: {}</div>",
                err
            )).into_response(),
        }
    }
}

