//! Configuration for the Spatial Gateway

use std::net::SocketAddr;
use crate::model::vqbit::CellOrigin;

/// Main configuration struct
#[derive(Debug, Clone)]
pub struct Config {
    /// Address to bind the HTTP/WebSocket server
    pub bind_addr: SocketAddr,
    /// Cell origin for ENU coordinate transformation
    pub cell_origin: CellOrigin,
    /// NATS URL for substrate messaging
    pub nats_url: String,
    /// ArangoDB URL for AKG persistence
    pub arangodb_url: String,
    /// LLM endpoint for semantic classification
    pub llm_endpoint: String,
    /// Maximum samples in world state
    pub max_world_samples: usize,
    /// Maximum age of samples in seconds
    pub max_sample_age_secs: f64,
    /// Session timeout in seconds
    pub session_timeout_secs: f64,
    /// Enable CORS for browser clients
    pub enable_cors: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            bind_addr: "0.0.0.0:8080".parse().unwrap(),
            cell_origin: CellOrigin {
                lat0_deg: 0.0,
                lon0_deg: 0.0,
                alt0_m: 0.0,
            },
            nats_url: "nats://nats:4222".to_string(),
            arangodb_url: "http://arangodb:8529".to_string(),
            llm_endpoint: "http://gaiaos-llm-router:11434/api/generate".to_string(),
            max_world_samples: 1_000_000,
            max_sample_age_secs: 3600.0,
            session_timeout_secs: 300.0,
            enable_cors: true,
        }
    }
}

impl Config {
    /// Load configuration from environment variables
    pub fn from_env() -> Self {
        let mut config = Self::default();
        
        // Bind address
        if let Ok(addr) = std::env::var("BIND_ADDR") {
            if let Ok(parsed) = addr.parse() {
                config.bind_addr = parsed;
            }
        }
        
        if let Ok(port) = std::env::var("PORT") {
            if let Ok(p) = port.parse::<u16>() {
                config.bind_addr = SocketAddr::from(([0, 0, 0, 0], p));
            }
        }
        
        // Cell origin
        config.cell_origin = CellOrigin {
            lat0_deg: std::env::var("CELL_ORIGIN_LAT")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0.0),
            lon0_deg: std::env::var("CELL_ORIGIN_LON")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0.0),
            alt0_m: std::env::var("CELL_ORIGIN_ALT")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0.0),
        };
        
        // Service URLs
        if let Ok(url) = std::env::var("NATS_URL") {
            config.nats_url = url;
        }
        
        if let Ok(url) = std::env::var("ARANGO_URL") {
            config.arangodb_url = url;
        }
        
        if let Ok(url) = std::env::var("LLM_ENDPOINT") {
            config.llm_endpoint = url;
        }
        
        // Limits
        if let Ok(v) = std::env::var("MAX_WORLD_SAMPLES") {
            if let Ok(n) = v.parse() {
                config.max_world_samples = n;
            }
        }
        
        if let Ok(v) = std::env::var("MAX_SAMPLE_AGE_SECS") {
            if let Ok(n) = v.parse() {
                config.max_sample_age_secs = n;
            }
        }
        
        if let Ok(v) = std::env::var("SESSION_TIMEOUT_SECS") {
            if let Ok(n) = v.parse() {
                config.session_timeout_secs = n;
            }
        }
        
        // Features
        if let Ok(v) = std::env::var("ENABLE_CORS") {
            config.enable_cors = v.to_lowercase() == "true" || v == "1";
        }
        
        config
    }
}
