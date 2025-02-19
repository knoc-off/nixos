// src/utils/middleware.rs
use axum::{
    body::Body,
    http::Request,
    middleware::Next,
    response::Response,
};

pub async fn log_request(req: Request<Body>, next: Next) -> Response {
    tracing::debug!("Request: {} {}", req.method(), req.uri());
    next.run(req).await
}

