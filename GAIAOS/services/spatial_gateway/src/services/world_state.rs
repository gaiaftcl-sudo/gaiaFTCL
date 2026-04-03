//! World State Service
//! 
//! The live truth field - stores all spatial samples and supports queries.
//! This is the canonical source of "what is where" in GaiaOS.

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::model::vqbit::Vqbit8D;
use crate::model::cell::CellDomain;

/// A single sample in the world state
#[derive(Debug, Clone)]
pub struct WorldSample {
    /// Cell that produced this sample
    pub cell_id: Uuid,
    /// Domain of the cell
    pub domain: CellDomain,
    /// 8D vQbit representation
    pub vqbit: Vqbit8D,
    /// Timestamp (unix seconds)
    pub ts_unix: f64,
}

/// Configuration for world state
#[derive(Debug, Clone)]
pub struct WorldStateConfig {
    /// Maximum samples to retain
    pub max_samples: usize,
    /// Maximum age of samples in seconds
    pub max_age_secs: f64,
    /// Whether to deduplicate samples from same cell
    pub deduplicate_cells: bool,
}

impl Default for WorldStateConfig {
    fn default() -> Self {
        Self {
            max_samples: 1_000_000,
            max_age_secs: 3600.0, // 1 hour
            deduplicate_cells: true,
        }
    }
}

/// World state storage and query service
#[derive(Clone)]
pub struct WorldState {
    /// All samples (could be replaced with spatial index)
    samples: Arc<RwLock<Vec<WorldSample>>>,
    /// Latest sample per cell (for deduplication)
    latest_by_cell: Arc<RwLock<HashMap<Uuid, WorldSample>>>,
    /// Configuration
    config: WorldStateConfig,
}

impl Default for WorldState {
    fn default() -> Self {
        Self::new(WorldStateConfig::default())
    }
}

impl WorldState {
    /// Create new world state with config
    pub fn new(config: WorldStateConfig) -> Self {
        Self {
            samples: Arc::new(RwLock::new(Vec::new())),
            latest_by_cell: Arc::new(RwLock::new(HashMap::new())),
            config,
        }
    }
    
    /// Get current unix timestamp
    pub fn now() -> f64 {
        Vqbit8D::now_unix()
    }
    
    /// Insert a new sample
    pub async fn insert_sample(&self, sample: WorldSample) {
        // Update latest per cell
        self.latest_by_cell
            .write()
            .await
            .insert(sample.cell_id, sample.clone());
        
        // Add to main store
        let mut samples = self.samples.write().await;
        
        // SAFETY: Check deduplication setting to prevent memory bloat
        if self.config.deduplicate_cells {
            // If we already have a recent sample from this cell, skip
            // This prevents one cell from flooding the store
            let has_recent = samples.iter().rev().take(100).any(|s| {
                s.cell_id == sample.cell_id && 
                (sample.ts_unix - s.ts_unix).abs() < 1.0  // Within 1 second
            });
            
            if has_recent {
                tracing::trace!(
                    cell_id = %sample.cell_id,
                    "Skipping duplicate sample from same cell"
                );
                return;
            }
        }
        
        samples.push(sample);
        
        // Prune if over limit
        if samples.len() > self.config.max_samples {
            let excess = samples.len() - self.config.max_samples;
            samples.drain(0..excess);
        }
    }
    
    /// Query samples in a spatial/temporal region
    /// Note: For this version, we treat (lon, lat) as (d0_x, d1_y) directly
    /// In production, the vQbits store ENU coordinates, so queries should be in ENU
    pub async fn query_region(
        &self,
        domain: Option<&CellDomain>,
        lon_min: f64,
        lon_max: f64,
        lat_min: f64,
        lat_max: f64,
        t_min: Option<f64>,
        t_max: Option<f64>,
    ) -> Vec<WorldSample> {
        let samples = self.samples.read().await;
        
        samples
            .iter()
            .filter(|s| {
                // Domain filter
                let in_dom = domain.map(|d| &s.domain == d).unwrap_or(true);
                
                // Spatial bounds (using d0_x as lon proxy, d1_y as lat proxy)
                // Note: In production, you'd convert query bbox to ENU first
                let in_x = s.vqbit.d0_x >= lon_min && s.vqbit.d0_x <= lon_max;
                let in_y = s.vqbit.d1_y >= lat_min && s.vqbit.d1_y <= lat_max;
                
                // Temporal filter
                let in_time = {
                    let t = s.ts_unix;
                    let ok_min = t_min.map(|v| t >= v).unwrap_or(true);
                    let ok_max = t_max.map(|v| t <= v).unwrap_or(true);
                    ok_min && ok_max
                };
                
                in_dom && in_x && in_y && in_time
            })
            .cloned()
            .collect()
    }
    
