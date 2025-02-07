use std::path::{Path, PathBuf};

#[cfg(debug_assertions)]
mod paths {
    use super::*;
    pub const WEBSITE_DATA: &str = "website_data";
    pub const STATIC_CONTENT: &str = "static";

    pub fn secret_endpoint() -> PathBuf {
        Path::new(WEBSITE_DATA).join("endpoint")
    }

    pub fn database() -> PathBuf {
        Path::new(WEBSITE_DATA).join("database.db")
    }

    pub fn user_content() -> PathBuf {
        Path::new(WEBSITE_DATA).join("user-content")
    }

    pub fn resume_data() -> PathBuf {
        Path::new(WEBSITE_DATA).join("resume_data.json")
    }

    pub fn api_key() -> PathBuf {
        Path::new(WEBSITE_DATA).join("API_KEY")
    }

    pub fn icons() -> PathBuf {
        Path::new(STATIC_CONTENT).join("icons")
    }
}

#[cfg(not(debug_assertions))]
mod paths {
    use super::*;
    pub const WEBSITE_DATA: &str = "/var/lib/axum-website";
    pub const STATIC_CONTENT: &str = "/run/axum-website/static";

    pub fn secret_endpoint() -> PathBuf {
        Path::new(WEBSITE_DATA).join("endpoint")
    }

    pub fn database() -> PathBuf {
        Path::new(WEBSITE_DATA).join("database.db")
    }

    pub fn user_content() -> PathBuf {
        Path::new(WEBSITE_DATA).join("user-content")
    }

    pub fn resume_data() -> PathBuf {
        Path::new(WEBSITE_DATA).join("resume_data.json")
    }

    pub fn api_key() -> PathBuf {
        Path::new(WEBSITE_DATA).join("API_KEY")
    }

    pub fn icons() -> PathBuf {
        Path::new(STATIC_CONTENT).join("icons")
    }
}

pub fn database_url() -> String {
    format!("sqlite:{}", paths::database().display())
}

pub fn secret_endpoint_path() -> PathBuf {
    paths::secret_endpoint()
}

pub fn secret_api_key() -> PathBuf {
    paths::api_key()
}

pub fn database_path() -> PathBuf {
    paths::database()
}

// pub fn website_data_path() -> PathBuf {
//     PathBuf::from(paths::WEBSITE_DATA)
// }

pub fn user_content_path() -> PathBuf {
    paths::user_content()
}

pub fn static_content_path() -> PathBuf {
    PathBuf::from(paths::STATIC_CONTENT)
}

pub fn resume_data_path() -> PathBuf {
    paths::resume_data()
}

pub fn icons_path() -> PathBuf {
    paths::icons()
}
