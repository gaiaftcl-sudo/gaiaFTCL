mod dns_surface;
mod godaddy;
mod provider;
mod readonly;
mod reconcile;
mod secrets;

use anyhow::{Context, Result};
use axum::{
    extract::State,
    http::StatusCode,
    response::Json,
    routing::{get, post},
    Router,
};
use dns_surface::{build_dns_surface_dying_json, build_dns_surface_json};
use provider::DnsProvider;
use reconcile::{CycleEvidence, Reconciler, ReconcileStatus};
use secrets::Secrets;
use std::fs;
use std::sync::Arc;
use tokio::sync::RwLock;
use tower_http::trace::TraceLayer;

#[derive(Clone)]
struct AppState {
    reconciler: Arc<RwLock<Reconciler>>,
    last_evidence: Arc<RwLock<Option<CycleEvidence>>>,
    last_ok_ts: Arc<RwLock<Option<String>>>,
    reconcile_token: Option<String>,
    nats: Arc<async_nats::Client>,
    cell_id: String,
    expected_ip: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    tracing::info!("🌐 DNS Authority starting...");

    // Load configuration
    dotenvy::dotenv().ok();

    let secrets = Secrets::load()?;

    let domain = std::env::var("DNS_DOMAIN").unwrap_or_else(|_| "gaiaftcl.com".to_string());
    let ttl: u32 = std::env::var("DNS_TTL")
        .unwrap_or_else(|_| "600".to_string())
        .parse()
        .context("Invalid DNS_TTL")?;
    let head_public_ip = secrets.get("HEAD_PUBLIC_IP").map(|s| s.to_string());
    let reconcile_token = secrets.get("DNS_RECONCILE_TOKEN").map(|s| s.to_string());

    // Create provider
    let provider: Arc<dyn DnsProvider> = if secrets.has_godaddy_credentials() {
        let api_key = secrets.get_required("GODADDY_API_KEY")?;
        let api_secret = secrets.get_required("GODADDY_API_SECRET")?;
        
        tracing::info!("✅ GoDaddy credentials found - using GoDaddy provider");
        Arc::new(godaddy::GoDaddyProvider::new(api_key, api_secret))
    } else {
        tracing::warn!("⚠️  No GoDaddy credentials - running in READ_ONLY mode");
        Arc::new(readonly::ReadOnlyProvider)
    };

    if head_public_ip.is_none() {
        tracing::warn!("⚠️  HEAD_PUBLIC_IP not set - will run in READ_ONLY mode");
    }

    let reconciler = Arc::new(RwLock::new(Reconciler::new(
        provider.clone(),
        domain.clone(),
        ttl,
        head_public_ip.clone(),
    )));

    let cell_id = std::env::var("CELL_ID").unwrap_or_else(|_| "unknown-cell".to_string());
    let expected_ip = std::env::var("CELL_IP")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .or_else(|| head_public_ip.clone())
        .unwrap_or_default();

    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://gaiaftcl-nats:4222".to_string());
    let nats_client = Arc::new(connect_nats_forever(&nats_url).await);

    let last_evidence = Arc::new(RwLock::new(None));
    let last_ok_ts = Arc::new(RwLock::new(None));

    let state = AppState {
        reconciler: reconciler.clone(),
        last_evidence: last_evidence.clone(),
        last_ok_ts: last_ok_ts.clone(),
        reconcile_token,
        nats: nats_client.clone(),
        cell_id: cell_id.clone(),
        expected_ip: expected_ip.clone(),
    };

    // Create evidence directory
    fs::create_dir_all("/opt/gaia/evidence/dns_authority")?;

    // Start background reconciliation loop
    let reconciler_clone = reconciler.clone();
    let last_evidence_clone = last_evidence.clone();
    let last_ok_ts_clone = last_ok_ts.clone();
    let nc_loop = (*nats_client).clone();
    let cid_loop = cell_id.clone();
    let eip_loop = expected_ip.clone();

