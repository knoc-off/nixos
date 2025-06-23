// feature-immo24/src/lib.rs (or wherever your router is defined)

use app_state::AppState;
use axum::{
    routing::{get, patch, post, delete},
    Router,
};

mod handlers;
mod models;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/", get(handlers::query_listings))
        .route("/", post(handlers::create_listing))
        .route("/:scout_id", patch(handlers::update_listing))
        .route("/:scout_id", get(handlers::get_listing))
        //.route("/:scout_id", delete(handlers::delete_listing))
        .route("/settings", get(handlers::get_settings))
        .route("/settings", post(handlers::update_settings))
        .route(
            "/:scout_id/generate-message",
            post(handlers::generate_message_handler),
        )
}
