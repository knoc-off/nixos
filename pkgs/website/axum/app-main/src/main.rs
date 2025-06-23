// src/main.rs

use axum::{ routing::get_service, Router};
use sqlx::SqlitePool;
use std::net::SocketAddr;
use tower_http::services::ServeDir;
use feature_immo24;

use tracing_subscriber;

use axum::middleware::from_fn_with_state; // We need this

// Modules for features and shared components
// mod blog;
mod config;
// mod immo24;
mod middleware;
mod utils;

use app_state::{AppState, Settings};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    // Initialize the database connection pool
    let pool = SqlitePool::connect(&config::database_url())
        .await
        .expect("Failed to connect to the database");

    let http_client = reqwest::Client::new(); // Create the client once


    let settings = app_state::Settings {
        openrouter_api_key: config::openrouter_api_key(),
        static_path: config::static_content_path(),
    };

    // Create the shared state
    let app_state = AppState { pool , http_client, settings: settings.clone()};

    // Build the application router by composing feature modules
    let app = create_router(app_state);

    let port = 3000;
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    println!("🚀 Server listening on http://{}", addr);

    tracing::info!("Config: static_path: {}, openrouter_api_key: {}", settings.static_path, settings.openrouter_api_key );
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect(&format!("Failed to bind to port: {}", port));

    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await
    .unwrap();
}

fn create_router(state: AppState) -> Router {
    let immo24_routes = feature_immo24::router()
        .route_layer(from_fn_with_state(state.clone(),middleware::auth::api_key_auth));

    Router::new()
        // Nest all your feature routers
        // .nest("/blog", blog::router())
        .nest("/immo24", immo24_routes)
        .nest_service(
            "/static",
            get_service(ServeDir::new(config::static_content_path())),
        )
        .fallback(utils::not_found::handler)
        // 1. Provide the state to the router FIRST.
        // Now, all routes and subsequent layers have access to AppState.
        .with_state(state.clone())
        // 2. Apply the logger layer AFTER the state is available.
        // We use from_fn_with_state to pass the pool directly.
        //.layer(from_fn_with_state(
        //    state.pool,
        //    middleware::logger::log_request,
        //))}
}
