//! Compile the vendored `.proto` subset into prost types at build time.
//!
//! Anki's build uses `protoc`, which is not available in our sandbox, so we
//! parse the vendored protos with `protox` (pure Rust) and hand the
//! resulting descriptor set to `prost-build`. No network, no protoc.

use std::path::PathBuf;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_dir = PathBuf::from("proto");
    let files = [
        "anki/generic.proto",
        "anki/notetypes.proto",
        "anki/decks.proto",
    ];

    for f in &files {
        println!("cargo:rerun-if-changed=proto/{f}");
    }

    let fds = protox::compile(files, [proto_dir])?;
    prost_build::Config::new()
        .compile_fds(fds)?;

    Ok(())
}
