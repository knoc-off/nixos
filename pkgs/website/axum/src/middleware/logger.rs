// src/middleware/logger.rs
use axum::{
    body::Body,
    extract::ConnectInfo,
    http::{Request, HeaderMap},
    middleware::Next,
    response::Response,
};
use std::{net::SocketAddr, time::Instant};
use sqlx::SqlitePool;

#[derive(Debug)]
pub struct RequestLog {
    method: String,
    path: String,
    query_params: Option<String>,
    user_agent: Option<String>,
    referer: Option<String>,
    ip_address: Option<String>,
    host: Option<String>,
    duration_ms: i64,
    status_code: i32,
    content_type: Option<String>,
    accept_language: Option<String>,
    content_length: Option<i64>,
    is_mobile: bool,
    is_bot: bool,
}

impl RequestLog {
    fn from_request(
        request: &Request<Body>,
        headers: &HeaderMap,
        connect_info: Option<&ConnectInfo<SocketAddr>>,
    ) -> Self {
        let user_agent = headers
            .get("user-agent")
            .and_then(|h| h.to_str().ok())
            .map(String::from);

        let is_mobile = user_agent
            .as_ref()
            .map(|ua| {
                ua.contains("Mobile") || ua.contains("Android") || ua.contains("iPhone")
            })
            .unwrap_or(false);

        let is_bot = user_agent
            .as_ref()
            .map(|ua| {
                ua.contains("bot") ||
                ua.contains("crawler") ||
                ua.contains("spider") ||
                ua.contains("Googlebot")
            })
            .unwrap_or(false);

        RequestLog {
            method: request.method().to_string(),
            path: request.uri().path().to_string(),
            query_params: request.uri().query().map(String::from),
            user_agent,
            referer: headers
                .get("referer")
                .and_then(|h| h.to_str().ok())
                .map(String::from),
            ip_address: connect_info
                .map(|ci| ci.0.ip().to_string()),
            host: headers
                .get("host")
                .and_then(|h| h.to_str().ok())
                .map(String::from),
            duration_ms: 0,
            status_code: 0,
            content_type: headers
                .get("content-type")
                .and_then(|h| h.to_str().ok())
                .map(String::from),
            accept_language: headers
                .get("accept-language")
                .and_then(|h| h.to_str().ok())
                .map(String::from),
            content_length: headers
                .get("content-length")
                .and_then(|h| h.to_str().ok())
                .and_then(|v| v.parse().ok()),
            is_mobile,
            is_bot,
        }
    }

    async fn save(&self, pool: &SqlitePool) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            INSERT INTO request_logs (
                method, path, query_params, user_agent, referer,
                ip_address, host, duration_ms, status_code,
                content_type, accept_language, content_length,
                is_mobile, is_bot
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            "#,
        )
        .bind(&self.method)
        .bind(&self.path)
        .bind(&self.query_params)
        .bind(&self.user_agent)
        .bind(&self.referer)
        .bind(&self.ip_address)
        .bind(&self.host)
        .bind(self.duration_ms)
        .bind(self.status_code)
        .bind(&self.content_type)
        .bind(&self.accept_language)
        .bind(self.content_length)
        .bind(self.is_mobile)
        .bind(self.is_bot)
        .execute(pool)
        .await?;

        Ok(())
    }
}

pub async fn log_request(
    connect_info: ConnectInfo<SocketAddr>,
    request: Request<Body>,
    next: Next,
) -> Response {
    let start = Instant::now();
    let pool = request
        .extensions()
        .get::<SqlitePool>()
        .expect("SQLite pool missing from extensions")
        .clone();

    // Create initial log entry
    let mut log = RequestLog::from_request(&request, request.headers(), Some(&connect_info));

    // Process the request
    let response = next.run(request).await;

    // Update log with response data
    log.duration_ms = start.elapsed().as_millis() as i64;
    log.status_code = response.status().as_u16() as i32;

    // Save log asynchronously
    tokio::spawn(async move {
        if let Err(e) = log.save(&pool).await {
            eprintln!("Failed to save request log: {}", e);
        }
    });

    response
}

