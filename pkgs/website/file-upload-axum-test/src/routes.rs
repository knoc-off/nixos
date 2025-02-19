// src/routes.rs
use axum::{
    Router,
    routing::{get, post},
    middleware::from_fn,
};
use tower_http::services::ServeDir;
use crate::{
    handlers::{upload, status},
    models::AppState,
    utils::middleware::log_request,
    config,
};

pub async fn create_router(aws_config: aws_types::SdkConfig) -> Router {
    let state = AppState::new(aws_sdk_textract::Client::new(&aws_config));

    Router::new()
        .route("/", get(upload::show_page))
        .route("/upload", post(upload::handle_upload))
        .route("/status/:id", get(status::check_status))
        .nest_service("/results", ServeDir::new("website_data/results"))
        .nest_service("/static", ServeDir::new(config::static_content_path()))  // Fixed function name
        .layer(from_fn(log_request))
        .with_state(state)
}

