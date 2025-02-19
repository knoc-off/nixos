use askama::Template;
use aws_sdk_textract::{
    Client,
    primitives::Blob,
    types::{Document, FeatureType, BlockType},
};
use axum::{
    extract::{Multipart, State},
    response::{Html, IntoResponse},
};
use tokio::sync::RwLock;
use uuid::Uuid;
use std::collections::HashMap;
use tracing::{info, error, debug};

#[derive(Clone)]
pub struct AwsConfig {
    pub client: Client,
}

lazy_static::lazy_static! {
    static ref PROCESSING_STATUS: RwLock<HashMap<String, String>> = RwLock::new(HashMap::new());
}

#[derive(Template)]
#[template(path = "upload.html")]
struct UploadTemplate {}

pub async fn upload_page() -> impl IntoResponse {
    HtmlTemplate(UploadTemplate {})
}

pub async fn upload_handler(
    State(aws_config): State<AwsConfig>,
    mut multipart: Multipart,
) -> impl IntoResponse {
    debug!("upload_handler called");

    while let Some(field) = multipart.next_field().await.unwrap_or(None) {
        let field_name = field.name().map(|s| s.to_string()).unwrap_or_else(|| "unknown".to_string());
        let file_name = field.file_name().map(|s| s.to_string()).unwrap_or_else(|| "unknown".to_string());
        debug!("Field received: name = {:?}, file_name = {:?}", field_name, file_name);

        match field.bytes().await {
            Ok(bytes) => {
                debug!("File size: {} bytes", bytes.len());
                let process_id = Uuid::new_v4().to_string();
                info!("Received upload with process_id: {}", process_id);

                tokio::spawn({
                    let client = aws_config.client.clone();
                    let process_id = process_id.clone();
                    let bytes = bytes.clone();

                    async move {
                        info!("Starting Textract processing for process_id: {}", process_id);
                        match process_document(&client, &bytes).await {
                            Ok(text) => {
                                info!("Textract processing successful for process_id: {}", process_id);
                                PROCESSING_STATUS.write().await.insert(process_id, text);
                            }
                            Err(e) => {
                                error!("Textract processing failed for process_id: {}: {}", process_id, e);
                                PROCESSING_STATUS.write().await.insert(
                                    process_id,
                                    format!("Error: {}", e),
                                );
                            }
                        }
                    }
                });

                return Html(format!(r#"
                    <div id="upload-status" hx-get="/upload/status/{}" hx-trigger="load delay:500ms">
                        Processing...
                    </div>
                "#, process_id));
            }
            Err(e) => {
                error!("Error reading field bytes: {}", e);
                return Html("<div class='error'>Failed to read file</div>".to_string());
            }
        }
    }

    error!("No file uploaded");
    Html("<div class='error'>No file uploaded</div>".to_string())
}

pub async fn upload_status(
    axum::extract::Path(process_id): axum::extract::Path<String>,
) -> impl IntoResponse {
    info!("Checking status for process_id: {}", process_id);
    match PROCESSING_STATUS.read().await.get(&process_id) {
        Some(status) if status.starts_with("Error") => {
            error!("Process {} returned error: {}", process_id, status);
            Html(format!("<div class='error'>{}</div>", status))
        }
        Some(text) => {
            info!("Process {} completed successfully", process_id);
            Html(format!("<div class='result'><pre>{}</pre></div>", text))
        }
        None => {
            info!("Process {} still processing", process_id);
            Html(format!(r#"
                <div hx-get="/upload/status/{}" hx-trigger="load delay:500ms">
                    Still processing...
                </div>
            "#, process_id))
        }
    }
}

async fn process_document(client: &Client, bytes: &[u8]) -> anyhow::Result<String> {
    info!("Processing document with Textract...");
    let document = Document::builder()
        .bytes(Blob::new(bytes.to_vec()))
        .build();

    debug!("Document size: {} bytes", bytes.len());

    let response = client
        .analyze_document()
        .document(document)
        .feature_types(FeatureType::Forms)
        .feature_types(FeatureType::Tables)
        .send()
        .await;

    match response {
        Ok(resp) => {
            debug!("Textract response: {:?}", resp);

            let text = resp
                .blocks()
                .iter()
                .filter_map(|block| {
                    if let Some(block_type) = block.block_type() {
                        if block_type == &BlockType::Line {
                            return block.text().map(|s| s.to_string());
                        }
                    }
                    None
                })
                .collect::<Vec<_>>()
                .join("\n");

            info!("Extracted text: {}", text);
            Ok(text)
        }
        Err(e) => {
            error!("Textract error: {}", e);
            Err(anyhow::anyhow!("Textract failed: {}", e))
        }
    }
}

struct HtmlTemplate<T>(T);

impl<T: Template> IntoResponse for HtmlTemplate<T> {
    fn into_response(self) -> axum::response::Response {
        match self.0.render() {
            Ok(html) => Html(html).into_response(),
            Err(err) => Html(format!("Template error: {}", err)).into_response(),
        }
    }
}

