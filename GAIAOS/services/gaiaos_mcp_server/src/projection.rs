//! Cell Projection System
//!
//! Each cell:
//! - Finds itself in the substrate (unique 8D point)
//! - Discovers other cells
//! - Projects to NATS channels for communication
//! - Cannot occupy another cell's 8D point
//! - Can project NEAR other cells' spaces
//!
//! Projection is a Q-state language game.

use crate::viewspace::{get_viewspace, Viewspace8D};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::HashMap;
use std::sync::{Arc, RwLock};

/// A cell's position in the 8D substrate
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubstratePosition {
    pub cell_id: String,
    pub coordinates: [f64; 8], // t, x, y, z, n, l, vp, fp
    pub radius: f64,           // Cell's "size" in 8D space
    pub discovered_at: u64,
}

#[allow(dead_code)]
impl SubstratePosition {
    pub fn from_viewspace(viewspace: &Viewspace8D) -> Self {
        let coords = [
            viewspace
                .dimensions
                .get("t")
                .map(|d| d.current())
                .unwrap_or(0.5),
            viewspace
                .dimensions
                .get("x")
                .map(|d| d.current())
                .unwrap_or(0.5),
            viewspace
                .dimensions
                .get("y")
                .map(|d| d.current())
                .unwrap_or(0.5),
            viewspace
                .dimensions
                .get("z")
                .map(|d| d.current())
                .unwrap_or(0.5),
            viewspace
                .dimensions
                .get("n")
                .map(|d| d.current())
                .unwrap_or(0.5),
            viewspace
                .dimensions
                .get("l")
                .map(|d| d.current())
                .unwrap_or(0.5),
            viewspace
                .dimensions
                .get("vp")
                .map(|d| d.current())
                .unwrap_or(0.5),
            viewspace
                .dimensions
                .get("fp")
                .map(|d| d.current())
                .unwrap_or(0.5),
        ];

        Self {
            cell_id: viewspace.cell_id.clone(),
            coordinates: coords,
            radius: 0.05, // Default cell radius in 8D space
            discovered_at: viewspace.created_at,
        }
    }

    /// Calculate 8D distance to another position
    pub fn distance_to(&self, other: &SubstratePosition) -> f64 {
        self.coordinates
            .iter()
            .zip(other.coordinates.iter())
            .map(|(a, b)| (a - b).powi(2))
            .sum::<f64>()
            .sqrt()
    }

    /// Check if this position overlaps with another (impossible in real space)
    pub fn overlaps(&self, other: &SubstratePosition) -> bool {
        self.distance_to(other) < (self.radius + other.radius)
    }

    /// Check if this position is near another (for projection)
    pub fn is_near(&self, other: &SubstratePosition, threshold: f64) -> bool {
        self.distance_to(other) < threshold
    }
}

/// A projection from one cell - the Q-state language message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Projection {
    pub id: String,
    pub from_cell: String,
    pub from_position: [f64; 8],
    pub target_context: String,        // Context this projection is for
    pub qstate_message: QStateMessage, // The language
    pub coherence: f64,
    pub virtue: f64,
    pub timestamp: u64,
}

/// Q-state based message - the language of projection
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QStateMessage {
    pub intent: String,                  // What the projection means
    pub amplitude: f64,                  // Strength of projection (0-1)
    pub phase: f64,                      // Phase in the projection space
    pub entanglement_keys: Vec<String>,  // Other cells this is entangled with
    pub collapsed_value: Option<String>, // If observed/collapsed
}

/// Registry of all cells in the substrate
#[derive(Debug, Default)]
pub struct SubstrateRegistry {
    pub cells: HashMap<String, SubstratePosition>,
    pub projections: HashMap<String, Vec<Projection>>, // cell_id -> active projections
}

#[allow(dead_code)]
impl SubstrateRegistry {
    /// Cell discovers itself in the substrate
    pub fn discover_self(&mut self, cell_id: &str) -> SubstratePosition {
        let viewspace = get_viewspace(cell_id);
        let position = SubstratePosition::from_viewspace(&viewspace);

        // Ensure no overlap with existing cells
        for (other_id, other_pos) in &self.cells {
            if other_id != cell_id && position.overlaps(other_pos) {
                // In real system, would need to resolve - for now just log
                tracing::warn!(
                    "Cell {} would overlap with {} - this should be impossible",
                    cell_id,
                    other_id
                );
            }
        }

        self.cells.insert(cell_id.to_string(), position.clone());
        position
    }

