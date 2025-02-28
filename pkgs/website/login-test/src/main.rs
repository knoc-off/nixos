// src/main.rs
mod users;
mod web;
mod config;
mod llm_processor; // Add this line
mod filters;

use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

use crate::web::App;
use crate::llm_processor::run_processor_loop; // Add this line

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::registry()
        .with(EnvFilter::new(std::env::var("RUST_LOG").unwrap_or_else(
            |_| "axum_login=debug,tower_sessions=debug,sqlx=warn,tower_http=debug".into(),
        )))
        .with(tracing_subscriber::fmt::layer())
        .try_init()?;

    // Spawn the background worker
    tokio::spawn(run_processor_loop());

    // Start the web server
    App::new().await?.serve().await
}

