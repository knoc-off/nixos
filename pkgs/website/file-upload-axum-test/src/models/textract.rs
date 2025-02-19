use aws_sdk_textract::Client;
use serde::Serialize;

#[derive(Serialize)]
pub struct TextItem {
    text: String,
    confidence: f32,
}

pub struct AppState {
    textract_client: Client,
    processing: tokio::sync::RwLock<rustbreak::FileDatabase<Vec<TextItem>>>,
}

impl AppState {
    pub fn new(client: Client) -> Self {
        Self {
            textract_client: client,
            processing: rustbreak::FileDatabase::memory_only().unwrap(),
        }
    }

    pub async fn store_status(&self, id: String, items: Vec<TextItem>) {
        self.processing.write().await.insert(id, items).unwrap();
    }
}

