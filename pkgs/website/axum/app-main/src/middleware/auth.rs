// app-main/src/middleware/auth.rs
use app_state::AppState;
use axum::{
    extract::{Request, State},
    http::StatusCode,
    middleware::Next,
    response::Response,
};

pub async fn api_key_auth(
    State(state): State<AppState>,
    req: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    // Get the API key from the request headers
    let api_key = if let Some(key) = req.headers().get("X-API-KEY") {
        key.to_str().unwrap_or("")
    } else {
        // No API Key header found
        return Err(StatusCode::UNAUTHORIZED);
    };

    // Check if the key exists in our database
    let key_exists = sqlx::query("SELECT 1 FROM api_keys WHERE key = ?")
        .bind(api_key)
        .fetch_optional(&state.pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .is_some();

    if key_exists {
        // Key is valid, proceed to the next middleware or the handler
        Ok(next.run(req).await)
    } else {
        // Key is invalid
        Err(StatusCode::FORBIDDEN)
    }
}
