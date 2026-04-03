use anyhow::{anyhow, Context, Result};
use chrono::{DateTime, NaiveDate, TimeZone, Utc};
use grib::{
    codetables::{CodeTable4_2, Lookup as _},
    Grib2SubmessageDecoder,
};
use log::{info, warn};
use serde::Deserialize;
use serde_json::json;
use std::{collections::HashMap, fs::File, io::BufReader, path::Path};

#[derive(Clone)]
struct ArangoClient {
    http: reqwest::Client,
    base_url: String,
    db: String,
    user: String,
    password: String,
}

impl ArangoClient {
    fn new(base_url: String, db: String, user: String, password: String) -> Self {
        Self {
            http: reqwest::Client::new(),
            base_url,
            db,
            user,
            password,
        }
    }

    async fn ensure_collection(&self, collection: &str) -> Result<()> {
        let url = format!(
            "{}/_db/{}/_api/collection/{}",
            self.base_url.trim_end_matches('/'),
            self.db,
            collection
        );
        let resp = self
            .http
            .get(url.clone())
            .basic_auth(&self.user, Some(&self.password))
            .send()
            .await
            .context("arango get collection")?;
        if resp.status().is_success() {
            return Ok(());
        }
        if resp.status().as_u16() != 404 {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!(
                "arango collection check failed: status={} collection={} body={}",
                status,
                collection,
                text
            ));
        }

        // Create collection when missing (idempotent safety for historical backfill jobs).
        let create_url = format!(
            "{}/_db/{}/_api/collection",
            self.base_url.trim_end_matches('/'),
            self.db
        );
        let create_resp = self
            .http
            .post(create_url)
            .basic_auth(&self.user, Some(&self.password))
            .json(&json!({ "name": collection }))
            .send()
            .await
            .context("arango create collection")?;
        if !create_resp.status().is_success() {
            let status = create_resp.status();
            let text = create_resp.text().await.unwrap_or_default();
            return Err(anyhow!(
                "arango create collection failed: status={} collection={} body={}",
                status,
                collection,
                text
            ));
        }
        Ok(())
    }

    async fn upsert_document(&self, collection: &str, doc: &serde_json::Value) -> Result<()> {
        let key = doc
            .get("_key")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow!("missing _key in doc"))?;
        let url = format!(
            "{}/_db/{}/_api/document/{}?overwrite=true",
            self.base_url.trim_end_matches('/'),
            self.db,
            collection
        );

        let resp = self
            .http
            .post(url)
            .basic_auth(&self.user, Some(&self.password))
            .json(doc)
            .send()
            .await
            .context("arango PUT")?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!(
                "arango upsert failed: status={} key={} body={}",
                status,
                key,
                text
            ));
        }
        Ok(())
    }
}

#[derive(Debug, Clone)]
struct Config {
    manifest_path: String,
    gfs_root: String,
    tile_step_deg: f64,
    levels_mb: Vec<i32>,
    max_tiles_per_layer: usize,
    atmosphere_tiles_collection: String,
}

#[derive(Debug, Deserialize)]
struct Manifest {
    schema: String,
    generated_at: i64,
    entries: Vec<ManifestEntry>,
}

#[derive(Debug, Deserialize)]
struct ManifestEntry {
    date: String,
    cycle_hour: i32,
    forecast_hour: i32,
    url: String,
    path: String,
    bytes: u64,
    sha256: String,
}

#[derive(Debug, Default, Clone)]
struct LayerTile {
    lat: f64,
    lon: f64,
    temp_k: Option<f64>,
    u_ms: Option<f64>,
    v_ms: Option<f64>,
    hgt_m: Option<f64>,
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();

