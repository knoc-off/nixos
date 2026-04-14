//! Credential reader: loads bearer token from a JSON credentials file.
//!
//! Reads the file fresh on every request. No caching, no refresh logic.
//! If the file is missing or the token is expired, returns a clear error
//! telling the user what to do.
//!
//! Supports two credential file formats:
//! 1. Flat: `{"token": "...", "expires_at": "..."}`
//! 2. Nested (Claude CLI): `{"claudeAiOauth": {"accessToken": "...", "expiresAt": 1234567890}}`

use std::path::{Path, PathBuf};

use serde::Deserialize;

/// A resolved credential with auth metadata.
#[derive(Debug, Clone)]
pub struct Credential {
    /// The bearer token.
    pub token: String,
    /// Whether this is an OAuth token (from claudeAiOauth).
    /// Determines whether we send `Authorization: Bearer` + oauth beta,
    /// or `x-api-key`.
    pub is_oauth: bool,
}

/// The nested OAuth credential block (Claude CLI format).
#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
struct OAuthBlock {
    access_token: Option<String>,
    #[allow(dead_code)]
    refresh_token: Option<String>,
    /// Expiry as milliseconds since epoch (number).
    expires_at: Option<serde_json::Value>,
}

/// The credentials file — tries both flat and nested shapes.
#[derive(Deserialize, Debug)]
struct CredentialsFile {
    // -- Flat fields --
    #[serde(alias = "token", alias = "access_token", alias = "apiKey")]
    token: Option<String>,

    #[serde(alias = "expires_at", alias = "expiresAt")]
    expires_at: Option<serde_json::Value>,

    // -- Nested (Claude CLI) --
    #[serde(rename = "claudeAiOauth")]
    claude_ai_oauth: Option<OAuthBlock>,
}

/// Reads credentials from a configurable JSON file path.
#[derive(Debug, Clone)]
pub struct CredentialReader {
    path: PathBuf,
}

impl CredentialReader {
    /// Create a new reader for the given credentials file path.
    pub fn new(path: PathBuf) -> Self {
        Self { path }
    }

    /// Read the credentials file and return the credential (token + metadata).
    ///
    /// This reads the file fresh on every call. No caching.
    pub fn read_credential(&self) -> Result<Credential, CredentialError> {
        self.read_credential_from(&self.path)
    }

    /// Convenience: just get the token string. Used where is_oauth doesn't matter.
    pub fn read_token(&self) -> Result<String, CredentialError> {
        self.read_credential().map(|c| c.token)
    }

    /// Internal: read from a specific path.
    fn read_credential_from(&self, path: &Path) -> Result<Credential, CredentialError> {
        let content = std::fs::read_to_string(path).map_err(|e| {
            CredentialError::Missing(path.display().to_string(), e.to_string())
        })?;

        let creds: CredentialsFile = serde_json::from_str(&content).map_err(|e| {
            CredentialError::ParseFailed(path.display().to_string(), e.to_string())
        })?;

        // Try nested claudeAiOauth first, then flat fields
        let (token, expires_at, is_oauth) = if let Some(oauth) = &creds.claude_ai_oauth {
            (oauth.access_token.clone(), oauth.expires_at.clone(), true)
        } else {
            (creds.token.clone(), creds.expires_at.clone(), false)
        };

        let token = token.ok_or_else(|| {
            CredentialError::NoToken(path.display().to_string())
        })?;

        if token.is_empty() {
            return Err(CredentialError::NoToken(path.display().to_string()));
        }

        // Check expiry if present
        if let Some(ref expires_val) = expires_at {
            let expired = match expires_val {
                // Number: could be seconds or milliseconds epoch
                serde_json::Value::Number(n) => {
                    if let Some(ts) = n.as_i64() {
                        let now_ms = std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .unwrap_or_default()
                            .as_millis() as i64;

                        // Heuristic: if >= 1e12 it's milliseconds, otherwise seconds
                        if ts >= 1_000_000_000_000 {
                            ts < now_ms
                        } else {
                            ts < (now_ms / 1000)
                        }
                    } else {
                        false
                    }
                }
                // String: try parsing as integer
                serde_json::Value::String(s) => {
                    if let Ok(ts) = s.parse::<i64>() {
                        let now_s = std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .unwrap_or_default()
                            .as_secs() as i64;
                        ts < now_s
                    } else {
                        false
                    }
                }
                _ => false,
            };

            if expired {
                return Err(CredentialError::Expired(path.display().to_string()));
            }
        }

        Ok(Credential { token, is_oauth })
    }

