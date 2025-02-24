// src/routes.rs
use axum::{
    routing::{get, post},
    Router, Extension,
};
use sqlx::SqlitePool;
use crate::handlers::check::{index, handle_check};
use crate::handlers::results::{get_results_page, get_status};
use crate::handlers::api::get_status_json; // Import the new JSON endpoint

pub fn create_router(pool: SqlitePool) -> Router {
    Router::new()
        .route("/", get(index))
        .route("/check", post(handle_check))
        .route("/results/:uuid", get(get_results_page))
        .route("/status/:uuid", get(get_status))
        .route("/status_json/:uuid", get(get_status_json))
        .layer(Extension(pool))
}




