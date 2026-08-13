//! Crate-local error type. Every variant is convertible into
//! [`marki_render::RenderError`] at the trait boundary.

#[derive(Debug, thiserror::Error)]
pub enum MediaError {
    #[error("failed to parse media block: {0}")]
    Parse(String),
    #[error("media not found for `{src}` (searched {searched})")]
    NotFound { src: String, searched: String },
    #[error("no media sources configured; set [media_sources] in marki config")]
    NoSources,
    #[error("unsupported media extension `.{ext}` for `{src}`")]
    UnsupportedExt { src: String, ext: String },
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
}

impl From<MediaError> for marki_render::RenderError {
    fn from(e: MediaError) -> Self {
        use marki_render::RenderError as B;
        match e {
            MediaError::Parse(s) => B::Parse(s),
            MediaError::NotFound { .. } => B::Resolve(e.to_string()),
            MediaError::NoSources => B::Internal(e.to_string()),
            MediaError::UnsupportedExt { .. } => B::Resolve(e.to_string()),
            MediaError::Io(e) => B::Io(e.to_string()),
        }
    }
}
