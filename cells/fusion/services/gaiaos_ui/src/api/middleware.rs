//! Security Middleware for Default Deny
//! 
//! Checks:
//! - Presence of JWT token (cookie or header)
//! - Required role/permissions for specific paths
//! - Onboarding status
//! - UI Surface Release Status (LOCKED gate)

use crate::api::wallet_auth::Claims;
use axum::{
    body::Body,
    extract::{Request, State},
    http::{header, StatusCode},
    middleware::Next,
    response::{Response, Html, IntoResponse},
};
use axum_extra::extract::cookie::CookieJar;
use jsonwebtoken::{decode, DecodingKey, Validation};
use std::sync::Arc;
use tracing::{warn, info};

const SESSION_COOKIE: &str = "gaiaftcl_session";

pub const LOCKED_BANNER_HTML: &str = r#"<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>LOCKED - GAIAFTCL</title>
  <style>
    body { font-family: 'Courier New', monospace; background:#000; color:#f00; display:flex; align-items:center; justify-content:center; min-height:100vh; margin:0; }
    .box { border: 2px solid #f00; padding: 2rem; max-width: 600px; text-align: center; background: #100; box-shadow: 0 0 20px #f00; }
    h1 { font-size: 3rem; margin: 0; }
    p { font-size: 1.2rem; color: #ff4444; }
    .reason { background: #300; padding: 1rem; margin-top: 1rem; font-size: 0.9rem; text-align: left; }
  </style>
</head>
<body>
  <div class="box">
    <h1>LOCKED</h1>
    <p>CONSTITUTIONAL VIOLATION DETECTED</p>
    <div class="reason">
      ID: GAIAOS_FAMILY_UI_IQ_OQ_PQ_PLAYWRIGHT_TOPOLOGY_V1<br>
      REASON: MISSING_UI_RELEASE_ENVELOPE<br>
      STATUS: PROVENANCE NOT VERIFIED<br>
      ACTION: FAMILY IQ/OQ/PQ REQUIRED
    </div>
    <p style="font-size: 0.8rem; margin-top: 2rem;">Silence is allowed. Interruption is not.</p>
  </div>
</body>
</html>
"#;

pub async fn auth_middleware(
    State(state): State<Arc<crate::AppState>>,
    jar: CookieJar,
    req: Request<Body>,
    next: Next,
) -> Result<Response, StatusCode> {
    let path = req.uri().path();
    
    // 1. CONSTITUTIONAL GATE: Check if UI is RELEASED
    // Exemptions: /health, and requests with the validation secret
    let is_validation_request = req.headers().get("X-Gaia-Validation-Token").map(|v| v == "GAIA_INTERNAL_VALIDATION_2026").unwrap_or(false);
    
    if !is_validation_request && (path == "/" || path.starts_with("/docs/") || path.starts_with("/app/") || path.starts_with("/founder/") || path == "/onboard/") {
        let is_released = std::path::Path::new("../../ftcl/ui_validation/envelopes/GAIAFTCL_PORTAL_V1.release.json").exists();
        if !is_released {
            info!("UI LOCKED: Access to {} blocked by missing release envelope", path);
            return Ok(Html(LOCKED_BANNER_HTML).into_response());
        }
    }

    // 2. PUBLIC PATHS (P0) - Authentication bypass
    if path == "/" || path == "/health" || path.starts_with("/api/auth/wallet/") || path.starts_with("/docs/") || path.starts_with("/onboard/") || path.starts_with("/static/") || path.starts_with("/assets/") {
        return Ok(next.run(req).await);
    }

    // 3. AUTHENTICATION CHECK
    let token = jar
        .get(SESSION_COOKIE)
        .map(|c| c.value().to_string())
        .or_else(|| {
            req.headers()
                .get(header::AUTHORIZATION)
                .and_then(|v| v.to_str().ok())
                .and_then(|s| s.strip_prefix("Bearer "))
                .map(|s| s.to_string())
        })
        .or_else(|| {
            // Support token in query string (common for WebSockets)
            req.uri().query()
                .and_then(|q| {
                    q.split('&')
                        .find(|pair| pair.starts_with("token="))
                        .and_then(|pair| pair.strip_prefix("token="))
                        .map(|s| s.to_string())
                })
        });

    let token = match token {
        Some(t) => t,
        None => {
            warn!("Unauthorized access attempt to: {}", path);
            if path.starts_with("/app/") || path.starts_with("/founder/") {
                return Ok(axum::response::Redirect::temporary("/onboard/").into_response());
            }
            return Err(StatusCode::UNAUTHORIZED);
        }
    };

    let claims = match decode::<Claims>(
        &token,
        &DecodingKey::from_secret(state.jwt_secret.as_bytes()),
        &Validation::default(),
    ) {
        Ok(data) => data.claims,
        Err(_) => {
            if path.starts_with("/app/") || path.starts_with("/founder/") {
                return Ok(axum::response::Redirect::temporary("/onboard/").into_response());
            }
            return Err(StatusCode::UNAUTHORIZED);
        }
    };

    // 4. ACCESS CONTROL (Role-based)
    if path.starts_with("/founder/") && claims.role != "FOUNDER" {
        warn!("Non-founder attempted to access: {}", path);
        return Err(StatusCode::FORBIDDEN);
    }

    if path.starts_with("/app/") && !claims.onboarded {
        warn!("Non-onboarded user attempted to access: {}", path);
        return Err(StatusCode::FORBIDDEN);
    }

    Ok(next.run(req).await)
}
