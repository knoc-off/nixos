//! Crate-local error type. Every variant is convertible into
//! [`marki_core::BlockError`] at the trait boundary.

#[derive(Debug, thiserror::Error)]
pub enum FlagError {
    #[error("failed to parse flag block: {0}")]
    Parse(String),
    #[error("flag SVG not found for `{flag}` (searched {searched})")]
    NotFound { flag: String, searched: String },
    #[error("no flag sources configured; set [flag_sources] in markid config")]
    NoSources,
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
}

impl From<FlagError> for marki_core::BlockError {
    fn from(e: FlagError) -> Self {
        use marki_core::BlockError as B;
        match e {
            FlagError::Parse(s) => B::Parse(s),
            FlagError::NotFound { .. } => B::Resolve(e.to_string()),
            FlagError::NoSources => B::Internal(e.to_string()),
            FlagError::Io(e) => B::Io(e.to_string()),
        }
    }
}
