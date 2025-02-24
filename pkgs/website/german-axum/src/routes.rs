use axum::{
    routing::{get, post},
    Router, Extension,
};
use sqlx::SqlitePool;
use crate::handlers::check::{index, handle_check};
use crate::handlers::results::{get_results_page, get_status};

pub fn create_router(pool: SqlitePool) -> Router {
    Router::new()
        .route("/", get(index))
        .route("/check", post(handle_check))
        .route("/results/:uuid", get(get_results_page))
        .route("/status/:uuid", get(get_status))
        .layer(Extension(pool))
}