    /// Query samples near a point (in ENU meters or lon/lat depending on storage)
    pub async fn query_near(
        &self,
        x: f64,
        y: f64,
        radius: f64,
        domain: Option<&CellDomain>,
        limit: Option<usize>,
    ) -> Vec<WorldSample> {
        let samples = self.samples.read().await;
        
        let mut results: Vec<(f64, WorldSample)> = samples
            .iter()
            .filter(|s| {
                let dx = s.vqbit.d0_x - x;
                let dy = s.vqbit.d1_y - y;
                let dist = (dx * dx + dy * dy).sqrt();
                let in_radius = dist <= radius;
                let in_dom = domain.map(|d| &s.domain == d).unwrap_or(true);
                in_radius && in_dom
            })
            .map(|s| {
                let dx = s.vqbit.d0_x - x;
                let dy = s.vqbit.d1_y - y;
                let dist = (dx * dx + dy * dy).sqrt();
                (dist, s.clone())
            })
            .collect();
        
        // Sort by distance
        results.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap());
        
        // Apply limit
        if let Some(lim) = limit {
            results.truncate(lim);
        }
        
        results.into_iter().map(|(_, s)| s).collect()
    }
    
    /// Get latest position for each cell in a domain
    #[allow(dead_code)]
    pub async fn get_latest_by_domain(&self, domain: &CellDomain) -> Vec<WorldSample> {
        self.latest_by_cell
            .read()
            .await
            .values()
            .filter(|s| &s.domain == domain)
            .cloned()
            .collect()
    }
    
    /// Get latest position for a specific cell
    #[allow(dead_code)]
    pub async fn get_latest_for_cell(&self, cell_id: &Uuid) -> Option<WorldSample> {
        self.latest_by_cell.read().await.get(cell_id).cloned()
    }
    
    /// Get all latest positions
    #[allow(dead_code)]
    pub async fn get_all_latest(&self) -> Vec<WorldSample> {
        self.latest_by_cell.read().await.values().cloned().collect()
    }
    
    /// Prune old samples
    pub async fn prune_old(&self) -> usize {
        let now = Self::now();
        let cutoff = now - self.config.max_age_secs;
        
        let mut samples = self.samples.write().await;
        let original_len = samples.len();
        
        samples.retain(|s| s.ts_unix >= cutoff);
        
        let pruned = original_len - samples.len();
        if pruned > 0 {
            tracing::debug!("Pruned {} old samples", pruned);
        }
        
        pruned
    }
    
    /// Get total sample count
    #[allow(dead_code)]
    pub async fn sample_count(&self) -> usize {
        self.samples.read().await.len()
    }
    
    /// Get stats about the world state
    pub async fn stats(&self) -> WorldStateStats {
        let samples = self.samples.read().await;
        let latest = self.latest_by_cell.read().await;
        
        let mut domain_counts: HashMap<CellDomain, usize> = HashMap::new();
        for s in samples.iter() {
            *domain_counts.entry(s.domain.clone()).or_insert(0) += 1;
        }
        
        WorldStateStats {
            total_samples: samples.len(),
            active_cells: latest.len(),
            samples_by_domain: domain_counts,
        }
    }
}

/// Statistics about the world state
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct WorldStateStats {
    pub total_samples: usize,
    pub active_cells: usize,
    /// Breakdown of samples by domain (returned in stats() for monitoring)
    pub samples_by_domain: HashMap<CellDomain, usize>,
}
