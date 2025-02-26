// ./src/web/register.rs
use askama::Template;
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse, Redirect},
    routing::{get, post},
    Form, Router,
};
use axum_messages::{Message, Messages};
use once_cell::sync::Lazy;
use password_auth::generate_hash;
use serde::Deserialize;
use sqlx::SqlitePool;

// Use a static string for the registration secret
// In a real app, you might want to use environment variables or a more secure approach
static REGISTRATION_SECRET: Lazy<String> = Lazy::new(||
    std::env::var("REGISTRATION_SECRET").unwrap_or_else(|_| "super-secret-code".to_string())
);

#[derive(Template)]
#[template(path = "register.html")]
struct RegisterTemplate {
    messages: Vec<Message>,
    error_class: String,
    message_class: String,
}

#[derive(Deserialize)]
pub struct RegisterForm {
    username: String,
    password: String,
    secret: String,
}

pub fn router() -> Router<SqlitePool> {
    Router::new()
        .route("/register", get(self::get::register))
        .route("/register", post(self::post::register))
}

mod get {
    use super::*;

    pub async fn register(messages: Messages) -> Html<String> {
        let messages_vec: Vec<Message> = messages.into_iter().collect();
        let has_error = messages_vec.iter().any(|m| m.level == axum_messages::Level::Error);

        Html(
            RegisterTemplate {
                messages: messages_vec,
                error_class: if has_error { "red".to_string() } else { "green".to_string() },
                message_class: if has_error { "red".to_string() } else { "green".to_string() },
            }
            .render()
            .unwrap(),
        )
    }
}

mod post {
    use super::*;

    pub async fn register(
        State(db): State<SqlitePool>,
        messages: Messages,
        Form(form): Form<RegisterForm>,
    ) -> impl IntoResponse {
        // Check if the secret is correct
        if form.secret != *REGISTRATION_SECRET {
            messages.error("Invalid registration secret");
            return Redirect::to("/register").into_response();
        }

        // Check if username is empty
        if form.username.trim().is_empty() {
            messages.error("Username cannot be empty");
            return Redirect::to("/register").into_response();
        }

        // Check if password is too short
        if form.password.len() < 6 {
            messages.error("Password must be at least 6 characters");
            return Redirect::to("/register").into_response();
        }

        // Check if user already exists
        let user_exists = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM users WHERE username = ?")
            .bind(&form.username)
            .fetch_one(&db)
            .await;

        match user_exists {
            Ok(count) if count > 0 => {
                messages.error("Username already exists");
                return Redirect::to("/register").into_response();
            }
            Err(_) => {
                return StatusCode::INTERNAL_SERVER_ERROR.into_response();
            }
            _ => {}
        }

        // Generate password hash
        let password_hash = match tokio::task::spawn_blocking(move || {
            generate_hash(&form.password)
        }).await {
            Ok(hash) => hash,
            Err(_) => {
                return StatusCode::INTERNAL_SERVER_ERROR.into_response();
            }
        };

        // Insert the new user
        let result = sqlx::query("INSERT INTO users (username, password) VALUES (?, ?)")
            .bind(&form.username)
            .bind(&password_hash)
            .execute(&db)
            .await;

        match result {
            Ok(_) => {
                messages.success(format!("User {} registered successfully! You can now log in.", form.username));
                Redirect::to("/login").into_response()
            }
            Err(_) => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
        }
    }
}

