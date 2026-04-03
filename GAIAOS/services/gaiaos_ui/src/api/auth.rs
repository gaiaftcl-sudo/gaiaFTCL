//! Authentication API - Google OAuth flow
//!
//! Endpoints:
//! - GET /api/auth/oauth/google/url - Get OAuth redirect URL
//! - GET /api/auth/oauth/google/callback - Handle OAuth callback
//! - GET /api/auth/me - Get current user profile
//! - POST /api/auth/logout - Logout

use axum::{
    extract::{Query, State},
    http::{header, StatusCode},
    response::{IntoResponse, Redirect},
    Json,
};
use axum_extra::extract::cookie::{Cookie, CookieJar};
use chrono::Utc;
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{error, info, warn};
use uuid::Uuid;

use crate::AppState;

/// Cookie name for the session token
const SESSION_COOKIE: &str = "gaiaos_session";

/// JWT claims
#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String, // user id
    pub email: String,
    pub name: Option<String>,
    pub avatar_url: Option<String>,
    pub exp: i64, // expiration timestamp
    pub iat: i64, // issued at
}

/// User profile returned by /api/auth/me
#[derive(Debug, Serialize)]
pub struct UserProfile {
    pub id: String,
    pub email: String,
    pub name: Option<String>,
    #[serde(rename = "avatarUrl")]
    pub avatar_url: Option<String>,
    pub qsig: Option<String>,
    pub roles: Vec<String>,
}

/// Response from /api/auth/oauth/google/url
#[derive(Serialize)]
pub struct OAuthUrlResponse {
    pub url: String,
    pub state: String,
}

/// Query params from Google OAuth callback (all fields used by serde for URL query deserialization)
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct OAuthCallback {
    pub code: Option<String>,
    /// OAuth state parameter (should match value sent in authorization request)
    /// CRITICAL: Must be validated to prevent CSRF attacks
    pub state: Option<String>,
    pub error: Option<String>,
}

/// Google token exchange response
#[derive(Debug, Deserialize)]
struct GoogleTokenResponse {
    access_token: String,
    #[allow(dead_code)]
    expires_in: i64,
    #[allow(dead_code)]
    token_type: String,
    #[allow(dead_code)]
    scope: Option<String>,
    /// Google's signed JWT token (should be validated in production)
    id_token: Option<String>,
}

/// Google user info response
#[derive(Debug, Deserialize)]
struct GoogleUserInfo {
    id: String,
    email: String,
    name: Option<String>,
    picture: Option<String>,
}

/// GET /api/auth/oauth/google/url
/// Returns the URL to redirect the user to for Google OAuth
pub async fn google_url(State(state): State<Arc<AppState>>, jar: CookieJar) -> impl IntoResponse {
    let client_id = &state.google_client_id;
    let redirect_uri = &state.google_redirect_uri;

    if client_id.is_empty() || client_id == "YOUR_GOOGLE_CLIENT_ID" {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(serde_json::json!({
                "error": "Google OAuth not configured",
                "message": "GOOGLE_CLIENT_ID environment variable not set"
            })),
        )
            .into_response();
    }

    // Generate state for CSRF protection
    let oauth_state = Uuid::new_v4().to_string();

    // Store state in secure cookie for validation in callback
    let state_cookie = Cookie::build(("oauth_state", oauth_state.clone()))
        .path("/")
        .http_only(true)
        .secure(false) // Set to true in production with HTTPS
        .max_age(time::Duration::minutes(10)) // Short-lived for security
        .build();

    let jar = jar.add(state_cookie);

    // Build OAuth URL
    let url = format!(
        "https://accounts.google.com/o/oauth2/v2/auth?\
        client_id={}&\
        redirect_uri={}&\
        response_type=code&\
        scope=openid%20email%20profile&\
        state={}&\
        access_type=offline&\
        prompt=consent",
        urlencoding::encode(client_id),
        urlencoding::encode(redirect_uri),
        urlencoding::encode(&oauth_state),
    );

    info!("Generated OAuth URL for state: {}", oauth_state);

    (
        jar,
        Json(OAuthUrlResponse {
            url,
            state: oauth_state,
        }),
    )
        .into_response()
}

