
use axum::{
    extract::Extension,
    routing::{get, get_service},
    Router,
    http::StatusCode,
    response::{Html, IntoResponse},
};

use axum::response::Response;
use std::fs;
use tower_http::services::ServeDir;

use sqlx::SqlitePool;
use tracing_subscriber;

mod handlers;
use handlers::{hidden::hidden, home::home};

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
    let secret_endpoint = fs::read_to_string("/etc/secrets/endpoint")
        .expect("Failed to read the secret endpoint file")
        .trim()
        .to_string();

    // Initialize the database connection pool
    let pool = SqlitePool::connect("sqlite:database.db")
        .await
        .expect("Failed to connect to the database");


    let app = Router::new()
        .route("/", get(home))
        .route(&format!("/{}", secret_endpoint), get(hidden))
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

