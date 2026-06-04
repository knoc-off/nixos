//! Rate-limit utilization state captured from upstream response headers.

use std::sync::Mutex;

use serde::Serialize;

/// Cached rate-limit data from Anthropic's `anthropic-ratelimit-unified-*` headers.
#[derive(Debug, Default)]
pub struct UsageState {
    inner: Mutex<UsageSnapshot>,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct UsageSnapshot {
    /// 5-hour window utilization (0.0–1.0).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub five_hour_utilization: Option<f64>,
    /// 5-hour window status ("allowed", "rejected", etc.).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub five_hour_status: Option<String>,
    /// 5-hour window reset time (unix timestamp seconds).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub five_hour_reset: Option<u64>,

    /// 7-day window utilization (0.0–1.0).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub seven_day_utilization: Option<f64>,
    /// 7-day window status.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub seven_day_status: Option<String>,
    /// 7-day window reset time (unix timestamp seconds).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub seven_day_reset: Option<u64>,

    /// When this snapshot was last updated (unix timestamp seconds).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<u64>,
}

impl UsageState {
    /// Update the cached state from upstream response headers.
    pub fn update_from_headers(&self, headers: &reqwest::header::HeaderMap) {
        let get = |name: &str| -> Option<String> {
            headers.get(name).and_then(|v| v.to_str().ok()).map(|s| s.to_string())
        };

        let mut snap = self.inner.lock().unwrap();

        if let Some(v) = get("anthropic-ratelimit-unified-5h-utilization") {
            snap.five_hour_utilization = v.parse().ok();
        }
        if let Some(v) = get("anthropic-ratelimit-unified-5h-status") {
            snap.five_hour_status = Some(v);
        }
        if let Some(v) = get("anthropic-ratelimit-unified-5h-reset") {
            snap.five_hour_reset = v.parse().ok();
        }

        if let Some(v) = get("anthropic-ratelimit-unified-7d-utilization") {
            snap.seven_day_utilization = v.parse().ok();
        }
        if let Some(v) = get("anthropic-ratelimit-unified-7d-status") {
            snap.seven_day_status = Some(v);
        }
        if let Some(v) = get("anthropic-ratelimit-unified-7d-reset") {
            snap.seven_day_reset = v.parse().ok();
        }

        snap.updated_at = Some(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0),
        );
    }

    /// Get a clone of the current snapshot.
    pub fn snapshot(&self) -> UsageSnapshot {
        self.inner.lock().unwrap().clone()
    }
}