    /// Get the path this reader is configured for.
    pub fn path(&self) -> &Path {
        &self.path
    }
}

/// Errors from credential operations.
#[derive(Debug, thiserror::Error)]
pub enum CredentialError {
    #[error(
        "credentials file not found: {0} ({1}). \
         Run your provider's auth command to create it."
    )]
    Missing(String, String),

    #[error(
        "failed to parse credentials file: {0} ({1}). \
         The file may be corrupted."
    )]
    ParseFailed(String, String),

    #[error(
        "no token found in credentials file: {0}. \
         Expected 'claudeAiOauth.accessToken', 'token', 'access_token', or 'apiKey'."
    )]
    NoToken(String),

    #[error(
        "token in {0} has expired. \
         Run your provider's auth command to refresh."
    )]
    Expired(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_read_valid_token_flat() {
        let dir = std::env::temp_dir();
        let path = dir.join("test-creds-valid.json");
        std::fs::write(
            &path,
            r#"{"token": "sk-test-123", "expires_at": "9999999999"}"#,
        )
        .unwrap();

        let reader = CredentialReader::new(path);
        let cred = reader.read_credential().unwrap();
        assert_eq!(cred.token, "sk-test-123");
        assert!(!cred.is_oauth);
    }

    #[test]
    fn test_read_claude_oauth_nested() {
        let dir = std::env::temp_dir();
        let path = dir.join("test-creds-claude-oauth.json");
        std::fs::write(
            &path,
            r#"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-test","refreshToken":"sk-ant-ort01-test","expiresAt":9999999999999}}"#,
        )
        .unwrap();

        let reader = CredentialReader::new(path);
        let cred = reader.read_credential().unwrap();
        assert_eq!(cred.token, "sk-ant-oat01-test");
        assert!(cred.is_oauth);
    }

    #[test]
    fn test_claude_oauth_expired() {
        let dir = std::env::temp_dir();
        let path = dir.join("test-creds-claude-expired.json");
        std::fs::write(
            &path,
            r#"{"claudeAiOauth":{"accessToken":"sk-ant-expired","expiresAt":1000000000000}}"#,
        )
        .unwrap();

        let reader = CredentialReader::new(path);
        let result = reader.read_credential();
        assert!(matches!(result, Err(CredentialError::Expired(_))));
    }

    #[test]
    fn test_read_access_token_alias() {
        let dir = std::env::temp_dir();
        let path = dir.join("test-creds-access.json");
        std::fs::write(&path, r#"{"access_token": "at-test-456"}"#).unwrap();

        let reader = CredentialReader::new(path);
        let cred = reader.read_credential().unwrap();
        assert_eq!(cred.token, "at-test-456");
        assert!(!cred.is_oauth);
    }

    #[test]
    fn test_missing_file() {
        let reader = CredentialReader::new(PathBuf::from("/nonexistent/creds.json"));
        let result = reader.read_credential();
        assert!(matches!(result, Err(CredentialError::Missing(_, _))));
    }

    #[test]
    fn test_expired_token_string() {
        let dir = std::env::temp_dir();
        let path = dir.join("test-creds-expired-str.json");
        std::fs::write(
            &path,
            r#"{"token": "sk-expired", "expires_at": "1000000000"}"#,
        )
        .unwrap();

        let reader = CredentialReader::new(path);
        let result = reader.read_credential();
        assert!(matches!(result, Err(CredentialError::Expired(_))));
    }

    #[test]
    fn test_empty_token() {
        let dir = std::env::temp_dir();
        let path = dir.join("test-creds-empty.json");
        std::fs::write(&path, r#"{"token": ""}"#).unwrap();

        let reader = CredentialReader::new(path);
        let result = reader.read_credential();
        assert!(matches!(result, Err(CredentialError::NoToken(_))));
    }
}
