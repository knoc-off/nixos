use actix_web::{web, App, HttpResponse, HttpServer, Responder};
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct FormData {
    name: String,
    fruits: Vec<String>,
}

#[derive(Serialize)]
struct BackendResponse {
    message: String,
}

async fn process(form: web::Json<FormData>) -> impl Responder {
    let fruits_str = if form.fruits.is_empty() {
        "no fruits".to_string()
    } else {
        form.fruits.join(", ")
    };

    let message = format!(
        "Hello, {}! You selected the following fruits: {}.",
        form.name, fruits_str
    );

    HttpResponse::Ok().json(BackendResponse { message })
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new().service(web::resource("/api/process").route(web::post().to(process)))
    })
    .bind("127.0.0.1:8081")?
    .run()
    .await
}
