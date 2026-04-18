//! OpenSky API client with Basic Auth support (OAuth2 fallback).
//! 
//! OpenSky Network provides free access with Basic Auth using username/password.
//! OAuth2 client credentials are for premium accounts.

use chrono::{DateTime, Utc};
use reqwest::StatusCode;
use serde::Deserialize;
use std::time::Duration;

#[derive(Debug, thiserror::Error)]
pub enum OpenSkyError {
    #[error("HTTP error {0}: {1}")]
    Http(u16, String),
    #[error("Request error: {0}")]
    Request(String),
    #[error("Token error: {0}")]
    TokenError(String),
    #[error("Rate limited, retry after {0} seconds")]
    RateLimited(u64),
}

#[derive(Debug, Deserialize)]
struct TokenResponse {
    access_token: String,
    expires_in: i64,
}

pub struct OpenSkyClient {
    username: String,
    password: String,
    use_basic_auth: bool,
    token: Option<String>,
    token_expires_at: Option<DateTime<Utc>>,
    http: reqwest::Client,
}

impl OpenSkyClient {
    pub fn new(username: String, password: String) -> Self {
        let http = reqwest::Client::builder()
            .timeout(Duration::from_secs(30))
            .user_agent("GaiaOS-ATC-Ingest/1.0")
            .build()
            .expect("Failed to build reqwest client");

        // Check if this looks like a username (contains @ or is short) vs client_id
        let use_basic_auth = !username.is_empty() && !password.is_empty();
        
        log::info!("OpenSky client initialized (basic_auth={})", use_basic_auth);

        Self {
            username,
            password,
            use_basic_auth,
            token: None,
            token_expires_at: None,
            http,
        }
    }

    async fn ensure_token(&mut self) -> Result<(), OpenSkyError> {
        // If using basic auth, we don't need a token
        if self.use_basic_auth {
            return Ok(());
        }
        
        let now = Utc::now();

        if let (Some(_token), Some(exp)) = (&self.token, &self.token_expires_at) {
            if *exp > now {
                return Ok(());
            } else {
                log::info!("OpenSky token expired, refreshing...");
            }
        }

        let url = "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token";

        let form = [
            ("grant_type", "client_credentials"),
            ("client_id", self.username.as_str()),
            ("client_secret", self.password.as_str()),
        ];

        let resp = self
            .http
            .post(url)
            .form(&form)
            .send()
            .await
            .map_err(|e| OpenSkyError::TokenError(e.to_string()))?;

        if resp.status() != StatusCode::OK {
            let status = resp.status().as_u16();
            let text = resp.text().await.unwrap_or_default();
            return Err(OpenSkyError::TokenError(format!(
                "token HTTP {}: {}",
                status, text
            )));
        }

        let tr: TokenResponse = resp
            .json()
            .await
            .map_err(|e| OpenSkyError::TokenError(e.to_string()))?;

        let expires_at = now + chrono::Duration::seconds((tr.expires_in as f64 * 0.9) as i64);
        self.token = Some(tr.access_token);
        self.token_expires_at = Some(expires_at);

        log::info!("✓ Obtained new OpenSky OAuth2 token (expires in ~{} min)", tr.expires_in / 60);
        Ok(())
    }

    pub async fn fetch_states_bbox(
        &mut self,
        lamin: f64,
        lamax: f64,
        lomin: f64,
        lomax: f64,
    ) -> Result<serde_json::Value, OpenSkyError> {
        let url = "https://opensky-network.org/api/states/all";

        let params = [
            ("lamin", format!("{:.4}", lamin)),
            ("lamax", format!("{:.4}", lamax)),
            ("lomin", format!("{:.4}", lomin)),
            ("lomax", format!("{:.4}", lomax)),
        ];

        let resp = if self.use_basic_auth {
            // Use Basic Auth for free tier
            self.http
                .get(url)
                .query(&params)
                .basic_auth(&self.username, Some(&self.password))
                .send()
                .await
                .map_err(|e| OpenSkyError::Request(e.to_string()))?
        } else {
            // Use OAuth2 Bearer token for premium
            self.ensure_token().await?;
            let token = self
                .token
                .as_ref()
                .ok_or_else(|| OpenSkyError::TokenError("missing token".into()))?
                .clone();
                
            self.http
                .get(url)
                .query(&params)
                .bearer_auth(&token)
                .send()
                .await
                .map_err(|e| OpenSkyError::Request(e.to_string()))?
        };

        if resp.status() == StatusCode::TOO_MANY_REQUESTS {
            let retry = resp
                .headers()
                .get("X-Rate-Limit-Retry-After-Seconds")
                .and_then(|v| v.to_str().ok())
                .and_then(|s| s.parse::<u64>().ok())
                .unwrap_or(60);
            return Err(OpenSkyError::RateLimited(retry));
        }

        let status = resp.status().as_u16();
        if status != 200 {
            let text = resp.text().await.unwrap_or_default();
            return Err(OpenSkyError::Http(status, text));
        }

        let json: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| OpenSkyError::Request(e.to_string()))?;
        Ok(json)
    }
}

