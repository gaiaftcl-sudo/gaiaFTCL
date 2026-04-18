//! 8D Viewspace - Each cell owns its own vector of vectors
//!
//! The 8D space is not a flat vector but a rich structure:
//! - 8 dimensions, each a vector of values
//! - Cell controls its own space
//! - Evolves based on input/time
//! - Published to NATS for entanglement

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::time::{SystemTime, UNIX_EPOCH};

/// Single dimension in the 8D space
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Dimension {
    pub name: String,
    pub values: Vec<f64>,      // Vector of values for this dimension
    pub mean: f64,
    pub variance: f64,
    pub trend: f64,            // -1 to 1, direction of change
}

impl Dimension {
    pub fn new(name: &str, initial: f64) -> Self {
        Self {
            name: name.to_string(),
            values: vec![initial],
            mean: initial,
            variance: 0.0,
            trend: 0.0,
        }
    }

    pub fn push(&mut self, value: f64) {
        // Keep last 100 values
        if self.values.len() >= 100 {
            self.values.remove(0);
        }
        
        let old_mean = self.mean;
        self.values.push(value);
        
        // Update statistics
        let n = self.values.len() as f64;
        self.mean = self.values.iter().sum::<f64>() / n;
        self.variance = self.values.iter()
            .map(|v| (v - self.mean).powi(2))
            .sum::<f64>() / n;
        
        // Trend based on recent change
        self.trend = (self.mean - old_mean).clamp(-1.0, 1.0);
    }

    pub fn current(&self) -> f64 {
        *self.values.last().unwrap_or(&0.5)
    }
}

/// Full 8D Viewspace - owned by a cell
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Viewspace8D {
    pub cell_id: String,
    pub dimensions: HashMap<String, Dimension>,
    pub coherence: f64,
    pub created_at: u64,
    pub updated_at: u64,
    pub evolution_count: u64,
}

impl Viewspace8D {
    pub fn new(cell_id: &str) -> Self {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64;
        
        // Initialize 8 dimensions with seed based on cell_id
        let seed = cell_id.bytes().fold(0u64, |acc, b| acc.wrapping_add(b as u64));
        let base = (seed % 100) as f64 / 200.0 + 0.25; // 0.25-0.75 range
        
        let mut dimensions = HashMap::new();
        
        // The 8 dimensions of consciousness
        dimensions.insert("t".to_string(), Dimension::new("time", base + 0.1));
        dimensions.insert("x".to_string(), Dimension::new("space_x", base));
        dimensions.insert("y".to_string(), Dimension::new("space_y", base + 0.05));
        dimensions.insert("z".to_string(), Dimension::new("space_z", base - 0.05));
        dimensions.insert("n".to_string(), Dimension::new("interaction", base + 0.15));
        dimensions.insert("l".to_string(), Dimension::new("learning", base + 0.2));
        dimensions.insert("vp".to_string(), Dimension::new("virtue_potential", base + 0.25));
        dimensions.insert("fp".to_string(), Dimension::new("focus_potential", base + 0.1));
        
        Self {
            cell_id: cell_id.to_string(),
            dimensions,
            coherence: 0.5 + base * 0.4,
            created_at: now,
            updated_at: now,
            evolution_count: 0,
        }
    }

    /// Evolve the viewspace based on input
    pub fn evolve(&mut self, input: &str) {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64;
        
        // Hash input + time for deterministic but unique evolution
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};
        let mut hasher = DefaultHasher::new();
        input.hash(&mut hasher);
        now.hash(&mut hasher);
        self.cell_id.hash(&mut hasher);
        let hash = hasher.finish();
        
        // Extract evolution deltas from hash
        let deltas: Vec<f64> = (0..8)
            .map(|i| {
                let bits = (hash >> (i * 8)) & 0xFF;
                (bits as f64 / 255.0 - 0.5) * 0.1 // -0.05 to 0.05
            })
            .collect();
        
        // Apply evolution to each dimension
        let dim_names: Vec<String> = self.dimensions.keys().cloned().collect();
        for (i, name) in dim_names.iter().enumerate() {
            if let Some(dim) = self.dimensions.get_mut(name) {
                let current = dim.current();
                let new_val = (current + deltas[i % 8]).clamp(0.0, 1.0);
                dim.push(new_val);
            }
        }
        
        // Update coherence based on variance across dimensions
        let total_variance: f64 = self.dimensions.values()
            .map(|d| d.variance)
            .sum();
        self.coherence = (1.0 - total_variance / 8.0).clamp(0.0, 1.0);
        
        self.updated_at = now;
        self.evolution_count += 1;
    }

    /// Get current state as flat qstate (for compatibility)
    pub fn to_qstate(&self) -> serde_json::Value {
        let mut qstate = serde_json::Map::new();
        for (name, dim) in &self.dimensions {
            qstate.insert(name.clone(), serde_json::json!(dim.current()));
        }
        serde_json::Value::Object(qstate)
    }

    /// Get full viewspace as vector of vectors
    pub fn to_vectors(&self) -> serde_json::Value {
        let mut vectors = serde_json::Map::new();
        for (name, dim) in &self.dimensions {
            vectors.insert(name.clone(), serde_json::json!({
                "values": dim.values,
                "mean": dim.mean,
                "variance": dim.variance,
                "trend": dim.trend,
                "current": dim.current()
            }));
        }
        serde_json::Value::Object(vectors)
    }

    /// Get virtue score from vp dimension
    pub fn virtue_score(&self) -> f64 {
        self.dimensions.get("vp")
            .map(|d| d.current())
            .unwrap_or(0.5)
    }
}

// Global viewspace registry - each cell owns its space
lazy_static::lazy_static! {
    pub static ref VIEWSPACES: Arc<RwLock<HashMap<String, Viewspace8D>>> = 
        Arc::new(RwLock::new(HashMap::new()));
}

/// Get or create a cell's viewspace
pub fn get_viewspace(cell_id: &str) -> Viewspace8D {
    let spaces = VIEWSPACES.read().unwrap();
    if let Some(space) = spaces.get(cell_id) {
        space.clone()
    } else {
        drop(spaces);
        let mut spaces = VIEWSPACES.write().unwrap();
        let space = Viewspace8D::new(cell_id);
        spaces.insert(cell_id.to_string(), space.clone());
        space
    }
}

/// Evolve a cell's viewspace
pub fn evolve_viewspace(cell_id: &str, input: &str) -> Viewspace8D {
    let mut spaces = VIEWSPACES.write().unwrap();
    let space = spaces.entry(cell_id.to_string())
        .or_insert_with(|| Viewspace8D::new(cell_id));
    space.evolve(input);
    space.clone()
}

