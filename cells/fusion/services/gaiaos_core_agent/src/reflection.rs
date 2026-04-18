//! GaiaOS Core Agent Reflection (evidence-only)
//!
//! This module produces an evidence-grounded progress report across substrates
//! and nominates next world-models to instantiate, without simulation or LLM calls.

use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::json;

#[derive(Debug, Clone, Serialize)]
pub struct ReflectionReport {
    pub arango_url: String,
    pub database: String,
    pub collection_counts: Vec<CollectionCount>,
    pub recommended_next_worlds: Vec<NextWorldRecommendation>,
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct CollectionCount {
    pub collection: String,
    pub count: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct NextWorldRecommendation {
    pub world: String,
    pub rationale: String,
    pub required_real_ingests: Vec<String>,
    pub required_validator_gates: Vec<String>,
}

#[derive(Clone)]
struct Arango {
    base_url: String,
    db: String,
    user: String,
    password: String,
    client: reqwest::Client,
}

impl Arango {
    fn from_env() -> Result<Self> {
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(20))
            .build()
            .context("failed to build reqwest client")?;
        Ok(Self {
            base_url: std::env::var("ARANGO_URL").unwrap_or_else(|_| "http://arangodb:8529".to_string()),
            db: std::env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
            user: std::env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            password: std::env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
            client,
        })
    }

    async fn count_collection(&self, collection: &str) -> Result<i64> {
        let url = format!("{}/_db/{}/_api/cursor", self.base_url.trim_end_matches('/'), self.db);
        let aql = format!(
            "FOR d IN {collection} COLLECT WITH COUNT INTO length RETURN length",
            collection = collection
        );
        let resp = self
            .client
            .post(url)
            .basic_auth(&self.user, Some(&self.password))
            .json(&json!({ "query": aql }))
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("count query failed for {collection}: {status} {text}"));
        }

        #[derive(Deserialize)]
        struct CursorResp {
            result: Vec<i64>,
        }
        let body: CursorResp = resp.json().await?;
        Ok(body.result.get(0).copied().unwrap_or(0))
    }
}

pub async fn generate_reflection_report() -> Result<ReflectionReport> {
    let arango = Arango::from_env()?;

    let collections = vec![
        // Macro field substrate
        "observations",
        "atmosphere_tiles",
        "ocean_tiles",
        "biosphere_tiles",
        "field_relations",
        "field_validations",
        // Molecular substrate
        "molecular_tiles",
        "molecular_interactions",
        "protein_structures",
        "drug_molecules",
        "folding_trajectories",
        // Astro substrate
        "gravitational_tiles",
        "orbital_trajectories",
        "space_objects",
        "conjunction_events",
        // FoT claims
        "mcp_claims",
    ];

    let mut counts: Vec<CollectionCount> = Vec::new();
    let mut notes: Vec<String> = Vec::new();

    for c in &collections {
        match arango.count_collection(c).await {
            Ok(n) => counts.push(CollectionCount {
                collection: c.to_string(),
                count: n,
            }),
            Err(e) => {
                // Evidence-only: record missing collections as a blocker rather than guessing.
                notes.push(format!("collection_count_unavailable: {c}: {e}"));
                counts.push(CollectionCount {
                    collection: c.to_string(),
                    count: -1,
                });
            }
        }
    }

    let get = |name: &str| counts.iter().find(|x| x.collection == name).map(|x| x.count).unwrap_or(-1);

    let mut recs: Vec<NextWorldRecommendation> = Vec::new();

    // If molecular substrate has no data, the next world is molecular ingest wiring.
    if get("molecular_tiles") <= 0 || get("molecular_tiles") == -1 {
        recs.push(NextWorldRecommendation {
            world: "Molecular substrate (protein folding + drug binding)".to_string(),
            rationale: "Schema + validators exist; evidence lane is empty or unknown. Closure requires real molecular tiles + interactions and validated prediction artifacts.".to_string(),
            required_real_ingests: vec![
                "MD engine snapshots -> molecular_tiles (AMBER/OpenMM/GROMACS output)".to_string(),
                "Bond/interaction extraction -> molecular_interactions".to_string(),
                "Protein registry -> protein_structures (sequence + binding sites)".to_string(),
                "Drug registry -> drug_molecules (SMILES + constitutional fields)".to_string(),
            ],
            required_validator_gates: vec![
                "qfot_molecular temporal+provenance+observer closure".to_string(),
                "molecular energy-term presence (potential/kinetic)".to_string(),
            ],
        });
    }

    // If astro substrate has no data, next world is orbital/gravity ingest wiring.
    if get("gravitational_tiles") <= 0 || get("gravitational_tiles") == -1 {
        recs.push(NextWorldRecommendation {
            world: "Astro world (gravity field + orbital traffic)".to_string(),
            rationale: "Schema + validators exist; evidence lane is empty or unknown. Closure requires real gravitational tiles and validated forecast artifacts.".to_string(),
            required_real_ingests: vec![
                "TLE/ephemeris ingest -> orbital_trajectories/space_objects".to_string(),
                "Gravity model ingest -> gravitational_tiles (JPL/SGP4 outputs)".to_string(),
                "Conjunction screening ingest -> conjunction_events".to_string(),
            ],
            required_validator_gates: vec![
                "qfot_astro temporal+provenance+observer closure".to_string(),
                "gravity-term presence (gravitational_potential/g_field_magnitude)".to_string(),
            ],
        });
    }

    // Always propose one additional “next world” beyond the 3-substrate triad, grounded by macro stack readiness.
    recs.push(NextWorldRecommendation {
        world: "Biosphere world (ecosystems + pathogens + food web fields)".to_string(),
        rationale: "Macro substrate closure machinery (tiles+relations+validators) is in place; biosphere is the next natural continuous field with strong observational grounding (satellite NDVI, epidemiology, fisheries).".to_string(),
        required_real_ingests: vec![
            "Remote sensing tiles (NDVI/land cover) -> boundary_tiles or new biosphere_tiles".to_string(),
            "Epidemiology case streams -> observations".to_string(),
            "Fisheries/agriculture production -> trajectories/relations".to_string(),
        ],
        required_validator_gates: vec![
            "temporal closure (publish time < valid time)".to_string(),
            "observer closure (sensor provenance required)".to_string(),
            "constitutional closure (safety constraints for bio domain)".to_string(),
        ],
    });

    Ok(ReflectionReport {
        arango_url: arango.base_url,
        database: arango.db,
        collection_counts: counts,
        recommended_next_worlds: recs,
        notes,
    })
}