    tokio::spawn(async move {
        reconciliation_loop(
            reconciler_clone,
            last_evidence_clone,
            last_ok_ts_clone,
            nc_loop,
            cid_loop,
            eip_loop,
        )
        .await;
    });

    // Build router
    let app = Router::new()
        .route("/health", get(health))
        .route("/api/dns/status", get(dns_status))
        .route("/api/dns/reconcile", post(dns_reconcile))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    // Start server
    let port = std::env::var("DNS_AUTHORITY_PORT")
        .unwrap_or_else(|_| "8804".to_string())
        .parse::<u16>()
        .context("Invalid DNS_AUTHORITY_PORT")?;

    let addr = format!("0.0.0.0:{}", port);
    tracing::info!("🚀 DNS Authority listening on {}", addr);
    tracing::info!("   Status: http://127.0.0.1:{}/api/dns/status", port);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

async fn connect_nats_forever(url: &str) -> async_nats::Client {
    loop {
        match async_nats::connect(url).await {
            Ok(c) => {
                tracing::info!("NATS connected (DNS surface): {}", url);
                return c;
            }
            Err(e) => {
                tracing::warn!("NATS connect failed, retry in 3s: {}", e);
                tokio::time::sleep(std::time::Duration::from_secs(3)).await;
            }
        }
    }
}

async fn publish_dns_surface_nc(nc: &async_nats::Client, cell_id: &str, value: &serde_json::Value) {
    let subject = format!("gaiaftcl.dns.surface.{}", cell_id);
    let payload = match serde_json::to_vec(value) {
        Ok(b) => b,
        Err(e) => {
            tracing::error!("dns surface serialize: {}", e);
            return;
        }
    };
    if let Err(e) = nc.publish(subject, payload.into()).await {
        tracing::warn!("dns surface publish failed: {}", e);
    }
}

async fn reconciliation_loop(
    reconciler: Arc<RwLock<Reconciler>>,
    last_evidence: Arc<RwLock<Option<CycleEvidence>>>,
    last_ok_ts: Arc<RwLock<Option<String>>>,
    nc: async_nats::Client,
    cell_id: String,
    expected_ip: String,
) {
    let interval_secs = std::env::var("DNS_RECONCILE_INTERVAL_SECONDS")
        .unwrap_or_else(|_| "300".to_string())
        .parse::<u64>()
        .unwrap_or(300);

    loop {
        tracing::info!("🔄 Starting DNS reconciliation cycle");

        let evidence = {
            let mut reconciler = reconciler.write().await;
            match reconciler.reconcile().await {
                Ok(evidence) => evidence,
                Err(e) => {
                    tracing::error!("Reconciliation failed: {}", e);
                    let (last_r, last_d) = {
                        let g = last_evidence.read().await;
                        match g.as_ref() {
                            Some(ev) => (
                                dns_surface::pick_resolved_ip(ev),
                                ev.observed.iter().any(|o| !o.match_desired),
                            ),
                            None => (String::new(), false),
                        }
                    };
                    let body = build_dns_surface_dying_json(
                        &cell_id,
                        &expected_ip,
                        &format!("reconcile_error: {}", e),
                        &last_r,
                        last_d,
                    );
                    publish_dns_surface_nc(&nc, &cell_id, &body).await;
                    tokio::time::sleep(tokio::time::Duration::from_secs(interval_secs)).await;
                    continue;
                }
            }
        };

        // Update last_ok_ts if valid
        if evidence.status == ReconcileStatus::Valid {
            let mut last_ok = last_ok_ts.write().await;
            *last_ok = Some(evidence.ts_end.clone());
        }

        // Write evidence
        if let Err(e) = write_evidence(&evidence).await {
            tracing::error!("Failed to write evidence: {}", e);
        }

        // Update last evidence
        {
            let mut last = last_evidence.write().await;
            *last = Some(evidence.clone());
        }

        tracing::info!(
            "✅ Cycle complete: status={:?}, consecutive_failures={}",
            evidence.status,
            evidence.consecutive_failures
        );

        let surface = build_dns_surface_json(&evidence, &cell_id, &expected_ip);
        publish_dns_surface_nc(&nc, &cell_id, &surface).await;

        tokio::time::sleep(tokio::time::Duration::from_secs(interval_secs)).await;
    }
}

async fn write_evidence(evidence: &CycleEvidence) -> Result<()> {
    let date = chrono::Utc::now().format("%Y%m%d").to_string();
    let dir = format!("/opt/gaia/evidence/dns_authority/{}", date);
    fs::create_dir_all(&dir)?;

    let ts = chrono::Utc::now().format("%Y%m%dT%H%M%S").to_string();
    let filename = format!("{}/cycle_{}.json", dir, ts);
    let temp_filename = format!("{}.tmp", filename);

    let content = serde_json::to_string_pretty(evidence)?;
    fs::write(&temp_filename, content)?;
    fs::rename(temp_filename, filename)?;

    Ok(())
}

async fn health() -> &'static str {
    "OK"
}

