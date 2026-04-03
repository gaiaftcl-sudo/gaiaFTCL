use crate::model::Patch;
use chrono::{DateTime, Utc};
use log::{error, info};
use reqwest::StatusCode;
use serde::Deserialize;
use serde_json::json;

#[derive(Clone)]
pub struct ArangoClient {
    base_url: String,
    db_name: String,
    collection: String,
    user: String,
    password: String,
    client: reqwest::Client,
}

#[derive(Debug, Deserialize)]
struct CursorResult<T> {
    result: Vec<T>,
    #[allow(dead_code)]
    #[serde(rename = "hasMore")]
    has_more: bool,
}

impl ArangoClient {
    pub fn new(
        base_url: &str,
        db_name: &str,
        collection: &str,
        user: &str,
        password: &str,
    ) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let client = reqwest::Client::builder()
            .user_agent("GaiaOS-CrystalSnapshot/0.1")
            .build()?;
        Ok(Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            db_name: db_name.to_string(),
            collection: collection.to_string(),
            user: user.to_string(),
            password: password.to_string(),
            client,
        })
    }

    async fn query_patches_internal(
        &self,
        lat: f64,
        lon: f64,
        radius_km: f64,
        t_min: DateTime<Utc>,
        t_max: DateTime<Utc>,
        context_filter: &str,
    ) -> Result<Vec<Patch>, Box<dyn std::error::Error + Send + Sync>> {
        let url = format!(
            "{base}/_db/{db}/_api/cursor",
            base = self.base_url,
            db = self.db_name
        );

        let radius_m = radius_km * 1000.0;
        let t_min_ms = t_min.timestamp_millis();
        let t_max_ms = t_max.timestamp_millis();

        // Production ATC query - return latest position per aircraft within viewport
        let query = format!(r#"
FOR p IN @@collection
  FILTER p.scale == "planetary"
  FILTER p.context LIKE @context_filter
  FILTER p.center_lat != null AND p.center_lon != null
  LET lat_diff = ABS(p.center_lat - @lat)
  LET lon_diff = ABS(p.center_lon - @lon)
  LET approx_dist_km = SQRT(lat_diff * lat_diff + lon_diff * lon_diff) * 111.0
  FILTER approx_dist_km <= @radius_km
  LET ts = DATE_TIMESTAMP(p.timestamp)
  FILTER ts >= @t_min AND ts <= @t_max
  SORT p.timestamp DESC
  LIMIT 15000
  RETURN p
"#);

        let bind_vars = json!({
            "@collection": self.collection,
            "lat": lat,
            "lon": lon,
            "radius_km": radius_km,
            "t_min": t_min_ms,
            "t_max": t_max_ms,
            "context_filter": context_filter,
        });

        info!("Querying patches with context filter: {}", context_filter);

        let resp = self
            .client
            .post(&url)
            .basic_auth(&self.user, Some(&self.password))
            .json(&json!({
                "query": query,
                "bindVars": bind_vars,
                "batchSize": 20000
            }))
            .send()
            .await?;

        if resp.status() != StatusCode::CREATED && resp.status() != StatusCode::OK {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            error!("Arango cursor error {}: {}", status, text);
            return Err(format!("Arango cursor error {}: {}", status, text).into());
        }

        let payload: CursorResult<Patch> = resp.json().await?;
        info!("Found {} patches for context {}", payload.result.len(), context_filter);
        Ok(payload.result)
    }

    pub async fn query_atc_patches(
        &self,
        lat: f64,
        lon: f64,
        radius_km: f64,
        t_min: DateTime<Utc>,
        t_max: DateTime<Utc>,
    ) -> Result<Vec<Patch>, Box<dyn std::error::Error + Send + Sync>> {
        // Use planetary:atc_live% to exclude conflicts (which are planetary:atc_conflict)
        self.query_patches_internal(lat, lon, radius_km, t_min, t_max, "planetary:atc_live%").await
    }

    pub async fn query_weather_patches(
        &self,
        lat: f64,
        lon: f64,
        radius_km: f64,
        t_min: DateTime<Utc>,
        t_max: DateTime<Utc>,
    ) -> Result<Vec<Patch>, Box<dyn std::error::Error + Send + Sync>> {
        self.query_patches_internal(lat, lon, radius_km, t_min, t_max, "planetary:weather%").await
    }

    pub async fn query_observer_patches(
        &self,
        lat: f64,
        lon: f64,
        radius_km: f64,
        t_min: DateTime<Utc>,
        t_max: DateTime<Utc>,
    ) -> Result<Vec<Patch>, Box<dyn std::error::Error + Send + Sync>> {
        self.query_patches_internal(lat, lon, radius_km, t_min, t_max, "planetary:observer%")
            .await
    }

    pub async fn query_conflict_patches(
        &self,
        lat: f64,
        lon: f64,
        radius_km: f64,
        t_min: DateTime<Utc>,
        t_max: DateTime<Utc>,
    ) -> Result<Vec<Patch>, Box<dyn std::error::Error + Send + Sync>> {
        self.query_patches_internal(lat, lon, radius_km, t_min, t_max, "planetary:atc_conflict%")
            .await
    }
}

