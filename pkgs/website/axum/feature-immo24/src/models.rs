// feature-immo24/src/models.rs

use serde::{Deserialize, Serialize};
use sqlx::types::Json;
use serde_json::Value as JsonValue; // Use an alias for clarity
use sqlx::FromRow;


/// Represents the settings that can be configured via the API.
/// This is the main struct for the /settings endpoint.
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ImmoSettings {
    pub reasoning_context: ReasoningContext,
    pub message_template: String,
}

/// Payload for the new message generation endpoint.
#[derive(Debug, Deserialize)]
pub struct GenerateMessagePayload {
    /// An optional, additional instruction to refine the generated message.
    pub refinement_prompt: Option<String>,
}

/// Response from the message generation endpoint.
#[derive(Debug, Serialize)]
pub struct GeneratedMessageResponse {
    pub message: String,
}


// === Existing Structs (with minor additions) ===

/// Represents the query parameters for filtering listings.
#[derive(Debug, Deserialize)]
pub struct ListQueryParams {
    pub status: Option<String>, // Optional: filter by listing status
    pub limit: Option<i64>,     // Optional: limit the number of results
    pub offset: Option<i64>,    // Optional: offset for pagination
}


#[derive(Debug, Serialize, Deserialize, Clone, sqlx::Type, PartialEq)]
#[sqlx(type_name = "processing_status", rename_all = "snake_case")]
pub enum ProcessingStatus {
    Pending,
    Extracting,
    ExtractionFailed,
    Reasoning,
    ReasoningFailed,
    Completed,
}

impl Default for ProcessingStatus {
    fn default() -> Self {
        ProcessingStatus::Pending
    }
}

#[derive(Debug, Serialize, Deserialize, Clone, Default)]
pub struct UserInfo {
    pub phone: String,
    pub email: String,
    pub misc: String,

}

#[derive(Debug, Serialize, Deserialize, Clone, Default)]
pub struct ReasoningContext {
    pub user_info: UserInfo,
    pub desired_features: Vec<String>,
    pub dealbreaker_features: Vec<String>,
}

/// Every field is optional, allowing for partial updates.
#[derive(Debug, Deserialize)]
pub struct UpdateListingPayload {
    pub status: Option<String>,
    pub total_rent: Option<f64>,
    pub address: Option<String>,
    pub published_at: Option<String>,
    pub notes: Option<String>,

    // For partial JSON updates, we accept a generic JSON value.
    // This allows the client to send just `{"pets_allowed": false}` for example.
    pub property_details: Option<JsonValue>,
    pub source_stats: Option<JsonValue>,
    pub contact_person: Option<JsonValue>,
    pub text_descriptions: Option<JsonValue>,
    pub ai_insights: Option<JsonValue>,
}


#[derive(Debug, Serialize, Deserialize, Default, Clone)]
pub struct PropertyDetails {
    pub title: Option<String>,
    pub cold_rent: Option<f64>,
    pub additional_costs: Option<f64>,
    pub heating_costs_included: Option<bool>,
    pub floor: Option<String>,
    pub year_built: Option<String>,
    pub condition: Option<String>,
    pub equipment_quality: Option<String>,
    pub heating_type: Option<String>,
    pub energy_source: Option<String>,
    pub pets_allowed: Option<bool>,
}

#[derive(Debug, Serialize, Deserialize, Default, Clone)]
pub struct SourceStats {
    pub views: Option<i32>,
    pub saved: Option<i32>,
    pub contacted: Option<i32>,
}

#[derive(Debug, Serialize, Deserialize, Default, Clone)]
pub struct ContactPerson {
    pub name: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Default, Clone)]
pub struct TextDescriptions {
    pub title: Option<String>,
    pub object_description: Option<String>,
    pub miscellaneous: Option<String>,
    pub equipment_details: Option<String>,
    pub location: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone, FromRow, Default)]
pub struct AiInsights {
    // --- Fields from Extraction Step ---
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub key_features: Vec<String>,
    #[serde(default)]
    pub potential_cons: Vec<String>,
    #[serde(default)]
    pub floor_level: Option<String>,
    #[serde(default)]
    pub pet_policy: Option<String>,
    #[serde(default)]
    pub application_requirements: Vec<(String, String)>, // requirements for documents, or something.


    // --- Fields from Reasoning Step ---
    #[serde(default)]
    pub fitness_score: Option<u8>, // A score from 0-100
    #[serde(default)]
    pub fitness_verdict: Option<String>, // e.g., "Excellent Match", "Poor Match", "Reject"
    #[serde(default)]
    pub fitness_notes: Option<String>, // Explanation for the verdict and score
}

// === The main struct for reading from the database ===
// This maps 1-to-1 with the database table columns.
#[derive(Debug, FromRow, Serialize, Clone)]
pub struct Listing {
    pub id: i64,
    pub scout_id: String,
    pub status: String,
    pub total_rent: Option<f64>,
    pub address: Option<String>,
    pub published_at: Option<String>,
    pub notes: Option<String>,

    // sqlx will automatically deserialize the TEXT columns into these structs.
    pub property_details: Json<PropertyDetails>,
    pub source_stats: Json<SourceStats>,
    pub contact_person: Json<ContactPerson>,
    pub text_descriptions: Json<TextDescriptions>,

    pub processing_status: ProcessingStatus, // Changed from String
    pub processing_error: Option<String>,
    #[sqlx(json)]
    pub ai_insights: AiInsights,

    pub created_at: String,
    pub updated_at: String,
}

// === The struct for the incoming POST request payload ===
// This defines the shape of the JSON your API will accept.
#[derive(Debug, Deserialize)]
pub struct NewListing {
    pub scout_id: String,
    pub status: Option<String>,
    pub total_rent: Option<f64>,
    pub address: Option<String>,
    pub published_at: Option<String>,
    pub notes: Option<String>,

    // The payload can contain these nested objects directly.
    pub property_details: PropertyDetails,
    pub source_stats: SourceStats,
    pub contact_person: ContactPerson,
    pub text_descriptions: TextDescriptions,
}
