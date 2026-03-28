use std::fmt;
use std::io;

/// Typed error for the prompt-daemon library crate.
#[derive(Debug)]
pub enum Error {
    /// I/O error (socket bind, file read, protocol I/O).
    Io(io::Error),
    /// YAML config parse error.
    ConfigParse(serde_yaml_ng::Error),
    /// Filesystem watcher error.
    Watcher(notify::Error),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Io(e) => write!(f, "{e}"),
            Error::ConfigParse(e) => write!(f, "config parse: {e}"),
            Error::Watcher(e) => write!(f, "watcher: {e}"),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Error::Io(e) => Some(e),
            Error::ConfigParse(e) => Some(e),
            Error::Watcher(e) => Some(e),
        }
    }
}

impl From<io::Error> for Error {
    fn from(e: io::Error) -> Self {
        Error::Io(e)
    }
}

impl From<serde_yaml_ng::Error> for Error {
    fn from(e: serde_yaml_ng::Error) -> Self {
        Error::ConfigParse(e)
    }
}

impl From<notify::Error> for Error {
    fn from(e: notify::Error) -> Self {
        Error::Watcher(e)
    }
}
