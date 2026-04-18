mod arangodb_client;
mod model;

use actix_web::{web, App, HttpResponse, HttpServer, Responder};
use arangodb_client::ArangoClient;
use chrono::Utc;
use log::{info, warn};
use model::{BboxQuery, ErrorResponse, PerceptionReceipt, PerceptionUpdate};
use std::sync::Arc;
use uuid::Uuid;

const INDEX_HTML: &str = include_str!("../static/index.html");
const PHYSICS_HTML: &str = include_str!("../static/physics.html");

struct AppState {
    arango: Arc<ArangoClient>,
}

async fn index() -> impl Responder {
    HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(INDEX_HTML)
}

async fn physics() -> impl Responder {
    HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(PHYSICS_HTML)
}

async fn health() -> impl Responder {
    HttpResponse::Ok().json(serde_json::json!({
        "status": "ok",
        "component": "gaiaos-atc-view",
        "timestamp": Utc::now(),
    }))
}

fn normalize_bbox(q: &BboxQuery) -> (f64, f64, f64, f64) {
    let lamin = q.lamin.unwrap_or(-90.0);
    let lamax = q.lamax.unwrap_or(90.0);
    let lomin = q.lomin.unwrap_or(-180.0);
    let lomax = q.lomax.unwrap_or(180.0);
    (lamin, lamax, lomin, lomax)
}

async fn api_atc(state: web::Data<AppState>, query: web::Query<BboxQuery>) -> impl Responder {
    let (lamin, lamax, lomin, lomax) = normalize_bbox(&query);

    let res = state
        .arango
        .query_world_patches("planetary:atc_live", lamin, lamax, lomin, lomax)
        .await;

    match res {
        Ok(result) => HttpResponse::Ok().json(serde_json::json!({
            "status": "ok",
            "count": result.len(),
            "context": "planetary:atc_live",
            "lamin": lamin,
            "lamax": lamax,
            "lomin": lomin,
            "lomax": lomax,
            "patches": result
        })),
        Err(e) => HttpResponse::BadGateway().json(ErrorResponse {
            status: "error".to_string(),
            error: e.to_string(),
        }),
    }
}

async fn api_weather(state: web::Data<AppState>, query: web::Query<BboxQuery>) -> impl Responder {
    let (lamin, lamax, lomin, lomax) = normalize_bbox(&query);

    let res = state
        .arango
        .query_world_patches("planetary:weather", lamin, lamax, lomin, lomax)
        .await;

    match res {
        Ok(result) => HttpResponse::Ok().json(serde_json::json!({
            "status": "ok",
            "count": result.len(),
            "context": "planetary:weather",
            "lamin": lamin,
            "lamax": lamax,
            "lomin": lomin,
            "lomax": lomax,
            "patches": result
        })),
        Err(e) => HttpResponse::BadGateway().json(ErrorResponse {
            status: "error".to_string(),
            error: e.to_string(),
        }),
    }
}

async fn api_trajectories(state: web::Data<AppState>, query: web::Query<BboxQuery>) -> impl Responder {
    let (lamin, lamax, lomin, lomax) = normalize_bbox(&query);

    let res = state
        .arango
        .query_world_patches("planetary:atc_trajectory_ensemble", lamin, lamax, lomin, lomax)
        .await;

    match res {
        Ok(result) => HttpResponse::Ok().json(serde_json::json!({
            "status": "ok",
            "count": result.len(),
            "context": "planetary:atc_trajectory_ensemble",
            "lamin": lamin,
            "lamax": lamax,
            "lomin": lomin,
            "lomax": lomax,
            "patches": result
        })),
        Err(e) => HttpResponse::BadGateway().json(ErrorResponse {
            status: "error".to_string(),
            error: e.to_string(),
        }),
    }
}

async fn api_perceptions(
    state: web::Data<AppState>,
    payload: web::Json<PerceptionUpdate>,
) -> impl Responder {
    let receipt_id = Uuid::new_v4().to_string();
    let server_timestamp_ms = Utc::now().timestamp_millis() as f64;
    let count = payload.perceptions.len();

    info!(
        "Received perception update: frame_id={}, count={}, timestamp_ms={}",
        payload.frame_id, count, payload.timestamp_ms
    );

    // Store perception snapshot in ArangoDB
    let doc = serde_json::json!({
        "_key": format!("perception_{}_{}", payload.frame_id, receipt_id),
        "frame_id": payload.frame_id,
        "client_timestamp_ms": payload.timestamp_ms,
        "server_timestamp_ms": server_timestamp_ms,
        "receipt_id": receipt_id,
        "perceptions": payload.perceptions,
        "viewport": payload.viewport,
        "camera": payload.camera,
        "count": count,
        "schema": "gaiaos.atc.perception_snapshot/1.0"
    });

    match state.arango.insert_document("perception_snapshots", &doc).await {
        Ok(_) => {
            info!("Stored perception snapshot: {}", receipt_id);
            HttpResponse::Ok().json(PerceptionReceipt {
                accepted: true,
                receipt_id,
                frame_id: payload.frame_id,
                count,
                server_timestamp_ms,
                warnings: None,
            })
        }
        Err(e) => {
            warn!("Failed to store perception snapshot: {}", e);
            HttpResponse::InternalServerError().json(ErrorResponse {
                status: "error".to_string(),
                error: format!("Failed to store perception: {}", e),
            })
        }
    }
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init();

    info!("╔════════════════════════════════════════════════════════════╗");
    info!("║      GAIAOS ATC + WEATHER GLOBE VIEWER v0.1.0              ║");
    info!("║      Live world_patches visualization                      ║");
    info!("╚════════════════════════════════════════════════════════════╝");

    let arango_url =
        std::env::var("ARANGO_URL").unwrap_or_else(|_| "http://arangodb:8529".to_string());
    let db_name = std::env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string());
    let collection = std::env::var("ARANGO_WORLD_PATCHES_COLLECTION")
        .unwrap_or_else(|_| "world_patches".to_string());

    info!("ArangoDB: {}", arango_url);
    info!("Database: {}", db_name);
    info!("Collection: {}", collection);

    let arango =
        ArangoClient::new(&arango_url, &db_name, &collection).expect("Failed to init ArangoClient");

    let state = web::Data::new(AppState {
        arango: Arc::new(arango),
    });

    let bind_addr =
        std::env::var("ATC_VIEW_BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:8820".to_string());

    info!("🌍 ATC View listening on http://{}", bind_addr);

    HttpServer::new(move || {
        App::new()
            .app_data(state.clone())
            .route("/", web::get().to(index))
            .route("/physics", web::get().to(physics))
            .route("/physics.html", web::get().to(physics))
            .route("/health", web::get().to(health))
            .route("/api/atc", web::get().to(api_atc))
            .route("/api/weather", web::get().to(api_weather))
            .route("/api/trajectories", web::get().to(api_trajectories))
            .route("/api/perceptions", web::post().to(api_perceptions))
    })
    .bind(bind_addr)?
    .run()
    .await
}

