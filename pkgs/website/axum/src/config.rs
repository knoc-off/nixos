use std::path::{Path, PathBuf};

#[cfg(debug_assertions)]
mod paths {
    pub const SECRET_ENDPOINT: &str = "website_data/endpoint";
    pub const DATABASE: &str = "website_data/database.db";
    pub const USER_CONTENT: &str = "user-content";
    pub const WEBSITE_DATA: &str = "website_data";
    pub const STATIC_CONTENT: &str = "static";
    pub const RESUME_DATA: &str = "website_data/resume_data.json";
    pub const ICONS: &str = "static/icons";
}

#[cfg(not(debug_assertions))]
mod paths {
    pub const SECRET_ENDPOINT: &str = "/var/lib/axum-website/endpoint";
    pub const DATABASE: &str = "/var/lib/axum-website/database.db";
    pub const USER_CONTENT: &str = "/var/lib/axum-website/user-content";
    pub const STATIC_CONTENT: &str = "/run/axum-website/static";
    pub const RESUME_DATA: &str = "/var/lib/axum-website/resume_data.json";
    pub const ICONS: &str = "/run/axum-website/static/icons";
    pub const WEBSITE_DATA: &str = "/var/lib/axum-website";
}

pub fn database_url() -> String {
    format!("sqlite:{}", paths::DATABASE)
}

pub fn secret_endpoint_path() -> &'static Path {
    Path::new(paths::SECRET_ENDPOINT)
}

pub fn database_path() -> &'static Path {
    Path::new(paths::DATABASE)
}

pub fn website_data_path() -> &'static Path {
    Path::new(paths::WEBSITE_DATA)
}

pub fn user_content_path() -> &'static Path {
    Path::new(paths::USER_CONTENT)
}

pub fn static_content_path() -> &'static Path {
    Path::new(paths::STATIC_CONTENT)
}

pub fn resume_data_path() -> &'static Path {
    Path::new(paths::RESUME_DATA)
}

pub fn icons_path() -> &'static Path {
    Path::new(paths::ICONS)
}