    let cfg = Config {
        manifest_path: std::env::var("GFS_MANIFEST").unwrap_or_else(|_| {
            "artifacts/historical/gfs/aws/manifest.json".to_string()
        }),
        gfs_root: std::env::var("GFS_ROOT").unwrap_or_else(|_| "".to_string()),
        tile_step_deg: std::env::var("TILE_STEP_DEG")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(10.0),
        levels_mb: std::env::var("LEVELS_MB")
            .ok()
            .map(|v| {
                v.split(',')
                    .filter_map(|s| s.trim().parse::<i32>().ok())
                    .collect::<Vec<_>>()
            })
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| vec![300, 250, 200]),
        max_tiles_per_layer: std::env::var("MAX_TILES_PER_LAYER")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(3000),
        atmosphere_tiles_collection: std::env::var("ARANGO_ATMOSPHERE_TILES_COLLECTION")
            .unwrap_or_else(|_| "atmosphere_tiles_historical".to_string()),
    };

    let arango_url = std::env::var("ARANGO_URL").unwrap_or_else(|_| "http://arangodb:8529".into());
    let arango_db = std::env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".into());
    let arango_user = std::env::var("ARANGO_USER").unwrap_or_else(|_| "root".into());
    let arango_password =
        std::env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".into());

    let arango = ArangoClient::new(arango_url, arango_db, arango_user, arango_password);
    arango
        .ensure_collection(&cfg.atmosphere_tiles_collection)
        .await?;

    let manifest: Manifest = serde_json::from_slice(
        &std::fs::read(&cfg.manifest_path)
            .with_context(|| format!("read manifest {}", cfg.manifest_path))?,
    )
    .with_context(|| format!("parse manifest {}", cfg.manifest_path))?;

    if !manifest.schema.starts_with("gaiaos.entropy_analysis.gfs_aws_manifest/") {
        return Err(anyhow!(
            "unexpected manifest schema: {}",
            manifest.schema
        ));
    }

    info!(
        "historical_gfs_backfill: manifest schema={} generated_at={} entries={}",
        manifest.schema,
        manifest.generated_at,
        manifest.entries.len()
    );

    let mut total_written = 0usize;
    for e in &manifest.entries {
        let file_path = resolve_entry_path(&cfg, e);
        if !Path::new(&file_path).exists() {
            warn!("missing file {}, skipping (entry.path={})", file_path, e.path);
            continue;
        }
        let valid_time = compute_valid_time(&e.date, e.cycle_hour, e.forecast_hour)?;
        let written = ingest_one_file(&cfg, &arango, e, &file_path, valid_time).await?;
        total_written += written;
    }

    info!("historical_gfs_backfill: done total_tiles_written={}", total_written);
    Ok(())
}

fn resolve_entry_path(cfg: &Config, e: &ManifestEntry) -> String {
    let p = Path::new(&e.path);
    if p.is_absolute() {
        return e.path.clone();
    }

    // If manifest was generated on host, it likely contains:
    //   artifacts/historical/gfs/aws/YYYYMMDD/HH/atmos/...
    // In container, we mount that root at /data/gfs.
    let root = if !cfg.gfs_root.trim().is_empty() {
        Path::new(cfg.gfs_root.trim())
    } else {
        Path::new(&cfg.manifest_path)
            .parent()
            .unwrap_or_else(|| Path::new("."))
    };

    if let Some(rest) = e
        .path
        .strip_prefix("artifacts/historical/gfs/aws/")
    {
        return root.join(rest).to_string_lossy().to_string();
    }

    root.join(&e.path).to_string_lossy().to_string()
}

fn compute_valid_time(date: &str, cycle_hour: i32, forecast_hour: i32) -> Result<i64> {
    let d = NaiveDate::parse_from_str(date, "%Y-%m-%d").with_context(|| format!("date {date}"))?;
    let dt = d
        .and_hms_opt(cycle_hour as u32, 0, 0)
        .ok_or_else(|| anyhow!("invalid cycle hour {} for date {}", cycle_hour, date))?;
    let base: DateTime<Utc> = Utc.from_utc_datetime(&dt);
    Ok((base + chrono::Duration::hours(forecast_hour as i64)).timestamp())
}

fn normalize_lon_0_360(lon: f64) -> f64 {
    let mut x = lon % 360.0;
    if x < 0.0 {
        x += 360.0;
    }
    x
}

fn tile_center(v: f64, step: f64) -> f64 {
    (v / step).round() * step
}

fn atmosphere_tile_key(lat: f64, lon0_360: f64, valid_time: i64, step: f64, level_mb: i32) -> String {
    let latc = tile_center(lat, step);
    let lonc = tile_center(lon0_360, step);
    format!(
        "atm_hist_gfs_{}_{}_{}_{}",
        valid_time,
        level_mb,
        (latc * 100.0).round() as i64,
        (lonc * 100.0).round() as i64
    )
}

