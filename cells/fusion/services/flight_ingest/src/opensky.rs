//! OpenSky Network OAuth2 Client
//! 
//! Production-ready client for OpenSky REST API with:
//! - OAuth2 client credentials flow
//! - Automatic token refresh
//! - Rate limit handling (429)
//! - Proper error handling

use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, error, info, warn};

use crate::policy::{AircraftState, RegionBBox};

const TOKEN_URL: &str = "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token";
const API_BASE: &str = "https://opensky-network.org/api";

#[derive(Debug, Deserialize)]
struct TokenResponse {
    access_token: String,
    expires_in: u64,
    #[allow(dead_code)]
    token_type: String,
}

#[derive(Debug)]
struct TokenState {
    token: Option<String>,
    expires_at: DateTime<Utc>,
}

impl Default for TokenState {
    fn default() -> Self {
        Self {
            token: None,
            expires_at: Utc::now(),
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct OpenSkyResponse {
    pub time: Option<i64>,
    pub states: Option<Vec<Vec<serde_json::Value>>>,
}

/// OpenSky OAuth2 client with automatic token management
pub struct OpenSkyClient {
    client: Client,
    client_id: String,
    client_secret: String,
    token_state: Arc<RwLock<TokenState>>,
}

impl OpenSkyClient {
    pub fn new(client_id: &str, client_secret: &str) -> Self {
        let client = Client::builder()
            .user_agent("GaiaOS-FlightIngest/1.0")
            .timeout(std::time::Duration::from_secs(30))
            .build()
            .expect("Failed to build HTTP client");

        Self {
            client,
            client_id: client_id.to_string(),
            client_secret: client_secret.to_string(),
            token_state: Arc::new(RwLock::new(TokenState::default())),
        }
    }

    /// Check if current token is valid
    async fn token_valid(&self) -> bool {
        let state = self.token_state.read().await;
        state.token.is_some() && Utc::now() < state.expires_at
    }

    /// Refresh OAuth2 token using client credentials flow
    async fn refresh_token(&self) -> Result<()> {
        info!("Refreshing OpenSky OAuth2 token...");

        let params = [
            ("grant_type", "client_credentials"),
            ("client_id", &self.client_id),
            ("client_secret", &self.client_secret),
        ];

        let response = self
            .client
            .post(TOKEN_URL)
            .form(&params)
            .send()
            .await
            .context("Failed to send token request")?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            error!("Token request failed: {} - {}", status, body);
            anyhow::bail!("Token request failed: {} - {}", status, body);
        }

        let token_resp: TokenResponse = response
            .json()
            .await
            .context("Failed to parse token response")?;

        // Set expiry to 90% of actual expiry to avoid edge cases
        let expires_at = Utc::now() + chrono::Duration::seconds((token_resp.expires_in as f64 * 0.9) as i64);

        let mut state = self.token_state.write().await;
        state.token = Some(token_resp.access_token);
        state.expires_at = expires_at;

        info!("OAuth2 token refreshed, expires in ~{} seconds", token_resp.expires_in);
        Ok(())
    }

    /// Get valid token, refreshing if needed
    async fn get_token(&self) -> Result<String> {
        if !self.token_valid().await {
            self.refresh_token().await?;
        }

        let state = self.token_state.read().await;
        state.token.clone().context("No token available")
    }

    /// Fetch aircraft states for a bounding box
    pub async fn fetch_states(&self, region: &RegionBBox) -> Result<Vec<AircraftState>> {
        let token = self.get_token().await?;

        let url = format!(
            "{}/states/all?lamin={:.4}&lamax={:.4}&lomin={:.4}&lomax={:.4}",
            API_BASE, region.lamin, region.lamax, region.lomin, region.lomax
        );

        debug!("Fetching OpenSky states for region {}: {}", region.name, url);

        let response = self
            .client
            .get(&url)
            .bearer_auth(&token)
            .send()
            .await
            .context("Failed to send API request")?;

        let status = response.status();

        if status.as_u16() == 429 {
            let retry_after = response
                .headers()
                .get("X-Rate-Limit-Retry-After-Seconds")
                .and_then(|v| v.to_str().ok())
                .and_then(|s| s.parse::<u64>().ok())
                .unwrap_or(60);

            warn!("Rate limited by OpenSky, retry after {} seconds", retry_after);
            anyhow::bail!("RATE_LIMITED:{}", retry_after);
        }

        if !status.is_success() {
            let body = response.text().await.unwrap_or_default();
            error!("OpenSky API error: {} - {}", status, body);
            anyhow::bail!("OpenSky API error: {} - {}", status, body);
        }

        let data: OpenSkyResponse = response
            .json()
            .await
            .context("Failed to parse OpenSky response")?;

        let aircraft = self.parse_states(&data, &region.name);
        
        debug!("Received {} aircraft from OpenSky for region {}", aircraft.len(), region.name);
        Ok(aircraft)
    }

    /// Parse OpenSky state vectors into AircraftState structs
    fn parse_states(&self, response: &OpenSkyResponse, region: &str) -> Vec<AircraftState> {
        let states = match &response.states {
            Some(s) => s,
            None => return Vec::new(),
        };

        let mut aircraft = Vec::with_capacity(states.len());

        for state in states {
            if state.len() < 17 {
                continue;
            }

            // Skip aircraft on ground
            let on_ground = state[8].as_bool().unwrap_or(true);
            if on_ground {
                continue;
            }

            // Extract position
            let lon = match state[5].as_f64() {
                Some(v) => v,
                None => continue,
            };
            let lat = match state[6].as_f64() {
                Some(v) => v,
                None => continue,
            };

            let icao24 = state[0].as_str().unwrap_or("").to_string();
            let callsign = state[1].as_str().unwrap_or(&icao24).trim().to_string();
            let alt_m = state[7].as_f64().or_else(|| state[13].as_f64()).unwrap_or(0.0);
            let velocity_ms = state[9].as_f64().unwrap_or(0.0);
            let heading_deg = state[10].as_f64().unwrap_or(0.0);
            let vertical_rate_ms = state[11].as_f64().unwrap_or(0.0);
            let timestamp = state[4].as_i64().unwrap_or_else(|| Utc::now().timestamp());

            aircraft.push(AircraftState {
                icao24,
                callsign,
                lat,
                lon,
                alt_m,
                velocity_ms,
                heading_deg,
                vertical_rate_ms,
                last_update: DateTime::from_timestamp(timestamp, 0).unwrap_or_else(Utc::now),
                uncertainty: 0.0,
                region: region.to_string(),
                is_predicted: false,
            });
        }

        aircraft
    }

    /// Fetch own receiver states (unlimited, no credits)
    pub async fn fetch_own_states(&self) -> Result<Vec<AircraftState>> {
        let token = self.get_token().await?;

        let url = format!("{}/states/own", API_BASE);

        let response = self
            .client
            .get(&url)
            .bearer_auth(&token)
            .send()
            .await
            .context("Failed to send own states request")?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            // Own states might fail if user has no receivers - not fatal
            debug!("Own states not available: {} - {}", status, body);
            return Ok(Vec::new());
        }

        let data: OpenSkyResponse = response
            .json()
            .await
            .context("Failed to parse own states response")?;

        Ok(self.parse_states(&data, "OWN"))
    }
}

/// Represents a fetch result with metadata
#[derive(Debug)]
pub struct FetchResult {
    pub aircraft: Vec<AircraftState>,
    pub region: String,
    pub latency_ms: u64,
    pub is_rate_limited: bool,
    pub retry_after_secs: Option<u64>,
}

