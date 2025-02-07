use axum::{
    body::Body,
    extract::ConnectInfo,
    http::{Request, HeaderMap},
    middleware::Next,
    response::Response,
};
use sqlx::SqlitePool;
use std::{net::SocketAddr, time::Instant};

#[derive(sqlx::FromRow)]
struct RequestLog {
    method: String,
    path: String,
    query_params: Option<String>,
    user_agent: Option<String>,
    ip_address: Option<String>,
    duration_ms: i64,
    status_code: i32,
}

impl RequestLog {
    fn from_request(
        request: &Request<Body>,
        headers: &HeaderMap,
        connect_info: Option<&ConnectInfo<SocketAddr>>,
    ) -> Self {
        Self {
            method: request.method().to_string(),
            path: request.uri().path().to_string(),
            query_params: request.uri().query().map(String::from),
            user_agent: headers
                .get("user-agent")
                .and_then(|h| h.to_str().ok())
                .map(String::from),
            ip_address: connect_info.map(|ci| ci.0.ip().to_string()),
            duration_ms: 0,
            status_code: 0,
        }
    }

    async fn save(&self, pool: &SqlitePool) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            INSERT INTO request_logs (
                method, path, query_params, user_agent,
                ip_address, duration_ms, status_code
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            "#,
        )
        .bind(&self.method)
        .bind(&self.path)
        .bind(&self.query_params)
        .bind(&self.user_agent)
        .bind(&self.ip_address)
        .bind(self.duration_ms)
        .bind(self.status_code)
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
        .expect("SQLite pool missing")
        .clone();

    let mut log = RequestLog::from_request(&request, request.headers(), Some(&connect_info));

    let response = next.run(request).await;

    log.duration_ms = start.elapsed().as_millis() as i64;
    log.status_code = response.status().as_u16() as i32;

    tokio::spawn(async move {
        if let Err(e) = log.save(&pool).await {
            eprintln!("Failed to save request log: {}", e);
        }
    });

    response
}
