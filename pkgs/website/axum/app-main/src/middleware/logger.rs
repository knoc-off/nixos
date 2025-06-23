// app-main/src/middleware/logger.rs

use app_state::AppState; // <-- Use the crate here too
use axum::{
    extract::{Request, State},
    http::StatusCode,
    middleware::Next,
    response::Response,
};
use std::time::Instant;

pub async fn log_request(
    State(state): State<AppState>, // <-- Change this to use AppState
    req: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    let start = Instant::now();
    let method = req.method().clone();
    let uri = req.uri().clone();

    let response = next.run(req).await;

    let latency_ms = start.elapsed().as_millis() as i64;
    let status_code = response.status().as_u16() as i64;

    // Log the request to the database
    let _ = sqlx::query(
        "INSERT INTO request_logs (method, uri, status_code, latency_ms) VALUES (?, ?, ?, ?)",
    )
    .bind(method.to_string())
    .bind(uri.to_string())
    .bind(status_code)
    .bind(latency_ms)
    .execute(&state.pool) // <-- Use the pool from the state
    .await;

    Ok(response)
}
