//! Crate-local error type. Every variant is convertible into
//! [`marki_core::BlockError`] at the trait boundary.

#[derive(Debug, thiserror::Error)]
pub enum MapError {
    #[error("parse: {0}")]
    Parse(String),
    #[error("resolve: {0}")]
    Resolve(String),
    #[error("network: {0}")]
    Network(String),
    #[error("cache: {0}")]
    Cache(String),
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("project: {0}")]
    Project(String),
    #[error("internal: {0}")]
    Internal(String),
}

impl From<MapError> for marki_core::BlockError {
    fn from(e: MapError) -> Self {
        use marki_core::BlockError as B;
        match e {
            MapError::Parse(s) => B::Parse(s),
            MapError::Resolve(s) => B::Resolve(s),
            MapError::Network(s) => B::Network(s),
            MapError::Cache(s) => B::Cache(s),
            MapError::Io(e) => B::Io(e.to_string()),
            MapError::Project(s) => B::Internal(format!("project: {s}")),
            MapError::Internal(s) => B::Internal(s),
        }
    }
}
