// src/config.rs
use aws_types::SdkConfig;
use std::path::PathBuf;

pub fn static_content_path() -> PathBuf {  // Changed from static_path to match original
    PathBuf::from("static")
}

pub async fn load_aws_config() -> SdkConfig {
    if let Ok(env_path) = std::fs::read_to_string("/etc/secrets/aws/root.env") {
        for line in env_path.lines() {
            if let Some((key, value)) = line.split_once('=') {
                std::env::set_var(key.trim(), value.trim());
            }
        }
    }
    aws_config::from_env().load().await
}

