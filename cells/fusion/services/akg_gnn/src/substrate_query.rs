// services/akg_gnn/src/substrate_query.rs
// Direct ArangoDB queries for the unified 8D substrate

use anyhow::Result;
use log::{error, info, warn};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::api::{ProcedureEdge, ProcedureNode};

// ============================================================================
// QFOT FIELD SUBSTRATE QUERY TYPES
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FieldGeoPoint {
    #[serde(rename = "type")]
    pub typ: String,
    pub coordinates: [f64; 2], // [lon, lat]
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AtmosphereTileDoc {
    #[serde(rename = "_key")]
    pub key: String,
    pub location: FieldGeoPoint,
    pub altitude_ft: i32,
    pub forecast_time: i64,
    pub valid_time: i64,
    pub resolution_level: u8,
    pub resolution_deg: f64,
    pub state: Value,
    pub uncertainty: Value,
    pub provenance: Value,
    #[serde(default)]
    pub observations: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OceanTileDoc {
    #[serde(rename = "_key")]
    pub key: String,
    pub location: FieldGeoPoint,
    #[serde(default)]
    pub depth_m: Option<f64>,
    pub forecast_time: i64,
    pub valid_time: i64,
    pub resolution_level: u8,
    pub resolution_deg: f64,
    pub state: Value,
    pub uncertainty: Value,
    pub provenance: Value,
    #[serde(default)]
    pub observations: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BiosphereTileDoc {
    #[serde(rename = "_key")]
    pub key: String,
    pub location: FieldGeoPoint,
    pub forecast_time: i64,
    pub valid_time: i64,
    pub resolution_level: u8,
    pub resolution_deg: f64,
    pub state: Value,
    #[serde(default)]
    pub uncertainty: Value,
    pub provenance: Value,
    #[serde(default)]
    pub observations: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FieldRelationDoc {
    #[serde(rename = "_from")]
    pub from: String,
    #[serde(rename = "_to")]
    pub to: String,
    pub relation_type: String,
    #[serde(default)]
    pub coupling_strength: Option<f64>,
    #[serde(default)]
    pub valid_time: Option<i64>,
    #[serde(default)]
    pub flux: Option<Value>,
    #[serde(default)]
    pub interaction: Option<Value>,
    #[serde(default)]
    pub dwell_time_seconds: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObservationDoc {
    #[serde(rename = "_key")]
    pub key: String,
    pub observer_id: String,
    pub observer_type: String,
    pub timestamp: i64,
    pub location: FieldGeoPoint,
    #[serde(default)]
    pub altitude_ft: Option<f64>,
    pub measurement: Value,
    pub quality: Value,
    pub validates_tile: String,
    pub provenance: Value,
}

// ============================================================================
// MOLECULAR SUBSTRATE QUERY TYPES (Å scale)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MolecularTileDoc {
    #[serde(rename = "_key")]
    pub key: String,
    pub protein_id: String,
    pub trajectory_id: Option<String>,

    // 2D geo point (x,y). z stored separately (Arango geo is 2D).
    pub position_angstrom: FieldGeoPoint,
    pub z_angstrom: f64,
    pub resolution_angstrom: f64,

    pub simulation_time_ps: f64,
    pub timestep_fs: f64,

    pub state: Value,
    pub pattern: Option<Value>,
    pub uncertainty: Option<Value>,
    pub intent: Option<Value>,
    pub observations: Option<Value>,
    pub provenance: Value,

    #[serde(default)]
    pub forecast_time: Option<i64>,
    #[serde(default)]
    pub valid_time: Option<i64>,

    pub ingest_timestamp: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MolecularInteractionDoc {
    #[serde(rename = "_from")]
    pub from: String,
    #[serde(rename = "_to")]
    pub to: String,
    pub interaction_type: String,
    #[serde(default)]
    pub strength_kcal_mol: Option<f64>,
    #[serde(default)]
    pub equilibrium_distance_angstrom: Option<f64>,
    #[serde(default)]
    pub force_constant: Option<f64>,
    pub simulation_time_ps: f64,
    pub ingest_timestamp: i64,
}

// ============================================================================
// ASTRO SUBSTRATE QUERY TYPES (ECI km)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GravitationalTileDoc {
    #[serde(rename = "_key")]
    pub key: String,
    // 2D geo point (x,y). z stored separately.
    pub position_eci: FieldGeoPoint,
    pub z_km: f64,
    pub resolution_km: f64,
    pub epoch_seconds: i64,
    pub timestep_seconds: f64,
    pub state: Value,
    pub pattern: Option<Value>,
    pub uncertainty: Option<Value>,
    pub intent: Option<Value>,
    pub observations: Option<Value>,
    pub provenance: Value,

    #[serde(default)]
    pub forecast_time: Option<i64>,
    #[serde(default)]
    pub valid_time: Option<i64>,
}
/// Client for querying the substrate (ArangoDB)
pub struct SubstrateQuery {
    client: Client,
    base_url: String,
    db_name: String,
    auth: String,
}

impl SubstrateQuery {
    /// Create new substrate query client
    pub async fn new(url: &str, db_name: &str) -> Result<Self> {
        info!("Connecting to substrate at: {url}");

        let client = Client::new();
        let user = std::env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string());
        let password = std::env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string());
        let auth = base64_encode(&format!("{user}:{password}"));

        // Test connection
        let test_url = format!("{url}/_api/version");
        let resp = client
            .get(&test_url)
            .header("Authorization", format!("Basic {auth}"))
            .send()
            .await?;

        if !resp.status().is_success() {
            anyhow::bail!("Failed to connect to ArangoDB: {}", resp.status());
        }

        let version: Value = resp.json().await?;
        info!(
            "✓ Connected to ArangoDB {}",
            version["version"].as_str().unwrap_or("unknown")
        );

        Ok(Self {
            client,
            base_url: url.to_string(),
            db_name: db_name.to_string(),
            auth,
        })
    }

    /// Health check
    pub async fn health_check(&self) -> Result<bool> {
        let url = format!("{}/_api/version", self.base_url);
        match self
            .client
            .get(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .send()
            .await
        {
            Ok(resp) => Ok(resp.status().is_success()),
            Err(e) => {
                warn!("ArangoDB health check failed: {e}");
                Ok(false)
            }
        }
    }

    /// Query local patch of procedures around a center point
    pub async fn query_local_patch(
        &self,
        context_prefix: &str,
        center: &[f64; 8],
        radius: f64,
        weights: &[f64; 8],
        max_results: usize,
        intent_filter: Option<&str>,
    ) -> Result<Vec<ProcedureNode>> {
        // Build weighted distance calculation in AQL
        let distance_calc = format!(
            r#"
            LET d0 = (doc.d0_d7[0] - {c0}) * {w0}
            LET d1 = (doc.d0_d7[1] - {c1}) * {w1}
            LET d2 = (doc.d0_d7[2] - {c2}) * {w2}
            LET d3 = (doc.d0_d7[3] - {c3}) * {w3}
            LET d4 = (doc.d0_d7[4] - {c4}) * {w4}
            LET d5 = (doc.d0_d7[5] - {c5}) * {w5}
            LET d6 = (doc.d0_d7[6] - {c6}) * {w6}
            LET d7 = (doc.d0_d7[7] - {c7}) * {w7}
            LET weighted_dist = SQRT(d0*d0 + d1*d1 + d2*d2 + d3*d3 + d4*d4 + d5*d5 + d6*d6 + d7*d7)
            "#,
            c0 = center[0],
            c1 = center[1],
            c2 = center[2],
            c3 = center[3],
            c4 = center[4],
            c5 = center[5],
            c6 = center[6],
            c7 = center[7],
            w0 = weights[0],
            w1 = weights[1],
            w2 = weights[2],
            w3 = weights[3],
            w4 = weights[4],
            w5 = weights[5],
            w6 = weights[6],
            w7 = weights[7],
        );

        let intent_clause = intent_filter
            .map(|_| "FILTER CONTAINS(LOWER(doc.intent), LOWER(@intent))".to_string())
            .unwrap_or_default();

        let aql = format!(
            r#"
            FOR doc IN procedures
                FILTER STARTS_WITH(doc.context, @context_prefix)
                {distance_calc}
                FILTER weighted_dist <= @radius
                {intent_clause}
                SORT weighted_dist ASC
                LIMIT @max_results
                RETURN {{
                    id: doc._key,
                    context: doc.context,
                    d0_d7: doc.d0_d7,
                    intent: doc.intent,
                    success_rate: doc.success_rate,
                    execution_count: doc.execution_count,
                    risk_level: doc.risk_level,
                    confidence: 1.0 - (weighted_dist / @radius)
                }}
            "#,
        );

        let mut bind_vars = json!({
            "context_prefix": context_prefix,
            "radius": radius,
            "max_results": max_results as i64,
        });

        if let Some(intent) = intent_filter {
            bind_vars["intent"] = json!(intent);
        }

        self.aql_query(&aql, bind_vars).await
    }

    /// Query edges between a set of procedures
    pub async fn query_edges(&self, procedure_ids: &[&str]) -> Result<Vec<ProcedureEdge>> {
        if procedure_ids.is_empty() {
            return Ok(Vec::new());
        }

        let aql = r#"
            FOR edge IN procedure_edges
                LET from_key = SPLIT(edge._from, '/')[1]
                LET to_key = SPLIT(edge._to, '/')[1]
                FILTER from_key IN @ids AND to_key IN @ids
                RETURN {
                    from_id: from_key,
                    to_id: to_key,
                    edge_type: edge.type,
                    weight: edge.weight
                }
        "#;

        let bind_vars = json!({
            "ids": procedure_ids,
        });

        self.aql_query(aql, bind_vars).await
    }

    /// Store a new procedure node
    pub async fn store_procedure(&self, procedure: &ProcedureNode) -> Result<String> {
        let doc = json!({
            "_key": procedure.id,
            "context": procedure.context,
            "d0_d7": procedure.d0_d7,
            "intent": procedure.intent,
            "success_rate": procedure.success_rate,
            "execution_count": procedure.execution_count,
            "risk_level": procedure.risk_level,
        });

        let url = format!(
            "{}/_db/{}/_api/document/procedures",
            self.base_url, self.db_name
        );

        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .header("Content-Type", "application/json")
            .json(&doc)
            .send()
            .await?;

        if !resp.status().is_success() {
            let error: Value = resp.json().await.unwrap_or(json!({}));
            anyhow::bail!(
                "Failed to store procedure: {}",
                error["errorMessage"].as_str().unwrap_or("unknown error")
            );
        }

        let result: Value = resp.json().await?;
        Ok(result["_key"].as_str().unwrap_or(&procedure.id).to_string())
    }

    /// Update procedure after execution outcome
    pub async fn update_procedure_outcome(&self, procedure_id: &str, success: bool) -> Result<()> {
        let aql = if success {
            r#"
                FOR proc IN procedures
                    FILTER proc._key == @key
                    UPDATE proc WITH {
                        execution_count: proc.execution_count + 1,
                        success_rate: (proc.success_rate * proc.execution_count + 1) / (proc.execution_count + 1)
                    } IN procedures
            "#
        } else {
            r#"
                FOR proc IN procedures
                    FILTER proc._key == @key
                    UPDATE proc WITH {
                        execution_count: proc.execution_count + 1,
                        success_rate: (proc.success_rate * proc.execution_count) / (proc.execution_count + 1)
                    } IN procedures
            "#
        };

        let bind_vars = json!({"key": procedure_id});
        self.aql_query::<Value>(aql, bind_vars).await?;
        Ok(())
    }

    /// Store an edge between procedures
    pub async fn store_edge(&self, edge: &ProcedureEdge) -> Result<()> {
        let doc = json!({
            "_from": format!("procedures/{}", edge.from_id),
            "_to": format!("procedures/{}", edge.to_id),
            "type": edge.edge_type,
            "weight": edge.weight,
        });

        let url = format!(
            "{}/_db/{}/_api/document/procedure_edges",
            self.base_url, self.db_name
        );

        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .header("Content-Type", "application/json")
            .json(&doc)
            .send()
            .await?;

        if !resp.status().is_success() {
            let error: Value = resp.json().await.unwrap_or(json!({}));
            anyhow::bail!(
                "Failed to store edge: {}",
                error["errorMessage"].as_str().unwrap_or("unknown error")
            );
        }

        Ok(())
    }

    /// Execute an AQL query with bind variables
    async fn aql_query<T: for<'de> Deserialize<'de>>(
        &self,
        aql: &str,
        bind_vars: Value,
    ) -> Result<Vec<T>> {
        let url = format!("{}/_db/{}/_api/cursor", self.base_url, self.db_name);

        let body = json!({
            "query": aql,
            "bindVars": bind_vars,
            "batchSize": 1000
        });

        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await?;

        if !resp.status().is_success() {
            let error: Value = resp.json().await.unwrap_or(json!({}));
            let error_msg = error["errorMessage"].as_str().unwrap_or("unknown error");
            error!("AQL query failed: {error_msg}");
            anyhow::bail!("AQL query failed: {error_msg}");
        }

        let result: Value = resp.json().await?;
        let arr = result["result"].as_array().cloned().unwrap_or_default();
        let mut out: Vec<T> = Vec::with_capacity(arr.len());
        let mut dropped = 0usize;

        for v in arr {
            match serde_json::from_value::<T>(v) {
                Ok(t) => out.push(t),
                Err(e) => {
                    dropped += 1;
                    warn!("AQL decode dropped document: {e}");
                }
            }
        }

        if dropped > 0 {
            warn!("AQL decode dropped {} documents; returned {}", dropped, out.len());
        }

        Ok(out)
    }

    /// Get substrate statistics
    pub async fn get_substrate_stats(&self) -> Result<crate::api::SubstrateStats> {
        use std::collections::HashMap;

        // Count procedures by scale
        let aql = r#"
            LET total_procs = LENGTH(procedures)
            LET total_edges = LENGTH(procedure_edges)
            LET by_scale = (
                FOR doc IN procedures
                    COLLECT scale = SPLIT(doc.context, ":")[0]
                    AGGREGATE count = LENGTH(1)
                    RETURN { scale, count }
            )
            RETURN {
                total_procedures: total_procs,
                total_edges: total_edges,
                by_scale: by_scale
            }
        "#;

        let results: Vec<Value> = self.aql_query(aql, json!({})).await?;

        if let Some(result) = results.first() {
            let mut by_scale = HashMap::new();

            if let Some(scales) = result["by_scale"].as_array() {
                for item in scales {
                    if let (Some(scale), Some(count)) =
                        (item["scale"].as_str(), item["count"].as_u64())
                    {
                        by_scale.insert(scale.to_string(), count as usize);
                    }
                }
            }

            Ok(crate::api::SubstrateStats {
                total_procedures: result["total_procedures"].as_u64().unwrap_or(0) as usize,
                total_edges: result["total_edges"].as_u64().unwrap_or(0) as usize,
                procedures_by_scale: by_scale,
                arango_connected: true,
            })
        } else {
            Ok(crate::api::SubstrateStats::default())
        }
    }

    // ============================================================================
    // QFOT FIELD GRAPH QUERIES (tiles + relations + observations)
    // ============================================================================

    pub async fn query_atmosphere_tiles(
        &self,
        lat_min: f64,
        lat_max: f64,
        lon_min: f64,
        lon_max: f64,
        valid_time_min: i64,
        valid_time_max: i64,
        altitude_min_ft: Option<i32>,
        altitude_max_ft: Option<i32>,
        limit: usize,
    ) -> Result<Vec<AtmosphereTileDoc>> {
        let alt_clause = match (altitude_min_ft, altitude_max_ft) {
            (Some(_min), Some(_max)) => "FILTER tile.altitude_ft >= @alt_min AND tile.altitude_ft <= @alt_max",
            (Some(_min), None) => "FILTER tile.altitude_ft >= @alt_min",
            (None, Some(_max)) => "FILTER tile.altitude_ft <= @alt_max",
            (None, None) => "",
        };

        let aql = format!(
            r#"
FOR tile IN atmosphere_tiles
  FILTER tile.location.coordinates[1] >= @lat_min AND tile.location.coordinates[1] <= @lat_max
  FILTER tile.location.coordinates[0] >= @lon_min AND tile.location.coordinates[0] <= @lon_max
  FILTER tile.valid_time >= @t_min AND tile.valid_time <= @t_max
  {alt_clause}
  SORT tile.valid_time DESC
  LIMIT @limit
  RETURN tile
"#
        );

        let mut bind = json!({
            "lat_min": lat_min,
            "lat_max": lat_max,
            "lon_min": lon_min,
            "lon_max": lon_max,
            "t_min": valid_time_min,
            "t_max": valid_time_max,
            "limit": limit as i64
        });
        if let Some(v) = altitude_min_ft {
            bind["alt_min"] = json!(v);
        }
        if let Some(v) = altitude_max_ft {
            bind["alt_max"] = json!(v);
        }

        self.aql_query(&aql, bind).await
    }

    pub async fn query_ocean_tiles(
        &self,
        lat_min: f64,
        lat_max: f64,
        lon_min: f64,
        lon_max: f64,
        valid_time_min: i64,
        valid_time_max: i64,
        depth_min_m: Option<f64>,
        depth_max_m: Option<f64>,
        limit: usize,
    ) -> Result<Vec<OceanTileDoc>> {
        let depth_clause = match (depth_min_m, depth_max_m) {
            (Some(_min), Some(_max)) => "FILTER tile.depth_m >= @d_min AND tile.depth_m <= @d_max",
            (Some(_min), None) => "FILTER tile.depth_m >= @d_min",
            (None, Some(_max)) => "FILTER tile.depth_m <= @d_max",
            (None, None) => "",
        };

        let aql = format!(
            r#"
FOR tile IN ocean_tiles
  FILTER tile.location.coordinates[1] >= @lat_min AND tile.location.coordinates[1] <= @lat_max
  FILTER tile.location.coordinates[0] >= @lon_min AND tile.location.coordinates[0] <= @lon_max
  FILTER tile.valid_time >= @t_min AND tile.valid_time <= @t_max
  {depth_clause}
  SORT tile.valid_time DESC
  LIMIT @limit
  RETURN tile
"#
        );

        let mut bind = json!({
            "lat_min": lat_min,
            "lat_max": lat_max,
            "lon_min": lon_min,
            "lon_max": lon_max,
            "t_min": valid_time_min,
            "t_max": valid_time_max,
            "limit": limit as i64
        });
        if let Some(v) = depth_min_m {
            bind["d_min"] = json!(v);
        }
        if let Some(v) = depth_max_m {
            bind["d_max"] = json!(v);
        }

        self.aql_query(&aql, bind).await
    }

    pub async fn query_biosphere_tiles(
        &self,
        lat_min: f64,
        lat_max: f64,
        lon_min: f64,
        lon_max: f64,
        valid_time_min: i64,
        valid_time_max: i64,
        limit: usize,
    ) -> Result<Vec<BiosphereTileDoc>> {
        let aql = r#"
FOR tile IN biosphere_tiles
  FILTER tile.location.coordinates[1] >= @lat_min AND tile.location.coordinates[1] <= @lat_max
  FILTER tile.location.coordinates[0] >= @lon_min AND tile.location.coordinates[0] <= @lon_max
  FILTER tile.valid_time >= @t_min AND tile.valid_time <= @t_max
  SORT tile.valid_time DESC
  LIMIT @limit
  RETURN tile
"#;

        self.aql_query(
            aql,
            json!({
                "lat_min": lat_min,
                "lat_max": lat_max,
                "lon_min": lon_min,
                "lon_max": lon_max,
                "t_min": valid_time_min,
                "t_max": valid_time_max,
                "limit": limit as i64
            }),
        )
        .await
    }

    pub async fn query_field_relations(
        &self,
        valid_time_min: i64,
        valid_time_max: i64,
        limit: usize,
    ) -> Result<Vec<FieldRelationDoc>> {
        let aql = r#"
FOR rel IN field_relations
  FILTER rel.valid_time >= @t_min AND rel.valid_time <= @t_max
  SORT rel.valid_time DESC
  LIMIT @limit
  RETURN rel
"#;

        self.aql_query(
            aql,
            json!({
                "t_min": valid_time_min,
                "t_max": valid_time_max,
                "limit": limit as i64
            }),
        )
        .await
    }

    pub async fn query_observations(
        &self,
        lat_min: f64,
        lat_max: f64,
        lon_min: f64,
        lon_max: f64,
        ts_min: i64,
        ts_max: i64,
        limit: usize,
    ) -> Result<Vec<ObservationDoc>> {
        let aql = r#"
FOR obs IN observations
  FILTER obs.location.coordinates[1] >= @lat_min AND obs.location.coordinates[1] <= @lat_max
  FILTER obs.location.coordinates[0] >= @lon_min AND obs.location.coordinates[0] <= @lon_max
  FILTER obs.timestamp >= @ts_min AND obs.timestamp <= @ts_max
  SORT obs.timestamp DESC
  LIMIT @limit
  RETURN obs
"#;

        self.aql_query(
            aql,
            json!({
                "lat_min": lat_min,
                "lat_max": lat_max,
                "lon_min": lon_min,
                "lon_max": lon_max,
                "ts_min": ts_min,
                "ts_max": ts_max,
                "limit": limit as i64
            }),
        )
        .await
    }

    /// Upsert a raw document into an arbitrary collection (overwrite=true).
    ///
    /// This is used by QFOT forecast persistence and validation artifacts.
    pub async fn upsert_raw_document(&self, collection: &str, doc: &Value) -> Result<()> {
        let url = format!(
            "{}/_db/{}/_api/document/{}?overwrite=true",
            self.base_url, self.db_name, collection
        );

        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .header("Content-Type", "application/json")
            .json(doc)
            .send()
            .await?;

        if !resp.status().is_success() {
            let error: Value = resp.json().await.unwrap_or(json!({}));
            anyhow::bail!(
                "Failed to upsert document: {}",
                error["errorMessage"].as_str().unwrap_or("unknown error")
            );
        }
        Ok(())
    }

    // ============================================================================
    // Molecular queries
    // ============================================================================

    pub async fn query_molecular_tiles(
        &self,
        protein_id: &str,
        sim_time_ps_min: f64,
        sim_time_ps_max: f64,
        x_min: f64,
        x_max: f64,
        y_min: f64,
        y_max: f64,
        z_min: f64,
        z_max: f64,
        limit: usize,
    ) -> Result<Vec<MolecularTileDoc>> {
        let aql = r#"
FOR tile IN molecular_tiles
  FILTER tile.protein_id == @protein_id
  FILTER tile.simulation_time_ps >= @t_min AND tile.simulation_time_ps <= @t_max
  FILTER tile.position_angstrom.coordinates[0] >= @x_min AND tile.position_angstrom.coordinates[0] <= @x_max
  FILTER tile.position_angstrom.coordinates[1] >= @y_min AND tile.position_angstrom.coordinates[1] <= @y_max
  FILTER tile.z_angstrom >= @z_min AND tile.z_angstrom <= @z_max
  SORT tile.simulation_time_ps DESC
  LIMIT @limit
  RETURN tile
"#;

        self.aql_query(
            aql,
            json!({
                "protein_id": protein_id,
                "t_min": sim_time_ps_min,
                "t_max": sim_time_ps_max,
                "x_min": x_min,
                "x_max": x_max,
                "y_min": y_min,
                "y_max": y_max,
                "z_min": z_min,
                "z_max": z_max,
                "limit": limit as i64
            }),
        )
        .await
    }

    pub async fn query_molecular_interactions(
        &self,
        sim_time_ps_min: f64,
        sim_time_ps_max: f64,
        limit: usize,
    ) -> Result<Vec<MolecularInteractionDoc>> {
        let aql = r#"
FOR e IN molecular_interactions
  FILTER e.simulation_time_ps >= @t_min AND e.simulation_time_ps <= @t_max
  SORT e.simulation_time_ps DESC
  LIMIT @limit
  RETURN e
"#;

        self.aql_query(
            aql,
            json!({
                "t_min": sim_time_ps_min,
                "t_max": sim_time_ps_max,
                "limit": limit as i64
            }),
        )
        .await
    }

    // ============================================================================
    // Astro queries
    // ============================================================================

    pub async fn query_gravitational_tiles(
        &self,
        epoch_min: i64,
        epoch_max: i64,
        x_min: f64,
        x_max: f64,
        y_min: f64,
        y_max: f64,
        z_min: f64,
        z_max: f64,
        limit: usize,
    ) -> Result<Vec<GravitationalTileDoc>> {
        let aql = r#"
FOR tile IN gravitational_tiles
  FILTER tile.epoch_seconds >= @t_min AND tile.epoch_seconds <= @t_max
  FILTER tile.position_eci.coordinates[0] >= @x_min AND tile.position_eci.coordinates[0] <= @x_max
  FILTER tile.position_eci.coordinates[1] >= @y_min AND tile.position_eci.coordinates[1] <= @y_max
  FILTER tile.z_km >= @z_min AND tile.z_km <= @z_max
  SORT tile.epoch_seconds DESC
  LIMIT @limit
  RETURN tile
"#;

        self.aql_query(
            aql,
            json!({
                "t_min": epoch_min,
                "t_max": epoch_max,
                "x_min": x_min,
                "x_max": x_max,
                "y_min": y_min,
                "y_max": y_max,
                "z_min": z_min,
                "z_max": z_max,
                "limit": limit as i64
            }),
        )
        .await
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ATC + WEATHER QUERY PATTERNS
// ═══════════════════════════════════════════════════════════════════════════

/// ATC world patch from world_patches collection
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AtcWorldPatch {
    #[serde(rename = "_key")]
    pub key: String,
    pub scale: String,
    pub context: String,
    pub center_lat: f64,
    pub center_lon: f64,
    pub center_alt_m: f64,
    pub timestamp: String,
    pub d_vec: [f64; 8],
    // ATC fields
    pub icao24: Option<String>,
    pub callsign: Option<String>,
    pub origin_country: Option<String>,
    pub category: Option<i64>,
    pub velocity_ms: Option<f64>,
    pub heading_deg: Option<f64>,
    pub vertical_rate_ms: Option<f64>,
    pub is_predicted: Option<bool>,
    pub uncertainty: Option<f64>,
    // Weather overlay
    pub weather_d_vec: Option<[f64; 8]>,
    pub temperature_c: Option<f64>,
    pub wind_speed_ms: Option<f64>,
    pub visibility_m: Option<f64>,
    // Fused 8D
    pub fused_d_vec: Option<[f64; 8]>,
}

/// Weather world patch
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WeatherWorldPatch {
    #[serde(rename = "_key")]
    pub key: String,
    pub scale: String,
    pub context: String,
    pub center_lat: f64,
    pub center_lon: f64,
    pub center_alt_m: f64,
    pub timestamp: String,
    pub d_vec: [f64; 8],
    pub temperature_c: Option<f64>,
    pub humidity_pct: Option<f64>,
    pub wind_speed_ms: Option<f64>,
    pub wind_dir_deg: Option<f64>,
    pub visibility_m: Option<f64>,
    pub cloud_cover_pct: Option<f64>,
    pub precipitation_mm: Option<f64>,
    pub weather_code: Option<i64>,
}

/// Combined ATC + Weather context for /evolve/unified
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AtcWeatherContext {
    pub aircraft: Vec<AtcWorldPatch>,
    pub weather: Vec<WeatherWorldPatch>,
    pub center_lat: f64,
    pub center_lon: f64,
    pub radius_deg: f64,
    pub timestamp: String,
    /// Aggregated 8D state for the local patch
    pub aggregated_d_vec: [f64; 8],
    /// Estimated coherence of the local context
    pub coherence: f64,
    /// Total aircraft in patch
    pub aircraft_count: usize,
    /// Weather stations/points in patch
    pub weather_count: usize,
}

impl SubstrateQuery {
    /// Query ATC patches near a position
    /// Returns aircraft within radius_deg of (lat, lon)
    pub async fn query_atc_near(
        &self,
        lat: f64,
        lon: f64,
        radius_deg: f64,
        max_results: usize,
        max_age_secs: Option<i64>,
    ) -> Result<Vec<AtcWorldPatch>> {
        let age_filter = max_age_secs
            .map(|secs| {
                format!(
                    "FILTER DATE_DIFF(doc.timestamp, DATE_NOW(), 's') < {secs}"
                )
            })
            .unwrap_or_default();

        let aql = format!(
            r#"
            FOR doc IN world_patches
                FILTER doc.context == "planetary:atc_live"
                FILTER ABS(doc.center_lat - @lat) < @radius
                FILTER ABS(doc.center_lon - @lon) < @radius
                {age_filter}
                SORT doc.timestamp DESC
                LIMIT @max_results
                RETURN doc
            "#
        );

        let bind_vars = json!({
            "lat": lat,
            "lon": lon,
            "radius": radius_deg,
            "max_results": max_results as i64
        });

        self.aql_query(&aql, bind_vars).await
    }

    /// Query weather patches near a position
    pub async fn query_weather_near(
        &self,
        lat: f64,
        lon: f64,
        radius_deg: f64,
        max_results: usize,
    ) -> Result<Vec<WeatherWorldPatch>> {
        let aql = r#"
            FOR doc IN world_patches
                FILTER doc.context == "planetary:weather"
                FILTER ABS(doc.center_lat - @lat) < @radius
                FILTER ABS(doc.center_lon - @lon) < @radius
                SORT doc.timestamp DESC
                LIMIT @max_results
                RETURN doc
        "#;

        let bind_vars = json!({
            "lat": lat,
            "lon": lon,
            "radius": radius_deg,
            "max_results": max_results as i64
        });

        self.aql_query(aql, bind_vars).await
    }

    /// Query combined ATC + Weather context for /evolve/unified
    /// This is the main entry point for getting local context to feed into vChip
    pub async fn query_atc_weather_context(
        &self,
        lat: f64,
        lon: f64,
        radius_deg: f64,
        max_aircraft: usize,
        max_weather: usize,
        max_age_secs: Option<i64>,
    ) -> Result<AtcWeatherContext> {
        // Parallel queries for ATC and Weather
        let (aircraft, weather) = tokio::join!(
            self.query_atc_near(lat, lon, radius_deg, max_aircraft, max_age_secs),
            self.query_weather_near(lat, lon, radius_deg, max_weather)
        );

        let aircraft = aircraft.unwrap_or_default();
        let weather = weather.unwrap_or_default();

        // Compute aggregated 8D state
        let aggregated_d_vec = aggregate_atc_weather_8d(&aircraft, &weather);

        // Estimate coherence
        let coherence = estimate_context_coherence(&aircraft, &weather);

        let timestamp = chrono::Utc::now().to_rfc3339();

        Ok(AtcWeatherContext {
            aircraft_count: aircraft.len(),
            weather_count: weather.len(),
            aircraft,
            weather,
            center_lat: lat,
            center_lon: lon,
            radius_deg,
            timestamp,
            aggregated_d_vec,
            coherence,
        })
    }

    /// Get the nearest weather point to a position
    pub async fn get_nearest_weather(
        &self,
        lat: f64,
        lon: f64,
    ) -> Result<Option<WeatherWorldPatch>> {
        let aql = r#"
            FOR doc IN world_patches
                FILTER doc.context == "planetary:weather"
                LET dist = SQRT(
                    POW(doc.center_lat - @lat, 2) + 
                    POW(doc.center_lon - @lon, 2)
                )
                SORT dist ASC
                LIMIT 1
                RETURN doc
        "#;

        let bind_vars = json!({
            "lat": lat,
            "lon": lon
        });

        let results: Vec<WeatherWorldPatch> = self.aql_query(aql, bind_vars).await?;
        Ok(results.into_iter().next())
    }

    /// Get aircraft by ICAO24 identifier
    pub async fn get_aircraft_by_icao(&self, icao24: &str) -> Result<Option<AtcWorldPatch>> {
        let aql = r#"
            FOR doc IN world_patches
                FILTER doc.context == "planetary:atc_live"
                FILTER doc.icao24 == @icao24
                SORT doc.timestamp DESC
                LIMIT 1
                RETURN doc
        "#;

        let bind_vars = json!({
            "icao24": icao24
        });

        let results: Vec<AtcWorldPatch> = self.aql_query(aql, bind_vars).await?;
        Ok(results.into_iter().next())
    }

    /// Get aircraft count by region (for heatmap visualization)
    pub async fn get_aircraft_density(&self, grid_size_deg: f64) -> Result<Vec<(f64, f64, usize)>> {
        let aql = r#"
            FOR doc IN world_patches
                FILTER doc.context == "planetary:atc_live"
                FILTER DATE_DIFF(doc.timestamp, DATE_NOW(), 's') < 60
                LET lat_bucket = FLOOR(doc.center_lat / @grid_size) * @grid_size
                LET lon_bucket = FLOOR(doc.center_lon / @grid_size) * @grid_size
                COLLECT lat = lat_bucket, lon = lon_bucket WITH COUNT INTO count
                RETURN { lat, lon, count }
        "#;

        let bind_vars = json!({
            "grid_size": grid_size_deg
        });

        #[derive(Deserialize)]
        struct DensityRow {
            lat: f64,
            lon: f64,
            count: usize,
        }

        let results: Vec<DensityRow> = self.aql_query(aql, bind_vars).await?;
        Ok(results
            .into_iter()
            .map(|r| (r.lat, r.lon, r.count))
            .collect())
    }

    /// Cleanup old ATC patches (older than max_age_secs)
    pub async fn cleanup_old_atc_patches(&self, max_age_secs: i64) -> Result<usize> {
        let aql = r#"
            FOR doc IN world_patches
                FILTER doc.context == "planetary:atc_live"
                FILTER DATE_DIFF(doc.timestamp, DATE_NOW(), 's') > @max_age
                REMOVE doc IN world_patches
                RETURN OLD
        "#;

        let bind_vars = json!({
            "max_age": max_age_secs
        });

        let results: Vec<Value> = self.aql_query(aql, bind_vars).await?;
        Ok(results.len())
    }

    /// Query any collection by name (for Franklin's knowledge access)
    pub async fn query_collection(&self, collection: &str, limit: usize) -> Result<Vec<Value>> {
        let aql = format!(
            r#"
            FOR doc IN {}
                SORT doc._key DESC
                LIMIT @limit
                RETURN doc
            "#,
            collection
        );

        let bind_vars = json!({"limit": limit as i64});
        self.aql_query(&aql, bind_vars).await
    }

    /// Count documents in any collection
    pub async fn count_collection(&self, collection: &str) -> Result<usize> {
        let aql = format!(
            r#"
            RETURN LENGTH({})
            "#,
            collection
        );

        let results: Vec<usize> = self.aql_query(&aql, json!({})).await?;
        Ok(results.first().copied().unwrap_or(0))
    }
}

/// Aggregate 8D vectors from ATC and Weather data
/// Produces a single 8D vector representing the local context
fn aggregate_atc_weather_8d(aircraft: &[AtcWorldPatch], weather: &[WeatherWorldPatch]) -> [f64; 8] {
    let mut result = [0.0f64; 8];

    if aircraft.is_empty() && weather.is_empty() {
        return result;
    }

    // Aggregate ATC vectors (use fused if available, else raw d_vec)
    let mut atc_sum = [0.0f64; 8];
    let mut atc_count = 0;

    for ac in aircraft {
        let vec = ac.fused_d_vec.as_ref().unwrap_or(&ac.d_vec);
        for i in 0..8 {
            atc_sum[i] += vec[i];
        }
        atc_count += 1;
    }

    // Aggregate weather vectors
    let mut weather_sum = [0.0f64; 8];
    let mut weather_count = 0;

    for w in weather {
        for i in 0..8 {
            weather_sum[i] += w.d_vec[i];
        }
        weather_count += 1;
    }

    // Combine: ATC weighted 0.7, Weather weighted 0.3
    let atc_weight = 0.7;
    let weather_weight = 0.3;

    for i in 0..8 {
        let atc_avg = if atc_count > 0 {
            atc_sum[i] / atc_count as f64
        } else {
            0.0
        };

        let weather_avg = if weather_count > 0 {
            weather_sum[i] / weather_count as f64
        } else {
            0.0
        };

        if atc_count > 0 && weather_count > 0 {
            result[i] = atc_avg * atc_weight + weather_avg * weather_weight;
        } else if atc_count > 0 {
            result[i] = atc_avg;
        } else {
            result[i] = weather_avg;
        }
    }

    result
}

/// Estimate coherence of the local context
fn estimate_context_coherence(aircraft: &[AtcWorldPatch], weather: &[WeatherWorldPatch]) -> f64 {
    if aircraft.is_empty() && weather.is_empty() {
        return 0.5; // Unknown
    }

    let mut coherence = 0.5;

    // Factor 1: Aircraft uncertainty (lower = more coherent)
    if !aircraft.is_empty() {
        let avg_uncertainty: f64 =
            aircraft.iter().filter_map(|a| a.uncertainty).sum::<f64>() / aircraft.len() as f64;
        coherence += 0.2 * (1.0 - avg_uncertainty.min(1.0));
    }

    // Factor 2: Weather visibility (higher = more coherent)
    if !weather.is_empty() {
        let avg_visibility: f64 = weather
            .iter()
            .filter_map(|w| w.visibility_m)
            .map(|v| (v / 10000.0).min(1.0))
            .sum::<f64>()
            / weather.len().max(1) as f64;
        coherence += 0.15 * avg_visibility;
    }

    // Factor 3: Data freshness (more aircraft = more coherent picture)
    if aircraft.len() >= 5 {
        coherence += 0.15;
    } else if aircraft.len() >= 2 {
        coherence += 0.08;
    }

    coherence.clamp(0.0, 1.0)
}

// Base64 encoding helper
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
