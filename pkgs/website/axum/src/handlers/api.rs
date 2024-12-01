use axum::{extract::Extension, response::Json};
use serde::Serialize;
use sqlx::SqlitePool;

#[derive(Serialize)]
pub struct Data {
    id: i32,
    name: String,
}

async fn get_data(pool: Extension<SqlitePool>) -> Json<Vec<Data>> {
    let rows = sqlx::query(
        r#"
        SELECT
            id,
            name
        FROM my_table
        "#
    )
    .fetch_all(&pool)
    .await
    .expect("Failed to fetch data from the database")
    .into_iter()
    .map(|row| Data {
        id: row.get(0),
        name: row.get(1),
    })
    .collect();

    Json(rows)
}

