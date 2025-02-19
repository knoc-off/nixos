// src/models/mod.rs
use aws_sdk_textract::Client;
use serde::{Serialize, Deserialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

#[derive(Clone)]
pub struct AppState {
    pub textract_client: Client,
    pub results_store: ResultsStore,
}

#[derive(Clone)]
pub struct ResultsStore {
    store: Arc<RwLock<HashMap<String, Vec<TextItem>>>>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct TextItem {
    pub text: String,
    pub confidence: f32,
}

impl AppState {
    pub fn new(client: Client) -> Self {
        Self {
            textract_client: client,
            results_store: ResultsStore::new(),
        }
    }
}

impl ResultsStore {
    pub fn new() -> Self {
        Self {
            store: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub async fn insert(&self, id: String, items: Vec<TextItem>) {
        self.store.write().await.insert(id, items);
    }

    pub async fn get(&self, id: &str) -> Option<Vec<TextItem>> {
        self.store.read().await.get(id).cloned()
    }
}
