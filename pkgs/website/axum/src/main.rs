use axum::{
    extract::Extension,
    http::StatusCode,
    response::{Html, IntoResponse},
    routing::{get, get_service, post},
    Router,
};


use axum::response::Response;
use std::fs;
use tower_http::services::ServeDir;

use sqlx::SqlitePool;
use tracing_subscriber;

mod handlers;
use handlers::{hidden::hidden, home::home, not_found::not_found, resume::resume_main };

use askama::Template;

struct HtmlTemplate<T>(T);

impl<T: Template> IntoResponse for HtmlTemplate<T> {
    fn into_response(self) -> axum::response::Response {
        match self.0.render() {
            Ok(html) => Html(html).into_response(),
            Err(err) => {
                eprintln!("Template error: {}", err);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Failed to render template".to_string(),
                )
                    .into_response()
            }
        }
    }
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    // Read the secret endpoint from the file
    let secret_endpoint = fs::read_to_string("/opt/website_data/endpoint")
        .expect("Failed to read the secret endpoint file")
        .trim()
        .to_string();

    // Initialize the database connection pool
    let pool = SqlitePool::connect("sqlite:/opt/website_data/database.db")
        .await
        .expect("Failed to connect to the database");

    let app = Router::new()
        .route("/", get(home))
        .route("/api/data", get(handlers::api::get_data_table))
        .route("/api/data", post(handlers::api::add_data))
        .route(&format!("/{}", secret_endpoint), get(hidden))
        .route("/resume", get(resume_main))
        .route("/404", get(not_found))
        .fallback(get(not_found))
        .nest_service(
            "/static",
            get_service(ServeDir::new("static")).handle_error(|error| async move {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("Unhandled internal error: {}", error),
                )
            }),
        )
        .layer(Extension(pool));

    // run our app with hyper, listening globally on port 3000
    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000")
        .await
        .expect("Failed to bind to port 3000");
    axum::serve(listener, app).await.unwrap();
}




