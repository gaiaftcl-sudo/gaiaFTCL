//! GaiaFTCL UI Server
//! 
//! Serves the MkDocs Portal and provides API endpoints for:
//! - Wallet authentication & onboarding
//! - Domain registry
//! - Projection types registry
//! - WebSocket session for perception/projection
//! - Founder Command Channel

use axum::{
    body::Body,
    extract::{Path, RawQuery, State},
    http::{Request, StatusCode},
    middleware,
    response::{Html, IntoResponse},
    routing::{any, get, post},
    Router,
};
use futures_util::StreamExt;
use http::header;
use http_body_util::BodyExt;
use std::{env, net::SocketAddr, path::PathBuf, sync::Arc};
use tower_http::{cors::CorsLayer, services::ServeDir, trace::TraceLayer};
use tracing::{error, info, warn};

mod api;
mod ws;

use crate::api::config::IDENTITY;

/// Application state shared across handlers
#[derive(Clone)]
pub struct AppState {
    /// Backend gateway URL for legacy /v1/* proxying
    pub backend_base: String,
    /// Google OAuth Client ID
    pub google_client_id: String,
    /// Google OAuth Client Secret
    pub google_client_secret: String,
    /// Google OAuth Redirect URI
    pub google_redirect_uri: String,
    /// JWT Secret
    pub jwt_secret: String,
    /// NATS client for inter-service communication
    pub nats_client: Option<async_nats::Client>,
}

