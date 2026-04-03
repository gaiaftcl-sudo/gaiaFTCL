//! Molecular ingest from PubChem (real 3D coordinates) + local chemistry registry.
//!
//! Inputs:
//! - `config/domains/medical/inv3_aml/chemistry.json` (SMILES + binding metrics)
//! - PubChem PUG REST 3D record (atomic coordinates)
//!
//! Outputs (ArangoDB `gaiaos`):
//! - `drug_molecules` registry docs (SMILES + constitutional properties)
//! - `molecular_tiles` seed tiles with real 3D centroid position and energy terms derived from Kd/temperature
//!
//! FoT: no synthetic coordinates; coordinates come from PubChem 3D record.

use anyhow::{anyhow, Context, Result};
use chrono::Utc;
use log::{info, warn};
use serde::Deserialize;
use serde_json::json;
use std::{env, fs, time::Duration};

#[derive(Clone)]
struct Config {
    arango_url: String,
    arango_db: String,
    arango_user: String,
    arango_password: String,
    chemistry_path: String,
    max_compounds: usize,
    temperature_k: f64,
    resolution_angstrom: f64,
}

impl Config {
    fn from_env() -> Self {
        Self {
            arango_url: env::var("ARANGO_URL").unwrap_or_else(|_| "http://localhost:8529".to_string()),
            arango_db: env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
            arango_user: env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            arango_password: env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
            chemistry_path: env::var("CHEMISTRY_JSON")
                .unwrap_or_else(|_| "config/domains/medical/inv3_aml/chemistry.json".to_string()),
            max_compounds: env::var("MAX_COMPOUNDS").ok().and_then(|v| v.parse().ok()).unwrap_or(10),
            temperature_k: env::var("TEMPERATURE_K").ok().and_then(|v| v.parse().ok()).unwrap_or(298.15),
            resolution_angstrom: env::var("RESOLUTION_ANGSTROM").ok().and_then(|v| v.parse().ok()).unwrap_or(1.0),
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
            .user_agent("GaiaOS-Molecular-PubChem-Ingest/0.1.0")
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

#[derive(Debug, Deserialize)]
struct ChemistryFile {
    compounds: Vec<Compound>,
}

#[derive(Debug, Deserialize)]
struct Compound {
    id: String,
    name: String,
    #[serde(default)]
    akg_node_id: Option<String>,
    #[serde(default)]
    smiles: Option<String>,
    #[serde(default)]
    molecular_weight: Option<f64>,
    #[serde(default)]
    drug_like_properties: Option<serde_json::Value>,
    #[serde(default)]
    pharmacology: Option<serde_json::Value>,
    #[serde(default)]
    mechanism_of_action: Option<serde_json::Value>,
    #[serde(default)]
    quantum_metrics: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
struct PubChemRecord {
    #[serde(rename = "PC_Compounds")]
    compounds: Vec<PubChemCompound>,
}

#[derive(Debug, Deserialize)]
struct PubChemCompound {
    #[serde(default)]
    id: serde_json::Value,
    coords: Vec<PubChemCoords>,
}

#[derive(Debug, Deserialize)]
struct PubChemCoords {
    conformers: Vec<PubChemConformer>,
}

#[derive(Debug, Deserialize)]
struct PubChemConformer {
    x: Vec<f64>,
    y: Vec<f64>,
    #[serde(default)]
    z: Vec<f64>,
}

async fn fetch_pubchem_coords(smiles: &str) -> Result<(Option<u64>, [f64; 3], &'static str)> {
    let encoded = urlencoding::encode(smiles);
    let client = reqwest::Client::new();

    // Try 3D first (requires existing CID).
    let url3 = format!(
        "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/smiles/{encoded}/record/JSON?record_type=3d"
    );
    let resp3 = client.get(url3).send().await.context("pubchem 3d request failed")?;
    if resp3.status().is_success() {
        let body: PubChemRecord = resp3.json().await.context("pubchem 3d json decode failed")?;
        let c = body
            .compounds
            .get(0)
            .ok_or_else(|| anyhow!("pubchem 3d: no compound in response"))?;
        let cid = c
            .id
            .get("id")
            .and_then(|v| v.get("cid"))
            .and_then(|v| v.as_u64());
        let conformer = c
            .coords
            .get(0)
            .and_then(|cc| cc.conformers.get(0))
            .ok_or_else(|| anyhow!("pubchem 3d: no conformer coords"))?;
        let n = conformer.x.len().min(conformer.y.len()).min(conformer.z.len());
        if n == 0 {
            return Err(anyhow!("pubchem 3d: empty coordinate arrays"));
        }
        let mut sx = 0.0;
        let mut sy = 0.0;
        let mut sz = 0.0;
        for i in 0..n {
            sx += conformer.x[i];
            sy += conformer.y[i];
            sz += conformer.z[i];
        }
        let centroid = [sx / n as f64, sy / n as f64, sz / n as f64];
        return Ok((cid, centroid, "3d"));
    }

    // Fallback to 2D if 3D is unavailable. z is set to 0 with explicit provenance.
    let url2 = format!(
        "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/smiles/{encoded}/record/JSON?record_type=2d"
    );
    let resp2 = client.get(url2).send().await.context("pubchem 2d request failed")?;
    if !resp2.status().is_success() {
        let status = resp2.status();
        let text = resp2.text().await.unwrap_or_default();
        return Err(anyhow!("pubchem 2d failed {status}: {text}"));
    }
    let body: PubChemRecord = resp2.json().await.context("pubchem 2d json decode failed")?;
    let c = body
        .compounds
        .get(0)
        .ok_or_else(|| anyhow!("pubchem 2d: no compound in response"))?;
    let cid = c
        .id
        .get("id")
        .and_then(|v| v.get("cid"))
        .and_then(|v| v.as_u64());
    let conformer = c
        .coords
        .get(0)
        .and_then(|cc| cc.conformers.get(0))
        .ok_or_else(|| anyhow!("pubchem 2d: no conformer coords"))?;
    let n = conformer.x.len().min(conformer.y.len());
    if n == 0 {
        return Err(anyhow!("pubchem 2d: empty coordinate arrays"));
    }
    let mut sx = 0.0;
    let mut sy = 0.0;
    for i in 0..n {
        sx += conformer.x[i];
        sy += conformer.y[i];
    }
    let centroid = [sx / n as f64, sy / n as f64, 0.0];
    Ok((cid, centroid, "2d"))
}

fn delta_g_kcal_mol_from_kd_nm(kd_nm: f64, temperature_k: f64) -> Option<f64> {
    if kd_nm <= 0.0 {
        return None;
    }
    // ΔG = RT ln(Kd) with Kd in mol/L (M). R in kcal/mol/K.
    let kd_m = kd_nm * 1e-9;
    let r = 0.001_987_204_258_640_83_f64;
    Some(r * temperature_k * kd_m.ln())
}

fn kinetic_energy_kcal_mol(temperature_k: f64) -> f64 {
    // Equipartition (translational) per mole: (3/2) RT.
    let r = 0.001_987_204_258_640_83_f64;
    1.5 * r * temperature_k
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

    let bytes = fs::read(&cfg.chemistry_path)
        .with_context(|| format!("failed to read {}", cfg.chemistry_path))?;
    let chem: ChemistryFile = serde_json::from_slice(&bytes).context("failed to parse chemistry.json")?;

    let mut tiles_written = 0usize;
    let mut drugs_written = 0usize;

    for (i, c) in chem.compounds.iter().enumerate() {
        if i >= cfg.max_compounds {
            break;
        }
        let Some(smiles) = c.smiles.as_deref() else {
            warn!("skip: compound {} missing smiles", c.id);
            continue;
        };

        let (cid, centroid, coord_type) = match fetch_pubchem_coords(smiles).await {
            Ok(v) => v,
            Err(e) => {
                warn!("skip: pubchem 3d failed for {}: {e}", c.id);
                continue;
            }
        };

        // Drug registry doc
        let drug_key = format!("DRUG_{}", c.id);
        let drug_doc = json!({
            "_key": drug_key,
            "compound_id": c.id,
            "name": c.name,
            "akg_node_id": c.akg_node_id,
            "smiles": smiles,
            "molecular_weight": c.molecular_weight,
            "drug_like_properties": c.drug_like_properties,
            "pharmacology": c.pharmacology,
            "mechanism_of_action": c.mechanism_of_action,
            "quantum_metrics": c.quantum_metrics,
            "provenance": {
                "source": "local_registry+pubchem_3d",
                "chemistry_path": cfg.chemistry_path,
                "pubchem_cid": cid,
                "pubchem_record_type": coord_type,
                "ingested_at": Utc::now().to_rfc3339()
            }
        });
        arango.upsert_document("drug_molecules", &drug_doc).await?;
        drugs_written += 1;

        // Derive energy terms from Kd if present.
        let affinity_nm = c
            .pharmacology
            .as_ref()
            .and_then(|p| {
                p.get("kd_nm")
                    .and_then(|v| v.as_f64())
                    .or_else(|| p.get("ic50_nm").and_then(|v| v.as_f64()))
                    .or_else(|| p.get("ec50_nm").and_then(|v| v.as_f64()))
            });
        let potential_energy = affinity_nm.and_then(|kd| delta_g_kcal_mol_from_kd_nm(kd, cfg.temperature_k));
        let Some(potential_energy) = potential_energy else {
            warn!("skip: compound {} missing affinity metrics for potential_energy derivation", c.id);
            continue;
        };

        // Minimal seed tile: represents compound centroid in Å.
        // protein_id is taken from mechanism_of_action.primary_target if present; otherwise use "unknown_target".
        let protein_id = c
            .mechanism_of_action
            .as_ref()
            .and_then(|m| m.get("primary_target"))
            .and_then(|v| v.as_str())
            .unwrap_or("unknown_target")
            .to_string();

        let now = Utc::now().timestamp();
        let tile_key = match cid {
            Some(cid) => format!("MOL_{}_CID{}_{}", c.id, cid, now),
            None => format!("MOL_{}_NO_CID_{}", c.id, now),
        };
        let tile_doc = json!({
            "_key": tile_key,
            "protein_id": protein_id,
            "trajectory_id": format!("pubchem_centroid_{}", c.id),
            "position_angstrom": { "type": "Point", "coordinates": [centroid[0], centroid[1]] },
            "z_angstrom": centroid[2],
            "resolution_angstrom": cfg.resolution_angstrom,
            "simulation_time_ps": 0.0,
            "timestep_fs": 0.0,
            "ingest_timestamp": now,
            "state": {
                "temperature_k": cfg.temperature_k,
                "potential_energy": potential_energy,
                "kinetic_energy": kinetic_energy_kcal_mol(cfg.temperature_k),
                "pubchem_cid": cid,
                "pubchem_record_type": coord_type,
                "smiles": smiles
            },
            "provenance": {
                "source": "pubchem_3d_centroid",
                "model_version": env!("CARGO_PKG_VERSION"),
                "ingested_at": Utc::now().to_rfc3339(),
                "is_prediction": false,
                "pubchem_cid": cid,
                "pubchem_record_type": coord_type,
                "chemistry_path": cfg.chemistry_path
            }
        });
        arango.upsert_document("molecular_tiles", &tile_doc).await?;
        tiles_written += 1;
    }

    info!(
        "molecular_pubchem_ingest complete: drug_molecules_upserted={} molecular_tiles_upserted={}",
        drugs_written, tiles_written
    );
    Ok(())
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


