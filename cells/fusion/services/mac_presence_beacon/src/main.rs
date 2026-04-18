use actix_web::{web, App, HttpResponse, HttpServer, Responder};
use chrono::{DateTime, Timelike, Utc};
use log::{error, info};
use serde::Serialize;
use std::env;
use std::sync::Arc;
use tokio::time::{sleep, Duration};
use uuid::Uuid;

#[derive(Clone)]
struct Config {
    arango_url: String,
    arango_db: String,
    arango_user: String,
    arango_password: String,
    collection: String,
    cell_id: String,
    observer_name: String,
    lat: f64,
    lon: f64,
    alt_m: f64,
    interval_sec: u64,
    context: String,
    scale: String,
}

#[derive(Debug, Serialize)]
struct WorldPatch {
    #[serde(skip_serializing_if = "Option::is_none")]
    _key: Option<String>,
    scale: String,
    context: String,
    center_lat: f64,
    center_lon: f64,
    center_alt_m: f64,
    timestamp: DateTime<Utc>,
    d_vec: [f64; 8],
    observer: ObserverMeta,
}

#[derive(Debug, Serialize)]
struct ObserverMeta {
    cell_id: String,
    observer_name: String,
    host: String,
    kind: String,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: &'static str,
    service: &'static str,
    cell_id: String,
    context: String,
    observer_name: String,
    lat: f64,
    lon: f64,
}

struct AppState {
    config: Config,
}

async fn health_handler(state: web::Data<AppState>) -> impl Responder {
    HttpResponse::Ok().json(HealthResponse {
        status: "ok",
        service: "mac-presence-beacon",
        cell_id: state.config.cell_id.clone(),
        context: state.config.context.clone(),
        observer_name: state.config.observer_name.clone(),
        lat: state.config.lat,
        lon: state.config.lon,
    })
}

fn load_config() -> Config {
    let arango_url =
        env::var("ARANGO_URL").unwrap_or_else(|_| "http://arangodb:8529".to_string());
    let arango_db = env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string());
    let arango_user = env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string());
    let arango_password = env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string());
    let collection = env::var("ARANGO_WORLD_PATCHES_COLLECTION")
        .unwrap_or_else(|_| "world_patches".to_string());

    let cell_id = env::var("CELL_ID").unwrap_or_else(|_| "cell3-mac".to_string());
    let observer_name = env::var("OBSERVER_NAME").unwrap_or_else(|_| "Rick".to_string());

    let lat = env::var("OBSERVER_LAT")
        .ok()
        .and_then(|s| s.parse::<f64>().ok())
        .unwrap_or(41.6);
    let lon = env::var("OBSERVER_LON")
        .ok()
        .and_then(|s| s.parse::<f64>().ok())
        .unwrap_or(-71.9);
    let alt_m = env::var("OBSERVER_ALT_M")
        .ok()
        .and_then(|s| s.parse::<f64>().ok())
        .unwrap_or(50.0);

    let interval_sec = env::var("BEACON_INTERVAL_SEC")
        .ok()
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(60);

    let context = env::var("OBSERVER_CONTEXT")
        .unwrap_or_else(|_| "planetary:observer_cell3".to_string());
    let scale = env::var("OBSERVER_SCALE").unwrap_or_else(|_| "planetary".to_string());

    Config {
        arango_url,
        arango_db,
        arango_user,
        arango_password,
        collection,
        cell_id,
        observer_name,
        lat,
        lon,
        alt_m,
        interval_sec,
        context,
        scale,
    }
}

fn compute_8d(lat: f64, lon: f64, alt_m: f64, ts: DateTime<Utc>) -> [f64; 8] {
    let d0: f64 = lon / 180.0; // [-1,1]
    let d1: f64 = lat / 90.0;  // [-1,1]
    let d2: f64 = (alt_m / 15000.0).clamp(0.0, 1.0);

    let seconds = ts.num_seconds_from_midnight() as f64;
    let d3: f64 = (seconds / 86400.0).clamp(0.0, 1.0);

    let d4: f64 = 0.15; // intent: qualification/observation
    let d5: f64 = 0.05; // low risk
    let d6: f64 = (1.0_f64 - d5 * 0.7).clamp(0.0, 1.0);
    let d7: f64 = 0.1; // small but non-zero uncertainty

    [d0, d1, d2, d3, d4, d5, d6, d7]
}

async fn send_patch(config: &Config) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let ts = Utc::now();
    let d_vec = compute_8d(config.lat, config.lon, config.alt_m, ts);

    let host = hostname::get()
        .ok()
        .and_then(|h| h.into_string().ok())
        .unwrap_or_else(|| "unknown-host".to_string());

    let patch = WorldPatch {
        _key: Some(Uuid::new_v4().to_string()),
        scale: config.scale.clone(),
        context: config.context.clone(),
        center_lat: config.lat,
        center_lon: config.lon,
        center_alt_m: config.alt_m,
        timestamp: ts,
        d_vec,
        observer: ObserverMeta {
            cell_id: config.cell_id.clone(),
            observer_name: config.observer_name.clone(),
            host,
            kind: "mac_presence_beacon".to_string(),
        },
    };

    let url = format!(
        "{base}/_db/{db}/_api/document/{coll}",
        base = config.arango_url.trim_end_matches('/'),
        db = config.arango_db,
        coll = config.collection
    );

    let client = reqwest::Client::builder()
        .user_agent("GaiaOS-MacPresenceBeacon/0.1")
        .build()?;

    let resp = client
        .post(&url)
        .basic_auth(&config.arango_user, Some(&config.arango_password))
        .json(&patch)
        .send()
        .await?;

    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(format!("Arango insert error {}: {}", status, text).into());
    }

    info!(
        "📍 Sent presence patch: context={} lat={:.4} lon={:.4} alt_m={:.0} observer={}",
        patch.context, patch.center_lat, patch.center_lon, patch.center_alt_m, patch.observer.observer_name
    );

    Ok(())
}

async fn beacon_loop(config: Arc<Config>) {
    loop {
        if let Err(e) = send_patch(&config).await {
            error!("Failed to send presence patch: {e}");
        }
        sleep(Duration::from_secs(config.interval_sec)).await;
    }
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init();
    let config = Arc::new(load_config());

    info!("╔════════════════════════════════════════════════════════════╗");
    info!("║      GAIAOS MAC PRESENCE BEACON v0.1.0                     ║");
    info!("║      Cell 3 Observer → 8D World Patches                    ║");
    info!("╚════════════════════════════════════════════════════════════╝");
    info!(
        "Cell ID: {} | Context: {} | Observer: {}",
        config.cell_id, config.context, config.observer_name
    );
    info!(
        "Location: lat={:.4}, lon={:.4}, alt_m={:.0}",
        config.lat, config.lon, config.alt_m
    );
    info!(
        "ArangoDB: {}/_db/{}/{}",
        config.arango_url, config.arango_db, config.collection
    );
    info!("Beacon interval: {}s", config.interval_sec);

    let beacon_cfg = config.clone();
    tokio::spawn(async move {
        beacon_loop(beacon_cfg).await;
    });

    let app_state = web::Data::new(AppState {
        config: (*config).clone(),
    });

    info!("🌍 Mac Presence Beacon listening on http://0.0.0.0:8760");

    HttpServer::new(move || {
        App::new()
            .app_data(app_state.clone())
            .route("/health", web::get().to(health_handler))
    })
    .bind("0.0.0.0:8760")?
    .run()
    .await
}