async fn ingest_one_file(
    cfg: &Config,
    arango: &ArangoClient,
    e: &ManifestEntry,
    file_path: &str,
    valid_time: i64,
) -> Result<usize> {
    info!(
        "ingest file={} bytes={} sha256={} valid_time={}",
        file_path, e.bytes, e.sha256, valid_time
    );

    let f = File::open(file_path).with_context(|| format!("open {}", file_path))?;
    let f = BufReader::new(f);
    let grib2 = grib::from_reader(f).with_context(|| format!("parse grib2 {}", file_path))?;

    // For each pressure level, collect tiles for the 4 variables we need.
    let mut tiles_written = 0usize;
    for &level_mb in &cfg.levels_mb {
        let mut tiles: HashMap<(i64, i64), LayerTile> = HashMap::new();

        let mut found_temp = false;
        let mut found_uwind = false;
        let mut found_vwind = false;
        let mut found_hgt = false;

        for (_idx, sub) in grib2.iter() {
            let discipline = sub.indicator().discipline;
            let cat = match sub.prod_def().parameter_category() {
                Some(v) => v,
                None => continue,
            };
            let num = match sub.prod_def().parameter_number() {
                Some(v) => v,
                None => continue,
            };

            // We only care about isobaric surfaces at our target levels.
            let (first, _second) = match sub.prod_def().fixed_surfaces() {
                Some(v) => v,
                None => continue,
            };
            if first.surface_type != 100 {
                continue;
            }
            let p_pa = first.value();
            if !p_pa.is_finite() {
                continue;
            }
            let sfc_mb = (p_pa / 100.0).round() as i32;
            if sfc_mb != level_mb {
                continue;
            }

            let param_name = CodeTable4_2::new(discipline, cat).lookup(usize::from(num)).to_string();

            // Filter to the exact four fields needed.
            let kind = match (discipline, cat, num) {
                (0, 0, 0) => "temp_k",
                (0, 2, 2) => "u_ms",
                (0, 2, 3) => "v_ms",
                (0, 3, 5) => "hgt_m",
                _ => continue,
            };

            info!(
                "match level_mb={} kind={} discipline={} cat={} num={} name={}",
                level_mb, kind, discipline, cat, num, param_name
            );

            let latlons = sub.latlons().context("latlons")?;
            let decoder = Grib2SubmessageDecoder::from(sub).context("decoder")?;
            let values = decoder.dispatch().context("decode values")?;

            // Downsample by picking one representative point per tile.
            let mut kept = 0usize;
            for ((lat, lon), val) in latlons.zip(values) {
                if !val.is_finite() {
                    continue;
                }
                let lon0_360 = normalize_lon_0_360(f64::from(lon));
                let latc = tile_center(f64::from(lat), cfg.tile_step_deg);
                let lonc = tile_center(lon0_360, cfg.tile_step_deg);
                let key = ((latc * 100.0).round() as i64, (lonc * 100.0).round() as i64);
                let entry = tiles.entry(key).or_insert_with(|| LayerTile {
                    lat: latc,
                    lon: lonc,
                    ..Default::default()
                });

                let slot = match kind {
                    "temp_k" => &mut entry.temp_k,
                    "u_ms" => &mut entry.u_ms,
                    "v_ms" => &mut entry.v_ms,
                    "hgt_m" => &mut entry.hgt_m,
                    _ => continue,
                };

                if slot.is_none() {
                    *slot = Some(val as f64);
                    kept += 1;
                    if kept >= cfg.max_tiles_per_layer {
                        break;
                    }
                }
            }

            match kind {
                "temp_k" => found_temp = true,
                "u_ms" => found_uwind = true,
                "v_ms" => found_vwind = true,
                "hgt_m" => found_hgt = true,
                _ => {}
            }

            if found_temp && found_uwind && found_vwind && found_hgt {
                break;
            }
        }

        if !(found_temp && found_uwind && found_vwind && found_hgt) {
            warn!(
                "missing variables for level_mb={} temp={} u={} v={} hgt={} (file={})",
                level_mb, found_temp, found_uwind, found_vwind, found_hgt, e.path
            );
            continue;
        }

        // Write atmosphere tiles for those tiles that have all four values.
        let mut wrote_level = 0usize;
        for t in tiles.values() {
            let (temp_k, u_ms, v_ms, hgt_m) = match (t.temp_k, t.u_ms, t.v_ms, t.hgt_m) {
                (Some(a), Some(b), Some(c), Some(d)) => (a, b, c, d),
                _ => continue,
            };

            // Pressure level in Pa (from fixed surface)
            let pressure_pa = (level_mb as f64) * 100.0;
            // Ideal gas (dry air) for density
            let rho = pressure_pa / (287.05 * temp_k);

            // Approx geometric altitude from geopotential height (close enough for cruise-level regression evidence)
            let altitude_m = hgt_m;
            let altitude_ft = altitude_m * 3.28084;

            let tile_key = atmosphere_tile_key(t.lat, t.lon, valid_time, cfg.tile_step_deg, level_mb);

            let doc = json!({
              "_key": tile_key,
              "location": { "type": "Point", "coordinates": [t.lon, t.lat] },
              "valid_time": valid_time,
              "resolution_deg": cfg.tile_step_deg,
              "resolution_level": 4,
              "altitude_m": altitude_m,
              "altitude_ft": altitude_ft,
              "pressure_level_mb": level_mb,
              "state": {
                "air_density_kg_m3": rho,
                "temperature_k": temp_k,
                "pressure_pa": pressure_pa,
                "wind_u": u_ms,
                "wind_v": v_ms,
              },
              "provenance": {
                "source": "aws_gfs_0p25_historical",
                "dataset_url": e.url,
                    "file_path": file_path,
                "sha256": e.sha256,
                "ingested_at": Utc::now().to_rfc3339(),
              }
            });

            arango
                .upsert_document(&cfg.atmosphere_tiles_collection, &doc)
                .await?;
            wrote_level += 1;
        }

        tiles_written += wrote_level;
        info!(
            "wrote level_mb={} tiles_written={} (valid_time={})",
            level_mb, wrote_level, valid_time
        );
    }

    Ok(tiles_written)
}


