// src/handlers/blog.rs
use axum::{
    extract::Path,
    http::StatusCode,
    response::IntoResponse,
};
use pulldown_cmark::{Parser, Options, html::push_html};
use std::fs;

use crate::config;
use crate::HtmlTemplate;
use askama::Template;
use axum::response::Html;

use std::path::PathBuf;


use axum::response::Redirect;



#[derive(Template)]
#[template(path = "blog.html")]
struct BlogTemplate {
    content: String,
    title: String,
}

use axum::Json;
use serde::Serialize;

#[derive(Serialize)]
struct BlogPost {
    id: String,
    title: String,
    url: String,
}


fn get_cache_path(post_id: &str) -> PathBuf {
    config::website_data_path().join("cache").join(format!("{}.html", post_id))
}

pub async fn list_blog_posts() -> impl IntoResponse {
    let blog_dir = config::website_data_path().join("blogs");
    let mut blog_posts = Vec::new();

    if let Ok(entries) = fs::read_dir(blog_dir) {
        for entry in entries {
            if let Ok(entry) = entry {
                let path = entry.path();
                if path.is_file() && path.extension().and_then(|s| s.to_str()) == Some("md") {
                    let post_id = path.file_stem().and_then(|s| s.to_str()).unwrap_or("").to_string();
                    let content = fs::read_to_string(&path).unwrap_or_default();
                    let title = extract_title(&content);
                    let url = format!("/blog/{}/{}", post_id, title.replace(' ', "-").to_lowercase());

                    blog_posts.push(BlogPost { id: post_id, title, url });
                }
            }
        }
    }

    Json(blog_posts)
}

/// Extract the title from the first `#` heading in the Markdown content
fn extract_title(content: &str) -> String {
    let mut title = String::new();
    let mut in_title = false;

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

pub async fn blog_post(Path((post_id, slug)): Path<(String, String)>) -> impl IntoResponse {
    // Validate post_id to prevent directory traversal
    if !post_id.chars().all(|c| c.is_alphanumeric()) {
        return (StatusCode::BAD_REQUEST, "Invalid blog post ID").into_response();
    }

    let file_path = config::website_data_path().join("blogs").join(format!("{}.md", post_id));

    // Read the Markdown file to extract the title
    let content = match fs::read_to_string(&file_path) {
        Ok(content) => content,
        Err(_) => return (StatusCode::NOT_FOUND, format!("Blog post not found: {}", file_path.display())).into_response(),
    };

    // Extract the title and generate the correct slug
    let title = extract_title(&content);
    let correct_slug = title_to_slug(&title);

    // If the provided slug doesn't match the correct slug, redirect
    if slug != correct_slug {
        return Redirect::permanent(&format!("/blog/{}/{}", post_id, correct_slug)).into_response();
    }

    // Check the cache
    let cache_path = get_cache_path(&post_id);
    let html_output = if cache_path.exists() {
        fs::read_to_string(cache_path).unwrap_or_default()
    } else {
        // Set up Markdown parser with all extensions enabled
        let mut options = Options::empty();
        options.insert(Options::ENABLE_TABLES);
        options.insert(Options::ENABLE_FOOTNOTES);
        options.insert(Options::ENABLE_STRIKETHROUGH);
        options.insert(Options::ENABLE_TASKLISTS);

        let parser = Parser::new_ext(&content, options);
        let mut html_output = String::new();
        push_html(&mut html_output, parser);

        // Cache the rendered HTML
        fs::create_dir_all(cache_path.parent().unwrap()).unwrap();
        fs::write(cache_path, &html_output).unwrap();

        html_output
    };

    // Always use the template, whether serving cached content or fresh content
    let template = BlogTemplate {
        content: html_output,
        title,
    };

    HtmlTemplate(template).into_response()
}

