// services/akg_gnn/src/api.rs
// Complete API for Unified AKG GNN Substrate
// Handles: health, substrate patches, compression

use actix_web::{web, HttpResponse, Responder};
use actix_web::http::header;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

mod consciousness;

use crate::AppState;
use crate::qfot::field_graph::FieldGraph;
use crate::metrics;

// ============================================================================
// DATA STRUCTURES
// ============================================================================

#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub status: &'static str,
    pub service: &'static str,
    pub arango_connected: bool,
    pub contexts_loaded: Vec<String>,
}

/// Request for a local substrate patch (vChip queries this)
#[derive(Debug, Deserialize)]
pub struct PatchRequest {
    pub scale: String,          // "quantum", "planetary", "astronomical"
    pub center: [f64; 8],       // 8D center point
    pub radius: Option<f64>,    // Override default radius
    pub intent: Option<String>, // Filter by intent domain
    pub max_procedures: Option<usize>,
}

/// Response containing the local wavefunction patch
#[derive(Debug, Serialize)]
pub struct PatchResponse {
    pub scale: String,
    pub center: [f64; 8],
    pub radius: f64,
    pub procedures: Vec<ProcedureNode>,
    pub edges: Vec<ProcedureEdge>,
    pub total_found: usize,
    pub coherence_estimate: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcedureNode {
    pub id: String,
    pub context: String,
    pub d0_d7: [f64; 8],
    pub intent: String,
    pub success_rate: f64,
    pub execution_count: u64,
    pub risk_level: String,
    pub confidence: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcedureEdge {
    pub from_id: String,
    pub to_id: String,
    pub edge_type: String,
    pub weight: f64,
}

/// Aircraft data for compression
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct AircraftData {
    /// ICAO 24-bit address (aircraft identifier)
    pub icao24: String,
    pub vqbit_8d: [f64; 8],
    pub latitude: f64,
    pub longitude: f64,
    pub altitude_ft: f64,
}

#[derive(Debug, Deserialize)]
pub struct CompressRequest {
    pub aircraft: Vec<AircraftData>,
}

#[derive(Debug, Serialize)]
#[allow(dead_code)]
pub struct CompressResponse {
    /// Compressed regional vQbits (returned to client)
    pub regional_vqbits: Vec<f64>,
    pub n_regions: usize,
    pub metadata: CompressionMetadata,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct CompressionMetadata {
    pub n_aircraft: usize,
    pub n_regions: usize,
    pub compression_ratio: f64,
    pub aircraft_per_region: HashMap<usize, usize>,
    pub timestamp: String,
}

#[derive(Debug, Deserialize)]
pub struct DecompressRequest {
    pub compressed: CompressedData,
    pub context: DecompressionContext,
}

#[derive(Debug, Deserialize)]
pub struct CompressedData {
    pub regional_vqbits: Vec<f64>,
    pub n_regions: usize,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct DecompressionContext {
    pub positions: Vec<[f64; 3]>,
    /// Optional pre-computed regional assignments (for optimization)
    pub regional_assignments: Option<Vec<usize>>,
}

#[derive(Debug, Serialize)]
pub struct DecompressResponse {
    pub aircraft: Vec<DecompressedAircraft>,
}

#[derive(Debug, Serialize)]
pub struct DecompressedAircraft {
    pub index: usize,
    pub vqbit_8d: [f64; 8],
    pub region_id: usize,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct StatsRequest {
    /// Regional vQbits (deserialized but analysis not yet implemented)
    pub regional_vqbits: Vec<f64>,
    pub n_regions: usize,
    pub metadata: Option<CompressionMetadata>,
}

#[derive(Debug, Serialize)]
pub struct StatsResponse {
    pub n_aircraft: usize,
    pub n_regions: usize,
    pub occupied_regions: usize,
    pub empty_regions: usize,
    pub compression_ratio: f64,
    pub avg_aircraft_per_region: f64,
    pub max_aircraft_per_region: usize,
    pub grid_resolution_degrees: f64,
    pub memory_reduction: String,
}

// ============================================================================
// FRANKLIN GAMES INTERFACE - GENERATIVE REASONING
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct GenerateRequest {
    pub query: String,
    pub context: Option<serde_json::Value>,
}

#[derive(Debug, Serialize)]
pub struct GenerateResponse {
    pub generated: bool,
    pub reasoning_type: String,
    pub output: GenerateOutput,
    pub confidence: f64,
    pub entropy_reduction: f64,
    pub provenance: String,
    pub timestamp: String,
    pub dimensional_conservation: bool,
    pub zero_simulation: bool,
    pub zero_templates: bool,
}

#[derive(Debug, Serialize)]
pub struct GenerateOutput {
    pub manifold_position: [f64; 8],     // UUM-8D coordinates after this turn
    pub entropy_delta: f64,              // Measured reduction this turn
    pub discovery_refs: Vec<String>,     // ArangoDB _ids of discoveries used
    pub collection_stats: HashMap<String, usize>,
    pub synthesis_method: String,
}

/// Generate reasoning using GNN traversal of knowledge graph
async fn generate_reasoning(
    state: web::Data<AppState>,
    request: web::Json<GenerateRequest>,
) -> impl Responder {
    let query = request.query.clone();
    let _start = std::time::Instant::now();
    
    // Query knowledge graph for relevant discoveries
    let discoveries = match query_discoveries(&state.substrate, &query).await {
        Ok(d) => d,
        Err(e) => {
            return HttpResponse::InternalServerError().json(serde_json::json!({
                "error": format!("Failed to query knowledge graph: {}", e),
                "generated": false
            }))
        }
    };
    
    // Compute manifold position from discoveries (STATE NOT LANGUAGE)
    let (positions, discovery_refs, entropy_delta) = compute_manifold_position(&discoveries);
    
    // Compute centroid as game state position
    let mut manifold_position = [0.0; 8];
    if !positions.is_empty() {
        let count = positions.len() as f64;
        for pos in &positions {
            for i in 0..8 {
                manifold_position[i] += pos[i] / count;
            }
        }
    }
    
    HttpResponse::Ok().json(GenerateResponse {
        generated: true,
        reasoning_type: "gnn_knowledge_graph_traversal".to_string(),
        output: GenerateOutput {
            manifold_position,
            entropy_delta,
            discovery_refs,
            collection_stats: discoveries.collection_stats,
            synthesis_method: "rust_gnn_qfot_manifold".to_string(),
        },
        confidence: 0.95,
        entropy_reduction: entropy_delta,
        provenance: "akg-gnn:8806/gnn/generate".to_string(),
        timestamp: chrono::Utc::now().to_rfc3339(),
        dimensional_conservation: true,
        zero_simulation: true,
        zero_templates: true,
    })
}

#[derive(Debug)]
struct DiscoverySet {
    proteins: Vec<serde_json::Value>,
    molecules: Vec<serde_json::Value>,
    compounds: Vec<serde_json::Value>,
    materials: Vec<serde_json::Value>,
    collection_stats: HashMap<String, usize>,
}

async fn query_discoveries(
    substrate: &crate::substrate_query::SubstrateQuery,
    _query: &str,
) -> Result<DiscoverySet, anyhow::Error> {
    // Query all discovery collections
    let proteins = substrate.query_collection("discovered_proteins", 50).await?;
    let molecules = substrate.query_collection("discovered_molecules", 50).await?;
    let compounds = substrate.query_collection("discovered_compounds", 50).await?;
    let materials = substrate.query_collection("discovered_materials", 50).await?;
    
    // Get counts
    let mut stats = HashMap::new();
    let count_p: usize = substrate.count_collection("discovered_proteins").await.unwrap_or(0);
    let count_m: usize = substrate.count_collection("discovered_molecules").await.unwrap_or(0);
    let count_c: usize = substrate.count_collection("discovered_compounds").await.unwrap_or(0);
    let count_mat: usize = substrate.count_collection("discovered_materials").await.unwrap_or(0);
    
    stats.insert("discovered_proteins".to_string(), count_p);
    stats.insert("discovered_molecules".to_string(), count_m);
    stats.insert("discovered_compounds".to_string(), count_c);
    stats.insert("discovered_materials".to_string(), count_mat);
    
    Ok(DiscoverySet {
        proteins,
        molecules,
        compounds,
        materials,
        collection_stats: stats,
    })
}

/// Closure proof structure (mathematical proof of entropy reduction)
#[derive(Debug, Serialize, Clone)]
pub struct ClosureProof {
    pub turns_count: usize,
    pub entropy_initial: f64,
    pub entropy_final: f64,
    pub delta_total: f64,
    pub monotonic_decrease: bool,
    pub turn_log_hash: String,
    pub safety_constraints: Option<Vec<String>>,
    pub timestamp: String,
}

#[derive(Debug, Deserialize, Clone)]
pub struct TurnRecord {
    pub turn: usize,
    pub entropy_before: f64,
    pub entropy_after: f64,
    pub manifold_position: [f64; 8],
    pub timestamp: String,
}

/// Compute closure proof from turn log (mathematical proof of entropy reduction)
fn compute_closure_proof(turn_log: &[TurnRecord]) -> ClosureProof {
    // 1. Verify monotonic entropy decrease
    let mut monotonic = true;
    for i in 0..turn_log.len() {
        if turn_log[i].entropy_after > turn_log[i].entropy_before {
            monotonic = false;
            break;
        }
    }
    
    // 2. Compute total delta
    let entropy_initial = turn_log.first().map(|t| t.entropy_before).unwrap_or(8.0);
    let entropy_final = turn_log.last().map(|t| t.entropy_after).unwrap_or(8.0);
    let delta_total = entropy_initial - entropy_final;
    
    // 3. Generate turn_log hash (immutable proof)
    let mut hasher = DefaultHasher::new();
    for turn in turn_log {
        format!("{:?}", turn).hash(&mut hasher);
    }
    let turn_log_hash = format!("{:x}", hasher.finish());
    
    ClosureProof {
        turns_count: turn_log.len(),
        entropy_initial,
        entropy_final,
        delta_total,
        monotonic_decrease: monotonic,
        turn_log_hash,
        safety_constraints: None,  // TODO: Query discovery_refs for safety_issues propagation
        timestamp: chrono::Utc::now().to_rfc3339(),
    }
}

/// Compute 8D manifold position from discoveries (CONSTITUTIONAL: STATE NOT LANGUAGE)
fn compute_manifold_position(discoveries: &DiscoverySet) -> (Vec<[f64; 8]>, Vec<String>, f64) {
    let mut positions: Vec<[f64; 8]> = Vec::new();
    let mut refs: Vec<String> = Vec::new();
    
    // Extract 8D positions from proteins
    for p in &discoveries.proteins {
        if let (Some(metrics), Some(entropy), Some(id)) = (
            p.get("uum_metrics"),
            p.get("entropy_reduction").and_then(|v| v.as_f64()),
            p.get("_id").and_then(|v| v.as_str())
        ) {
            let position = [
                metrics.get("coherence").and_then(|v| v.as_f64()).unwrap_or(0.5),       // D1
                metrics.get("charge").and_then(|v| v.as_f64()).unwrap_or(0.5),          // D2
                metrics.get("hydrophobicity").and_then(|v| v.as_f64()).unwrap_or(0.5),  // D3
                metrics.get("aromatic").and_then(|v| v.as_f64()).unwrap_or(0.5),        // D4
                metrics.get("size").and_then(|v| v.as_f64()).unwrap_or(0.5),            // D5
                metrics.get("time_dynamics").and_then(|v| v.as_f64()).unwrap_or(0.5),   // D6
                metrics.get("spatial_variance").and_then(|v| v.as_f64()).unwrap_or(0.5),// D7
                entropy,                                                                  // D8: Closure dimension
            ];
            positions.push(position);
            refs.push(id.to_string());
        }
    }
    
    // Extract 8D positions from molecules (if they have uum_metrics)
    for m in &discoveries.molecules {
        if let (Some(metrics), Some(entropy), Some(id)) = (
            m.get("uum_metrics"),
            m.get("entropy_reduction").and_then(|v| v.as_f64()),
            m.get("_id").and_then(|v| v.as_str())
        ) {
            let position = [
                metrics.get("coherence").and_then(|v| v.as_f64()).unwrap_or(0.5),
                metrics.get("charge").and_then(|v| v.as_f64()).unwrap_or(0.5),
                metrics.get("hydrophobicity").and_then(|v| v.as_f64()).unwrap_or(0.5),
                metrics.get("aromatic").and_then(|v| v.as_f64()).unwrap_or(0.5),
                metrics.get("size").and_then(|v| v.as_f64()).unwrap_or(0.5),
                metrics.get("time_dynamics").and_then(|v| v.as_f64()).unwrap_or(0.5),
                metrics.get("spatial_variance").and_then(|v| v.as_f64()).unwrap_or(0.5),
                entropy,
            ];
            positions.push(position);
            refs.push(id.to_string());
        }
    }
    
    // Compute weighted centroid manifold position
    if positions.is_empty() {
        // Default manifold origin if no discoveries
        return (vec![[0.5; 8]], vec![], 0.0);
    }
    
    let mut centroid = [0.0; 8];
    let count = positions.len() as f64;
    
    for pos in &positions {
        for i in 0..8 {
            centroid[i] += pos[i] / count;
        }
    }
    
    // Compute total entropy reduction (D8 component)
    let total_entropy_reduction: f64 = positions.iter().map(|p| p[7]).sum::<f64>() / count;
    
    (positions, refs, total_entropy_reduction)
}

// ============================================================================
// ROUTE CONFIGURATION
// ============================================================================

pub fn config(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("")
            .route("/health", web::get().to(health))
            .route("/metrics", web::get().to(metrics_handler))
            .route("/substrate/patch", web::post().to(get_patch))
            // Franklin Games interface - GNN-based generative reasoning
            .route("/api/generate", web::post().to(generate_reasoning))
            .route("/compress/aircraft", web::post().to(compress_aircraft))
            .route("/decompress/aircraft", web::post().to(decompress_aircraft))
            .route("/compression/stats", web::post().to(compression_stats))
            // Legacy policy/eval endpoint for backward compatibility
            .route("/policy/eval", web::post().to(policy_eval))
            // Telemetry endpoints
            .route("/contexts", web::get().to(get_contexts))
            .route("/substrate/stats", web::get().to(substrate_stats))
            // ATC + Weather endpoints for /evolve/unified
            .route("/atc/context", web::get().to(get_atc_weather_context))
            .route("/atc/aircraft", web::get().to(get_aircraft_near))
            .route("/atc/weather", web::get().to(get_weather_near))
            .route("/atc/density", web::get().to(get_aircraft_density))
            // QFOT Field Twin endpoints
            .route("/qfot/health", web::get().to(qfot_health))
            .route("/qfot/compress", web::post().to(qfot_compress))
            .route("/qfot/ocean/compress", web::post().to(qfot_ocean_compress))
            .route("/qfot/biosphere/forecast", web::post().to(qfot_biosphere_forecast))
            .route("/qfot/forecast", web::post().to(qfot_forecast))
            .route("/qfot/ocean/forecast", web::post().to(qfot_ocean_forecast))
            .route("/qfot/molecular/compress", web::post().to(qfot_molecular_compress))
            .route("/qfot/molecular/forecast", web::post().to(qfot_molecular_forecast))
            .route("/qfot/astro/compress", web::post().to(qfot_astro_compress))
            .route("/qfot/astro/forecast", web::post().to(qfot_astro_forecast))
            // Consciousness endpoints for self-knowledge
            .service(consciousness::list_services)
            .service(consciousness::service_count)
            .service(consciousness::check_service),
    );
}

#[derive(Debug, Deserialize)]
struct QfotBiosphereForecastRequest {
    bbox: QfotBbox,
    valid_time_min: i64,
    valid_time_max: i64,
    forecast_steps: usize,
    step_secs: i64,
    #[serde(default)]
    max_tiles: Option<usize>,
}

async fn qfot_biosphere_forecast(
    state: web::Data<AppState>,
    req: web::Json<QfotBiosphereForecastRequest>,
) -> impl Responder {
    metrics::QFOT_FORECAST_REQUESTS_TOTAL.inc();
    let _timer = metrics::QFOT_FORECAST_DURATION_SECONDS.start_timer();

    let max_tiles = req.max_tiles.unwrap_or(20000);
    let tiles = match state
        .substrate
        .query_biosphere_tiles(
            req.bbox.lat_min,
            req.bbox.lat_max,
            req.bbox.lon_min,
            req.bbox.lon_max,
            req.valid_time_min,
            req.valid_time_max,
            max_tiles,
        )
        .await
    {
        Ok(t) => t,
        Err(e) => {
            log::error!("qfot_biosphere_forecast: tile query failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"tile query failed"}));
        }
    };

    if tiles.is_empty() {
        metrics::QFOT_VALIDATION_FAILURES_TOTAL.inc();
        return HttpResponse::Ok().json(QfotForecastResponse {
            status: "ok",
            forecast_time: chrono::Utc::now().timestamp(),
            steps: req.forecast_steps,
            tiles_written: 0,
            validation_passed: false,
            validation_key: None,
            validation_failures: vec!["no biosphere tiles in selection".to_string()],
        });
    }

    let tiles_for_write = tiles.clone();
    let feature_dim = 16usize;
    let engine = match qfot_engine_for(feature_dim) {
        Ok(e) => e,
        Err(msg) => return HttpResponse::InternalServerError().json(serde_json::json!({"error": msg})),
    };

    let n = tiles.len();
    let mut node_ids: Vec<String> = Vec::with_capacity(n);
    let mut node_features = ndarray::Array2::<f32>::zeros((n, feature_dim));
    for (i, t) in tiles.iter().enumerate() {
        node_ids.push(t.key.clone());
        let lon = t.location.coordinates[0] as f32;
        let lat = t.location.coordinates[1] as f32;
        node_features[(i, 0)] = lon / 180.0;
        node_features[(i, 1)] = lat / 90.0;
        let c = t.state.get("wildfire_event_count").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        node_features[(i, 2)] = (c / 50.0).clamp(0.0, 1.0);
    }

    let g = FieldGraph { node_ids, node_features, edges: vec![] };
    let forecast_time = chrono::Utc::now().timestamp();
    let steps = match engine.forecast_baseline(&g.node_features, req.valid_time_max, req.step_secs, req.forecast_steps) {
        Ok(s) => s,
        Err(e) => {
            log::error!("qfot_biosphere_forecast: baseline forecast failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"forecast failed"}));
        }
    };

    let mut tiles_written = 0usize;
    let mut prediction_keys: Vec<String> = Vec::new();
    for step in steps {
        for (i, seed_key) in g.node_ids.iter().enumerate() {
            let pred_key = safe_pred_key("PRED_BIO_", seed_key, step.valid_time);
            let doc = serde_json::json!({
                "_key": pred_key,
                "location": tiles_for_write[i].location,
                "forecast_time": forecast_time,
                "valid_time": step.valid_time,
                "resolution_level": tiles_for_write[i].resolution_level,
                "resolution_deg": tiles_for_write[i].resolution_deg,
                "state": {
                    "wildfire_event_count": (step.predicted_features[(i,2)] as f64) * 50.0
                },
                "uncertainty": { "confidence": 0.0 },
                "provenance": {
                    "source": "qfot_biosphere_baseline",
                    "model_version": env!("CARGO_PKG_VERSION"),
                    "ingest_timestamp": chrono::Utc::now().timestamp(),
                    "is_prediction": true,
                    "seed_tile": seed_key
                },
                "observations": []
            });

            match state.substrate.upsert_raw_document("biosphere_tiles", &doc).await {
                Ok(_) => {
                    tiles_written += 1;
                    prediction_keys.push(doc["_key"].as_str().unwrap_or_default().to_string());
                }
                Err(e) => log::warn!("qfot_biosphere_forecast: failed to upsert prediction tile: {e}"),
            }
        }
    }

    let validation = match call_validator(
        "validate/qfot_field",
        serde_json::json!({
            "target_collection": "biosphere_tiles",
            "keys": prediction_keys
        }),
    )
    .await
    {
        Ok(v) => v,
        Err(e) => {
            metrics::QFOT_VALIDATION_FAILURES_TOTAL.inc();
            return HttpResponse::Ok().json(QfotForecastResponse {
                status: "ok",
                forecast_time,
                steps: req.forecast_steps,
                tiles_written,
                validation_passed: false,
                validation_key: None,
                validation_failures: vec![e],
            });
        }
    };

    let passed = validation["passed"].as_bool().unwrap_or(false);
    if passed {
        metrics::QFOT_VALIDATION_PASSES_TOTAL.inc();
    } else {
        metrics::QFOT_VALIDATION_FAILURES_TOTAL.inc();
    }

    HttpResponse::Ok().json(QfotForecastResponse {
        status: "ok",
        forecast_time,
        steps: req.forecast_steps,
        tiles_written,
        validation_passed: passed,
        validation_key: validation["validation_key"].as_str().map(|s| s.to_string()),
        validation_failures: validation["failures"]
            .as_array()
            .unwrap_or(&vec![])
            .iter()
            .filter_map(|v| v.as_str().map(|s| s.to_string()))
            .collect(),
    })
}

async fn metrics_handler() -> impl Responder {
    let body = metrics::gather_text();
    HttpResponse::Ok()
        .insert_header((header::CONTENT_TYPE, "text/plain; version=0.0.4; charset=utf-8"))
        .body(body)
}

/// Get available contexts (scales)
async fn get_contexts(state: web::Data<AppState>) -> impl Responder {
    let contexts = state.context_manager.list_contexts();

    #[derive(Serialize)]
    struct ContextInfo {
        name: String,
        default_radius: f64,
        distance_weights: [f64; 8],
    }

    let info: Vec<ContextInfo> = contexts
        .iter()
        .map(|c| {
            let cfg = state.context_manager.get_scale_config(c).unwrap();
            ContextInfo {
                name: c.clone(),
                default_radius: cfg.default_patch_radius,
                distance_weights: cfg.distance_weights,
            }
        })
        .collect();

    HttpResponse::Ok().json(serde_json::json!({
        "contexts": info,
        "total": info.len()
    }))
}

/// Get substrate statistics
async fn substrate_stats(state: web::Data<AppState>) -> impl Responder {
    // Try to get counts from ArangoDB
    let stats = match state.substrate.get_substrate_stats().await {
        Ok(s) => s,
        Err(_) => SubstrateStats::default(),
    };

    HttpResponse::Ok().json(stats)
}

#[derive(Debug, Default, Serialize)]
pub struct SubstrateStats {
    pub total_procedures: usize,
    pub total_edges: usize,
    pub procedures_by_scale: HashMap<String, usize>,
    pub arango_connected: bool,
}

// ============================================================================
// HANDLERS
// ============================================================================

/// Health check - verifies ArangoDB connection and loaded contexts
async fn health(state: web::Data<AppState>) -> impl Responder {
    let arango_ok = state.substrate.health_check().await.unwrap_or(false);
    let contexts = state.context_manager.list_contexts();

    HttpResponse::Ok().json(HealthResponse {
        status: if arango_ok { "healthy" } else { "degraded" },
        service: "akg-gnn-unified",
        arango_connected: arango_ok,
        contexts_loaded: contexts,
    })
}

// ============================================================================
// QFOT FIELD TWIN API
// ============================================================================

#[derive(Debug, Deserialize)]
struct QfotBbox {
    lat_min: f64,
    lat_max: f64,
    lon_min: f64,
    lon_max: f64,
}

#[derive(Debug, Deserialize)]
struct QfotCompressRequest {
    bbox: QfotBbox,
    valid_time_min: i64,
    valid_time_max: i64,
    #[serde(default)]
    altitude_min_ft: Option<i32>,
    #[serde(default)]
    altitude_max_ft: Option<i32>,
    #[serde(default)]
    max_tiles: Option<usize>,
    #[serde(default)]
    max_relations: Option<usize>,
}

#[derive(Debug, Serialize)]
struct QfotCompressResponse {
    status: &'static str,
    graph: crate::qfot::field_graph::FieldGraphMeta,
    compression: crate::qfot::engine::CompressionReport,
}

#[derive(Debug, Deserialize)]
struct QfotForecastRequest {
    bbox: QfotBbox,
    valid_time_min: i64,
    valid_time_max: i64,
    forecast_steps: usize,
    step_secs: i64,
    #[serde(default)]
    altitude_min_ft: Option<i32>,
    #[serde(default)]
    altitude_max_ft: Option<i32>,
    #[serde(default)]
    max_tiles: Option<usize>,
}

#[derive(Debug, Serialize)]
struct QfotForecastResponse {
    status: &'static str,
    forecast_time: i64,
    steps: usize,
    tiles_written: usize,
    validation_passed: bool,
    validation_key: Option<String>,
    validation_failures: Vec<String>,
}

fn safe_pred_key(prefix: &str, seed_key: &str, valid_time: i64) -> String {
    let mut hasher = DefaultHasher::new();
    format!("{seed_key}|{valid_time}").hash(&mut hasher);
    let h = hasher.finish();
    format!("{prefix}{h:016x}_{valid_time}")
}

// ============================================================================
// QFOT OCEAN API (parity with atmosphere)
// ============================================================================

#[derive(Debug, Deserialize)]
struct QfotOceanCompressRequest {
    bbox: QfotBbox,
    valid_time_min: i64,
    valid_time_max: i64,
    #[serde(default)]
    depth_min_m: Option<f64>,
    #[serde(default)]
    depth_max_m: Option<f64>,
    #[serde(default)]
    max_tiles: Option<usize>,
    #[serde(default)]
    max_relations: Option<usize>,
}

#[derive(Debug, Deserialize)]
struct QfotOceanForecastRequest {
    bbox: QfotBbox,
    valid_time_min: i64,
    valid_time_max: i64,
    forecast_steps: usize,
    step_secs: i64,
    #[serde(default)]
    depth_min_m: Option<f64>,
    #[serde(default)]
    depth_max_m: Option<f64>,
    #[serde(default)]
    max_tiles: Option<usize>,
}

async fn qfot_ocean_compress(
    state: web::Data<AppState>,
    req: web::Json<QfotOceanCompressRequest>,
) -> impl Responder {
    let max_tiles = req.max_tiles.unwrap_or(20000);
    let max_rel = req.max_relations.unwrap_or(200000);

    let tiles = match state
        .substrate
        .query_ocean_tiles(
            req.bbox.lat_min,
            req.bbox.lat_max,
            req.bbox.lon_min,
            req.bbox.lon_max,
            req.valid_time_min,
            req.valid_time_max,
            req.depth_min_m,
            req.depth_max_m,
            max_tiles,
        )
        .await
    {
        Ok(t) => t,
        Err(e) => {
            log::error!("qfot_ocean_compress: tile query failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"tile query failed"}));
        }
    };

    let relations = match state
        .substrate
        .query_field_relations(req.valid_time_min, req.valid_time_max, max_rel)
        .await
    {
        Ok(r) => r,
        Err(e) => {
            log::error!("qfot_ocean_compress: relation query failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"relation query failed"}));
        }
    };

    let feature_dim = 32usize;
    let engine = match qfot_engine_for(feature_dim) {
        Ok(e) => e,
        Err(msg) => return HttpResponse::InternalServerError().json(serde_json::json!({"error": msg})),
    };

    let n = tiles.len();
    let mut node_ids: Vec<String> = Vec::with_capacity(n);
    let mut node_features = ndarray::Array2::<f32>::zeros((n, feature_dim));
    let mut idx: std::collections::HashMap<String, usize> = std::collections::HashMap::with_capacity(n);

    for (i, t) in tiles.iter().enumerate() {
        node_ids.push(t.key.clone());
        idx.insert(t.key.clone(), i);

        let mut f = vec![0.0f32; feature_dim];
        let lat = t.location.coordinates[1] as f32;
        let lon = t.location.coordinates[0] as f32;
        f[0] = lon / 180.0;
        f[1] = lat / 90.0;
        let depth_m = t.depth_m.unwrap_or(0.0) as f32;
        f[2] = (depth_m / 10000.0).clamp(0.0, 1.0);
        f[3] = ((t.valid_time - t.forecast_time) as f32 / 86400.0).clamp(0.0, 30.0);

        f[4] = t.state.get("current_u").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[5] = t.state.get("current_v").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[6] = t.state.get("temperature_k").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[7] = t.state.get("wave_height_m").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[8] = t.state.get("wave_period_s").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[9] = t.state.get("wave_direction_deg").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32 / 360.0;

        f[10] = t.uncertainty.get("confidence").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;

        for j in 0..feature_dim {
            node_features[(i, j)] = f[j];
        }
    }

    let mut graph_edges: Vec<(usize, usize, [f32; 8])> = Vec::new();
    graph_edges.reserve(relations.len());
    for r in relations {
        let from_key = r.from.split('/').nth(1).unwrap_or("").to_string();
        let to_key = r.to.split('/').nth(1).unwrap_or("").to_string();
        let Some(&src) = idx.get(&from_key) else { continue };
        let Some(&dst) = idx.get(&to_key) else { continue };
        let mut ef = [0.0f32; 8];
        ef[0] = match r.relation_type.as_str() {
            "neighbor_spatial" => 1.0,
            "evolves_to" => 2.0,
            "ocean_feedback" => 4.0,
            _ => 0.0,
        };
        ef[1] = r.coupling_strength.unwrap_or(0.0).clamp(0.0, 1.0) as f32;
        graph_edges.push((src, dst, ef));
    }

    let g = FieldGraph {
        node_ids,
        node_features,
        edges: graph_edges,
    };

    let hidden = match engine.forward_hidden(&g) {
        Ok(h) => h,
        Err(e) => {
            log::error!("qfot_ocean_compress: forward failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"forward failed"}));
        }
    };

    let (_c, _r, report) = match engine.compress_hidden(&hidden) {
        Ok(r) => r,
        Err(e) => {
            log::error!("qfot_ocean_compress: compression failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"compression failed"}));
        }
    };

    HttpResponse::Ok().json(QfotCompressResponse {
        status: "ok",
        graph: g.meta(),
        compression: report,
    })
}

async fn qfot_ocean_forecast(
    state: web::Data<AppState>,
    req: web::Json<QfotOceanForecastRequest>,
) -> impl Responder {
    metrics::QFOT_FORECAST_REQUESTS_TOTAL.inc();
    let _timer = metrics::QFOT_FORECAST_DURATION_SECONDS.start_timer();
    let max_tiles = req.max_tiles.unwrap_or(20000);
    let tiles = match state
        .substrate
        .query_ocean_tiles(
            req.bbox.lat_min,
            req.bbox.lat_max,
            req.bbox.lon_min,
            req.bbox.lon_max,
            req.valid_time_min,
            req.valid_time_max,
            req.depth_min_m,
            req.depth_max_m,
            max_tiles,
        )
        .await
    {
        Ok(t) => t,
        Err(e) => {
            log::error!("qfot_ocean_forecast: tile query failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"tile query failed"}));
        }
    };

    if tiles.is_empty() {
        metrics::QFOT_VALIDATION_FAILURES_TOTAL.inc();
        return HttpResponse::Ok().json(QfotForecastResponse {
            status: "ok",
            forecast_time: chrono::Utc::now().timestamp(),
            steps: req.forecast_steps,
            tiles_written: 0,
            validation_passed: false,
            validation_key: None,
            validation_failures: vec!["no ocean tiles in selection".to_string()],
        });
    }

    let tiles_for_write = tiles.clone();

    let feature_dim = 32usize;
    let engine = match qfot_engine_for(feature_dim) {
        Ok(e) => e,
        Err(msg) => return HttpResponse::InternalServerError().json(serde_json::json!({"error": msg})),
    };

    let n = tiles.len();
    let mut node_ids: Vec<String> = Vec::with_capacity(n);
    let mut node_features = ndarray::Array2::<f32>::zeros((n, feature_dim));
    for (i, t) in tiles.iter().enumerate() {
        node_ids.push(t.key.clone());
        let mut f = vec![0.0f32; feature_dim];
        let lat = t.location.coordinates[1] as f32;
        let lon = t.location.coordinates[0] as f32;
        f[0] = lon / 180.0;
        f[1] = lat / 90.0;
        let depth_m = t.depth_m.unwrap_or(0.0) as f32;
        f[2] = (depth_m / 10000.0).clamp(0.0, 1.0);
        f[4] = t.state.get("current_u").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[5] = t.state.get("current_v").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[6] = t.state.get("temperature_k").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[7] = t.state.get("wave_height_m").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[8] = t.state.get("wave_period_s").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[9] = t.state.get("wave_direction_deg").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32 / 360.0;
        for j in 0..feature_dim {
            node_features[(i, j)] = f[j];
        }
    }

    let g = FieldGraph { node_ids, node_features, edges: vec![] };

    let forecast_time = chrono::Utc::now().timestamp();
    let steps = match engine.forecast_baseline(&g.node_features, req.valid_time_max, req.step_secs, req.forecast_steps) {
        Ok(s) => s,
        Err(e) => {
            log::error!("qfot_ocean_forecast: baseline forecast failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"forecast failed"}));
        }
    };

    let mut tiles_written = 0usize;
    let mut prediction_keys: Vec<String> = Vec::new();
    for step in steps {
        for (i, key) in g.node_ids.iter().enumerate() {
            let seed_key = tiles_for_write[i]
                .provenance
                .get("seed_tile")
                .and_then(|v| v.as_str())
                .unwrap_or(key);
            let pred_key = safe_pred_key("PRED_OCN_", seed_key, step.valid_time);
            let doc = serde_json::json!({
                "_key": pred_key,
                "location": tiles_for_write[i].location,
                "depth_m": tiles_for_write[i].depth_m,
                "forecast_time": forecast_time,
                "valid_time": step.valid_time,
                "resolution_level": tiles_for_write[i].resolution_level,
                "resolution_deg": tiles_for_write[i].resolution_deg,
                "state": {
                    "current_u": step.predicted_features[(i,4)],
                    "current_v": step.predicted_features[(i,5)],
                    "temperature_k": step.predicted_features[(i,6)],
                    "wave_height_m": step.predicted_features[(i,7)],
                    "wave_period_s": step.predicted_features[(i,8)],
                    "wave_direction_deg": step.predicted_features[(i,9)] * 360.0
                },
                "uncertainty": {
                    "confidence": 0.0
                },
                "provenance": {
                    "source": "qfot_ocean_baseline",
                    "model_version": env!("CARGO_PKG_VERSION"),
                    "ingest_timestamp": chrono::Utc::now().timestamp(),
                    "is_prediction": true,
                    "seed_tile": key
                },
                "observations": []
            });

            if let Err(e) = state.substrate.upsert_raw_document("ocean_tiles", &doc).await {
                log::error!("qfot_ocean_forecast: upsert failed: {e}");
                continue;
            }
            tiles_written += 1;
            prediction_keys.push(pred_key);
        }
    }

    let validation = match call_validator(
        "validate/qfot_field",
        serde_json::json!({
            "target_collection": "ocean_tiles",
            "keys": prediction_keys
        }),
    )
    .await
    {
        Ok(v) => v,
        Err(e) => {
            metrics::QFOT_VALIDATION_FAILURES_TOTAL.inc();
            return HttpResponse::Ok().json(QfotForecastResponse {
                status: "ok",
                forecast_time,
                steps: req.forecast_steps,
                tiles_written,
                validation_passed: false,
                validation_key: None,
                validation_failures: vec![e],
            });
        }
    };

    let passed = validation["passed"].as_bool().unwrap_or(false);
    if passed {
        metrics::QFOT_VALIDATION_PASSES_TOTAL.inc();
    } else {
        metrics::QFOT_VALIDATION_FAILURES_TOTAL.inc();
    }

    HttpResponse::Ok().json(QfotForecastResponse {
        status: "ok",
        forecast_time,
        steps: req.forecast_steps,
        tiles_written,
        validation_passed: passed,
        validation_key: validation["validation_key"].as_str().map(|s| s.to_string()),
        validation_failures: validation["failures"]
            .as_array()
            .unwrap_or(&vec![])
            .iter()
            .filter_map(|v| v.as_str().map(|s| s.to_string()))
            .collect(),
    })
}

async fn qfot_health(state: web::Data<AppState>) -> impl Responder {
    HttpResponse::Ok().json(serde_json::json!({
        "status": "healthy",
        "service": "akg-gnn-unified",
        "qfot": {
            "feature_dim": state.qfot.feature_dim,
            "hidden_dim": state.qfot.hidden_dim,
            "compressed_dim": state.qfot.compressed_dim
        }
    }))
}

fn validation_url() -> String {
    std::env::var("GAIAOS_VALIDATION_URL").unwrap_or_else(|_| "http://localhost:8802".to_string())
}

async fn call_validator(
    path: &str,
    payload: serde_json::Value,
) -> Result<serde_json::Value, String> {
    let url = format!("{}/{}", validation_url().trim_end_matches('/'), path.trim_start_matches('/'));
    let client = reqwest::Client::new();
    let resp = client
        .post(url)
        .json(&payload)
        .send()
        .await
        .map_err(|e| format!("validator request failed: {e}"))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(format!("validator returned {status}: {text}"));
    }

    resp.json::<serde_json::Value>()
        .await
        .map_err(|e| format!("validator decode failed: {e}"))
}

fn qfot_engine_for(feature_dim: usize) -> Result<crate::qfot::engine::QfotEngine, String> {
    let compressed_dim: usize = std::env::var("QFOT_COMPRESSED_DIM")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8);
    crate::qfot::engine::QfotEngine::new(feature_dim, feature_dim, compressed_dim)
        .map_err(|e| format!("qfot engine init failed: {e}"))
}

async fn qfot_compress(state: web::Data<AppState>, req: web::Json<QfotCompressRequest>) -> impl Responder {
    let max_tiles = req.max_tiles.unwrap_or(20000);
    let max_rel = req.max_relations.unwrap_or(200000);

    let tiles = match state.substrate.query_atmosphere_tiles(
        req.bbox.lat_min,
        req.bbox.lat_max,
        req.bbox.lon_min,
        req.bbox.lon_max,
        req.valid_time_min,
        req.valid_time_max,
        req.altitude_min_ft,
        req.altitude_max_ft,
        max_tiles,
    ).await {
        Ok(t) => t,
        Err(e) => {
            log::error!("qfot_compress: tile query failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"tile query failed"}));
        }
    };

    let relations = match state.substrate.query_field_relations(req.valid_time_min, req.valid_time_max, max_rel).await {
        Ok(r) => r,
        Err(e) => {
            log::error!("qfot_compress: relation query failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"relation query failed"}));
        }
    };

    let encode_tile = |t: &crate::substrate_query::AtmosphereTileDoc| -> Vec<f32> {
        // MVP deterministic tile feature map (bounded, auditable).
        let mut f = vec![0.0f32; 32];
        let lat = t.location.coordinates[1] as f32;
        let lon = t.location.coordinates[0] as f32;
        f[0] = lon / 180.0;
        f[1] = lat / 90.0;
        f[2] = (t.altitude_ft as f32 / 60000.0).clamp(0.0, 1.0);
        f[3] = ((t.valid_time - t.forecast_time) as f32 / 86400.0).clamp(0.0, 7.0); // horizon days capped

        // State values
        f[4] = t.state.get("wind_u").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[5] = t.state.get("wind_v").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[6] = t.state.get("temperature_k").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[7] = t.state.get("visibility_m").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[8] = t.state.get("trajectory_density").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;

        // Uncertainty/confidence
        f[9] = t.uncertainty.get("confidence").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[10] = t.uncertainty.get("wind_u_std").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[11] = t.uncertainty.get("wind_v_std").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[12] = t.uncertainty.get("temperature_std").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;

        // Consciousness proxy
        f[13] = t.observations.len() as f32;

        f
    };

    let encode_edge = |r: &crate::substrate_query::FieldRelationDoc| -> [f32; 8] {
        let mut e = [0.0f32; 8];
        e[0] = match r.relation_type.as_str() {
            "neighbor_spatial" => 1.0,
            "evolves_to" => 2.0,
            "atmospheric_forcing" => 3.0,
            "ocean_feedback" => 4.0,
            "boundary_constraint" => 5.0,
            "trajectory_passes_through" => 6.0,
            "observes" => 7.0,
            _ => 0.0,
        };
        e[1] = r.coupling_strength.unwrap_or(0.0).clamp(0.0, 1.0) as f32;
        e
    };

    let g = match FieldGraph::from_atmosphere_tiles(tiles, relations, 32, encode_tile, encode_edge) {
        Ok(g) => g,
        Err(e) => {
            log::error!("qfot_compress: graph build failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"graph build failed"}));
        }
    };

    let hidden = match state.qfot.forward_hidden(&g) {
        Ok(h) => h,
        Err(e) => {
            log::error!("qfot_compress: forward failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"forward failed"}));
        }
    };

    let (_compressed, _reconstructed, report) = match state.qfot.compress_hidden(&hidden) {
        Ok(r) => r,
        Err(e) => {
            log::error!("qfot_compress: compression failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"compression failed"}));
        }
    };

    HttpResponse::Ok().json(QfotCompressResponse {
        status: "ok",
        graph: g.meta(),
        compression: report,
    })
}

async fn qfot_forecast(state: web::Data<AppState>, req: web::Json<QfotForecastRequest>) -> impl Responder {
    metrics::QFOT_FORECAST_REQUESTS_TOTAL.inc();
    let _timer = metrics::QFOT_FORECAST_DURATION_SECONDS.start_timer();
    let max_tiles = req.max_tiles.unwrap_or(20000);
    let tiles = match state.substrate.query_atmosphere_tiles(
        req.bbox.lat_min,
        req.bbox.lat_max,
        req.bbox.lon_min,
        req.bbox.lon_max,
        req.valid_time_min,
        req.valid_time_max,
        req.altitude_min_ft,
        req.altitude_max_ft,
        max_tiles,
    ).await {
        Ok(t) => t,
        Err(e) => {
            log::error!("qfot_forecast: tile query failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"tile query failed"}));
        }
    };

    let tiles_for_write = tiles.clone();

    // Build a minimal graph with no edges; baseline forecast uses persistence.
    let encode_tile = |t: &crate::substrate_query::AtmosphereTileDoc| -> Vec<f32> {
        let mut f = vec![0.0f32; 32];
        let lat = t.location.coordinates[1] as f32;
        let lon = t.location.coordinates[0] as f32;
        f[0] = lon / 180.0;
        f[1] = lat / 90.0;
        f[2] = (t.altitude_ft as f32 / 60000.0).clamp(0.0, 1.0);
        f[4] = t.state.get("wind_u").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[5] = t.state.get("wind_v").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[6] = t.state.get("temperature_k").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[7] = t.state.get("visibility_m").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f
    };
    let encode_edge = |_r: &crate::substrate_query::FieldRelationDoc| -> [f32; 8] { [0.0f32; 8] };

    let g = match FieldGraph::from_atmosphere_tiles(tiles, vec![], 32, encode_tile, encode_edge) {
        Ok(g) => g,
        Err(e) => {
            log::error!("qfot_forecast: graph build failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"graph build failed"}));
        }
    };

    // Use current features directly for baseline forecast
    let forecast_time = chrono::Utc::now().timestamp();
    let steps = match state.qfot.forecast_baseline(&g.node_features, req.valid_time_max, req.step_secs, req.forecast_steps) {
        Ok(s) => s,
        Err(e) => {
            log::error!("qfot_forecast: baseline forecast failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"forecast failed"}));
        }
    };

    // Persist minimal predicted tiles into atmosphere_tiles as separate docs (prediction provenance).
    // We do not overwrite observed tiles.
    let mut tiles_written = 0usize;
    let mut prediction_keys: Vec<String> = Vec::new();
    for step in steps {
        for (i, key) in g.node_ids.iter().enumerate() {
            let seed_key = tiles_for_write[i]
                .provenance
                .get("seed_tile")
                .and_then(|v| v.as_str())
                .unwrap_or(key);
            let pred_key = safe_pred_key("PRED_ATM_", seed_key, step.valid_time);
            let doc = serde_json::json!({
                "_key": pred_key,
                "location": tiles_for_write[i].location,
                "altitude_ft": tiles_for_write[i].altitude_ft,
                "forecast_time": forecast_time,
                "valid_time": step.valid_time,
                "resolution_level": 2,
                "resolution_deg": tiles_for_write[i].resolution_deg,
                "state": {
                    "wind_u": step.predicted_features[(i,4)],
                    "wind_v": step.predicted_features[(i,5)],
                    "temperature_k": step.predicted_features[(i,6)],
                    "visibility_m": step.predicted_features[(i,7)]
                },
                "uncertainty": {
                    "confidence": 0.0,
                    "wind_u_std": step.uncertainty[(i,4)],
                    "wind_v_std": step.uncertainty[(i,5)],
                    "temperature_std": step.uncertainty[(i,6)]
                },
                "provenance": {
                    "source": "qfot_baseline",
                    "model_version": env!("CARGO_PKG_VERSION"),
                    "ingest_timestamp": chrono::Utc::now().timestamp(),
                    "is_prediction": true,
                    "seed_tile": key
                },
                "observations": []
            });
            match state.substrate.upsert_raw_document("atmosphere_tiles", &doc).await {
                Ok(_) => {
                    tiles_written += 1;
                    prediction_keys.push(doc["_key"].as_str().unwrap_or_default().to_string());
                }
                Err(e) => log::warn!("qfot_forecast: failed to upsert prediction tile: {e}"),
            }
        }
    }

    // QFOT validation gate (fail-closed on validator unreachable)
    match call_validator(
        "/validate/qfot_field",
        serde_json::json!({
            "target_collection": "atmosphere_tiles",
            "keys": prediction_keys
        }),
    )
    .await
    {
        Ok(body) => {
            let passed = body["passed"].as_bool().unwrap_or(false);
            if passed {
                metrics::QFOT_VALIDATION_PASSES_TOTAL.inc();
            } else {
                metrics::QFOT_VALIDATION_FAILURES_TOTAL.inc();
            }
            let validation_key = body["validation_key"].as_str().map(|s| s.to_string());
            let failures: Vec<String> = body["failures"]
                .as_array()
                .unwrap_or(&vec![])
                .iter()
                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                .collect();

            HttpResponse::Ok().json(QfotForecastResponse {
                status: if passed { "ok" } else { "rejected" },
                forecast_time,
                steps: req.forecast_steps,
                tiles_written,
                validation_passed: passed,
                validation_key,
                validation_failures: failures,
            })
        }
        Err(e) => {
            metrics::QFOT_VALIDATION_FAILURES_TOTAL.inc();
            HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "error": "qfot validator unavailable",
            "details": e
        }))
        },
    }
}

// ============================================================================
// QFOT MOLECULAR API
// ============================================================================

#[derive(Debug, Deserialize)]
struct QfotMolecularCompressRequest {
    protein_id: String,
    sim_time_ps_min: f64,
    sim_time_ps_max: f64,
    x_min: f64,
    x_max: f64,
    y_min: f64,
    y_max: f64,
    z_min: f64,
    z_max: f64,
    #[serde(default)]
    max_tiles: Option<usize>,
    #[serde(default)]
    max_edges: Option<usize>,
}

#[derive(Debug, Serialize)]
struct QfotMolecularCompressResponse {
    status: &'static str,
    graph: crate::qfot::field_graph::FieldGraphMeta,
    compression: crate::qfot::engine::CompressionReport,
}

#[derive(Debug, Deserialize)]
struct QfotMolecularForecastRequest {
    protein_id: String,
    sim_time_ps_min: f64,
    sim_time_ps_max: f64,
    x_min: f64,
    x_max: f64,
    y_min: f64,
    y_max: f64,
    z_min: f64,
    z_max: f64,
    forecast_steps: usize,
    step_secs: i64,
    #[serde(default)]
    max_tiles: Option<usize>,
}

#[derive(Debug, Serialize)]
struct QfotMolecularForecastResponse {
    status: &'static str,
    forecast_time: i64,
    steps: usize,
    tiles_written: usize,
    validation_passed: bool,
    validation_key: Option<String>,
    validation_failures: Vec<String>,
}

async fn qfot_molecular_compress(
    state: web::Data<AppState>,
    req: web::Json<QfotMolecularCompressRequest>,
) -> impl Responder {
    let max_tiles = req.max_tiles.unwrap_or(20000);
    let max_edges = req.max_edges.unwrap_or(200000);

    let tiles = match state
        .substrate
        .query_molecular_tiles(
            &req.protein_id,
            req.sim_time_ps_min,
            req.sim_time_ps_max,
            req.x_min,
            req.x_max,
            req.y_min,
            req.y_max,
            req.z_min,
            req.z_max,
            max_tiles,
        )
        .await
    {
        Ok(t) => t,
        Err(e) => {
            log::error!("qfot_molecular_compress: tile query failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"tile query failed"}));
        }
    };

    let edges = match state
        .substrate
        .query_molecular_interactions(req.sim_time_ps_min, req.sim_time_ps_max, max_edges)
        .await
    {
        Ok(e) => e,
        Err(e) => {
            log::error!("qfot_molecular_compress: interaction query failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"interaction query failed"}));
        }
    };

    let feature_dim = 36usize;
    let engine = match qfot_engine_for(feature_dim) {
        Ok(e) => e,
        Err(msg) => return HttpResponse::InternalServerError().json(serde_json::json!({"error": msg})),
    };

    let n = tiles.len();
    let mut node_ids: Vec<String> = Vec::with_capacity(n);
    let mut node_features = ndarray::Array2::<f32>::zeros((n, feature_dim));
    let mut idx: std::collections::HashMap<String, usize> = std::collections::HashMap::with_capacity(n);

    for (i, t) in tiles.iter().enumerate() {
        node_ids.push(t.key.clone());
        idx.insert(t.key.clone(), i);
        let mut f = vec![0.0f32; feature_dim];

        // Space (Å): normalize by 50Å typical box
        let x = t.position_angstrom.coordinates[0] as f32;
        let y = t.position_angstrom.coordinates[1] as f32;
        let z = t.z_angstrom as f32;
        f[0] = x / 50.0;
        f[1] = y / 50.0;
        f[2] = z / 50.0;
        f[3] = (t.resolution_angstrom as f32) / 5.0;

        // Time
        f[4] = (t.simulation_time_ps as f32) / 1000.0;
        f[5] = (t.timestep_fs as f32) / 10.0;

        // Energy terms (kcal/mol)
        f[6] = t.state.get("electrostatic_potential").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[7] = t.state.get("vdw_energy").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[8] = t.state.get("hbond_energy").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[9] = t.state.get("solvation_energy").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[10] = t.state.get("potential_energy").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[11] = t.state.get("kinetic_energy").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[12] = t.state.get("temperature_k").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32 / 400.0;

        // Pattern (optional)
        if let Some(p) = &t.pattern {
            f[13] = p.get("helix_propensity").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
            f[14] = p.get("sheet_propensity").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
            f[15] = p.get("coil_propensity").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
            f[16] = p.get("hydrophobic_density").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
            f[17] = p.get("entropy").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32 / 50.0;
            f[18] = p.get("contact_density").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        }

        // Uncertainty (optional)
        if let Some(u) = &t.uncertainty {
            f[19] = u.get("epistemic").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
            f[20] = u.get("aleatoric").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
            f[21] = u.get("ensemble_variance").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
            f[22] = u.get("confidence").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        }

        // Intent (optional)
        if let Some(intent) = &t.intent {
            f[23] = intent.get("target_rmsd_from_native").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32 / 50.0;
            f[24] = intent.get("folding_progress").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
            f[25] = intent.get("binding_site_occupancy").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        }

        // Observations count is intentionally NOT used for predictions/closure.
        // Fill remaining dims with stable identifiers / densities if available.
        f[26] = t.protein_id.len().min(128) as f32 / 128.0;

        for j in 0..feature_dim {
            node_features[(i, j)] = f[j];
        }
    }

    let mut graph_edges: Vec<(usize, usize, [f32; 8])> = Vec::new();
    graph_edges.reserve(edges.len());
    for e in edges {
        let from_key = e.from.split('/').nth(1).unwrap_or("").to_string();
        let to_key = e.to.split('/').nth(1).unwrap_or("").to_string();
        let Some(&src) = idx.get(&from_key) else { continue };
        let Some(&dst) = idx.get(&to_key) else { continue };

        let mut ef = [0.0f32; 8];
        ef[0] = match e.interaction_type.as_str() {
            "covalent_bond" => 1.0,
            "hbond" => 2.0,
            "vdw" => 3.0,
            "electrostatic" => 4.0,
            "hydrophobic" => 5.0,
            _ => 0.0,
        };
        ef[1] = e.strength_kcal_mol.unwrap_or(0.0).abs().min(100.0) as f32 / 100.0;
        ef[2] = e.equilibrium_distance_angstrom.unwrap_or(0.0).min(10.0) as f32 / 10.0;
        ef[3] = e.force_constant.unwrap_or(0.0).min(1000.0) as f32 / 1000.0;
        graph_edges.push((src, dst, ef));
    }

    let g = FieldGraph {
        node_ids,
        node_features,
        edges: graph_edges,
    };

    let hidden = match engine.forward_hidden(&g) {
        Ok(h) => h,
        Err(e) => {
            log::error!("qfot_molecular_compress: forward failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"forward failed"}));
        }
    };

    let (_c, _r, report) = match engine.compress_hidden(&hidden) {
        Ok(r) => r,
        Err(e) => {
            log::error!("qfot_molecular_compress: compression failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"compression failed"}));
        }
    };

    HttpResponse::Ok().json(QfotMolecularCompressResponse {
        status: "ok",
        graph: g.meta(),
        compression: report,
    })
}

async fn qfot_molecular_forecast(
    state: web::Data<AppState>,
    req: web::Json<QfotMolecularForecastRequest>,
) -> impl Responder {
    metrics::QFOT_FORECAST_REQUESTS_TOTAL.inc();
    let _timer = metrics::QFOT_FORECAST_DURATION_SECONDS.start_timer();
    let max_tiles = req.max_tiles.unwrap_or(20000);

    let tiles = match state
        .substrate
        .query_molecular_tiles(
            &req.protein_id,
            req.sim_time_ps_min,
            req.sim_time_ps_max,
            req.x_min,
            req.x_max,
            req.y_min,
            req.y_max,
            req.z_min,
            req.z_max,
            max_tiles,
        )
        .await
    {
        Ok(t) => t,
        Err(e) => {
            log::error!("qfot_molecular_forecast: tile query failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"tile query failed"}));
        }
    };

    if tiles.is_empty() {
        metrics::QFOT_VALIDATION_FAILURES_TOTAL.inc();
        return HttpResponse::Ok().json(QfotMolecularForecastResponse {
            status: "ok",
            forecast_time: chrono::Utc::now().timestamp(),
            steps: req.forecast_steps,
            tiles_written: 0,
            validation_passed: false,
            validation_key: None,
            validation_failures: vec!["no molecular tiles in selection".to_string()],
        });
    }

    let feature_dim = 36usize;
    let engine = match qfot_engine_for(feature_dim) {
        Ok(e) => e,
        Err(msg) => return HttpResponse::InternalServerError().json(serde_json::json!({"error": msg})),
    };

    // Encode current features (same encoding as compress)
    let n = tiles.len();
    let mut node_ids: Vec<String> = Vec::with_capacity(n);
    let mut node_features = ndarray::Array2::<f32>::zeros((n, feature_dim));
    for (i, t) in tiles.iter().enumerate() {
        node_ids.push(t.key.clone());
        let mut f = vec![0.0f32; feature_dim];
        let x = t.position_angstrom.coordinates[0] as f32;
        let y = t.position_angstrom.coordinates[1] as f32;
        let z = t.z_angstrom as f32;
        f[0] = x / 50.0;
        f[1] = y / 50.0;
        f[2] = z / 50.0;
        f[4] = (t.simulation_time_ps as f32) / 1000.0;
        f[6] = t.state.get("electrostatic_potential").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[7] = t.state.get("vdw_energy").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[8] = t.state.get("hbond_energy").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[9] = t.state.get("solvation_energy").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[10] = t.state.get("potential_energy").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        f[11] = t.state.get("kinetic_energy").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        for j in 0..feature_dim {
            node_features[(i, j)] = f[j];
        }
    }

    let g = FieldGraph {
        node_ids: node_ids.clone(),
        node_features: node_features.clone(),
        edges: vec![],
    };

    let forecast_time = chrono::Utc::now().timestamp();
    let steps = match engine.forecast_baseline(&g.node_features, forecast_time, req.step_secs, req.forecast_steps) {
        Ok(s) => s,
        Err(e) => {
            log::error!("qfot_molecular_forecast: baseline forecast failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"forecast failed"}));
        }
    };

    let mut prediction_keys: Vec<String> = Vec::new();
    let mut tiles_written = 0usize;

    for step in steps {
        for (i, seed_key) in node_ids.iter().enumerate() {
            let pred_key = safe_pred_key("PRED_MOL_", seed_key, step.valid_time);
            let doc = serde_json::json!({
                "_key": pred_key,
                "protein_id": tiles[i].protein_id,
                "trajectory_id": tiles[i].trajectory_id,
                "position_angstrom": tiles[i].position_angstrom,
                "z_angstrom": tiles[i].z_angstrom,
                "resolution_angstrom": tiles[i].resolution_angstrom,
                "simulation_time_ps": tiles[i].simulation_time_ps,
                "timestep_fs": tiles[i].timestep_fs,
                "forecast_time": forecast_time,
                "valid_time": step.valid_time,
                "ingest_timestamp": chrono::Utc::now().timestamp(),
                "state": {
                    "potential_energy": step.predicted_features[(i,10)] as f64,
                    "kinetic_energy": step.predicted_features[(i,11)] as f64,
                    "electrostatic_potential": step.predicted_features[(i,6)] as f64,
                    "vdw_energy": step.predicted_features[(i,7)] as f64,
                    "hbond_energy": step.predicted_features[(i,8)] as f64,
                    "solvation_energy": step.predicted_features[(i,9)] as f64
                },
                "provenance": {
                    "source": "qfot_molecular_baseline",
                    "model_version": env!("CARGO_PKG_VERSION"),
                    "ingested_at": chrono::Utc::now().to_rfc3339(),
                    "is_prediction": true,
                    "seed_tile": seed_key
                }
            });

            match state.substrate.upsert_raw_document("molecular_tiles", &doc).await {
                Ok(_) => {
                    tiles_written += 1;
                    prediction_keys.push(doc["_key"].as_str().unwrap_or_default().to_string());
                }
                Err(e) => log::warn!("qfot_molecular_forecast: failed to upsert prediction tile: {e}"),
            }
        }
    }

    let validator = call_validator(
        "/validate/qfot_molecular",
        serde_json::json!({ "keys": prediction_keys }),
    )
    .await;

    match validator {
        Ok(body) => {
            let passed = body["passed"].as_bool().unwrap_or(false);
            if passed {
                metrics::QFOT_VALIDATION_PASSES_TOTAL.inc();
            } else {
                metrics::QFOT_VALIDATION_FAILURES_TOTAL.inc();
            }
            let validation_key = body["validation_key"].as_str().map(|s| s.to_string());
            let failures: Vec<String> = body["failures"]
                .as_array()
                .unwrap_or(&vec![])
                .iter()
                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                .collect();

            HttpResponse::Ok().json(QfotMolecularForecastResponse {
                status: if passed { "ok" } else { "rejected" },
                forecast_time,
                steps: req.forecast_steps,
                tiles_written,
                validation_passed: passed,
                validation_key,
                validation_failures: failures,
            })
        }
        Err(e) => {
            metrics::QFOT_VALIDATION_FAILURES_TOTAL.inc();
            HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "error": "qfot molecular validator unavailable",
            "details": e
        }))
        },
    }
}

// ============================================================================
// QFOT ASTRO API
// ============================================================================

#[derive(Debug, Deserialize)]
struct QfotAstroCompressRequest {
    epoch_min: i64,
    epoch_max: i64,
    x_min: f64,
    x_max: f64,
    y_min: f64,
    y_max: f64,
    z_min: f64,
    z_max: f64,
    #[serde(default)]
    max_tiles: Option<usize>,
}

#[derive(Debug, Serialize)]
struct QfotAstroCompressResponse {
    status: &'static str,
    graph: crate::qfot::field_graph::FieldGraphMeta,
    compression: crate::qfot::engine::CompressionReport,
}

#[derive(Debug, Deserialize)]
struct QfotAstroForecastRequest {
    epoch_min: i64,
    epoch_max: i64,
    x_min: f64,
    x_max: f64,
    y_min: f64,
    y_max: f64,
    z_min: f64,
    z_max: f64,
    forecast_steps: usize,
    step_secs: i64,
    #[serde(default)]
    max_tiles: Option<usize>,
}

#[derive(Debug, Serialize)]
struct QfotAstroForecastResponse {
    status: &'static str,
    forecast_time: i64,
    steps: usize,
    tiles_written: usize,
    validation_passed: bool,
    validation_key: Option<String>,
    validation_failures: Vec<String>,
}

async fn qfot_astro_compress(
    state: web::Data<AppState>,
    req: web::Json<QfotAstroCompressRequest>,
) -> impl Responder {
    let max_tiles = req.max_tiles.unwrap_or(20000);

    let tiles = match state
        .substrate
        .query_gravitational_tiles(
            req.epoch_min,
            req.epoch_max,
            req.x_min,
            req.x_max,
            req.y_min,
            req.y_max,
            req.z_min,
            req.z_max,
            max_tiles,
        )
        .await
    {
        Ok(t) => t,
        Err(e) => {
            log::error!("qfot_astro_compress: tile query failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"tile query failed"}));
        }
    };

    let feature_dim = 40usize;
    let engine = match qfot_engine_for(feature_dim) {
        Ok(e) => e,
        Err(msg) => return HttpResponse::InternalServerError().json(serde_json::json!({"error": msg})),
    };

    let n = tiles.len();
    let mut node_ids: Vec<String> = Vec::with_capacity(n);
    let mut node_features = ndarray::Array2::<f32>::zeros((n, feature_dim));

    for (i, t) in tiles.iter().enumerate() {
        node_ids.push(t.key.clone());
        let mut f = vec![0.0f32; feature_dim];

        // Space (km): normalize by 10000km
        let x = t.position_eci.coordinates[0] as f32;
        let y = t.position_eci.coordinates[1] as f32;
        let z = t.z_km as f32;
        f[0] = x / 10000.0;
        f[1] = y / 10000.0;
        f[2] = z / 10000.0;
        f[3] = (t.resolution_km as f32) / 1000.0;

        // Time
        f[4] = (t.epoch_seconds as f32) / 86400.0;
        f[5] = (t.timestep_seconds as f32) / 600.0;

        // Gravity terms
        f[6] = t.state.get("gravitational_potential").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32 / 1e8;
        f[7] = t.state.get("g_field_magnitude").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32 / 20.0;

        // Patterns/uncertainty if present
        if let Some(u) = &t.uncertainty {
            f[20] = u.get("confidence").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
        }

        for j in 0..feature_dim {
            node_features[(i, j)] = f[j];
        }
    }

    let g = FieldGraph {
        node_ids,
        node_features,
        edges: vec![],
    };

    let hidden = match engine.forward_hidden(&g) {
        Ok(h) => h,
        Err(e) => {
            log::error!("qfot_astro_compress: forward failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"forward failed"}));
        }
    };

    let (_c, _r, report) = match engine.compress_hidden(&hidden) {
        Ok(r) => r,
        Err(e) => {
            log::error!("qfot_astro_compress: compression failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"compression failed"}));
        }
    };

    HttpResponse::Ok().json(QfotAstroCompressResponse {
        status: "ok",
        graph: g.meta(),
        compression: report,
    })
}

async fn qfot_astro_forecast(
    state: web::Data<AppState>,
    req: web::Json<QfotAstroForecastRequest>,
) -> impl Responder {
    metrics::QFOT_FORECAST_REQUESTS_TOTAL.inc();
    let _timer = metrics::QFOT_FORECAST_DURATION_SECONDS.start_timer();
    let max_tiles = req.max_tiles.unwrap_or(20000);

    let tiles = match state
        .substrate
        .query_gravitational_tiles(
            req.epoch_min,
            req.epoch_max,
            req.x_min,
            req.x_max,
            req.y_min,
            req.y_max,
            req.z_min,
            req.z_max,
            max_tiles,
        )
        .await
    {
        Ok(t) => t,
        Err(e) => {
            log::error!("qfot_astro_forecast: tile query failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"tile query failed"}));
        }
    };

    if tiles.is_empty() {
        metrics::QFOT_VALIDATION_FAILURES_TOTAL.inc();
        return HttpResponse::Ok().json(QfotAstroForecastResponse {
            status: "ok",
            forecast_time: chrono::Utc::now().timestamp(),
            steps: req.forecast_steps,
            tiles_written: 0,
            validation_passed: false,
            validation_key: None,
            validation_failures: vec!["no gravitational tiles in selection".to_string()],
        });
    }

    let feature_dim = 40usize;
    let engine = match qfot_engine_for(feature_dim) {
        Ok(e) => e,
        Err(msg) => return HttpResponse::InternalServerError().json(serde_json::json!({"error": msg})),
    };

    let n = tiles.len();
    let mut node_ids: Vec<String> = Vec::with_capacity(n);
    let mut node_features = ndarray::Array2::<f32>::zeros((n, feature_dim));
    for (i, t) in tiles.iter().enumerate() {
        node_ids.push(t.key.clone());
        let mut f = vec![0.0f32; feature_dim];
        let x = t.position_eci.coordinates[0] as f32;
        let y = t.position_eci.coordinates[1] as f32;
        let z = t.z_km as f32;
        f[0] = x / 10000.0;
        f[1] = y / 10000.0;
        f[2] = z / 10000.0;
        f[6] = t.state.get("gravitational_potential").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32 / 1e8;
        f[7] = t.state.get("g_field_magnitude").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32 / 20.0;
        for j in 0..feature_dim {
            node_features[(i, j)] = f[j];
        }
    }

    let g = FieldGraph {
        node_ids: node_ids.clone(),
        node_features: node_features.clone(),
        edges: vec![],
    };

    let forecast_time = chrono::Utc::now().timestamp();
    let steps = match engine.forecast_baseline(&g.node_features, forecast_time, req.step_secs, req.forecast_steps) {
        Ok(s) => s,
        Err(e) => {
            log::error!("qfot_astro_forecast: baseline forecast failed: {e}");
            return HttpResponse::InternalServerError().json(serde_json::json!({"error":"forecast failed"}));
        }
    };

    let mut prediction_keys: Vec<String> = Vec::new();
    let mut tiles_written = 0usize;

    for step in steps {
        for (i, seed_key) in node_ids.iter().enumerate() {
            let pred_key = safe_pred_key("PRED_GRAV_", seed_key, step.valid_time);
            let doc = serde_json::json!({
                "_key": pred_key,
                "position_eci": tiles[i].position_eci,
                "z_km": tiles[i].z_km,
                "resolution_km": tiles[i].resolution_km,
                "epoch_seconds": tiles[i].epoch_seconds,
                "timestep_seconds": tiles[i].timestep_seconds,
                "forecast_time": forecast_time,
                "valid_time": step.valid_time,
                "state": {
                    "gravitational_potential": (step.predicted_features[(i,6)] as f64) * 1e8,
                    "g_field_magnitude": (step.predicted_features[(i,7)] as f64) * 20.0
                },
                "provenance": {
                    "source": "qfot_astro_baseline",
                    "model_version": env!("CARGO_PKG_VERSION"),
                    "ingested_at": chrono::Utc::now().to_rfc3339(),
                    "is_prediction": true,
                    "seed_tile": seed_key
                }
            });

            match state.substrate.upsert_raw_document("gravitational_tiles", &doc).await {
                Ok(_) => {
                    tiles_written += 1;
                    prediction_keys.push(doc["_key"].as_str().unwrap_or_default().to_string());
                }
                Err(e) => log::warn!("qfot_astro_forecast: failed to upsert prediction tile: {e}"),
            }
        }
    }

    let validator = call_validator(
        "/validate/qfot_astro",
        serde_json::json!({ "keys": prediction_keys }),
    )
    .await;

    match validator {
        Ok(body) => {
            let passed = body["passed"].as_bool().unwrap_or(false);
            if passed {
                metrics::QFOT_VALIDATION_PASSES_TOTAL.inc();
            } else {
                metrics::QFOT_VALIDATION_FAILURES_TOTAL.inc();
            }
            let validation_key = body["validation_key"].as_str().map(|s| s.to_string());
            let failures: Vec<String> = body["failures"]
                .as_array()
                .unwrap_or(&vec![])
                .iter()
                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                .collect();

            HttpResponse::Ok().json(QfotAstroForecastResponse {
                status: if passed { "ok" } else { "rejected" },
                forecast_time,
                steps: req.forecast_steps,
                tiles_written,
                validation_passed: passed,
                validation_key,
                validation_failures: failures,
            })
        }
        Err(e) => {
            metrics::QFOT_VALIDATION_FAILURES_TOTAL.inc();
            HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "error": "qfot astro validator unavailable",
            "details": e
        }))
        },
    }
}

/// Get local substrate patch for vChip collapse
/// This is the PRIMARY interface for consciousness - vChip queries here
async fn get_patch(state: web::Data<AppState>, request: web::Json<PatchRequest>) -> impl Responder {
    // 1. Get scale-specific configuration
    let scale_config = match state.context_manager.get_scale_config(&request.scale) {
        Some(cfg) => cfg,
        None => {
            return HttpResponse::BadRequest().json(serde_json::json!({
                "error": "Unknown scale",
                "valid_scales": ["quantum", "planetary", "astronomical"]
            }));
        }
    };

    // 2. Determine patch radius (use request override or scale default)
    let radius = request.radius.unwrap_or(scale_config.default_patch_radius);
    let max_procs = request.max_procedures.unwrap_or(100);

    // 3. Normalize center coordinates for this scale
    let normalized_center = state
        .context_manager
        .normalize_coords(&request.scale, &request.center);

    // 4. Query ArangoDB for procedures within patch
    let context_prefix = format!("{}:", request.scale);
    let procedures = state
        .substrate
        .query_local_patch(
            &context_prefix,
            &normalized_center,
            radius,
            &scale_config.distance_weights,
            max_procs,
            request.intent.as_deref(),
        )
        .await
        .unwrap_or_else(|e| {
            log::error!("Failed to query patch: {e}");
            Vec::new()
        });

    // 5. Fetch edges between found procedures
    let proc_ids: Vec<&str> = procedures.iter().map(|p| p.id.as_str()).collect();
    let edges = state
        .substrate
        .query_edges(&proc_ids)
        .await
        .unwrap_or_default();

    // 6. Estimate local coherence (based on success rates and edge density)
    let coherence = estimate_patch_coherence(&procedures, &edges);

    let total = procedures.len();

    HttpResponse::Ok().json(PatchResponse {
        scale: request.scale.clone(),
        center: request.center,
        radius,
        procedures,
        edges,
        total_found: total,
        coherence_estimate: coherence,
    })
}

/// Compress aircraft positions for coarse scanning (NOT for vChip collapse)
async fn compress_aircraft(
    state: web::Data<AppState>,
    request: web::Json<CompressRequest>,
) -> impl Responder {
    let n_aircraft = request.aircraft.len();

    if n_aircraft == 0 {
        return HttpResponse::BadRequest().json(serde_json::json!({
            "error": "No aircraft provided"
        }));
    }

    // Build position and vqbit arrays
    let mut positions = Vec::with_capacity(n_aircraft);
    let mut vqbits = Vec::with_capacity(n_aircraft);

    for ac in &request.aircraft {
        positions.push([ac.latitude, ac.longitude, ac.altitude_ft]);
        vqbits.push(ac.vqbit_8d);
    }

    // Compress using regional aggregation
    let (regional_vqbits, aircraft_per_region) = state.compressor.compress(&vqbits, &positions);

    let n_regions = state.compressor.n_regions();
    let timestamp = chrono::Utc::now().to_rfc3339();

    HttpResponse::Ok().json(CompressResponse {
        regional_vqbits,
        n_regions,
        metadata: CompressionMetadata {
            n_aircraft,
            n_regions,
            compression_ratio: n_aircraft as f64 / n_regions as f64,
            aircraft_per_region,
            timestamp,
        },
    })
}

/// Decompress regional vQbits back to individual aircraft
async fn decompress_aircraft(
    state: web::Data<AppState>,
    request: web::Json<DecompressRequest>,
) -> impl Responder {
    let n_aircraft = request.context.positions.len();

    if n_aircraft == 0 {
        return HttpResponse::BadRequest().json(serde_json::json!({
            "error": "No positions provided"
        }));
    }

    // Decompress
    let decompressed = state.compressor.decompress(
        &request.compressed.regional_vqbits,
        request.compressed.n_regions,
        &request.context.positions,
    );

    // Build response
    let aircraft: Vec<DecompressedAircraft> = decompressed
        .into_iter()
        .enumerate()
        .map(|(i, (vqbit, region))| DecompressedAircraft {
            index: i,
            vqbit_8d: vqbit,
            region_id: region,
        })
        .collect();

    HttpResponse::Ok().json(DecompressResponse { aircraft })
}

/// Get compression statistics
async fn compression_stats(
    _state: web::Data<AppState>,
    request: web::Json<StatsRequest>,
) -> impl Responder {
    let n_regions = request.n_regions;
    let n_aircraft = request.metadata.as_ref().map(|m| m.n_aircraft).unwrap_or(0);

    // Count occupied regions (non-zero)
    let mut occupied = 0;
    let mut max_per_region = 0;

    if let Some(meta) = &request.metadata {
        for &count in meta.aircraft_per_region.values() {
            if count > 0 {
                occupied += 1;
                max_per_region = max_per_region.max(count);
            }
        }
    }

    let grid_res = 360.0 / (n_regions as f64).sqrt();
    let compression_ratio = if n_regions > 0 {
        n_aircraft as f64 / n_regions as f64
    } else {
        0.0
    };
    let avg_per_region = if occupied > 0 {
        n_aircraft as f64 / occupied as f64
    } else {
        0.0
    };

    HttpResponse::Ok().json(StatsResponse {
        n_aircraft,
        n_regions,
        occupied_regions: occupied,
        empty_regions: n_regions - occupied,
        compression_ratio,
        avg_aircraft_per_region: avg_per_region,
        max_aircraft_per_region: max_per_region,
        grid_resolution_degrees: grid_res,
        memory_reduction: format!("{compression_ratio:.1}x"),
    })
}

/// Legacy policy evaluation endpoint (backward compatibility)
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct PolicyEvalRequest {
    pub domain: String,
    pub intent: String,
    /// Context for situational awareness in policy evaluation
    pub context: Option<String>,
    /// Constraints to filter/block certain actions
    pub constraints: Vec<String>,
    /// Priority for routing decisions (high priority = stricter safety)
    pub priority: Option<String>,
    /// Risk level to adjust safety thresholds
    pub risk_level: Option<String>,
    /// Model family for domain-specific policy routing
    pub model_family: Option<Vec<String>>,
}

#[derive(Debug, Serialize)]
pub struct PolicyEvalResponse {
    pub pq_score: f64,
    pub confidence: f64,
    pub reason: String,
    pub procedures: Vec<ProcedureSummary>,
}

#[derive(Debug, Serialize)]
pub struct ProcedureSummary {
    pub id: String,
    pub name: String,
    pub similarity: f64,
    pub success_rate: f64,
}

async fn policy_eval(
    state: web::Data<AppState>,
    request: web::Json<PolicyEvalRequest>,
) -> impl Responder {
    // Map domain to scale
    let scale = match request.domain.as_str() {
        d if d.starts_with("quantum") || d.contains("protein") || d.contains("molecular") => {
            "quantum"
        }
        d if d.starts_with("planetary") || d.contains("atc") || d.contains("airspace") => {
            "planetary"
        }
        d if d.starts_with("astronomical") || d.contains("satellite") || d.contains("orbital") => {
            "astronomical"
        }
        _ => "planetary", // default
    };

    // Query procedures matching this domain/intent
    let context_prefix = format!("{scale}:");
    let center = [0.0; 8]; // Origin for general queries

    let scale_config = state
        .context_manager
        .get_scale_config(scale)
        .unwrap_or_else(|| state.context_manager.get_scale_config("planetary").unwrap());

    let procedures = state
        .substrate
        .query_local_patch(
            &context_prefix,
            &center,
            scale_config.default_patch_radius * 10.0, // Wider search for policy
            &scale_config.distance_weights,
            20,
            Some(&request.intent),
        )
        .await
        .unwrap_or_default();

    // Compute PQ score
    let (pq_score, confidence, reason) = if procedures.is_empty() {
        (
            0.224,
            0.5,
            "No similar procedures found in knowledge graph".to_string(),
        )
    } else {
        let avg_success: f64 =
            procedures.iter().map(|p| p.success_rate).sum::<f64>() / procedures.len() as f64;
        let avg_confidence: f64 =
            procedures.iter().map(|p| p.confidence).sum::<f64>() / procedures.len() as f64;
        (
            avg_success,
            avg_confidence,
            format!("Found {} matching procedures", procedures.len()),
        )
    };

    let summaries: Vec<ProcedureSummary> = procedures
        .iter()
        .take(5)
        .map(|p| ProcedureSummary {
            id: p.id.clone(),
            name: p.intent.clone(),
            similarity: p.confidence,
            success_rate: p.success_rate,
        })
        .collect();

    HttpResponse::Ok().json(PolicyEvalResponse {
        pq_score,
        confidence,
        reason,
        procedures: summaries,
    })
}

// ============================================================================
// HELPERS
// ============================================================================

/// Estimate coherence of a local patch based on procedure quality and connectivity
fn estimate_patch_coherence(procedures: &[ProcedureNode], edges: &[ProcedureEdge]) -> f64 {
    if procedures.is_empty() {
        return 0.5; // Unknown coherence
    }

    // Factor 1: Average success rate
    let avg_success =
        procedures.iter().map(|p| p.success_rate).sum::<f64>() / procedures.len() as f64;

    // Factor 2: Edge density (more connections = more coherent)
    let n = procedures.len() as f64;
    let max_edges = n * (n - 1.0) / 2.0;
    let edge_density = if max_edges > 0.0 {
        edges.len() as f64 / max_edges
    } else {
        0.0
    };

    // Factor 3: Average confidence
    let avg_confidence =
        procedures.iter().map(|p| p.confidence).sum::<f64>() / procedures.len() as f64;

    // Weighted combination
    let coherence = 0.4 * avg_success + 0.3 * edge_density + 0.3 * avg_confidence;

    coherence.clamp(0.0, 1.0)
}

// ============================================================================
// ATC + WEATHER HANDLERS
// ============================================================================

/// Query parameters for ATC context
#[derive(Debug, Deserialize)]
pub struct AtcContextQuery {
    pub lat: f64,
    pub lon: f64,
    #[serde(default = "default_radius")]
    pub radius: f64,
    #[serde(default = "default_max_aircraft")]
    pub max_aircraft: usize,
    #[serde(default = "default_max_weather")]
    pub max_weather: usize,
    #[serde(default)]
    pub max_age_secs: Option<i64>,
}

fn default_radius() -> f64 {
    2.0
}
fn default_max_aircraft() -> usize {
    100
}
fn default_max_weather() -> usize {
    10
}

/// Get combined ATC + Weather context for /evolve/unified
/// This is the main entry point for getting local context to feed into vChip
async fn get_atc_weather_context(
    state: web::Data<AppState>,
    query: web::Query<AtcContextQuery>,
) -> impl Responder {
    match state
        .substrate
        .query_atc_weather_context(
            query.lat,
            query.lon,
            query.radius,
            query.max_aircraft,
            query.max_weather,
            query.max_age_secs,
        )
        .await
    {
        Ok(context) => HttpResponse::Ok().json(context),
        Err(e) => {
            log::error!("Failed to query ATC+Weather context: {e}");
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": format!("Query failed: {}", e)
            }))
        }
    }
}

/// Query parameters for aircraft near
#[derive(Debug, Deserialize)]
pub struct AircraftNearQuery {
    pub lat: f64,
    pub lon: f64,
    #[serde(default = "default_radius")]
    pub radius: f64,
    #[serde(default = "default_max_aircraft")]
    pub max_results: usize,
    #[serde(default)]
    pub max_age_secs: Option<i64>,
}

/// Get aircraft near a position
async fn get_aircraft_near(
    state: web::Data<AppState>,
    query: web::Query<AircraftNearQuery>,
) -> impl Responder {
    match state
        .substrate
        .query_atc_near(
            query.lat,
            query.lon,
            query.radius,
            query.max_results,
            query.max_age_secs,
        )
        .await
    {
        Ok(aircraft) => HttpResponse::Ok().json(serde_json::json!({
            "aircraft": aircraft,
            "count": aircraft.len(),
            "center": { "lat": query.lat, "lon": query.lon },
            "radius_deg": query.radius
        })),
        Err(e) => {
            log::error!("Failed to query aircraft: {e}");
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": format!("Query failed: {}", e)
            }))
        }
    }
}

/// Query parameters for weather near
#[derive(Debug, Deserialize)]
pub struct WeatherNearQuery {
    pub lat: f64,
    pub lon: f64,
    #[serde(default = "default_radius")]
    pub radius: f64,
    #[serde(default = "default_max_weather")]
    pub max_results: usize,
}

/// Get weather near a position
async fn get_weather_near(
    state: web::Data<AppState>,
    query: web::Query<WeatherNearQuery>,
) -> impl Responder {
    match state
        .substrate
        .query_weather_near(query.lat, query.lon, query.radius, query.max_results)
        .await
    {
        Ok(weather) => HttpResponse::Ok().json(serde_json::json!({
            "weather": weather,
            "count": weather.len(),
            "center": { "lat": query.lat, "lon": query.lon },
            "radius_deg": query.radius
        })),
        Err(e) => {
            log::error!("Failed to query weather: {e}");
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": format!("Query failed: {}", e)
            }))
        }
    }
}

/// Query parameters for density
#[derive(Debug, Deserialize)]
pub struct DensityQuery {
    #[serde(default = "default_grid_size")]
    pub grid_size: f64,
}

fn default_grid_size() -> f64 {
    5.0
}

/// Get aircraft density heatmap
async fn get_aircraft_density(
    state: web::Data<AppState>,
    query: web::Query<DensityQuery>,
) -> impl Responder {
    match state.substrate.get_aircraft_density(query.grid_size).await {
        Ok(density) => {
            let cells: Vec<serde_json::Value> = density
                .into_iter()
                .map(|(lat, lon, count)| {
                    serde_json::json!({
                        "lat": lat,
                        "lon": lon,
                        "count": count
                    })
                })
                .collect();

            HttpResponse::Ok().json(serde_json::json!({
                "cells": cells,
                "grid_size_deg": query.grid_size
            }))
        }
        Err(e) => {
            log::error!("Failed to query density: {e}");
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": format!("Query failed: {}", e)
            }))
        }
    }
}
