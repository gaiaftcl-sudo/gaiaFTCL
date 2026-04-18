//! Astro TLE Ingest (evidence-only, live source)
//!
//! Fetches TLEs from Celestrak and writes:
//! - `space_objects` (name, norad_id, tle lines, epoch)
//! - `gravitational_tiles` at the TLE epoch (SGP4 propagation at t=0)
//!
//! FoT: no synthetic positions; position/velocity computed via SGP4 from published TLE.

use anyhow::{anyhow, Context, Result};
use chrono::{NaiveDateTime, TimeZone, Utc};
use log::{info, warn};
use serde_json::json;
use std::{env, time::Duration};

#[derive(Clone)]
struct Config {
    arango_url: String,
    arango_db: String,
    arango_user: String,
    arango_password: String,
    tle_url: String,
    max_objects: usize,
    resolution_km: f64,
    timestep_seconds: i64,

    // Optional Space-Track (preferred when credentials provided)
    spacetrack_username: Option<String>,
    spacetrack_password: Option<String>,
    spacetrack_password_file: Option<String>,
    spacetrack_gp_query_url: String,
}

impl Config {
    fn from_env() -> Self {
        Self {
            arango_url: env::var("ARANGO_URL").unwrap_or_else(|_| "http://localhost:8529".to_string()),
            arango_db: env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
            arango_user: env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            arango_password: env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
            tle_url: env::var("TLE_SOURCE_URL").unwrap_or_else(|_| {
                "https://celestrak.org/NORAD/elements/gp.php?GROUP=active&FORMAT=tle".to_string()
            }),
            max_objects: env::var("MAX_OBJECTS").ok().and_then(|v| v.parse().ok()).unwrap_or(200),
            resolution_km: env::var("RESOLUTION_KM").ok().and_then(|v| v.parse().ok()).unwrap_or(10.0),
            timestep_seconds: env::var("TIMESTEP_SECONDS").ok().and_then(|v| v.parse().ok()).unwrap_or(60),

            spacetrack_username: env::var("SPACETRACK_USERNAME").ok().filter(|s| !s.trim().is_empty()),
            spacetrack_password: env::var("SPACETRACK_PASSWORD").ok().filter(|s| !s.trim().is_empty()),
            spacetrack_password_file: env::var("SPACETRACK_PASSWORD_FILE").ok().filter(|s| !s.trim().is_empty()),
            spacetrack_gp_query_url: env::var("SPACETRACK_GP_QUERY_URL").unwrap_or_else(|_| {
                // 3le format: name + line1 + line2, easiest to reuse existing parser.
                // Limit is applied by appending /limit/{N}.
                "https://www.space-track.org/basicspacedata/query/class/gp/DECAY_DATE/null-val/EPOCH/%3Enow-30/orderby/NORAD_CAT_ID/format/3le".to_string()
            }),
        }
    }
}

#[derive(Clone)]
struct Arango {
    base_url: String,
    db_name: String,
    http: reqwest::Client,
    auth_header: String,
}

impl Arango {
    fn new(base_url: String, db_name: String, user: String, password: String) -> Result<Self> {
        let http = reqwest::Client::builder()
            .timeout(Duration::from_secs(45))
            .user_agent("GaiaOS-Astro-TLE-Ingest/0.1.0")
            .build()
            .context("failed to build reqwest client")?;
        let auth = base64_encode(&format!("{user}:{password}"));
        Ok(Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            db_name,
            http,
            auth_header: format!("Basic {auth}"),
        })
    }

    async fn upsert_document(&self, collection: &str, doc: &serde_json::Value) -> Result<()> {
        let url = format!(
            "{}/_db/{}/_api/document/{}?overwrite=true",
            self.base_url, self.db_name, collection
        );
        let resp = self
            .http
            .post(url)
            .header("Authorization", &self.auth_header)
            .header("Content-Type", "application/json")
            .json(doc)
            .send()
            .await
            .context("arango upsert request failed")?;
        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("Arango upsert failed {status}: {text}"));
        }
        Ok(())
    }
}

