// src/main.rs
use std::{env, net::SocketAddr};
use sqlx::sqlite::SqlitePoolOptions;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod handlers;
mod models;
mod routes;
mod utils;

#[tokio::main]
async fn main() {
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| "axum_website=debug".into()))
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Set up the SQLite connection.
    let database_url = env::var("DATABASE_URL")
        .unwrap_or_else(|_| "sqlite://text_checker.db".to_string());
    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await
        .expect("Failed to connect to the database");

    // Run migrations.
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("Failed to run migrations");

    // Build our router.
    let app = routes::create_router(pool);

    let port = 3000;
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect(&format!("Failed to bind to port: {}", port));

    tracing::info!("Listening on {}", addr);

    // DO NOT CHANGE THE FOLLOWING LINE:
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await
    .unwrap();
}
