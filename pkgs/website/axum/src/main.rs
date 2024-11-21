use askama::Template;
use axum::{
    extract::Form,
    http::StatusCode,
    response::{Html, IntoResponse},
    routing::{get, post},
    Router,
};
use serde::Deserialize;
use tracing_subscriber;
// use sqlx::sqlite::SqlitePool;

#[tokio::main]
async fn main() {
    // initialize tracing
    tracing_subscriber::fmt::init();

    // let pool = SqlitePool::connect("sqlite://count.db").await.unwrap();

    // build our application with routes
    let app = Router::new()
        .route("/", get(index))
        .route("/click", post(handle_click));

    // run our app with hyper, listening globally on port 3000
    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

// Handler to render the index page
async fn index() -> impl IntoResponse {
    let template = IndexTemplate { count: 0 };
    HtmlTemplate(template)
}

// Handler to handle the htmx post request
async fn handle_click(Form(input): Form<ClickForm>) -> impl IntoResponse {
    let new_count = input.count + 1;
    let template = IndexTemplate { count: new_count };
    HtmlTemplate(template)
}

// Data sent from the form
#[derive(Deserialize)]
struct ClickForm {
    count: usize,
}

// Askama template for the index page
#[derive(Template)]
#[template(path = "index.html")]
struct IndexTemplate {
    count: usize,
}

// Wrapper to render Askama templates with Axum
struct HtmlTemplate<T>(T);

impl<T: Template> IntoResponse for HtmlTemplate<T> {
    fn into_response(self) -> axum::response::Response {
        match self.0.render() {
            Ok(html) => Html(html).into_response(),
            Err(_) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to render template".to_string(),
            )
                .into_response(),
        }
    }
}
