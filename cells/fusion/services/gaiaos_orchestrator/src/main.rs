mod health_client;
mod model;

use actix_web::{web, App, HttpResponse, HttpServer, Responder};
use chrono::Utc;
use health_client::{HealthClient, OrchestratorConfig};
use log::info;
use model::SimpleHealthResponse;
use std::sync::Arc;

struct AppState {
    health_client: Arc<HealthClient>,
}

async fn root() -> impl Responder {
    HttpResponse::Ok().json(serde_json::json!({
        "status": "ok",
        "component": "gaiaos-orchestrator",
        "message": "Unified 8D ATC + Weather orchestrator online"
    }))
}

async fn health() -> impl Responder {
    HttpResponse::Ok().json(SimpleHealthResponse {
        status: "ok".to_string(),
        component: "gaiaos-orchestrator",
        timestamp: Utc::now(),
    })
}

async fn system_status(state: web::Data<AppState>) -> impl Responder {
    let status = state.health_client.gather_system_status().await;
    HttpResponse::Ok().json(status)
}

async fn cells_status(state: web::Data<AppState>) -> impl Responder {
    let status = state.health_client.gather_system_status().await;
    HttpResponse::Ok().json(status.cells)
}

async fn contexts_status(state: web::Data<AppState>) -> impl Responder {
    let status = state.health_client.gather_system_status().await;
    HttpResponse::Ok().json(status.contexts)
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init();

    info!("╔════════════════════════════════════════════════════════════╗");
    info!("║      GAIAOS ORCHESTRATOR v0.1.0                            ║");
    info!("║      Unified System Status + Cell Health Monitor           ║");
    info!("╚════════════════════════════════════════════════════════════╝");

    let cfg = OrchestratorConfig {
        akg_url: std::env::var("AKG_URL").unwrap_or_else(|_| "http://akg-gnn:8700".to_string()),
        vchip_url: std::env::var("VCHIP_URL").unwrap_or_else(|_| "http://vchip:8001".to_string()),
        core_url: std::env::var("CORE_URL")
            .unwrap_or_else(|_| "http://core-agent:8804".to_string()),
        virtue_url: std::env::var("VIRTUE_URL")
            .unwrap_or_else(|_| "http://virtue-engine:8810".to_string()),
        franklin_url: std::env::var("FRANKLIN_URL")
            .unwrap_or_else(|_| "http://franklin-guardian:8803".to_string()),
        weather_ingest_url: std::env::var("WEATHER_URL")
            .unwrap_or_else(|_| "http://weather-ingest:8750".to_string()),
    };

    info!("Configuration:");
    info!("  AKG URL: {}", cfg.akg_url);
    info!("  vChip URL: {}", cfg.vchip_url);
    info!("  Core URL: {}", cfg.core_url);
    info!("  Virtue URL: {}", cfg.virtue_url);
    info!("  Franklin URL: {}", cfg.franklin_url);
    info!("  Weather URL: {}", cfg.weather_ingest_url);

    let health_client = Arc::new(HealthClient::new(cfg));
    let state = web::Data::new(AppState { health_client });

    let bind_addr =
        std::env::var("ORCH_BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:8815".to_string());

    info!("🧠 Orchestrator listening on http://{}", bind_addr);

    HttpServer::new(move || {
        App::new()
            .app_data(state.clone())
            .route("/", web::get().to(root))
            .route("/health", web::get().to(health))
            .route("/status/system", web::get().to(system_status))
            .route("/status/cells", web::get().to(cells_status))
            .route("/status/contexts", web::get().to(contexts_status))
    })
    .bind(bind_addr)?
    .run()
    .await
}

