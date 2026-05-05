//! Crate-local error type. Every variant is convertible into
//! [`marki_core::BlockError`] at the trait boundary.

use std::path::PathBuf;

#[derive(Debug, thiserror::Error)]
pub enum TypstError {
    #[error("typst binary not found or not executable: {0}")]
    BinaryNotFound(PathBuf),

    #[error("typst compile failed:\n{0}")]
    Compile(String),

    #[error("io: {0}")]
    Io(#[from] std::io::Error),
}

impl From<TypstError> for marki_core::BlockError {
    fn from(e: TypstError) -> Self {
        use marki_core::BlockError as B;
        match e {
            TypstError::BinaryNotFound(_) => B::Internal(e.to_string()),
            TypstError::Compile(_) => B::Internal(e.to_string()),
            TypstError::Io(ref io) => B::Io(io.to_string()),
        }
    }
}
