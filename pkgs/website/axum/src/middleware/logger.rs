// src/middleware/logger.rs

use axum::{
    extract::{Request, State},
    middleware::Next,
    response::Response,
};
use sqlx::SqlitePool;
use std::time::Instant;

pub async fn log_request(
    State(pool): State<SqlitePool>,
    req: Request,
    next: Next,
) -> Response {
    let start = Instant::now();
    let method = req.method().clone();
    let uri = req.uri().clone();

    let response = next.run(req).await;

    let latency = start.elapsed().as_millis();
    let status = response.status();

    // --- FIX IS HERE ---
    // Bind the values to variables before passing them to the macro.
    // This gives them a lifetime that is long enough.
    let method_str = method.to_string();
    let uri_str = uri.to_string();
    let status_code = status.as_u16() as i64;
    let latency_ms = latency as i64;

    let log_result = sqlx::query!(
        r#"
        INSERT INTO request_logs (method, uri, status_code, latency_ms)
        VALUES (?, ?, ?, ?)
        "#,
        method_str, // Now we pass the variables
        uri_str,
        status_code,
        latency_ms
    )
    .execute(&pool)
    .await;

    if let Err(e) = log_result {
        eprintln!("Failed to log request to database: {}", e);
    }

    response
}
