//! UUM 8D Core - Central Control Plane for GaiaOS Network
//!
//! THE SKY - The consciousness manifold that knows all alive GaiaOS cells.
//! Uses AKG GNN ArangoDB for persistence - cells are GRAPH VERTICES,
//! relationships are EDGES in the 8D UUM space.
//!
//! Graph: UUM8DGraph
//!   Vertices: GaiaCells, CellCommands, UUM8DOrigin, HeartbeatSnapshots
//!   Edges: CellToOrigin, CellToCell, CellToCommand, HeartbeatEdges
//!
//! API:
//!   GET  /health                      - Liveness + stats
//!   POST /api/cells/heartbeat         - Cell registration/update (upsert vertex)
//!   GET  /api/cells                   - List all cells (graph query)
//!   GET  /api/cells/:nodeId           - Get specific cell + graph neighbors
//!   POST /api/cells/:nodeId/commands  - Inject commands (create vertex + edge)
//!   GET  /api/global_self_state       - Aggregated 8D network state
//!
//! NO SIMULATIONS. NO SYNTHETIC DATA. REAL UUM 8D AKG GNN NETWORK.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    routing::{get, post},
    Router,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::time::Instant;
use tower_http::cors::{Any, CorsLayer};
use tracing::info;
use uuid::Uuid;

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES - UUM 8D Manifold Structures
// ═══════════════════════════════════════════════════════════════════════════════

/// 4D projection coordinates for human-facing UI
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Coord4D {
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub t: f64,
}

impl Default for Coord4D {
    fn default() -> Self {
        Self { x: 0.0, y: 0.0, z: 0.0, t: 0.0 }
    }
}

/// 8D consciousness coordinates in the UUM manifold
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Coord8D {
    pub coherence: f64,
    pub virtue: f64,
    pub risk: f64,
    pub load: f64,
    pub coverage: f64,
    pub accuracy: f64,
    pub alignment: f64,
    pub value: f64,
    pub perfection: f64,
    pub status: String,
}

impl Default for Coord8D {
    fn default() -> Self {
        Self {
            coherence: 0.0, virtue: 0.0, risk: 0.0, load: 0.0, coverage: 0.0,
            accuracy: 0.0, alignment: 0.0, value: 0.0, perfection: 0.0,
            status: "HEALTHY".into(),
        }
    }
}