/// GET /api/auth/oauth/google/callback
/// Handles the OAuth callback from Google
pub async fn google_callback(
    State(state): State<Arc<AppState>>,
    Query(params): Query<OAuthCallback>,
    jar: CookieJar,
) -> impl IntoResponse {
    // Check for errors
    if let Some(error) = params.error {
        error!("OAuth error from Google: {}", error);
        return Redirect::to(&format!("/login?error={}", urlencoding::encode(&error)))
            .into_response();
    }

    // SECURITY: Validate OAuth state to prevent CSRF attacks
    // The state parameter must match the one we generated and stored
    let received_state = match params.state {
        Some(s) => s,
        None => {
            error!("OAuth callback missing state parameter - possible CSRF attack");
            return Redirect::to("/login?error=missing_state").into_response();
        }
    };

    // Retrieve expected state from cookie (set by google_url endpoint)
    let expected_state = jar.get("oauth_state").map(|c| c.value().to_string());
    
    match expected_state {
        Some(expected) if expected == received_state => {
            info!("OAuth state validated successfully");
        }
        Some(expected) => {
            error!(
                "OAuth state mismatch - possible CSRF attack. Expected: {}, Got: {}",
                expected, received_state
            );
            return Redirect::to("/login?error=invalid_state").into_response();
        }
        None => {
            error!("OAuth state cookie not found - session may have expired");
            return Redirect::to("/login?error=state_expired").into_response();
        }
    }

    let code = match params.code {
        Some(c) => c,
        None => {
            return Redirect::to("/login?error=missing_code").into_response();
        }
    };

    // Clear the state cookie after successful validation
    let state_cookie = Cookie::build(("oauth_state", ""))
        .path("/")
        .http_only(true)
        .max_age(time::Duration::seconds(0))
        .build();
    let jar = jar.remove(state_cookie);

    info!("Received OAuth callback with code");

    // Exchange code for tokens
    let token_response = match exchange_code_for_tokens(&state, &code).await {
        Ok(tokens) => tokens,
        Err(e) => {
            error!("Failed to exchange code for tokens: {}", e);
            return Redirect::to(&format!("/login?error={}", urlencoding::encode(&e)))
                .into_response();
        }
    };

    // Get user info from Google
    let user_info = match get_google_user_info(&token_response.access_token).await {
        Ok(info) => info,
        Err(e) => {
            error!("Failed to get user info: {}", e);
            return Redirect::to(&format!("/login?error={}", urlencoding::encode(&e)))
                .into_response();
        }
    };

    info!("OAuth successful for user: {}", user_info.email);

    // SAFETY: Validate id_token if present (Google JWT)
    if let Some(id_token) = &token_response.id_token {
        // Validate Google's id_token signature with Google's public keys
        match validate_google_id_token(id_token).await {
            Ok(claims) => {
                info!(
                    "✅ Valid id_token for user: {} (iss: {}, aud: {})",
                    claims.email, claims.iss, claims.aud
                );
                // Verify issuer
                if claims.iss != "https://accounts.google.com"
                    && claims.iss != "accounts.google.com"
                {
                    error!("❌ Invalid issuer in id_token: {}", claims.iss);
                    return Redirect::to("/login?error=invalid_token_issuer").into_response();
                }
                // Verify audience matches our client ID
                let expected_client_id = &state.google_client_id;
                if claims.aud != *expected_client_id {
                    error!("❌ Invalid audience in id_token: {}", claims.aud);
                    return Redirect::to("/login?error=invalid_token_audience").into_response();
                }
                // Verify expiration
                let now = Utc::now().timestamp();
                if claims.exp < now {
                    error!("❌ Expired id_token: exp={}, now={}", claims.exp, now);
                    return Redirect::to("/login?error=token_expired").into_response();
                }
                info!("✅ All id_token claims validated successfully");
            }
            Err(e) => {
                error!("❌ Failed to validate id_token: {}", e);
                return Redirect::to("/login?error=token_validation_failed").into_response();
            }
        }
    } else {
        warn!("Google token response missing id_token");
    }

    // Generate JWT
    let now = Utc::now();
    let exp = now + chrono::Duration::days(7);

    let claims = Claims {
        sub: user_info.id.clone(),
        email: user_info.email.clone(),
        name: user_info.name.clone(),
        avatar_url: user_info.picture.clone(),
        exp: exp.timestamp(),
        iat: now.timestamp(),
    };

    let token = match encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
    ) {
        Ok(t) => t,
        Err(e) => {
            error!("Failed to create JWT: {}", e);
            return Redirect::to("/login?error=token_creation_failed").into_response();
        }
    };

    // Set session cookie
    let cookie = Cookie::build((SESSION_COOKIE, token.clone()))
        .path("/")
        .http_only(true)
        .secure(false) // Set to true in production with HTTPS
        .max_age(time::Duration::days(7))
        .build();

    let jar = jar.add(cookie);

    // Redirect to app with token in URL (for localStorage storage)
    let redirect_url = format!("/app?session_token={token}");

    (jar, Redirect::to(&redirect_url)).into_response()
}