fn parse_tle_triplets(text: &str) -> Vec<(String, String, String)> {
    let mut out = Vec::new();
    let lines = text
        .lines()
        .map(|l| l.trim_end().to_string())
        .filter(|l| !l.is_empty())
        .collect::<Vec<_>>();

    // Some TLE feeds are NAME + line1 + line2.
    // If the feed is strictly line1+line2, this will degrade gracefully.
    let mut i = 0usize;
    while i + 2 < lines.len() {
        let a = &lines[i];
        let b = &lines[i + 1];
        let c = &lines[i + 2];
        if b.starts_with('1') && c.starts_with('2') {
            out.push((a.clone(), b.clone(), c.clone()));
            i += 3;
            continue;
        }
        // If we are aligned on line1/line2 without name:
        if a.starts_with('1') && b.starts_with('2') {
            out.push(("UNKNOWN".to_string(), a.clone(), b.clone()));
            i += 2;
            continue;
        }
        i += 1;
    }
    out
}

fn earth_mu_km3_s2() -> f64 {
    398_600.4418
}

fn gravity_terms_km(position: [f64; 3]) -> (f64, f64) {
    let r = (position[0] * position[0] + position[1] * position[1] + position[2] * position[2]).sqrt();
    if r <= 0.0 {
        return (0.0, 0.0);
    }
    let mu = earth_mu_km3_s2();
    // Gravitational potential (specific) in km^2/s^2 (negative).
    let potential = -mu / r;
    // Acceleration magnitude in km/s^2.
    let gmag = mu / (r * r);
    (potential, gmag)
}

fn key_for_sat_epoch(norad: u64, epoch_seconds: i64) -> String {
    format!("GRAV_NORAD_{norad}_E{epoch_seconds}")
}

fn base64_encode(input: &str) -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let bytes = input.as_bytes();
    let mut result = String::new();
    for chunk in bytes.chunks(3) {
        let mut n: u32 = 0;
        for (i, &byte) in chunk.iter().enumerate() {
            n |= (byte as u32) << (16 - i * 8);
        }
        let padding = 3 - chunk.len();
        for i in 0..(4 - padding) {
            let idx = ((n >> (18 - i * 6)) & 0x3F) as usize;
            result.push(ALPHABET[idx] as char);
        }
        for _ in 0..padding {
            result.push('=');
        }
    }
    result
}

fn naive_to_epoch_seconds(dt: NaiveDateTime) -> i64 {
    Utc.from_utc_datetime(&dt).timestamp()
}

