use std::path::PathBuf;

/// Returns the path where icon SVG files are stored.
///
/// In this example we assume that the icons are installed into
/// the `static/icons` directory (which is also published in your Nix
/// build steps).
pub fn icons_path() -> PathBuf {
    // You could customize this further (e.g. via an environment variable)
    PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/static/icons"))
}

