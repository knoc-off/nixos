// src/state.rs

use sqlx::SqlitePool;

/// The shared state for the entire application.
///
/// This struct holds all the shared resources, like database pools, HTTP clients,
/// or configuration, that our handlers and middleware might need.
///
/// By placing it in its own file, it can be easily imported by any module
/// (`blog`, `immo24`, `middleware`, etc.) without creating circular dependencies.
///
/// It's marked `#[derive(Clone)]` because Axum requires the state to be cloneable.
/// For `SqlitePool` (which is based on an `Arc`), this is a very cheap operation.
#[derive(Clone)]
pub struct AppState {
    pub pool: SqlitePool,
    // You can add other shared resources here in the future.
    // For example:
    // pub http_client: reqwest::Client,
    // pub app_config: Arc<AppConfig>,
}
