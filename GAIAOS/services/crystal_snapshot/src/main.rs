mod arangodb_client;
mod model;

use actix_web::{web, App, HttpResponse, HttpServer, Responder, middleware};
use actix_cors::Cors;
use arangodb_client::ArangoClient;
use chrono::{Duration, Utc};
use log::{error, info};
use model::{HealthResponse, SnapshotRequest, SnapshotResponse};
use std::env;
use std::sync::Arc;

struct AppState {
    arango: Arc<ArangoClient>,
}

async fn health_handler() -> impl Responder {
    HttpResponse::Ok().json(HealthResponse {
        status: "ok",
        service: "crystal-snapshot",
        info: "GaiaOS Crystal Snapshot - Show me what the crystal saw here",
    })
}

async fn snapshot_handler(
    state: web::Data<AppState>,
    payload: web::Json<SnapshotRequest>,
) -> impl Responder {
    let req = payload.into_inner();
    let center_lat = req.lat;
    let center_lon = req.lon;
    let radius_km = req.radius_km;

    let now = Utc::now();
    let t_min = now - Duration::seconds(req.seconds_back);
    let t_max = now + Duration::seconds(req.seconds_forward);

    info!(
        "🔮 Crystal snapshot request: lat={:.4}, lon={:.4}, radius_km={:.0}, window=[{}, {}]",
        center_lat, center_lon, radius_km, t_min, t_max
    );

    let atc_res = state
        .arango
        .query_atc_patches(center_lat, center_lon, radius_km, t_min, t_max)
        .await;
    let weather_res = state
        .arango
        .query_weather_patches(center_lat, center_lon, radius_km, t_min, t_max)
        .await;
    let observer_res = state
        .arango
        .query_observer_patches(center_lat, center_lon, radius_km, t_min, t_max)
        .await;
    let conflict_res = state
        .arango
        .query_conflict_patches(center_lat, center_lon, radius_km, t_min, t_max)
        .await;

    let atc = match atc_res {
        Ok(v) => v,
        Err(e) => {
            error!("ATC query failed: {e}");
            Vec::new()
        }
    };

    let weather = match weather_res {
        Ok(v) => v,
        Err(e) => {
            error!("Weather query failed: {e}");
            Vec::new()
        }
    };

    let observers = match observer_res {
        Ok(v) => v,
        Err(e) => {
            error!("Observer query failed: {e}");
            Vec::new()
        }
    };

    let conflicts = match conflict_res {
        Ok(v) => v,
        Err(e) => {
            error!("Conflict query failed: {e}");
            Vec::new()
        }
    };

    info!(
        "🔮 Crystal snapshot result: {} ATC, {} weather, {} observers, {} conflicts",
        atc.len(), weather.len(), observers.len(), conflicts.len()
    );

    let resp = SnapshotResponse {
        center_lat,
        center_lon,
        radius_km,
        t_min,
        t_max,
        atc_count: atc.len(),
        weather_count: weather.len(),
        observer_count: observers.len(),
        conflict_count: conflicts.len(),
        atc,
        weather,
        observers,
        conflicts,
    };

    HttpResponse::Ok().json(resp)
}

/// GET version of snapshot for simpler testing
async fn snapshot_get_handler(
    state: web::Data<AppState>,
    query: web::Query<SnapshotRequest>,
) -> impl Responder {
    let req = query.into_inner();
    let payload = web::Json(req);
    snapshot_handler(state, payload).await
}

fn load_arango_config() -> (String, String, String, String, String) {
    let arango_url =
        env::var("ARANGO_URL").unwrap_or_else(|_| "http://arangodb:8529".to_string());
    let db_name = env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string());
    let collection =
        env::var("ARANGO_WORLD_PATCHES_COLLECTION").unwrap_or_else(|_| "world_patches".to_string());
    let user = env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string());
    let password = env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string());
    (arango_url, db_name, collection, user, password)
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init();
    let (arango_url, db_name, collection, user, password) = load_arango_config();

    info!("╔════════════════════════════════════════════════════════════╗");
    info!("║      GAIAOS CRYSTAL SNAPSHOT v0.1.0                        ║");
    info!("║      Show me what the crystal saw here                     ║");
    info!("╚════════════════════════════════════════════════════════════╝");
    info!(
        "ArangoDB: {}/_db/{}/{}",
        arango_url, db_name, collection
    );

    let arango_client = ArangoClient::new(&arango_url, &db_name, &collection, &user, &password)
        .expect("Failed to initialize Arango client");
    let state = web::Data::new(AppState {
        arango: Arc::new(arango_client),
    });

    info!("🔮 Crystal Snapshot Service listening on http://0.0.0.0:8765");

    HttpServer::new(move || {
        let cors = Cors::default()
            .allow_any_origin()
            .allow_any_method()
            .allow_any_header()
            .max_age(3600);

        App::new()
            .wrap(cors)
            .app_data(state.clone())
            .route("/health", web::get().to(health_handler))
            .route("/crystal/snapshot", web::post().to(snapshot_handler))
            .route("/crystal/snapshot", web::get().to(snapshot_get_handler))
    })
    .bind("0.0.0.0:8765")?
    .run()
    .await
}