async fn fetch_tle_body(cfg: &Config) -> Result<(String, String, String)> {
    // Returns (body, provenance_source, provenance_url)
    if let Some(username) = cfg.spacetrack_username.clone() {
        let password = match (&cfg.spacetrack_password_file, &cfg.spacetrack_password) {
            (Some(path), _) => std::fs::read_to_string(path)
                .with_context(|| format!("failed to read SPACETRACK_PASSWORD_FILE at {path}"))?
                .trim()
                .to_string(),
            (None, Some(p)) => p.trim().to_string(),
            (None, None) => String::new(),
        };

        if !password.is_empty() {
            let client = reqwest::Client::builder()
                .timeout(Duration::from_secs(45))
                .user_agent("GaiaOS-Astro-TLE-Ingest/0.1.0")
                .build()
                .context("failed to build reqwest client")?;

            // Login (returns cookies)
            let login_resp = client
                .post("https://www.space-track.org/ajaxauth/login")
                .form(&[("identity", username.as_str()), ("password", password.as_str())])
                .send()
                .await
                .context("spacetrack login failed")?;

            if !login_resp.status().is_success() {
                let status = login_resp.status();
                let text = login_resp.text().await.unwrap_or_default();
                return Err(anyhow!("spacetrack login http {status}: {text}"));
            }

            // Collect Set-Cookie headers and replay as Cookie header.
            let mut cookie_pairs: Vec<String> = Vec::new();
            for v in login_resp.headers().get_all(reqwest::header::SET_COOKIE).iter() {
                if let Ok(s) = v.to_str() {
                    if let Some(pair) = s.split(';').next() {
                        if !pair.trim().is_empty() {
                            cookie_pairs.push(pair.trim().to_string());
                        }
                    }
                }
            }
            if cookie_pairs.is_empty() {
                return Err(anyhow!("spacetrack login returned no cookies"));
            }
            let cookie_header = cookie_pairs.join("; ");

            // Query
            let url = format!(
                "{}/limit/{}",
                cfg.spacetrack_gp_query_url.trim_end_matches('/'),
                cfg.max_objects
            );
            info!("Fetching TLEs from Space-Track (limit={})", cfg.max_objects);
            let body = client
                .get(&url)
                .header(reqwest::header::COOKIE, cookie_header)
                .send()
                .await
                .context("failed to fetch spacetrack gp data")?
                .error_for_status()
                .context("spacetrack gp query returned error")?
                .text()
                .await
                .context("failed to read spacetrack gp body")?;

            return Ok((body, "spacetrack_gp_3le".to_string(), url));
        }

        warn!("Space-Track username set but password is empty; falling back to Celestrak");
    }

    // Fallback to Celestrak
    info!("Fetching TLEs from {}", cfg.tle_url);
    let body = reqwest::Client::new()
        .get(&cfg.tle_url)
        .send()
        .await
        .context("failed to fetch TLE source")?
        .error_for_status()
        .context("TLE source returned error")?
        .text()
        .await
        .context("failed to read TLE body")?;
    Ok((body, "celestrak_active_tle".to_string(), cfg.tle_url.clone()))
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();
    let cfg = Config::from_env();
    let arango = Arango::new(
        cfg.arango_url.clone(),
        cfg.arango_db.clone(),
        cfg.arango_user.clone(),
        cfg.arango_password.clone(),
    )?;

    let (body, provenance_source, provenance_url) = fetch_tle_body(&cfg).await?;

    let triplets = parse_tle_triplets(&body);
    if triplets.is_empty() {
        return Err(anyhow!("no TLE triplets parsed from source"));
    }

    let mut objects_written = 0usize;
    let mut tiles_written = 0usize;

    for (idx, (name, l1, l2)) in triplets.into_iter().enumerate() {
        if idx >= cfg.max_objects {
            break;
        }

        let elements = match sgp4::Elements::from_tle(
            Some(name.clone()),
            l1.as_bytes(),
            l2.as_bytes(),
        ) {
            Ok(e) => e,
            Err(e) => {
                warn!("skip: failed to parse TLE for {name}: {e}");
                continue;
            }
        };

        let constants = match sgp4::Constants::from_elements(&elements) {
            Ok(c) => c,
            Err(e) => {
                warn!("skip: failed to init SGP4 for {name} norad={} : {e}", elements.norad_id);
                continue;
            }
        };

        // Propagate at epoch (t=0) to get TEME position in km.
        let pred = match constants.propagate(sgp4::MinutesSinceEpoch(0.0)) {
            Ok(p) => p,
            Err(e) => {
                warn!("skip: propagate failed for {name} norad={} : {e}", elements.norad_id);
                continue;
            }
        };

        let epoch_seconds = naive_to_epoch_seconds(elements.datetime);
        let pos = [pred.position[0], pred.position[1], pred.position[2]];
        let (gp, gmag) = gravity_terms_km(pos);

        let obj_key = format!("NORAD_{}", elements.norad_id);
        let obj_doc = json!({
            "_key": obj_key,
            "norad_id": elements.norad_id,
            "name": name,
            "epoch_seconds": epoch_seconds,
            "tle": {
                "line1": l1,
                "line2": l2
            },
            "elements": {
                "inclination_deg": elements.inclination,
                "raan_deg": elements.right_ascension,
                "eccentricity": elements.eccentricity,
                "arg_perigee_deg": elements.argument_of_perigee,
                "mean_anomaly_deg": elements.mean_anomaly,
                "mean_motion_rev_per_day": elements.mean_motion
            },
            "provenance": {
                "source": provenance_source,
                "tle_url": provenance_url,
                "ingested_at": Utc::now().to_rfc3339()
            }
        });
        arango.upsert_document("space_objects", &obj_doc).await?;
        objects_written += 1;

        let tile_key = key_for_sat_epoch(elements.norad_id, epoch_seconds);
        let tile_doc = json!({
            "_key": tile_key,
            "position_eci": { "type": "Point", "coordinates": [pos[0], pos[1]] },
            "z_km": pos[2],
            "resolution_km": cfg.resolution_km,
            "epoch_seconds": epoch_seconds,
            "timestep_seconds": cfg.timestep_seconds,
            "state": {
                "gravitational_potential": gp,
                "g_field_magnitude": gmag,
                "central_body": "earth",
                "norad_id": elements.norad_id
            },
            "provenance": {
                "source": "sgp4_tle_epoch",
                "tle_url": cfg.tle_url,
                "model_version": env!("CARGO_PKG_VERSION"),
                "ingested_at": Utc::now().to_rfc3339(),
                "is_prediction": false
            }
        });
        arango.upsert_document("gravitational_tiles", &tile_doc).await?;
        tiles_written += 1;
    }

    info!(
        "astro_tle_ingest complete: space_objects_upserted={} gravitational_tiles_upserted={}",
        objects_written, tiles_written
    );
    Ok(())
}