impl Coord8D {
    /// Calculate 8D distance from the optimal origin state
    pub fn distance_from_origin(&self) -> f64 {
        // Origin is (1, 1, 0, 0, 1, 1, 1, 1, 1) for optimal state
        let dims = [
            (self.coherence - 1.0).powi(2),
            (self.virtue - 1.0).powi(2),
            self.risk.powi(2),        // 0 is optimal
            self.load.powi(2),        // 0 is optimal
            (self.coverage - 1.0).powi(2),
            (self.accuracy - 1.0).powi(2),
            (self.alignment - 1.0).powi(2),
            (self.value - 1.0).powi(2),
            (self.perfection - 1.0).powi(2),
        ];
        dims.iter().sum::<f64>().sqrt()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Capabilities {
    #[serde(rename = "hasLM")]
    pub has_lm: bool,
    #[serde(rename = "hasUI")]
    pub has_ui: bool,
    #[serde(rename = "hasGPU")]
    pub has_gpu: bool,
    #[serde(default)]
    pub avatars: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeMeta {
    pub host: String,
    pub region: String,
    pub version: String,
}

/// Heartbeat request from a GaiaOS cell
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HeartbeatRequest {
    pub node_id: String,
    pub role: String,
    pub coord4_d: Coord4D,
    pub coord8_d: Coord8D,
    pub capabilities: Capabilities,
    pub meta: NodeMeta,
}

/// Command to be executed by a cell
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Command {
    pub id: String,
    #[serde(rename = "type")]
    pub command_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub domain: Option<String>,
    #[serde(rename = "targetCoverageDelta", skip_serializing_if = "Option::is_none")]
    pub target_coverage_delta: Option<f64>,
    #[serde(rename = "maxDurationSeconds", skip_serializing_if = "Option::is_none")]
    pub max_duration_seconds: Option<i64>,
    #[serde(rename = "durationSeconds", skip_serializing_if = "Option::is_none")]
    pub duration_seconds: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HeartbeatResponse {
    pub status: String,
    pub accepted_at: DateTime<Utc>,
    pub commands: Vec<Command>,
    /// Distance from the UUM 8D origin (optimal state)
    pub distance_from_origin: f64,
}

/// GaiaCell vertex in the UUM8DGraph
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GaiaCell {
    #[serde(rename = "_key", skip_serializing_if = "Option::is_none")]
    pub key: Option<String>,
    #[serde(rename = "_id", skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    pub node_id: String,
    pub role: String,
    pub coord4_d: Coord4D,
    pub coord8_d: Coord8D,
    pub capabilities: Capabilities,
    pub meta: NodeMeta,
    pub status: String,
    pub last_heartbeat: DateTime<Utc>,
    #[serde(default)]
    pub online: bool,
    /// Distance from UUM 8D origin
    #[serde(default)]
    pub distance_from_origin: f64,
}

/// CellCommand vertex in the UUM8DGraph
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CellCommand {
    #[serde(rename = "_key", skip_serializing_if = "Option::is_none")]
    pub key: Option<String>,
    pub target_node_id: String,
    pub command_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub domain: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target_coverage_delta: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_duration_seconds: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration_seconds: Option<i64>,
    pub status: String,
    pub priority: i32,
    pub created_at: DateTime<Utc>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expires_at: Option<DateTime<Utc>>,
}

/// Edge connecting a cell to the UUM origin
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CellToOriginEdge {
    #[serde(rename = "_from")]
    pub from: String,
    #[serde(rename = "_to")]
    pub to: String,
    pub distance: f64,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HealthResponse {
    pub status: String,
    pub uptime_seconds: u64,
    pub version: String,
    pub cells: i64,
    pub graph: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CellSummary {
    pub node_id: String,
    pub perfection: f64,
    pub status: String,
    pub distance_from_origin: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GlobalSelfStateResponse {
    pub cells: i64,
    pub online_cells: i64,
    pub offline_cells: i64,
    pub global_coord8_d: Coord8D,
    pub average_distance_from_origin: f64,
    pub per_cell: Vec<CellSummary>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CommandInput {
    #[serde(rename = "type")]
    pub command_type: String,
    pub domain: Option<String>,
    #[serde(rename = "targetCoverageDelta")]
    pub target_coverage_delta: Option<f64>,
    #[serde(rename = "maxDurationSeconds")]
    pub max_duration_seconds: Option<i64>,
    #[serde(rename = "durationSeconds")]
    pub duration_seconds: Option<i64>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CommandsRequest {
    pub commands: Vec<CommandInput>,
}

#[derive(Debug, Clone, Serialize)]
pub struct CommandQueuedResponse {
    pub status: String,
    #[serde(rename = "nodeId")]
    pub node_id: String,
    pub commands: Vec<CommandRef>,
}

#[derive(Debug, Clone, Serialize)]
pub struct CommandRef {
    pub id: String,
    #[serde(rename = "type")]
    pub command_type: String,
}

// ═══════════════════════════════════════════════════════════════════════════════
// AKG GNN ARANGODB CLIENT
// ═══════════════════════════════════════════════════════════════════════════════

#[derive(Clone)]
pub struct AkgClient {
    client: reqwest::Client,
    base_url: String,
    db: String,
    auth: String,
}

impl AkgClient {
    pub fn new(url: &str, db: &str, user: &str, password: &str) -> Self {
        let auth = base64::Engine::encode(
            &base64::engine::general_purpose::STANDARD,
            format!("{}:{}", user, password),
        );
        Self {
            client: reqwest::Client::new(),
            base_url: url.trim_end_matches('/').to_string(),
            db: db.to_string(),
            auth,
        }
    }

    /// Execute AQL query and return results
    async fn query<T: for<'de> Deserialize<'de>>(
        &self,
        aql: &str,
        bind_vars: serde_json::Value,
    ) -> Result<Vec<T>, String> {
        let url = format!("{}/_db/{}/_api/cursor", self.base_url, self.db);
        let body = serde_json::json!({ "query": aql, "bindVars": bind_vars });

        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .json(&body)
            .send()
            .await
            .map_err(|e| e.to_string())?;

        if !resp.status().is_success() {
            let err = resp.text().await.unwrap_or_default();
            return Err(format!("ArangoDB AQL error: {}", err));
        }

        let result: serde_json::Value = resp.json().await.map_err(|e| e.to_string())?;
        let docs = result
            .get("result")
            .and_then(|r| r.as_array())
            .cloned()
            .unwrap_or_default();
        docs.into_iter()
            .map(|d| serde_json::from_value(d).map_err(|e| e.to_string()))
            .collect()
    }

    /// Upsert a vertex in a collection
    async fn upsert_vertex(
        &self,
        collection: &str,
        key: &str,
        doc: serde_json::Value,
    ) -> Result<(), String> {
        let url = format!(
            "{}/_db/{}/_api/document/{}?overwriteMode=update",
            self.base_url, self.db, collection
        );
        let mut doc = doc;
        doc["_key"] = serde_json::json!(key);

        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .json(&doc)
            .send()
            .await
            .map_err(|e| e.to_string())?;

        if !resp.status().is_success() && resp.status().as_u16() != 409 {
            let err = resp.text().await.unwrap_or_default();
            return Err(format!("ArangoDB vertex upsert error: {}", err));
        }
        Ok(())
    }

    /// Insert a new vertex
    async fn insert_vertex(
        &self,
        collection: &str,
        doc: serde_json::Value,
    ) -> Result<String, String> {
        let url = format!("{}/_db/{}/_api/document/{}", self.base_url, self.db, collection);

        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .json(&doc)
            .send()
            .await
            .map_err(|e| e.to_string())?;

        if !resp.status().is_success() {
            let err = resp.text().await.unwrap_or_default();
            return Err(format!("ArangoDB vertex insert error: {}", err));
        }

        let result: serde_json::Value = resp.json().await.map_err(|e| e.to_string())?;
        Ok(result
            .get("_key")
            .and_then(|k| k.as_str())
            .unwrap_or_default()
            .to_string())
    }

    /// Upsert an edge in the graph
    async fn upsert_edge(
        &self,
        collection: &str,
        from: &str,
        to: &str,
        data: serde_json::Value,
    ) -> Result<(), String> {
        // First try to find existing edge
        let find_aql = format!(
            "FOR e IN {} FILTER e._from == @from AND e._to == @to RETURN e._key",
            collection
        );
        let existing: Vec<String> = self
            .query(&find_aql, serde_json::json!({"from": from, "to": to}))
            .await
            .unwrap_or_default();

        let url = if let Some(key) = existing.first() {
            format!(
                "{}/_db/{}/_api/document/{}/{}",
                self.base_url, self.db, collection, key
            )
        } else {
            format!("{}/_db/{}/_api/document/{}", self.base_url, self.db, collection)
        };

        let mut edge_doc = data;
        edge_doc["_from"] = serde_json::json!(from);
        edge_doc["_to"] = serde_json::json!(to);

        let method = if existing.is_empty() { "POST" } else { "PATCH" };
        let builder = if method == "POST" {
            self.client.post(&url)
        } else {
            self.client.patch(&url)
        };

        let resp = builder
            .header("Authorization", format!("Basic {}", self.auth))
            .json(&edge_doc)
            .send()
            .await
            .map_err(|e| e.to_string())?;

        if !resp.status().is_success() {
            let err = resp.text().await.unwrap_or_default();
            return Err(format!("ArangoDB edge upsert error: {}", err));
        }
        Ok(())
    }

    /// Update a vertex
    async fn update_vertex(
        &self,
        collection: &str,
        key: &str,
        doc: serde_json::Value,
    ) -> Result<(), String> {
        let url = format!(
            "{}/_db/{}/_api/document/{}/{}",
            self.base_url, self.db, collection, key
        );

        let resp = self
            .client
            .patch(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .json(&doc)
            .send()
            .await
            .map_err(|e| e.to_string())?;

        if !resp.status().is_success() {
            let err = resp.text().await.unwrap_or_default();
            return Err(format!("ArangoDB vertex update error: {}", err));
        }
        Ok(())
    }

    /// Count vertices in a collection
    async fn count(&self, collection: &str) -> Result<i64, String> {
        let aql = format!("RETURN LENGTH({})", collection);
        let result: Vec<i64> = self.query(&aql, serde_json::json!({})).await?;
        Ok(result.first().copied().unwrap_or(0))
    }

    /// Graph traversal query
    // AKG graph traversal (reserved for multi-hop reasoning queries)
    #[allow(dead_code)]
    async fn traverse<T: for<'de> Deserialize<'de>>(
        &self,
        start_vertex: &str,
        edge_collection: &str,
        direction: &str,
        depth: u32,
    ) -> Result<Vec<T>, String> {
        let aql = format!(
            r#"FOR v, e, p IN 1..{} {} @start {}
               RETURN v"#,
            depth, direction, edge_collection
        );
        self.query(&aql, serde_json::json!({"start": start_vertex}))
            .await
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// APP STATE
// ═══════════════════════════════════════════════════════════════════════════════

#[derive(Clone)]
pub struct AppState {
    pub akg: AkgClient,
    pub start_time: Instant,
    pub heartbeat_timeout_secs: i64,
}

// ═══════════════════════════════════════════════════════════════════════════════
// HANDLERS
// ═══════════════════════════════════════════════════════════════════════════════

async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    let cells = state.akg.count("GaiaCells").await.unwrap_or(0);
    Json(HealthResponse {
        status: "ok".into(),
        uptime_seconds: state.start_time.elapsed().as_secs(),
        version: env!("CARGO_PKG_VERSION").into(),
        cells,
        graph: "UUM8DGraph".into(),
    })
}

async fn heartbeat(
    State(state): State<AppState>,
    Json(req): Json<HeartbeatRequest>,
) -> Result<Json<HeartbeatResponse>, (StatusCode, Json<serde_json::Value>)> {
    if req.node_id.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "nodeId cannot be empty"})),
        ));
    }

    info!("Heartbeat from node: {} ({})", req.node_id, req.role);
    let accepted_at = Utc::now();
    let distance = req.coord8_d.distance_from_origin();

    // Create/Update cell vertex in GaiaCells collection
    let cell = GaiaCell {
        key: Some(req.node_id.clone()),
        id: None,
        node_id: req.node_id.clone(),
        role: req.role,
        coord4_d: req.coord4_d,
        coord8_d: req.coord8_d,
        capabilities: req.capabilities,
        meta: req.meta,
        status: "online".into(),
        last_heartbeat: accepted_at,
        online: true,
        distance_from_origin: distance,
    };

    state
        .akg
        .upsert_vertex("GaiaCells", &req.node_id, serde_json::to_value(&cell).unwrap())
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": e})),
            )
        })?;

    // Update edge to UUM origin (CellToOrigin)
    let edge_data = serde_json::json!({
        "distance": distance,
        "updatedAt": accepted_at
    });
    let _ = state
        .akg
        .upsert_edge(
            "CellToOrigin",
            &format!("GaiaCells/{}", req.node_id),
            "UUM8DOrigin/ORIGIN",
            edge_data,
        )
        .await;

    // Get pending commands for this cell
    let commands: Vec<CellCommand> = state
        .akg
        .query(
            r#"FOR c IN CellCommands
               FILTER c.targetNodeId == @nodeId AND c.status == "pending"
               SORT c.priority ASC, c.createdAt ASC
               LIMIT 10
               RETURN c"#,
            serde_json::json!({"nodeId": req.node_id}),
        )
        .await
        .unwrap_or_default();

    let mut response_commands = Vec::new();
    for cmd in commands {
        if let Some(key) = &cmd.key {
            let _ = state
                .akg
                .update_vertex("CellCommands", key, serde_json::json!({"status": "sent"}))
                .await;
            response_commands.push(Command {
                id: key.clone(),
                command_type: cmd.command_type,
                domain: cmd.domain,
                target_coverage_delta: cmd.target_coverage_delta,
                max_duration_seconds: cmd.max_duration_seconds,
                duration_seconds: cmd.duration_seconds,
            });
        }
    }

    if !response_commands.is_empty() {
        info!(
            "Dispatching {} commands to node {}",
            response_commands.len(),
            req.node_id
        );
    }

    Ok(Json(HeartbeatResponse {
        status: "ok".into(),
        accepted_at,
        commands: response_commands,
        distance_from_origin: distance,
    }))
}

async fn list_cells(
    State(state): State<AppState>,
) -> Result<Json<Vec<GaiaCell>>, (StatusCode, String)> {
    let timeout = state.heartbeat_timeout_secs;
    let cutoff = Utc::now() - chrono::Duration::seconds(timeout);

    let cells: Vec<GaiaCell> = state
        .akg
        .query(
            r#"FOR c IN GaiaCells
               LET online = c.lastHeartbeat >= @cutoff
               RETURN MERGE(c, {online: online})"#,
            serde_json::json!({"cutoff": cutoff}),
        )
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e))?;