/// GET /api/auth/me
/// Returns the current user's profile
pub async fn me(State(state): State<Arc<AppState>>, jar: CookieJar, headers: axum::http::HeaderMap) -> impl IntoResponse {
    // Try to get token from cookie first, then from Authorization header
    let token = jar
        .get(SESSION_COOKIE)
        .map(|c| c.value().to_string())
        .or_else(|| {
            headers
                .get(header::AUTHORIZATION)
                .and_then(|v| v.to_str().ok())
                .and_then(|s| s.strip_prefix("Bearer "))
                .map(|s| s.to_string())
        });

    let token = match token {
        Some(t) => t,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({ "error": "Not authenticated" })),
            )
                .into_response();
        }
    };

    // Decode and validate JWT
    let claims = match decode::<Claims>(
        &token,
        &DecodingKey::from_secret(state.jwt_secret.as_bytes()),
        &Validation::default(),
    ) {
        Ok(data) => data.claims,
        Err(e) => {
            error!("Invalid JWT: {}", e);
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({ "error": "Invalid or expired token" })),
            )
                .into_response();
        }
    };

    // Generate QSig (8D quantum signature placeholder)
    let qsig = format!("QSTATE8D-{}-BOUND", &claims.sub[..8.min(claims.sub.len())]);

    // Determine roles (in a real system, look this up in DB)
    let roles = if claims.email.contains("gillespie") || claims.email.contains("gaiaos") {
        vec!["founder".to_string(), "admin".to_string()]
    } else {
        vec!["user".to_string()]
    };

    let profile = UserProfile {
        id: claims.sub,
        email: claims.email,
        name: claims.name,
        avatar_url: claims.avatar_url,
        qsig: Some(qsig),
        roles,
    };

    Json(profile).into_response()
}

/// POST /api/auth/logout
/// Clears the session
pub async fn logout(jar: CookieJar) -> impl IntoResponse {
    let cookie = Cookie::build((SESSION_COOKIE, ""))
        .path("/")
        .http_only(true)
        .max_age(time::Duration::seconds(0))
        .build();

    let jar = jar.remove(cookie);

    (jar, StatusCode::NO_CONTENT)
}

/// POST /api/auth/dev-login
/// Development bypass - creates a test session without OAuth
/// WARNING: Only for development/testing purposes!
pub async fn dev_login(State(state): State<Arc<AppState>>, jar: CookieJar) -> impl IntoResponse {
    info!("Dev login requested - bypassing OAuth");

    // Create a dev user
    let dev_user_id = "dev-user-001";
    let dev_email = "dev@gaiaos.cloud";

    // Generate JWT
    let now = Utc::now();
    let exp = now + chrono::Duration::days(7);

    let claims = Claims {
        sub: dev_user_id.to_string(),
        email: dev_email.to_string(),
        name: Some("GaiaOS Developer".to_string()),
        avatar_url: None,
        exp: exp.timestamp(),
        iat: now.timestamp(),
    };

    let token = match encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
    ) {
        Ok(t) => t,
        Err(e) => {
            error!("Failed to create dev JWT: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "error": "Failed to create token" })),
            )
                .into_response();
        }
    };

    // Set session cookie
    let cookie = Cookie::build((SESSION_COOKIE, token.clone()))
        .path("/")
        .http_only(true)
        .secure(false)
        .max_age(time::Duration::days(7))
        .build();

    let jar = jar.add(cookie);

    // Generate QSig
    let qsig = format!(
        "QSTATE8D-{}-DEV-BOUND",
        &dev_user_id[..8.min(dev_user_id.len())]
    );

    let response = serde_json::json!({
        "token": token,
        "user": {
            "id": dev_user_id,
            "email": dev_email,
            "name": "GaiaOS Developer",
            "avatarUrl": null,
            "qsig": qsig,
            "roles": ["dev", "admin", "founder"]
        }
    });

    info!("Dev login successful for {}", dev_email);

    (jar, Json(response)).into_response()
}

