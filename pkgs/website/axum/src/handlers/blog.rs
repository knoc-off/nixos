use anyhow::{Context, Result};
use askama::Template;
use axum::{
    body::Body,
    extract::{Extension, Path, Query, Request, State},
    http::HeaderValue,
    http::{header::AUTHORIZATION, StatusCode},
    response::{IntoResponse, Json, Redirect},
};
use bytes::Bytes;
use pulldown_cmark::{html::push_html, Options, Parser};
use serde::{Deserialize, Serialize};
use sqlx::SqlitePool;
use std::sync::Arc;

use crate::utils::encode_base62;
use crate::HtmlTemplate; // Import the encoding function

#[derive(Template)]
#[template(path = "blog.html")]
struct BlogTemplate {
    content: String,
    title: String,
}

#[derive(Serialize, Deserialize, Debug, sqlx::FromRow)]
pub struct BlogPost {
    pub id: String,
    pub title: String,
    pub slug: String,
    pub content: String,
    pub metadata: String,
    pub created_at: String,
    pub updated_at: String,
    pub cached_html: Option<String>,
    pub json_tags: Option<String>,
    pub deleted: bool,
}

#[derive(Serialize, Deserialize, Debug, sqlx::FromRow)]
pub struct BlogPostSummary {
    pub id: String, // UUID
    pub title: String,
    pub slug: String,
    pub metadata: String,
    pub created_at: String,
    pub updated_at: String,
    pub json_tags: Option<String>,
    //pub cached_html: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, sqlx::FromRow)]
pub struct Tag {
    pub id: i64,
    pub name: String,
}

#[derive(Deserialize, Debug)]
pub struct NewBlogPost {
    pub title: String,
    pub content: String,
    pub metadata: String, // Allow the user to provide metadata directly
    pub tags: Vec<String>,
}

#[derive(Deserialize, Debug)]
pub struct UpdateBlogPost {
    pub title: Option<String>,
    pub content: Option<String>,
    pub metadata: Option<String>,
    pub tags: Option<Vec<String>>,
    pub deleted: Option<bool>,
}

// Shared state for authentication
#[derive(Clone)]
pub struct AuthState {
    pub api_key: String,
}

#[axum::debug_handler]
pub async fn create_blog_post(
    State(auth_state): State<Arc<AuthState>>,
    Extension(pool): Extension<SqlitePool>,
    req: Request, // Extract the Request directly
) -> impl IntoResponse {
    println!("create_blog_post: Starting...");

    // Authentication
    let auth_header = req
        .headers()
        .get(AUTHORIZATION)
        .and_then(|header: &HeaderValue| header.to_str().ok());

    println!("create_blog_post: Auth header: {:?}", auth_header);

    match auth_header {
        Some(auth_token)
            if auth_token.strip_prefix("Bearer ").unwrap_or(auth_token) == auth_state.api_key =>
        {
            println!("create_blog_post: Authentication successful");

            // Manually extract the JSON payload
            let body: Body = req.into_body();
            let bytes: Bytes = match axum::body::to_bytes(body, usize::MAX).await {
                Ok(b) => b,
                Err(e) => {
                    eprintln!("create_blog_post: Failed to read request body: {}", e);
                    return (StatusCode::BAD_REQUEST, "Invalid request body").into_response();
                }
            };

            println!("create_blog_post: Request body read successfully");

            let new_post: NewBlogPost = match serde_json::from_slice(&bytes) {
                Ok(post) => {
                    println!("create_blog_post: JSON parsed successfully: {:?}", post);
                    post
                }
                Err(e) => {
                    eprintln!("create_blog_post: Failed to parse JSON: {}", e);
                    return (StatusCode::BAD_REQUEST, "Invalid JSON").into_response();
                }
            };

            let title = new_post.title.clone();
            let content = new_post.content.clone();
            let metadata_json = new_post.metadata.clone();
            let slug = title_to_slug(&title);
            let json_tags = serde_json::to_string(&new_post.tags).unwrap_or_default();

            // Start a transaction
            let mut tx = pool.begin().await.expect("Failed to start transaction");

            // Increment the counter
            let updated_counter: (i64,) = sqlx::query_as(
                "UPDATE blog_post_counter SET counter = counter + 1 WHERE id = 1 RETURNING counter",
            )
            .fetch_one(&mut *tx)
            .await
            .map_err(|e| {
                eprintln!("Failed to increment counter: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Failed to create blog post",
                )
            })
            .expect("error"); // BAD UNWRAP!

            let post_id = encode_base62(updated_counter.0); // Encode the counter value

            // Insert the new blog post
            let result = sqlx::query(
                "INSERT INTO blog_posts (id, title, slug, content, metadata, json_tags) VALUES (?, ?, ?, ?, ?, ?)"
            )
            .bind(&post_id)
            .bind(&title)
            .bind(&slug)
            .bind(&content)
            .bind(&metadata_json)
            .bind(&json_tags)
            .execute(&mut *tx)
            .await;

            let result = match result {
                Ok(result) => {
                    println!("create_blog_post: Blog post inserted successfully");
                    result
                }
                Err(e) => {
                    eprintln!("create_blog_post: Failed to insert blog post: {}", e);
                    println!("create_blog_post: Failed to insert blog post: {}", e);
                    tx.rollback().await.expect("Failed to rollback transaction");
                    return (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        "Failed to create blog post",
                    )
                        .into_response();
                }
            };

            // Insert the tags
            for tag_name in new_post.tags {
                // Check if the tag already exists
                let tag: Option<Tag> = sqlx::query_as("SELECT id, name FROM tags WHERE name = ?")
                    .bind(&tag_name)
                    .fetch_optional(&mut *tx)
                    .await
                    .expect("Failed to fetch tag");

                let tag_id = match tag {
                    Some(existing_tag) => existing_tag.id,
                    None => {
                        // Insert the new tag
                        let result = sqlx::query("INSERT INTO tags (name) VALUES (?)")
                            .bind(&tag_name)
                            .execute(&mut *tx)
                            .await
                            .expect("Failed to insert tag");
                        result.last_insert_rowid()
                    }
                };

                // Insert into the join table
                sqlx::query("INSERT INTO blog_post_tags (blog_post_id, tag_id) VALUES (?, ?)")
                    .bind(&post_id)
                    .bind(tag_id)
                    .execute(&mut *tx)
                    .await
                    .expect("Failed to insert into blog_post_tags");
            }

            // Commit the transaction
            tx.commit().await.expect("Failed to commit transaction");

            println!("create_blog_post: Transaction committed successfully");

            (StatusCode::CREATED, "Blog post created").into_response()
        }
        _ => {
            println!("create_blog_post: Authentication failed");
            return (StatusCode::UNAUTHORIZED, "Invalid API key").into_response();
        }
    }
}

#[axum::debug_handler]
pub async fn update_blog_post(
    State(auth_state): State<Arc<AuthState>>,
    Extension(pool): Extension<SqlitePool>,
    Path(id): Path<String>, // UUID
    req: Request,
) -> impl IntoResponse {
    // Authentication
    let auth_header = req
        .headers()
        .get(AUTHORIZATION)
        .and_then(|header: &HeaderValue| header.to_str().ok());

    match auth_header {
        Some(auth_token)
            if auth_token.strip_prefix("Bearer ").unwrap_or(auth_token) == auth_state.api_key =>
        {
            // Manually extract the JSON payload
            let body: Body = req.into_body();
            let bytes: Bytes = match axum::body::to_bytes(body, usize::MAX).await {
                Ok(b) => b,
                Err(e) => {
                    eprintln!("Failed to read request body: {}", e);
                    return (StatusCode::BAD_REQUEST, "Invalid request body").into_response();
                }
            };

            let updated_post: UpdateBlogPost = match serde_json::from_slice(&bytes) {
                Ok(post) => post,
                Err(e) => {
                    eprintln!("Failed to parse JSON: {}", e);
                    return (StatusCode::BAD_REQUEST, "Invalid JSON").into_response();
                }
            };

            // Fetch the existing blog post
            let existing_post: BlogPost =
                match sqlx::query_as("SELECT * FROM blog_posts WHERE id = ?")
                    .bind(&id)
                    .fetch_one(&pool)
                    .await
                {
                    Ok(post) => post,
                    Err(_) => {
                        return (StatusCode::NOT_FOUND, "Blog post not found").into_response()
                    }
                };

            // Update the fields if they are provided
            let title = updated_post.title.unwrap_or(existing_post.title);
            let content = updated_post.content.unwrap_or(existing_post.content);
            let metadata_json = updated_post.metadata.unwrap_or(existing_post.metadata);
            let slug = title_to_slug(&title);
            let deleted = updated_post.deleted.unwrap_or(existing_post.deleted);

            // Preserve existing tags if not provided in the update
            let tags = match updated_post.tags {
                Some(new_tags) => new_tags,
                None => {
                    // Fetch existing tags from the database
                    let existing_tags: Vec<Tag> = sqlx::query_as("SELECT t.id, t.name FROM tags t INNER JOIN blog_post_tags bpt ON t.id = bpt.tag_id WHERE bpt.blog_post_id = ?")
                .bind(&id)
                .fetch_all(&pool)
                .await
                .expect("Failed to fetch existing tags");

                    existing_tags.into_iter().map(|tag| tag.name).collect()
                }
            };

            let json_tags = serde_json::to_string(&tags).unwrap_or_default();

            // Start a transaction
            let mut tx = pool.begin().await.expect("Failed to start transaction");

            // Update the blog post in the database
            let result = sqlx::query(
                "UPDATE blog_posts SET title = ?, slug = ?, content = ?, metadata = ?, json_tags = ?, cached_html = NULL, deleted = ? WHERE id = ?"
            )
            .bind(&title)
            .bind(&slug)
            .bind(&content)
            .bind(&metadata_json)
            .bind(&json_tags)
            .bind(deleted)
            .bind(&id)
            .execute(&mut *tx)
            .await;

            match result {
                Ok(_) => (),
                Err(e) => {
                    eprintln!("Failed to update blog post: {}", e);
                    tx.rollback().await.expect("Failed to rollback transaction");
                    return (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        "Failed to update blog post",
                    )
                        .into_response();
                }
            };

            // Delete existing tags for the blog post
            sqlx::query("DELETE FROM blog_post_tags WHERE blog_post_id = ?")
                .bind(&id)
                .execute(&mut *tx)
                .await
                .expect("Failed to delete existing tags");

            // Insert the new tags
            for tag_name in tags {
                // Check if the tag already exists
                let tag: Option<Tag> = sqlx::query_as("SELECT id, name FROM tags WHERE name = ?")
                    .bind(&tag_name)
                    .fetch_optional(&mut *tx)
                    .await
                    .expect("Failed to fetch tag");

                let tag_id = match tag {
                    Some(existing_tag) => existing_tag.id,
                    None => {
                        // Insert the new tag
                        let result = sqlx::query("INSERT INTO tags (name) VALUES (?)")
                            .bind(&tag_name)
                            .execute(&mut *tx)
                            .await
                            .expect("Failed to insert tag");
                        result.last_insert_rowid()
                    }
                };

                // Insert into the join table
                sqlx::query("INSERT INTO blog_post_tags (blog_post_id, tag_id) VALUES (?, ?)")
                    .bind(&id)
                    .bind(tag_id)
                    .execute(&mut *tx)
                    .await
                    .expect("Failed to insert into blog_post_tags");
            }

            // Commit the transaction
            tx.commit().await.expect("Failed to commit transaction");

            (StatusCode::OK, "Blog post updated").into_response()
        }
        _ => return (StatusCode::UNAUTHORIZED, "Invalid API key").into_response(),
    }
}

/// Extract the title from the first `#` heading in the Markdown content
pub fn extract_title(content: &str) -> String {
    let mut title = String::new();

    for line in content.lines() {
        if line.starts_with("# ") {
            title = line.trim_start_matches("# ").trim().to_string();
            break;
        }
    }

    if title.is_empty() {
        title = "Untitled Blog Post".to_string();
    }

    title
}

/// Convert a title into a URL-friendly slug
fn title_to_slug(title: &str) -> String {
    title
        .to_lowercase()
        .replace(' ', "-")
        .chars()
        .filter(|c| c.is_alphanumeric() || *c == '-')
        .collect()
}

#[derive(Deserialize)]
pub struct BlogQueryParams {
    pub limit: Option<i64>,
    pub offset: Option<i64>,
    pub tags: Option<String>,
}

#[axum::debug_handler]
pub async fn list_blog_posts(
    Query(params): Query<BlogQueryParams>,
    Extension(pool): Extension<SqlitePool>,
) -> impl IntoResponse {
    let limit = params.limit.unwrap_or(10);
    let offset = params.offset.unwrap_or(0);
    let tags = params.tags.unwrap_or_default();

    let mut query = "SELECT bp.id, bp.title, bp.slug, bp.metadata, bp.created_at, bp.updated_at, bp.json_tags, bp.cached_html FROM blog_posts bp WHERE bp.deleted = FALSE".to_string();
    let mut where_clauses = Vec::new();
    let mut bind_params: Vec<String> = Vec::new();

    if !tags.is_empty() {
        query.push_str(" INNER JOIN blog_post_tags bpt ON bp.id = bpt.blog_post_id INNER JOIN tags t ON bpt.tag_id = t.id");
        where_clauses.push("t.name LIKE ?".to_string());
        bind_params.push(format!("%{}%", tags));
    }

    if !where_clauses.is_empty() {
        query.push_str(" AND "); // Add AND before tag conditions
        query.push_str(&where_clauses.join(" AND "));
    }

    query.push_str(" ORDER BY bp.created_at DESC LIMIT ? OFFSET ?");

    let mut sqlx_query = sqlx::query_as::<_, BlogPostSummary>(&query);

    for param in bind_params {
        sqlx_query = sqlx_query.bind(param);
    }

    sqlx_query = sqlx_query.bind(limit);
    sqlx_query = sqlx_query.bind(offset);

    let blog_posts = sqlx_query.fetch_all(&pool).await.unwrap_or_default();

    Json(blog_posts)
}


pub async fn blog_post(
    Path((post_id, slug)): Path<(String, String)>, // UUID
    Extension(pool): Extension<SqlitePool>,
) -> impl IntoResponse {
    // Fetch the blog post from the database
    let blog_post: Result<BlogPost, (StatusCode, String)> = sqlx::query_as("SELECT * FROM blog_posts WHERE id = ?")
        .bind(&post_id)
        .fetch_one(&pool)
        .await
        .map_err(|_| (StatusCode::NOT_FOUND, "Blog post not found".to_string()));

    let blog_post = match blog_post {
        Ok(post) => post,
        Err(_) => {
            // Construct the redirect URL
            let redirect_url = format!("/404?url=/blogs/{}/{}", post_id, slug);
            return Redirect::temporary(&redirect_url).into_response();
        }
    };

    if blog_post.deleted {
        // Construct the redirect URL
        let redirect_url = format!("/404?url=/blogs/{}/{}", post_id, slug);
        return Redirect::temporary(&redirect_url).into_response();
    }

    // Extract the title and generate the correct slug
    let title = extract_title(&blog_post.content);
    let correct_slug = title_to_slug(&title);

    // If the provided slug doesn't match the correct slug, redirect
    if slug != correct_slug {
        return Redirect::permanent(&format!("/blogs/{}/{}", post_id, correct_slug)).into_response();
    }

    // Check the cache
    let html_output = match &blog_post.cached_html {
        Some(html_content) => {
            //println!("Serving cached version of blog post: {}", post_id);
            html_content.clone() // Clone the html_content
        }
        None => {
            println!("No cache found, rendering blog post: {}", post_id);
            render_markdown(&blog_post, &pool).await.expect("error rendering markdown")
        }
    };

    // Always use the template, whether serving cached content or fresh content
    let template = BlogTemplate {
        content: html_output,
        title,
    };

    HtmlTemplate(template).into_response()
}


async fn render_markdown(blog_post: &BlogPost, pool: &SqlitePool) -> Result<String, anyhow::Error> {
    // Set up Markdown parser with all extensions enabled
    let mut options = Options::empty();
    options.insert(Options::ENABLE_TABLES);
    options.insert(Options::ENABLE_FOOTNOTES);
    options.insert(Options::ENABLE_STRIKETHROUGH);
    options.insert(Options::ENABLE_TASKLISTS);

    let parser = Parser::new_ext(&blog_post.content, options);
    let mut html_output = String::new();
    push_html(&mut html_output, parser);

    // Cache the rendered HTML in the database
    sqlx::query("UPDATE blog_posts SET cached_html = ? WHERE id = ?")
        .bind(&html_output)
        .bind(&blog_post.id)
        .execute(pool)
        .await
        .context("Failed to cache HTML in the database")?;

    Ok(html_output)
}