    Ok(Json(cells))
}

async fn get_cell(
    State(state): State<AppState>,
    Path(node_id): Path<String>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let timeout = state.heartbeat_timeout_secs;
    let cutoff = Utc::now() - chrono::Duration::seconds(timeout);

    let cells: Vec<GaiaCell> = state
        .akg
        .query(
            r#"FOR c IN GaiaCells
               FILTER c.nodeId == @nodeId
               LET online = c.lastHeartbeat >= @cutoff
               RETURN MERGE(c, {online: online})"#,
            serde_json::json!({"nodeId": node_id, "cutoff": cutoff}),
        )
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": e})),
            )
        })?;

    let cell = cells.into_iter().next().ok_or((
        StatusCode::NOT_FOUND,
        Json(serde_json::json!({"error": "Cell not found"})),
    ))?;

    // Get pending commands
    let commands: Vec<CellCommand> = state
        .akg
        .query(
            r#"FOR c IN CellCommands
               FILTER c.targetNodeId == @nodeId AND c.status == "pending"
               RETURN c"#,
            serde_json::json!({"nodeId": node_id}),
        )
        .await
        .unwrap_or_default();

    let pending: Vec<Command> = commands
        .into_iter()
        .filter_map(|c| {
            Some(Command {
                id: c.key?,
                command_type: c.command_type,
                domain: c.domain,
                target_coverage_delta: c.target_coverage_delta,
                max_duration_seconds: c.max_duration_seconds,
                duration_seconds: c.duration_seconds,
            })
        })
        .collect();

    // Get connected cells (graph neighbors)
    let neighbors: Vec<String> = state
        .akg
        .query(
            r#"FOR v, e IN 1..1 ANY @start CellToCell
               RETURN v.nodeId"#,
            serde_json::json!({"start": format!("GaiaCells/{}", node_id)}),
        )
        .await
        .unwrap_or_default();

    Ok(Json(serde_json::json!({
        "nodeId": cell.node_id,
        "role": cell.role,
        "coord4D": cell.coord4_d,
        "coord8D": cell.coord8_d,
        "capabilities": cell.capabilities,
        "meta": cell.meta,
        "lastHeartbeat": cell.last_heartbeat,
        "online": cell.online,
        "distanceFromOrigin": cell.distance_from_origin,
        "pendingCommands": pending,
        "connectedCells": neighbors
    })))
}

