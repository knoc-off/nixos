//use axum::{
//    extract::{Extension, Form},
//    response::{Html, IntoResponse},
//};
//use serde::{Serialize, Deserialize};
//use sqlx::SqlitePool;
//use askama::Template;
//
//#[derive(Template)]
//#[template(path = "data_table.html")]
//struct DataTableTemplate {
//    items: Vec<Data>
//}
//
//#[derive(Serialize, Deserialize, sqlx::FromRow)]
//pub struct Data {
//    id: i32,
//    name: String,
//}
//
//#[derive(Deserialize)]
//pub struct NewData {
//    name: String,
//}

//// This will render the data table partial
//pub async fn get_data_table(Extension(pool): Extension<SqlitePool>) -> impl IntoResponse {
//    let items = sqlx::query_as::<_, Data>(
//        "SELECT id, name FROM my_table ORDER BY id DESC"
//    )
//    .fetch_all(&pool)
//    .await
//    .unwrap_or_default();
//
//    let template = DataTableTemplate { items };
//    Html(template.render().unwrap_or_default())
//}
//
//pub async fn add_data(
//    Extension(pool): Extension<SqlitePool>,
//    Form(new_data): Form<NewData>,
//) -> impl IntoResponse {
//    sqlx::query(
//        "INSERT INTO my_table (name) VALUES (?)"
//    )
//    .bind(new_data.name)
//    .execute(&pool)
//    .await
//    .expect("Failed to insert data");
//
//    // Return the updated table
//    get_data_table(Extension(pool)).await
//}
//
