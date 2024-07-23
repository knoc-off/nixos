use actix_files as fs;
use actix_web::{web, App, HttpServer, Result};
use actix_files::NamedFile;
use std::env;
use std::path::PathBuf;
use lazy_static::lazy_static;

lazy_static! {
    static ref STATIC_DIR: PathBuf = {
        let exe_path = env::current_exe().unwrap();
        let exe_dir = exe_path.parent().unwrap();
        exe_dir.join("static")
    };
}

async fn index() -> Result<NamedFile> {
    Ok(NamedFile::open(STATIC_DIR.join("index.html"))?)
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            .route("/", web::get().to(index))
            .service(fs::Files::new("/", STATIC_DIR.clone()).show_files_listing())
    })
    .bind("127.0.0.1:8081")?
    .run()
    .await
}