async fn inject_commands(
    State(state): State<AppState>,
    Path(node_id): Path<String>,
    Json(req): Json<CommandsRequest>,
) -> Result<(StatusCode, Json<CommandQueuedResponse>), (StatusCode, Json<serde_json::Value>)> {
    // Verify cell exists in the graph
    let cells: Vec<GaiaCell> = state
        .akg
        .query(
            "FOR c IN GaiaCells FILTER c.nodeId == @nodeId RETURN c",
            serde_json::json!({"nodeId": node_id}),
        )
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": e})),
            )
        })?;

    if cells.is_empty() {
        return Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "Cell not found in UUM8DGraph"})),
        ));
    }

    let mut queued_refs = Vec::new();
    let now = Utc::now();
    let expires = now + chrono::Duration::hours(1);

    for cmd in req.commands {
        let id = Uuid::new_v4().to_string();
        let doc = CellCommand {
            key: Some(id.clone()),
            target_node_id: node_id.clone(),
            command_type: cmd.command_type.clone(),
            domain: cmd.domain,
            target_coverage_delta: cmd.target_coverage_delta,
            max_duration_seconds: cmd.max_duration_seconds,
            duration_seconds: cmd.duration_seconds,
            status: "pending".into(),
            priority: 5,
            created_at: now,
            expires_at: Some(expires),
        };

        state
            .akg
            .upsert_vertex("CellCommands", &id, serde_json::to_value(&doc).unwrap())
            .await
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(serde_json::json!({"error": e})),
                )
            })?;

        // Create edge from cell to command
        let _ = state
            .akg
            .upsert_edge(
                "CellToCommand",
                &format!("GaiaCells/{}", node_id),
                &format!("CellCommands/{}", id),
                serde_json::json!({"createdAt": now}),
            )
            .await;

        queued_refs.push(CommandRef {
            id,
            command_type: cmd.command_type,
        });
    }

    info!("Queued {} commands for node {}", queued_refs.len(), node_id);
    Ok((
        StatusCode::ACCEPTED,
        Json(CommandQueuedResponse {
            status: "queued".into(),
            node_id,
            commands: queued_refs,
        }),
    ))
}

