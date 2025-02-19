use axum::{routing::{get, post}, Router};
use std::net::SocketAddr;
use tower_http::services::ServeDir;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod config;
mod handlers;

use handlers::upload::*;

// Add at the top of main.rs
use axum::{body::Body, middleware::Next};
use axum::http::Request;

// Add this middleware function
async fn log_route(req: Request<Body>, next: Next) -> impl axum::response::IntoResponse {
    let path = req.uri().path().to_owned();
    tracing::debug!("Request to: {}", path);
    next.run(req).await
}

#[tokio::main]
async fn main() {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "axum_website=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::debug!("Logger initialized");

    let aws_config = config::load_aws_config().await;
    let aws_state = AwsConfig {
        client: aws_sdk_textract::Client::new(&aws_config),
    };

    tracing::debug!("Building router...");
    let app = Router::new()
        .route("/", get(upload_page))
        .route("/upload", post(upload_handler))
        .route("/upload/status/:id", get(upload_status))
        .nest_service(
            "/results",
            ServeDir::new("website_data/results/")
        )
        .nest_service(
            "/static",
            ServeDir::new(config::static_content_path())
        )
        .layer(axum::middleware::from_fn(log_route))
        .with_state(aws_state);
    tracing::debug!("Router built.");

    let port = 3000;
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::debug!("Binding to address: {}", addr);
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect(&format!("Failed to bind to port: {}", port));
    tracing::debug!("Listening on: {}", addr);

    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await
    .unwrap();
}