/// Exchange OAuth code for tokens
async fn exchange_code_for_tokens(
    state: &AppState,
    code: &str,
) -> Result<GoogleTokenResponse, String> {
    let client = reqwest::Client::new();

    let params = [
        ("code", code),
        ("client_id", &state.google_client_id),
        ("client_secret", &state.google_client_secret),
        ("redirect_uri", &state.google_redirect_uri),
        ("grant_type", "authorization_code"),
    ];

    let response = client
        .post("https://oauth2.googleapis.com/token")
        .form(&params)
        .send()
        .await
        .map_err(|e| format!("Token request failed: {e}"))?;

    if !response.status().is_success() {
        let error_text = response.text().await.unwrap_or_default();
        return Err(format!("Token exchange failed: {error_text}"));
    }

    response
        .json::<GoogleTokenResponse>()
        .await
        .map_err(|e| format!("Failed to parse token response: {e}"))
}

/// Get user info from Google
async fn get_google_user_info(access_token: &str) -> Result<GoogleUserInfo, String> {
    let client = reqwest::Client::new();

    let response = client
        .get("https://www.googleapis.com/oauth2/v2/userinfo")
        .bearer_auth(access_token)
        .send()
        .await
        .map_err(|e| format!("User info request failed: {e}"))?;

    if !response.status().is_success() {
        let error_text = response.text().await.unwrap_or_default();
        return Err(format!("User info request failed: {error_text}"));
    }

    response
        .json::<GoogleUserInfo>()
        .await
        .map_err(|e| format!("Failed to parse user info: {e}"))
}

/// Google ID token claims for validation (all fields used by serde JWT deserialization)
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct GoogleIdTokenClaims {
    iss: String,
    aud: String,
    sub: String,
    email: String,
    #[serde(default)]
    email_verified: bool,
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    picture: Option<String>,
    exp: i64,
    iat: i64,
}

/// Validate Google's id_token by fetching Google's public keys and verifying signature
async fn validate_google_id_token(id_token: &str) -> Result<GoogleIdTokenClaims, String> {
    // Decode without verification first to get the header
    let header = jsonwebtoken::decode_header(id_token)
        .map_err(|e| format!("Failed to decode token header: {}", e))?;

    let kid = header.kid.ok_or("Token missing kid header")?;

    // Fetch Google's public keys
    let client = reqwest::Client::new();
    let jwks_response = client
        .get("https://www.googleapis.com/oauth2/v3/certs")
        .send()
        .await
        .map_err(|e| format!("Failed to fetch Google JWKS: {}", e))?;

    let jwks: serde_json::Value = jwks_response
        .json()
        .await
        .map_err(|e| format!("Failed to parse JWKS: {}", e))?;

    // Find the key matching the kid
    let keys = jwks["keys"].as_array().ok_or("Invalid JWKS format")?;
    let key = keys
        .iter()
        .find(|k| k["kid"].as_str() == Some(&kid))
        .ok_or_else(|| format!("Key with kid {} not found", kid))?;

    let n = key["n"].as_str().ok_or("Missing n in JWK")?;
    let e = key["e"].as_str().ok_or("Missing e in JWK")?;

    // Create decoding key from RSA components
    let decoding_key = DecodingKey::from_rsa_components(n, e)
        .map_err(|e| format!("Failed to create decoding key: {}", e))?;

    // Validate the token
    let mut validation = Validation::new(jsonwebtoken::Algorithm::RS256);
    // validation.set_audience(&[get_google_client_id()]); // Handled caller side or needs state
    validation.set_issuer(&["https://accounts.google.com", "accounts.google.com"]);

    let token_data = decode::<GoogleIdTokenClaims>(id_token, &decoding_key, &validation)
        .map_err(|e| format!("Token validation failed: {}", e))?;

    Ok(token_data.claims)
}

// URL encoding helper
mod urlencoding {
    pub fn encode(s: &str) -> String {
        url::form_urlencoded::byte_serialize(s.as_bytes()).collect()
    }
}