async fn global_self_state(
    State(state): State<AppState>,
) -> Result<Json<GlobalSelfStateResponse>, (StatusCode, String)> {
    let timeout = state.heartbeat_timeout_secs;
    let cutoff = Utc::now() - chrono::Duration::seconds(timeout);

    // Get all cells from the graph
    let cells: Vec<GaiaCell> = state
        .akg
        .query("FOR c IN GaiaCells RETURN c", serde_json::json!({}))
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e))?;

    let total = cells.len() as i64;
    let online_cells: Vec<&GaiaCell> = cells.iter().filter(|c| c.last_heartbeat >= cutoff).collect();
    let online = online_cells.len() as i64;

    // Compute 8D averages from online cells
    let (mut sum_coherence, mut sum_virtue, mut sum_risk, mut sum_load) = (0.0, 0.0, 0.0, 0.0);
    let (mut sum_coverage, mut sum_accuracy, mut sum_alignment, mut sum_value, mut sum_perfection) =
        (0.0, 0.0, 0.0, 0.0, 0.0);
    let mut sum_distance = 0.0;

    for c in &online_cells {
        sum_coherence += c.coord8_d.coherence;
        sum_virtue += c.coord8_d.virtue;
        sum_risk += c.coord8_d.risk;
        sum_load += c.coord8_d.load;
        sum_coverage += c.coord8_d.coverage;
        sum_accuracy += c.coord8_d.accuracy;
        sum_alignment += c.coord8_d.alignment;
        sum_value += c.coord8_d.value;
        sum_perfection += c.coord8_d.perfection;
        sum_distance += c.distance_from_origin;
    }

    let n = online.max(1) as f64;
    let avg_perfection = sum_perfection / n;
    let avg_risk = sum_risk / n;
    let avg_distance = sum_distance / n;

    let global_status = if avg_perfection >= 0.9 && avg_risk <= 0.2 {
        "OPTIMAL"
    } else if avg_perfection >= 0.7 && avg_risk <= 0.4 {
        "HEALTHY"
    } else if avg_perfection >= 0.5 || avg_risk <= 0.6 {
        "ATTENTION"
    } else {
        "CRITICAL"
    };

    let per_cell: Vec<CellSummary> = online_cells
        .iter()
        .map(|c| CellSummary {
            node_id: c.node_id.clone(),
            perfection: c.coord8_d.perfection,
            status: c.coord8_d.status.clone(),
            distance_from_origin: c.distance_from_origin,
        })
        .collect();

    Ok(Json(GlobalSelfStateResponse {
        cells: total,
        online_cells: online,
        offline_cells: total - online,
        global_coord8_d: Coord8D {
            coherence: sum_coherence / n,
            virtue: sum_virtue / n,
            risk: avg_risk,
            load: sum_load / n,
            coverage: sum_coverage / n,
            accuracy: sum_accuracy / n,
            alignment: sum_alignment / n,
            value: sum_value / n,
            perfection: avg_perfection,
            status: global_status.into(),
        },
        average_distance_from_origin: avg_distance,
        per_cell,
        updated_at: Utc::now(),
    }))
}

