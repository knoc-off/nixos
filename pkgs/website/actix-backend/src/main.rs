use actix_web::{web, App, HttpResponse, HttpServer, Responder};
use rusqlite::{Connection, params};
use serde::{Deserialize, Serialize};
use std::sync::Mutex;

#[derive(Deserialize, Serialize)]
struct FruitPreference {
    name: String,
    fruits: String,
}

#[derive(Serialize)]
struct BackendResponse {
    message: String,
}

type DbConnection = web::Data<Mutex<Connection>>;

async fn store_preferences(
    db: DbConnection,
    preferences: web::Json<FruitPreference>,
) -> impl Responder {
    let conn = db.lock().unwrap();

    match conn.execute(
        "INSERT OR REPLACE INTO preferences (name, fruits) VALUES (?1, ?2)",
        params![preferences.name, preferences.fruits],
    ) {
        Ok(_) => HttpResponse::Ok().json(BackendResponse {
            message: "Preferences stored successfully".to_string(),
        }),
        Err(e) => HttpResponse::InternalServerError().json(BackendResponse {
            message: format!("Error: {}", e),
        }),
    }
}

async fn get_preferences(
    db: DbConnection,
    name: web::Path<String>,
) -> impl Responder {
    let conn = db.lock().unwrap();

    match conn.query_row(
        "SELECT name, fruits FROM preferences WHERE name = ?1",
        params![name.as_str()],
        |row| {
            Ok(FruitPreference {
                name: row.get(0)?,
                fruits: row.get(1)?,
            })
        },
    ) {
        Ok(pref) => HttpResponse::Ok().json(pref),
        Err(rusqlite::Error::QueryReturnedNoRows) => {
            HttpResponse::NotFound().json(BackendResponse {
                message: "User not found".to_string(),
            })
        }
        Err(e) => HttpResponse::InternalServerError().json(BackendResponse {
            message: format!("Error: {}", e),
        }),
    }
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // Create/open database and initialize table
    let conn = Connection::open("preferences.db").expect("Failed to open database");
    conn.execute(
        "CREATE TABLE IF NOT EXISTS preferences (
            name TEXT PRIMARY KEY,
            fruits TEXT NOT NULL
        )",
        [],
    ).expect("Failed to create table");

    let db = web::Data::new(Mutex::new(conn));

    HttpServer::new(move || {
        App::new()
            .app_data(db.clone())
            .service(
                web::resource("/api/preferences")
                    .route(web::post().to(store_preferences))
            )
            .service(
                web::resource("/api/preferences/{name}")
                    .route(web::get().to(get_preferences))
            )
    })
    .bind("127.0.0.1:8081")?
    .run()
    .await
}

