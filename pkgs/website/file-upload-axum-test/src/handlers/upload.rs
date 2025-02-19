// src/handlers/upload.rs
use askama::Template;
use axum::{
    extract::{Multipart, State},
    response::{Html, IntoResponse},
};
use aws_sdk_textract::{
    types::{Document, BlockType, FeatureType},
    primitives::Blob,
    Client,
};
use uuid::Uuid;
use tracing::{error, info, debug};
use std::error::Error;  // Added this import
use crate::{
    models::{AppState, TextItem},
    utils::templates::HtmlTemplate,
};

#[derive(Template)]
#[template(path = "upload.html")]
struct UploadTemplate {}

pub async fn show_page() -> impl IntoResponse {
    HtmlTemplate(UploadTemplate {})
}

async fn save_to_file(process_id: &str, items: &[TextItem]) -> anyhow::Result<()> {
    let results_dir = std::path::Path::new("website_data/results");
    tokio::fs::create_dir_all(results_dir).await?;

    let file_path = results_dir.join(format!("{}.json", process_id));
    let json = serde_json::to_string_pretty(items)?;
    tokio::fs::write(file_path, json).await?;

    Ok(())
}

pub async fn handle_upload(
    State(state): State<AppState>,
    mut multipart: Multipart,
) -> impl IntoResponse {
    while let Ok(Some(field)) = multipart.next_field().await {
        if let Ok(bytes) = field.bytes().await {
            let process_id = Uuid::new_v4().to_string();
            let process_id_clone = process_id.clone();
            let client = state.textract_client.clone();
            let results_store = state.results_store.clone();

            debug!("Starting processing for document ID: {}", process_id);

            tokio::spawn(async move {
                match process_document(&client, &bytes).await {
                    Ok(items) => {
                        info!("Successfully processed document {}", process_id_clone);
                        results_store.insert(process_id_clone.clone(), items.clone()).await;

                        if let Err(e) = save_to_file(&process_id_clone, &items).await {
                            error!("Failed to save results to file: {}", e);
                        }
                    }
                    Err(e) => {
                        error!("Processing error for {}: {}", process_id_clone, e);
                        results_store.insert(
                            process_id_clone,
                            vec![TextItem {
                                text: format!("Error processing document: {}", e),
                                confidence: 0.0,
                            }],
                        ).await;
                    }
                }
            });

            return Html(format!(
                r#"<div id="result-container">
                    <div class="p-4 bg-gray-100 rounded">
                        <p class="mb-2">Upload successful! Processing document...</p>
                        <div hx-get="/status/{}" hx-trigger="load delay:1s">
                            <div class="animate-pulse">Processing...</div>
                        </div>
                        <p class="mt-2">Results will be available at: <a href="/results/{}.json" class="text-blue-500 hover:underline">/results/{}.json</a></p>
                    </div>
                </div>"#,
                process_id, process_id, process_id
            ));
        }
    }

    Html("<div class='error'>Upload failed</div>".to_string())
}

// async fn process_document(client: &Client, bytes: &[u8]) -> anyhow::Result<Vec<TextItem>> {
//     debug!("Starting document processing with Textract");
//     let document = Document::builder()
//         .bytes(Blob::new(bytes.to_vec()))
//         .build();
//
//     let response = client
//         .analyze_document()
//         .document(document)
//         .feature_types(FeatureType::Forms)
//         .feature_types(FeatureType::Tables)
//         .send()
//         .await?;
//
//     debug!("Received response from Textract, processing blocks");
//     let items = response
//         .blocks()
//         .iter()
//         .filter_map(|block| {
//             if let Some(block_type) = block.block_type() {
//                 if block_type == &BlockType::Line {
//                     let text = block.text()?.to_string();
//                     let confidence = block.confidence().unwrap_or(0.0);
//                     debug!("Extracted text with confidence {}: {}", confidence, text);
//                     return Some(TextItem { text, confidence });
//                 }
//             }
//             None
//         })
//         .collect::<Vec<_>>();
//
//     info!("Extracted {} text items", items.len());
//     Ok(items)
// }

async fn process_document(client: &Client, bytes: &[u8]) -> anyhow::Result<Vec<TextItem>> {
    debug!("Starting document processing with Textract");
    let document = Document::builder()
        .bytes(Blob::new(bytes.to_vec()))
        .build();

    let response = client
        .analyze_document()
        .document(document)
        .feature_types(FeatureType::Forms)
        .feature_types(FeatureType::Tables)
        .send()
        .await
        .map_err(|e| {
            error!("Textract API error: {:?}", e);
            anyhow::anyhow!("Textract API error: {}", e)
        })?;

    debug!("Received response from Textract, processing blocks");
    let items = response
        .blocks()
        .iter()
        .filter_map(|block| {
            if let Some(block_type) = block.block_type() {
                if block_type == &BlockType::Line {
                    let text = block.text()?.to_string();
                    let confidence = block.confidence().unwrap_or(0.0);
                    debug!("Extracted text with confidence {}: {}", confidence, text);
                    return Some(TextItem { text, confidence });
                }
            }
            None
        })
        .collect::<Vec<_>>();

    info!("Extracted {} text items", items.len());
    Ok(items)
}

