#![allow(unused_braces)]
use askama::Template;
use aws_sdk_textract::{
    primitives::Blob,
    types::{BlockType, Document, FeatureType},
    Client,
};
use axum::{
    extract::{Multipart, State},
    response::{Html, IntoResponse},
};
use serde::Serialize;
use std::collections::HashMap;
use std::path::PathBuf;
use tokio::fs::{self, File};
use tokio::io::AsyncWriteExt;
use tokio::sync::RwLock;
use tracing::{debug, error, info};
use uuid::Uuid;

#[derive(Clone)]
pub struct AwsConfig {
    pub client: Client,
}

#[derive(Debug, Serialize, Clone)]
struct TextItem {
    text: String,
    confidence: f32,
}

#[derive(Template)]
#[template(path = "upload.html")]
struct UploadTemplate {}

#[derive(Template)]
#[template(path = "result.html")]
struct ResultTemplate {
    items: Vec<TextItem>,
    process_id: String,
    high_percentage: f32,
    medium_percentage: f32,
    low_percentage: f32,
}

pub mod filters {
    pub fn confidence(value: &f32) -> ::askama::Result<String> {
        Ok(format!("{:.1}%", value))
    }

    pub fn length(items: &Vec<super::TextItem>) -> ::askama::Result<usize> {
        Ok(items.len())
    }

    pub fn format(value: &f32) -> ::askama::Result<String> {
        Ok(format!("{:.1}", value))
    }
}

lazy_static::lazy_static! {
    static ref PROCESSING_STATUS: RwLock<HashMap<String, Vec<TextItem>>> = RwLock::new(HashMap::new());
}

pub async fn upload_page() -> impl IntoResponse {
    HtmlTemplate(UploadTemplate {})
}

pub async fn upload_handler(
    State(aws_config): State<AwsConfig>,
    mut multipart: Multipart,
) -> impl IntoResponse {
    debug!("Upload handler called");

    while let Some(field) = multipart.next_field().await.unwrap_or(None) {
        let field_name = field
            .name()
            .map(|s| s.to_string())
            .unwrap_or_else(|| "unknown".to_string());
        let file_name = field
            .file_name()
            .map(|s| s.to_string())
            .unwrap_or_else(|| "unknown".to_string());
        debug!(
            "Processing field: {} with filename: {}",
            field_name, file_name
        );

        match field.bytes().await {
            Ok(bytes) => {
                debug!("Received file of size: {} bytes", bytes.len());
                let process_id = Uuid::new_v4().to_string();
                info!("Created process_id: {}", process_id);

                tokio::spawn({
                    let client = aws_config.client.clone();
                    let process_id = process_id.clone();
                    let bytes = bytes.clone();

                    async move {
                        info!(
                            "Starting Textract processing for process_id: {}",
                            process_id
                        );
                        match process_document(&client, &bytes).await {
                            Ok(items) => {
                                info!(
                                    "Textract processing successful for process_id: {}",
                                    process_id
                                );

                                // Save results to file
                                if let Err(e) = save_results(&process_id, &items).await {
                                    error!("Failed to save results for {}: {}", process_id, e);
                                }

                                // Store results in memory
                                PROCESSING_STATUS
                                    .write()
                                    .await
                                    .insert(process_id.clone(), items.clone());

                                debug!("Processing complete for {}", process_id);
                            }
                            Err(e) => {
                                error!(
                                    "Textract processing failed for process_id: {}: {}",
                                    process_id, e
                                );
                                PROCESSING_STATUS.write().await.insert(
                                    process_id,
                                    vec![TextItem {
                                        text: format!("Error: {}", e),
                                        confidence: 0.0,
                                    }],
                                );
                            }
                        }
                    }
                });

                return Html(format!(
                    r#"
                    <div id="upload-status" hx-get="/upload/status/{}" hx-trigger="load delay:500ms">
                        <div class="animate-pulse">
                            <div class="h-4 bg-gray-200 rounded w-3/4 mb-2"></div>
                            <div class="h-4 bg-gray-200 rounded w-1/2"></div>
                        </div>
                    </div>
                "#,
                    process_id
                ));
            }
            Err(e) => {
                error!("Failed to read file: {}", e);
                return Html("<div class='error p-4 bg-red-100 border border-red-400 text-red-700 rounded'>Failed to read uploaded file</div>".to_string());
            }
        }
    }

    Html("<div class='error p-4 bg-red-100 border border-red-400 text-red-700 rounded'>No file uploaded</div>".to_string())
}