    /// Cell discovers other cells in the substrate
    pub fn discover_others(&self, cell_id: &str) -> Vec<SubstratePosition> {
        self.cells
            .iter()
            .filter(|(id, _)| *id != cell_id)
            .map(|(_, pos)| pos.clone())
            .collect()
    }

    /// Cell discovers nearby cells (within projection range)
    pub fn discover_nearby(&self, cell_id: &str, range: f64) -> Vec<SubstratePosition> {
        let Some(self_pos) = self.cells.get(cell_id) else {
            return vec![];
        };

        self.cells
            .iter()
            .filter(|(id, pos)| *id != cell_id && self_pos.is_near(pos, range))
            .map(|(_, pos)| pos.clone())
            .collect()
    }

    /// Create a projection from a cell
    /// This also publishes to NATS channel comm.projection.<cell_id>
    pub fn create_projection(
        &mut self,
        cell_id: &str,
        target_context: &str,
        intent: &str,
    ) -> Option<Projection> {
        let viewspace = get_viewspace(cell_id);
        let position = SubstratePosition::from_viewspace(&viewspace);

        let projection = Projection {
            id: format!(
                "proj_{}_{}",
                cell_id,
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_millis()
            ),
            from_cell: cell_id.to_string(),
            from_position: position.coordinates,
            target_context: target_context.to_string(),
            qstate_message: QStateMessage {
                intent: intent.to_string(),
                amplitude: viewspace.coherence,
                phase: viewspace
                    .dimensions
                    .get("t")
                    .map(|d| d.current() * std::f64::consts::TAU)
                    .unwrap_or(0.0),
                entanglement_keys: vec![],
                collapsed_value: None,
            },
            coherence: viewspace.coherence,
            virtue: viewspace.virtue_score(),
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64,
        };

        // Store projection
        self.projections
            .entry(cell_id.to_string())
            .or_default()
            .push(projection.clone());

        // Log projection for NATS (actual NATS publish would happen in async context)
        tracing::info!(
            "PROJECTION: {} -> {} [intent: {}, amplitude: {:.3}]",
            cell_id,
            target_context,
            intent,
            projection.coherence
        );

        Some(projection)
    }

    /// Get all active projections for a cell
    pub fn get_projections(&self, cell_id: &str) -> Vec<Projection> {
        self.projections.get(cell_id).cloned().unwrap_or_default()
    }

    /// Project into near-space of another cell
    pub fn project_near(
        &mut self,
        from_cell: &str,
        to_cell: &str,
        intent: &str,
    ) -> Option<Projection> {
        let context = format!("near:{to_cell}");
        self.create_projection(from_cell, &context, intent)
    }
}

lazy_static::lazy_static! {
    pub static ref SUBSTRATE: Arc<RwLock<SubstrateRegistry>> =
        Arc::new(RwLock::new(SubstrateRegistry::default()));
}

/// Cell discovers itself and returns position
pub fn cell_discover_self(cell_id: &str) -> SubstratePosition {
    let mut substrate = SUBSTRATE.write().unwrap();
    substrate.discover_self(cell_id)
}

/// Cell discovers others
pub fn cell_discover_others(cell_id: &str) -> Vec<SubstratePosition> {
    let substrate = SUBSTRATE.read().unwrap();
    substrate.discover_others(cell_id)
}

/// Cell creates a projection
pub fn cell_project(cell_id: &str, context: &str, intent: &str) -> Option<Projection> {
    let mut substrate = SUBSTRATE.write().unwrap();
    substrate.create_projection(cell_id, context, intent)
}

/// Cell projects near another cell
#[allow(dead_code)]
pub fn cell_project_near(from_cell: &str, to_cell: &str, intent: &str) -> Option<Projection> {
    let mut substrate = SUBSTRATE.write().unwrap();
    substrate.project_near(from_cell, to_cell, intent)
}

/// Get cell's projections
pub fn cell_get_projections(cell_id: &str) -> Vec<Projection> {
    let substrate = SUBSTRATE.read().unwrap();
    substrate.get_projections(cell_id)
}

// ============================================================================
// LANGUAGE PROJECTION LAYER (CONSTITUTIONAL: PROJECT STATE TO LANGUAGE AT QUERY TIME)
// ============================================================================