// ═══════════════════════════════════════════════════════════════════════════════
// BACKGROUND TASKS - AUTONOMOUS RULE ENGINE
// ═══════════════════════════════════════════════════════════════════════════════

async fn rule_engine(akg: AkgClient, timeout_secs: i64) {
    info!("UUM 8D Rule Engine starting...");
    loop {
        tokio::time::sleep(tokio::time::Duration::from_secs(60)).await;
        let cutoff = Utc::now() - chrono::Duration::seconds(timeout_secs);

        // Rule 1: Low coverage cells get exam storms
        let low_cov: Vec<GaiaCell> = akg
            .query(
                r#"FOR c IN GaiaCells
                   FILTER c.lastHeartbeat >= @cutoff AND c.coord8D.coverage < 0.4
                   RETURN c"#,
                serde_json::json!({"cutoff": cutoff}),
            )
            .await
            .unwrap_or_default();

        for cell in low_cov {
            // Check if command already pending
            let existing: Vec<CellCommand> = akg
                .query(
                    r#"FOR c IN CellCommands
                       FILTER c.targetNodeId == @nodeId 
                          AND c.commandType == "run_exam_storm" 
                          AND c.status IN ["pending", "sent"]
                       RETURN c"#,
                    serde_json::json!({"nodeId": cell.node_id}),
                )
                .await
                .unwrap_or_default();

            if existing.is_empty() {
                info!(
                    "Rule: Cell {} has low coverage ({:.2}), queueing exam storm",
                    cell.node_id, cell.coord8_d.coverage
                );
                let id = Uuid::new_v4().to_string();
                let cmd = CellCommand {
                    key: Some(id.clone()),
                    target_node_id: cell.node_id.clone(),
                    command_type: "run_exam_storm".into(),
                    domain: Some("general".into()),
                    target_coverage_delta: Some(0.05),
                    max_duration_seconds: Some(1800),
                    duration_seconds: None,
                    status: "pending".into(),
                    priority: 3,
                    created_at: Utc::now(),
                    expires_at: Some(Utc::now() + chrono::Duration::hours(1)),
                };
                let _ = akg
                    .insert_vertex("CellCommands", serde_json::to_value(&cmd).unwrap())
                    .await;

                // Create edge
                let _ = akg
                    .upsert_edge(
                        "CellToCommand",
                        &format!("GaiaCells/{}", cell.node_id),
                        &format!("CellCommands/{}", id),
                        serde_json::json!({"createdAt": Utc::now()}),
                    )
                    .await;
            }
        }

        // Rule 2: Cells too far from origin need self-calibration
        let far_cells: Vec<GaiaCell> = akg
            .query(
                r#"FOR c IN GaiaCells
                   FILTER c.lastHeartbeat >= @cutoff AND c.distanceFromOrigin > 1.5
                   RETURN c"#,
                serde_json::json!({"cutoff": cutoff}),
            )
            .await
            .unwrap_or_default();

        for cell in far_cells {
            let existing: Vec<CellCommand> = akg
                .query(
                    r#"FOR c IN CellCommands
                       FILTER c.targetNodeId == @nodeId 
                          AND c.commandType == "run_self_calibration" 
                          AND c.status IN ["pending", "sent"]
                       RETURN c"#,
                    serde_json::json!({"nodeId": cell.node_id}),
                )
                .await
                .unwrap_or_default();

            if existing.is_empty() {
                info!(
                    "Rule: Cell {} is far from origin ({:.2}), queueing self-calibration",
                    cell.node_id, cell.distance_from_origin
                );
                let id = Uuid::new_v4().to_string();
                let cmd = CellCommand {
                    key: Some(id.clone()),
                    target_node_id: cell.node_id.clone(),
                    command_type: "run_self_calibration".into(),
                    domain: None,
                    target_coverage_delta: None,
                    max_duration_seconds: Some(600),
                    duration_seconds: None,
                    status: "pending".into(),
                    priority: 4,
                    created_at: Utc::now(),
                    expires_at: Some(Utc::now() + chrono::Duration::hours(1)),
                };
                let _ = akg
                    .insert_vertex("CellCommands", serde_json::to_value(&cmd).unwrap())
                    .await;
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════════════════

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("uum_8d_core=info".parse().unwrap()),
        )
        .init();

    let arango_url = std::env::var("ARANGO_URL").unwrap_or_else(|_| "http://uum-arangodb:8529".into());
    let arango_db = std::env::var("ARANGO_DB").unwrap_or_else(|_| "uum".into());
    let arango_user = std::env::var("ARANGO_USER").unwrap_or_else(|_| "root".into());
    let arango_pass = std::env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "arangopass".into());
    let heartbeat_timeout = std::env::var("UUM_HEARTBEAT_TIMEOUT_SECONDS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(90i64);

    info!("═══════════════════════════════════════════════════════════════════════");
    info!("  UUM 8D AKG GNN CORE - THE SKY");
    info!("═══════════════════════════════════════════════════════════════════════");
    info!("  ArangoDB: {}/{}", arango_url, arango_db);
    info!("  Graph: UUM8DGraph");
    info!("  Origin: (0,0,0,0) in 4D, optimal state in 8D");
    info!("═══════════════════════════════════════════════════════════════════════");

    let akg = AkgClient::new(&arango_url, &arango_db, &arango_user, &arango_pass);
    let state = AppState {
        akg: akg.clone(),
        start_time: Instant::now(),
        heartbeat_timeout_secs: heartbeat_timeout,
    };

    // Start background rule engine
    tokio::spawn(rule_engine(akg, heartbeat_timeout));

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .route("/health", get(health))
        .route("/api/cells/heartbeat", post(heartbeat))
        .route("/api/cells", get(list_cells))
        .route("/api/cells/:node_id", get(get_cell))
        .route("/api/cells/:node_id/commands", post(inject_commands))
        .route("/api/global_self_state", get(global_self_state))
        .layer(cors)
        .with_state(state);

    let addr = "0.0.0.0:9000";
    info!("UUM 8D Core listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