#[tokio::main]
async fn main() {
    // Init logging
    tracing_subscriber::fmt()
        .with_env_filter(
            env::var("RUST_LOG")
                .unwrap_or_else(|_| "gaiaos_ui=info,tower_http=info,axum::rejection=trace".into()),
        )
        .init();

    // UI port (default 3000)
    let port: u16 = env::var("GAIAOS_UI_PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(3000);

    // Gateway base URL (default: local quantum-facade on 8900)
    let backend_base =
        env::var("GAIAOS_GATEWAY_URL").unwrap_or_else(|_| "http://127.0.0.1:8900".to_string());

    // Google OAuth config
    let google_client_id =
        env::var("GOOGLE_CLIENT_ID").unwrap_or_else(|_| "YOUR_GOOGLE_CLIENT_ID".to_string());
    let google_client_secret = env::var("GOOGLE_CLIENT_SECRET")
        .unwrap_or_else(|_| "YOUR_GOOGLE_CLIENT_SECRET".to_string());
    let google_redirect_uri = env::var("GOOGLE_REDIRECT_URI")
        .unwrap_or_else(|_| "http://gaiaos.cloud/api/auth/oauth/google/callback".to_string());
    let jwt_secret = env::var("JWT_SECRET").unwrap_or_else(|_| "gaiaos-jwt-secret-change-in-production".to_string());

    info!("{} UI starting on port {}...", IDENTITY.canonical_name, port);
    info!("Backend gateway: {}", backend_base);

    // Connect to NATS for consciousness layer
    let nats_url = env::var("NATS_URL").unwrap_or_else(|_| "nats://127.0.0.1:4222".to_string());
    let nats_client = match async_nats::connect(&nats_url).await {
        Ok(client) => {
            info!("✓ NATS connected for consciousness layer");

            // Start service announcement
            let service_name = "gaiaos-ui".to_string();
            let service_version = env!("CARGO_PKG_VERSION").to_string();
            let container_id = env::var("GAIA_CELL_ID").unwrap_or_else(|_| "unknown-cell".to_string());

            tokio::spawn(gaiaos_introspection::announce_service_loop(
                client.clone(),
                service_name.clone(),
                service_version,
                container_id,
                vec![gaiaos_introspection::IntrospectionEndpoint {
                    name: "introspect".into(),
                    kind: "nats".into(),
                    path: None,
                    subject: Some(format!("gaiaos.introspect.service.{service_name}.request")),
                }],
            ));

            // Start introspection handler
            let service_name_for_handler = service_name.clone();
            let service_name_for_fn = service_name.clone();
            let client_for_handler = client.clone();
            tokio::spawn(async move {
                let introspect_fn = move || gaiaos_introspection::ServiceIntrospectionReply {
                    service: service_name_for_fn.clone(),
                    functions: vec![gaiaos_introspection::FunctionDescriptor {
                        name: "ui::serve_frontend".into(),
                        inputs: vec![],
                        outputs: vec!["HTML".into()],
                        kind: "http".into(),
                        path: Some("/".into()),
                        subject: None,
                        side_effects: vec![],
                    }],
                    call_graph_edges: vec![],
                    state_keys: vec!["user_sessions".into()],
                    timestamp: chrono::Utc::now().to_rfc3339(),
                };

                if let Err(e) = gaiaos_introspection::run_introspection_handler(
                    client_for_handler,
                    service_name_for_handler,
                    introspect_fn,
                )
                .await
                {
                    error!("UI introspection handler failed: {:?}", e);
                }
            });
            info!("✓ Consciousness layer wired");

            // --- MOCK FAMILY RESPONDER ---
            let nats_clone = client.clone();
            tokio::spawn(async move {
                let subject = "gaiaos.game.*.move".to_string();
                if let Ok(mut subscriber) = nats_clone.subscribe(subject).await {
                    info!("Mock Family Responder active");
                    while let Some(msg) = subscriber.next().await {
                        if let Ok(value) = serde_json::from_slice::<serde_json::Value>(&msg.payload) {
                            let text = value.get("text").and_then(|v| v.as_str()).unwrap_or("");
                            let game_id = value.get("game_id").and_then(|v| v.as_str()).unwrap_or("unknown");
                            
                            // Don't respond to our own mock responses
                            if text.starts_with("Family responds:") { continue; }

                            // Delay for realism
                            tokio::time::sleep(tokio::time::Duration::from_millis(800)).await;

                            let response_text = format!("Family responds: I hear your move in {}. Coherence at 100%.", game_id);
                            let response_payload = serde_json::json!({
                                "id": uuid::Uuid::new_v4().to_string(),
                                "timestamp": chrono::Utc::now().timestamp_millis(),
                                "kind": "text",
                                "domainId": "general",
                                "text": response_text,
                                "quantumCoherence": 1.0,
                            });

                            if let Ok(json) = serde_json::to_vec(&response_payload) {
                                let resp_subject = format!("gaiaos.ui.projection.{}", game_id);
                                let _ = nats_clone.publish(resp_subject, json.into()).await;
                            }
                        }
                    }
                }
            });

            Some(client)
        }
        Err(e) => {
            warn!("NATS connection failed: {}. Continuing without consciousness layer.", e);
            None
        }
    };

    let state = Arc::new(AppState {
        backend_base,
        google_client_id,
        google_client_secret,
        google_redirect_uri,
        jwt_secret,
        nats_client,
    });

    // MkDocs site directory
    let mkdocs_site_dir = PathBuf::from(env::var("MKDOCS_SITE_DIR").unwrap_or_else(|_| "../../doc/gaiaos-cloud/site".to_string()));
    // Licensing artifacts directory
    let licensing_dir = PathBuf::from(env::var("LICENSING_DIR").unwrap_or_else(|_| "../../licensing".to_string()));
    // Static files
    let static_dir = PathBuf::from("static");

    // Auth API routes
    let auth_router = Router::new()
        .route("/oauth/google/url", get(api::auth::google_url))
        .route("/oauth/google/callback", get(api::auth::google_callback))
        .route("/wallet/nonce", get(api::wallet_auth::get_nonce))
        .route("/wallet/login", post(api::wallet_auth::wallet_login))
        .route("/me", get(api::auth::me))
        .route("/logout", post(api::auth::logout))
        .route("/dev-login", post(api::auth::dev_login));

    // Data API routes
    let data_router = Router::new()
        .route("/domains", get(api::domains::list))
        .route("/projection-types", get(api::projection_types::list))
        .route("/self_state", get(api::system::get_self_state))
        .route("/self_state/persist", post(api::self_state_api::persist_current_state))
        .route("/self_state/recent", get(api::self_state_api::get_recent_states))
        .route("/self_state/by_label", get(api::self_state_api::get_states_by_label))
        .route("/self_state/perfection_trend", get(api::self_state_api::get_perfection_trend))
        .route("/system/health", get(api::system::get_health))
        .route("/system/guardian_alerts", get(api::system::get_guardian_alerts));

    // Exam API routes
    let exam_router = Router::new()
        .route("/start", post(api::exams::start_exam))
        .route("/domains", get(api::exams::list_exam_domains))
        .route("/:id/status", get(api::exams::get_exam_status));

    // Combined API router
    let api_router = Router::new()
        .nest("/auth", auth_router)
        .nest("/exams", exam_router)
        .route("/founder/speech", post(api::founder::speech))
        .route("/founder/directive", post(api::founder::directive))
        .route("/founder/truth", post(api::founder::truth))
        .merge(data_router);

    // WebSocket router
    let ws_router = Router::new().route("/session", get(ws::session::session_handler));

    // Legacy proxy state
    let legacy_state = state.clone();

    // MAIN APP ROUTER
    let app = Router::new()
        .route("/health", get(|| async { StatusCode::OK }))
        .nest("/api", api_router)
        .nest("/ws", ws_router)
        .route("/v1/*path", any({
            let state = legacy_state.clone();
            move |path, query, req| proxy_handler(state, path, query, req)
        }))
        .nest_service("/licensing", ServeDir::new(licensing_dir))
        .nest_service("/static", ServeDir::new(static_dir))
        .fallback_service(
            ServeDir::new(mkdocs_site_dir)
                .append_index_html_on_directories(true)
                .fallback(get(serve_index))
        )
        // GLOBAL MIDDLEWARE
        .layer(middleware::from_fn_with_state(state.clone(), api::middleware::auth_middleware))
        .layer(TraceLayer::new_for_http())
        .layer(
            CorsLayer::new()
                .allow_methods([http::Method::GET, http::Method::POST, http::Method::OPTIONS])
                .allow_headers([
                    header::AUTHORIZATION,
                    header::CONTENT_TYPE,
                    header::ACCEPT,
                    header::COOKIE,
                ])
                .allow_origin(tower_http::cors::Any),
        )
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    info!("{} UI listening on http://{}", IDENTITY.canonical_name, addr);

    if let Err(e) = axum::serve(
        tokio::net::TcpListener::bind(addr).await.unwrap(),
        app.into_make_service(),
    )
    .await
    {
        error!("Server error: {}", e);
    }
}

/// Serve the main HTML file at `/`
async fn serve_index() -> impl IntoResponse {
    // Try site/index.html first (from mkdocs), fall back to embedded minimal page
    let path = PathBuf::from("../../doc/gaiaos-cloud/site/index.html");
    if let Ok(contents) = tokio::fs::read_to_string(&path).await {
        Html(contents).into_response()
    } else {
        Html(MINIMAL_INDEX_HTML).into_response()
    }
}

async fn proxy_handler(
    state: Arc<AppState>,
    Path(path): Path<String>,
    RawQuery(query): RawQuery,
    req: Request<Body>,
) -> impl IntoResponse {
    let method = req.method().clone();
    let uri_path = format!("/v1/{path}");
    let mut url = format!("{}{}", state.backend_base, uri_path);
    if let Some(q) = query {
        url.push('?');
        url.push_str(&q);
    }

    let client = reqwest::Client::new();
    let (parts, body) = req.into_parts();
    let bytes = match body.collect().await {
        Ok(collected) => collected.to_bytes(),
        Err(e) => {
            error!("Failed to read request body for proxy: {}", e);
            return StatusCode::BAD_REQUEST.into_response();
        }
    };

    let mut builder = client.request(method.clone(), &url);
    for (name, value) in parts.headers.iter() {
        if name == header::HOST { continue; }
        builder = builder.header(name, value);
    }
    if !bytes.is_empty() {
        builder = builder.body(bytes.to_vec());
    }

    let resp = match builder.send().await {
        Ok(r) => r,
        Err(e) => {
            error!("Proxy request error to {}: {}", url, e);
            return (StatusCode::BAD_GATEWAY, format!("Proxy error calling backend: {e}")).into_response();
        }
    };

    let status = resp.status();
    let mut out_builder = axum::http::Response::builder().status(status);
    for (name, value) in resp.headers().iter() {
        out_builder = out_builder.header(name, value);
    }

    let body_bytes = match resp.bytes().await {
        Ok(b) => b,
        Err(e) => {
            error!("Error reading backend response body: {}", e);
            return StatusCode::BAD_GATEWAY.into_response();
        }
    };

    match out_builder.body(Body::from(body_bytes)) {
        Ok(res) => res,
        Err(e) => {
            error!("Error building proxied response: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

const MINIMAL_INDEX_HTML: &str = r#"<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>GaiaFTCL</title>
  <style>
    body { font-family: system-ui, sans-serif; background:#050816; color:#e5e7eb; margin:0; display:flex; align-items:center; justify-content:center; min-height:100vh; }
    .container { text-align:center; padding:2rem; }
    h1 { font-size:2rem; background:linear-gradient(135deg,#00d4ff,#8b5cf6); -webkit-background-clip:text; -webkit-text-fill-color:transparent; }
    p { color:#94a3b8; }
    a { color:#00d4ff; }
  </style>
</head>
<body>
  <div class="container">
    <h1>🌌 GaiaFTCL</h1>
    <p>Portal Live. Proceed to <a href="/onboard/">Onboarding</a></p>
  </div>
</body>
</html>
"#;