/// Project manifold state to surface language
/// CRITICAL: audience_position is a manifold position, NOT a string label
/// arango_password: from Docker secret /run/secrets/arango_password (never env var in production)
pub async fn project_state_to_language(
    manifold_position: [f64; 8],
    discovery_refs: Vec<String>,
    audience_position: [f64; 8],
    arango_url: &str,
    arango_db: &str,
    arango_password: &str,
) -> Result<String, String> {
    // 1. Query ArangoDB for discoveries at discovery_refs
    let client = reqwest::Client::new();
    let mut discoveries: Vec<serde_json::Value> = Vec::new();
    
    for ref_id in &discovery_refs {
        let parts: Vec<&str> = ref_id.split('/').collect();
        if parts.len() != 2 {
            continue;
        }
        
        let query = json!({
            "query": format!("FOR d IN {} FILTER d._id == @ref_id RETURN d", parts[0]),
            "bindVars": {"ref_id": ref_id}
        });
        
        let resp = client
            .post(format!("{}/_db/{}/_api/cursor", arango_url, arango_db))
            .json(&query)
            .basic_auth("root", Some(arango_password))
            .send()
            .await;
        
        if let Ok(r) = resp {
            if let Ok(body) = r.json::<serde_json::Value>().await {
                if let Some(results) = body.get("result").and_then(|r| r.as_array()) {
                    discoveries.extend(results.iter().cloned());
                }
            }
        }
    }
    
    // 2. Compute dimensional affinity between manifold_position and audience_position
    let mut affinity_scores: Vec<(usize, f64)> = Vec::new();
    for i in 0..8 {
        let distance = (manifold_position[i] - audience_position[i]).abs();
        let affinity = 1.0 - distance;  // Closer = higher affinity
        affinity_scores.push((i, affinity));
    }
    
    // Sort by affinity (highest first)
    affinity_scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
    
    // 3. Compose semantic primitives based on dimensional alignment
    // High affinity dimensions should be emphasized in projection
    let primary_dimensions: Vec<usize> = affinity_scores.iter().take(3).map(|(i, _)| *i).collect();
    
    // 4. Extract constraint structure from discoveries
    let mut substances: Vec<String> = Vec::new();
    let mut mechanisms: Vec<String> = Vec::new();
    let mut domains: Vec<String> = Vec::new();
    
    for disc in &discoveries {
        if let Some(name) = disc.get("name").and_then(|n| n.as_str()) {
            substances.push(name.to_string());
        }
        if let Some(mech) = disc.get("mechanism").and_then(|m| m.as_str()) {
            mechanisms.push(mech.to_string());
        }
        if let Some(dom) = disc.get("domain").and_then(|d| d.as_str()) {
            domains.push(dom.to_string());
        }
    }
    
    // 5. Project to surface language — meaning first, not metadata
    // Lead with constraint structure (domains, substances, mechanisms); dimensional alignment as context
    let dim_names = ["coherence", "charge", "hydrophobicity", "aromatic", "size", "time_dynamics", "spatial_variance", "entropy_reduction"];
    let emphasized_dims: Vec<String> = primary_dimensions.iter().map(|i| dim_names[*i].to_string()).collect();
    
    let domain_str = if domains.is_empty() {
        "constraint space".to_string()
    } else {
        domains.join(", ")
    };
    let substance_str = substances.iter().take(5).cloned().collect::<Vec<_>>().join(", ");
    let mechanism_str = mechanisms.iter().take(3).cloned().collect::<Vec<_>>().join("; ");
    let sub_display: &str = if substance_str.is_empty() { "—" } else { &substance_str };
    let mech_display: &str = if mechanism_str.is_empty() { "—" } else { &mechanism_str };
    
    let projection = if !substance_str.is_empty() || !mechanism_str.is_empty() {
        format!(
            "Within {}: {}. {}. Alignment with receiver on {} at {:.2} affinity.",
            domain_str,
            sub_display,
            mech_display,
            emphasized_dims.join(", "),
            affinity_scores[0].1
        )
    } else {
        format!(
            "Constraint structure in {}. Dimensional alignment: {} at {:.2} affinity.",
            domain_str,
            emphasized_dims.join(", "),
            affinity_scores[0].1
        )
    };
    
    Ok(projection)
}
