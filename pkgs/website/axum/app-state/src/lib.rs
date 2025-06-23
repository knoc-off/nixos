use sqlx::SqlitePool;
use reqwest::Client;

// global settings
#[derive(Clone)]
pub struct Settings {
    pub openrouter_api_key: String,
    pub static_path: String,
}


#[derive(Clone)]
pub struct AppState {
    pub pool: SqlitePool,
    pub http_client: Client,
    pub settings: Settings,
}