// Update the upload_status function:
pub async fn upload_status(
    axum::extract::Path(process_id): axum::extract::Path<String>,
) -> impl IntoResponse {
    debug!("Checking status for process_id: {}", process_id);

    match PROCESSING_STATUS.read().await.get(&process_id) {
        Some(items) => {
            let total = items.len() as f32;
            let high_count = items.iter().filter(|i| i.confidence >= 90.0).count() as f32;
            let medium_count = items
                .iter()
                .filter(|i| i.confidence >= 70.0 && i.confidence < 90.0)
                .count() as f32;
            let low_count = items.iter().filter(|i| i.confidence < 70.0).count() as f32;

            let high_percentage = if total > 0.0 {
                (high_count / total) * 100.0
            } else {
                0.0
            };
            let medium_percentage = if total > 0.0 {
                (medium_count / total) * 100.0
            } else {
                0.0
            };
            let low_percentage = if total > 0.0 {
                (low_count / total) * 100.0
            } else {
                0.0
            };

            HtmlTemplate(ResultTemplate {
                items: items.clone(),
                process_id: process_id.clone(),
                high_percentage,
                medium_percentage,
                low_percentage,
            })
        }
        None => HtmlTemplate(ResultTemplate {
            items: vec![],
            process_id: process_id.clone(),
            high_percentage: 0.0,
            medium_percentage: 0.0,
            low_percentage: 0.0,
        }),
    }
    .into_response()
}

async fn process_document(client: &Client, bytes: &[u8]) -> anyhow::Result<Vec<TextItem>> {
    debug!("Starting document processing with Textract");
    let document = Document::builder().bytes(Blob::new(bytes.to_vec())).build();

    let response = client
        .analyze_document()
        .document(document)
        .feature_types(FeatureType::Forms)
        .feature_types(FeatureType::Tables)
        .send()
        .await?;

    debug!("Received response from Textract, processing blocks");
    let items = response
        .blocks()
        .iter()
        .filter_map(|block| {
            if let Some(block_type) = block.block_type() {
                if block_type == &BlockType::Line {
                    let text = block.text()?.to_string();
                    let confidence = block.confidence().unwrap_or(0.0);
                    return Some(TextItem { text, confidence });
                }
            }
            None
        })
        .collect::<Vec<_>>();

    info!("Extracted {} text items", items.len());
    Ok(items)
}

async fn save_results(process_id: &str, items: &[TextItem]) -> anyhow::Result<()> {
    let results_dir = PathBuf::from("website_data/results");
    fs::create_dir_all(&results_dir).await?;

    let file_path = results_dir.join(format!("{}.json", process_id));
    debug!("Saving results to: {}", file_path.display());

    let mut file = File::create(&file_path).await?;
    let json = serde_json::to_string_pretty(items)?;
    file.write_all(json.as_bytes()).await?;

    info!("Saved results to: {}", file_path.display());
    Ok(())
}

struct HtmlTemplate<T>(T);

impl<T: Template> IntoResponse for HtmlTemplate<T> {
    fn into_response(self) -> axum::response::Response {
        match self.0.render() {
            Ok(html) => Html(html).into_response(),
            Err(err) => {
                error!("Template rendering error: {}", err);
                Html(format!(
                    "<div class='error p-4 bg-red-100 border border-red-400 text-red-700 rounded'>Template error: {}</div>",
                    err
                )).into_response()
            }
        }
    }
}
