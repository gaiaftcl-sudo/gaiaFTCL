//! QFOT Astro Validator
//!
//! Fail-closed validation gates for astro prediction tiles.
//! No synthetic inference is blessed without:
//! - temporal closure (forecast_time < valid_time)
//! - provenance (is_prediction=true, source=qfot_*)
//! - observer closure (predictions must not claim observations)

use anyhow::{anyhow, Context, Result};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::time::Duration;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QfotAstroValidationRequest {
    pub keys: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QfotAstroValidationResponse {
    pub passed: bool,
    pub validated: usize,
    pub failed: usize,
    pub failures: Vec<String>,
    pub validation_key: Option<String>,
}

#[derive(Clone)]
struct Arango {
    base_url: String,
    db_name: String,
    http: reqwest::Client,
    auth_header: String,
}

impl Arango {
    fn new() -> Result<Self> {
        let base_url = std::env::var("ARANGO_URL").unwrap_or_else(|_| "http://localhost:8529".to_string());
        let db_name = std::env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string());
        let user = std::env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string());
        let password = std::env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string());
        let http = reqwest::Client::builder()
            .timeout(Duration::from_secs(30))
            .user_agent("GaiaOS-Validation-QFOT-Astro/0.1.0")
            .build()
            .context("failed to build reqwest client")?;
        let auth = base64_encode(&format!("{user}:{password}"));
        Ok(Self {
            base_url,
            db_name,
            http,
            auth_header: format!("Basic {auth}"),
        })
    }

    async fn get_doc(&self, collection: &str, key: &str) -> Result<Value> {
        let url = format!(
            "{}/_db/{}/_api/document/{}/{}",
            self.base_url.trim_end_matches('/'),
            self.db_name,
            collection,
            key
        );
        let resp = self
            .http
            .get(url)
            .header("Authorization", &self.auth_header)
            .send()
            .await?;
        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("get_doc failed {status}: {text}"));
        }
        Ok(resp.json().await?)
    }

    async fn insert_validation_record(&self, doc: &Value) -> Result<String> {
        let url = format!(
            "{}/_db/{}/_api/document/field_validations",
            self.base_url.trim_end_matches('/'),
            self.db_name
        );
        let resp = self
            .http
            .post(url)
            .header("Authorization", &self.auth_header)
            .json(doc)
            .send()
            .await?;
        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("insert_validation_record failed {status}: {text}"));
        }
        let body: Value = resp.json().await?;
        Ok(body["_key"].as_str().unwrap_or_default().to_string())
    }
}

fn base64_encode(input: &str) -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let bytes = input.as_bytes();
    let mut result = String::new();

    for chunk in bytes.chunks(3) {
        let mut n: u32 = 0;
        for (i, &byte) in chunk.iter().enumerate() {
            n |= (byte as u32) << (16 - i * 8);
        }

        let padding = 3 - chunk.len();
        for i in 0..(4 - padding) {
            let idx = ((n >> (18 - i * 6)) & 0x3F) as usize;
            result.push(ALPHABET[idx] as char);
        }

        for _ in 0..padding {
            result.push('=');
        }
    }

    result
}

pub async fn validate_astro_predictions(req: QfotAstroValidationRequest) -> Result<QfotAstroValidationResponse> {
    let arango = Arango::new()?;
    let target_collection = "gravitational_tiles";

    if req.keys.is_empty() {
        return Ok(QfotAstroValidationResponse {
            passed: false,
            validated: 0,
            failed: 1,
            failures: vec!["no keys provided".to_string()],
            validation_key: None,
        });
    }

    let mut failures: Vec<String> = Vec::new();
    let mut validated = 0usize;

    for key in &req.keys {
        let doc = arango.get_doc(target_collection, key).await?;
        validated += 1;

        let forecast_time = doc["forecast_time"].as_i64().unwrap_or(0);
        let valid_time = doc["valid_time"].as_i64().unwrap_or(0);
        if forecast_time <= 0 || valid_time <= 0 || forecast_time >= valid_time {
            failures.push(format!("{key}: temporal_closure_failed forecast_time={forecast_time} valid_time={valid_time}"));
        }

        let is_prediction = doc["provenance"]["is_prediction"].as_bool().unwrap_or(false);
        if !is_prediction {
            failures.push(format!("{key}: provenance.is_prediction_missing_or_false"));
        }

        let source = doc["provenance"]["source"].as_str().unwrap_or("");
        if !source.starts_with("qfot_") {
            failures.push(format!("{key}: provenance.source_not_qfot ({source})"));
        }

        if doc.get("observations").is_some() {
            failures.push(format!("{key}: predictions_must_not_include_observations_field"));
        }

        // Minimal physical closure: gravitational potential and g field must exist.
        let gp = doc["state"]["gravitational_potential"].as_f64();
        let gmag = doc["state"]["g_field_magnitude"].as_f64();
        if gp.is_none() || gmag.is_none() {
            failures.push(format!("{key}: missing_gravity_terms state.gravitational_potential/state.g_field_magnitude"));
        }
    }

    let failed = failures.len();
    let passed = failed == 0;

    let record = json!({
        "timestamp": Utc::now().timestamp(),
        "target_collection": target_collection,
        "keys": req.keys,
        "valid_time": Utc::now().timestamp(),
        "passed": passed,
        "validated": validated,
        "failed": failed,
        "failures": failures,
        "provenance": {
            "source": "gaiaos_validation::qfot_astro",
            "version": env!("CARGO_PKG_VERSION"),
            "ingested_at": Utc::now().to_rfc3339()
        }
    });

    let validation_key = arango.insert_validation_record(&record).await.ok();

    Ok(QfotAstroValidationResponse {
        passed,
        validated,
        failed,
        failures: record["failures"]
            .as_array()
            .unwrap_or(&vec![])
            .iter()
            .filter_map(|v| v.as_str().map(|s| s.to_string()))
            .collect(),
        validation_key,
    })
}


