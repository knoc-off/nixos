use axum::{
    extract::Extension,
    http::StatusCode,
    response::{Html, IntoResponse},
    routing::{get, get_service, post},
    Router,
};



mod config;


use std::fs;
use tower_http::services::ServeDir;

use sqlx::SqlitePool;
use tracing_subscriber;

mod middleware;
use axum::middleware::from_fn_with_state;
use middleware::logger::log_request;
use std::net::SocketAddr;

mod handlers;
use handlers::{home::home, not_found::not_found, resume::resume_main};

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


    println!("Configuration Paths:");
    println!("├─ Secret Endpoint: {}", config::secret_endpoint_path().display());
    println!("├─ Database: {}", config::database_path().display());
    println!("├─ User Content: {}", config::user_content_path().display());
    println!("├─ Static Content: {}", config::static_content_path().display());
    println!("├─ Resume Data: {}", config::resume_data_path().display());
    println!("└─ Icons: {}", config::icons_path().display());
    println!("Database URL: {}", config::database_url());

    // Read the secret endpoint from the file
    let secret_endpoint = fs::read_to_string(config::secret_endpoint_path())
        .expect("Failed to read the secret endpoint file")
        .trim()
        .to_string();

    // Initialize the database connection pool
    let pool = SqlitePool::connect(&config::database_url())
        .await
        .expect("Failed to connect to the database");

    let app = Router::new()
        .route("/", get(home))
        .route("/blog/:post_id/:slug", get(handlers::blog::blog_post))
        .route("/blog/:post_id", get(handlers::blog::blog_post))
        .route("/blogs", get(handlers::blog::list_blog_posts)) // New route
        .route("/api/data", get(handlers::api::get_data_table))
        .route("/api/data", post(handlers::api::add_data))
        .route(&format!("/{}", secret_endpoint), get(resume_main))
        .route("/404", get(not_found))
        .fallback(get(not_found))
        .nest_service(
            "/content",
            get_service(ServeDir::new(config::user_content_path())).handle_error(|error| async move {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("Unhandled internal error: {}", error),
                )
            }),
        )
        .nest_service(
            "/static",
            get_service(ServeDir::new(config::static_content_path())).handle_error(|error| async move {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("Unhandled internal error: {}", error),
                )
            }),
        )
        .layer(from_fn_with_state(pool.clone(), log_request))
        .layer(Extension(pool));

    let port = 3000;
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
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