async fn dns_status(State(state): State<AppState>) -> Json<serde_json::Value> {
    let last_evidence = state.last_evidence.read().await;
    let last_ok_ts = state.last_ok_ts.read().await;

    match last_evidence.as_ref() {
        Some(evidence) => {
            let date = chrono::Utc::now().format("%Y%m%d").to_string();
            let last_evidence_file = format!(
                "/opt/gaia/evidence/dns_authority/{}/cycle_{}.json",
                date,
                evidence.ts_end.replace([':', '-'], "").replace('Z', "")
            );

            Json(serde_json::json!({
                "status": evidence.status,
                "desired_ip": evidence.desired.value,
                "observed": evidence.observed.iter().map(|obs| serde_json::json!({
                    "resolver": obs.resolver,
                    "values": obs.values,
                    "match": obs.match_desired
                })).collect::<Vec<_>>(),
                "last_ok_ts": last_ok_ts.as_ref(),
                "consecutive_failures": evidence.consecutive_failures,
                "reason_codes": evidence.reason_codes,
                "last_evidence_file": last_evidence_file,
                "provider_kind": evidence.provider.kind
            }))
        }
        None => Json(serde_json::json!({
            "status": "STARTING",
            "reason": "No cycles completed yet"
        })),
    }
}

async fn dns_reconcile(State(state): State<AppState>) -> Result<Json<serde_json::Value>, StatusCode> {
    // Check token if configured
    if let Some(required_token) = &state.reconcile_token {
        let provided_token = std::env::var("DNS_RECONCILE_TOKEN_PROVIDED").ok();
        if provided_token.as_ref() != Some(required_token) {
            tracing::warn!("Unauthorized reconcile attempt");
            return Err(StatusCode::UNAUTHORIZED);
        }
    }

    tracing::info!("Manual reconcile triggered");

    let evidence = {
        let mut reconciler = state.reconciler.write().await;
        match reconciler.reconcile().await {
            Ok(evidence) => evidence,
            Err(e) => {
                tracing::error!("Manual reconciliation failed: {}", e);
                return Err(StatusCode::INTERNAL_SERVER_ERROR);
            }
        }
    };

    // Update state
    if evidence.status == ReconcileStatus::Valid {
        let mut last_ok = state.last_ok_ts.write().await;
        *last_ok = Some(evidence.ts_end.clone());
    }

    if let Err(e) = write_evidence(&evidence).await {
        tracing::error!("Failed to write evidence: {}", e);
    }

    {
        let mut last = state.last_evidence.write().await;
        *last = Some(evidence.clone());
    }

    let surface = build_dns_surface_json(&evidence, &state.cell_id, &state.expected_ip);
    publish_dns_surface_nc(state.nats.as_ref(), &state.cell_id, &surface).await;

    Ok(Json(serde_json::json!({
        "success": true,
        "status": evidence.status,
        "consecutive_failures": evidence.consecutive_failures
    })))
}
