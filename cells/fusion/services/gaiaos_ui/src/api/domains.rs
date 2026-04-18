//! Domain Registry API
//!
//! GET /api/domains - Returns the list of available domains from AKG
//!
//! Domains are loaded dynamically from:
//! 1. ArangoDB Knowledge Graph (gaiaos_domains collection)
//! 2. Falls back to config/domains.json if AKG unavailable
//! 3. Falls back to minimal defaults only if both fail

use axum::{response::IntoResponse, Json};
use serde::{Deserialize, Serialize};
use std::path::Path;
use tracing::{info, warn};

/// Domain metadata matching frontend `DomainMeta` interface
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainMeta {
    pub id: String,
    pub label: String,
    pub color: String,
    pub icon: String,
    pub priority: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub risk_tier: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub virtue_requirements: Option<VirtueRequirements>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VirtueRequirements {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub honesty: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub justice: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub prudence: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temperance: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub beneficence: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct DomainsConfig {
    domains: Vec<DomainMeta>,
}

/// Load domains from config file
fn load_from_config() -> Option<Vec<DomainMeta>> {
    let config_paths = [
        "config/domains.json",
        "/root/cells/fusion/config/domains.json",
        "../config/domains.json",
    ];
    
    for path in config_paths {
        if Path::new(path).exists() {
            match std::fs::read_to_string(path) {
                Ok(content) => {
                    match serde_json::from_str::<DomainsConfig>(&content) {
                        Ok(config) => {
                            info!("Loaded {} domains from {}", config.domains.len(), path);
                            return Some(config.domains);
                        }
                        Err(e) => {
                            warn!("Failed to parse domains config {}: {}", path, e);
                        }
                    }
                }
                Err(e) => {
                    warn!("Failed to read domains config {}: {}", path, e);
                }
            }
        }
    }
    None
}

/// Load domains from ArangoDB (gaiaos_domains collection)
async fn load_from_akg() -> Option<Vec<DomainMeta>> {
    // Try to connect to ArangoDB and query domains
    let arangodb_url = std::env::var("ARANGODB_URL")
        .unwrap_or_else(|_| "http://127.0.0.1:8529".to_string());
    
    let client = reqwest::Client::new();
    let query = r#"{"query": "FOR d IN gaiaos_domains SORT d.priority RETURN d"}"#;
    
    match client
        .post(format!("{arangodb_url}/_db/gaiaos/_api/cursor"))
        .header("Content-Type", "application/json")
        .basic_auth("root", Some(""))
        .body(query)
        .send()
        .await
    {
        Ok(response) => {
            if response.status().is_success() {
                if let Ok(body) = response.json::<serde_json::Value>().await {
                    if let Some(result) = body.get("result") {
                        if let Ok(domains) = serde_json::from_value::<Vec<DomainMeta>>(result.clone()) {
                            info!("Loaded {} domains from AKG", domains.len());
                            return Some(domains);
                        }
                    }
                }
            }
        }
        Err(e) => {
            warn!("AKG connection failed: {}", e);
        }
    }
    None
}

/// Minimal fallback domains (only used if AKG and config both fail)
fn fallback_domains() -> Vec<DomainMeta> {
    warn!("Using fallback domains - AKG and config unavailable");
    vec![
        DomainMeta {
            id: "general".to_string(),
            label: "General".to_string(),
            color: "#64748b".to_string(),
            icon: "brain".to_string(),
            priority: 1,
            description: Some("General reasoning. Connect to AKG for full domain list.".to_string()),
            risk_tier: None,
            virtue_requirements: None,
        },
    ]
}

/// GET /api/domains
/// Returns the list of available domains from AKG or config
pub async fn list() -> impl IntoResponse {
    // Priority: AKG > Config file > Fallback
    let domains = if let Some(akg_domains) = load_from_akg().await {
        akg_domains
    } else if let Some(config_domains) = load_from_config() {
        config_domains
    } else {
        fallback_domains()
    };
    
    Json(domains)
}

