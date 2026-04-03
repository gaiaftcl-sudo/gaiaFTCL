// services/akg_gnn/src/compression.rs
// Regional compression for coarse scanning and storage
// WARNING: This is for UI/storage ONLY - NOT for vChip collapse!

use std::collections::HashMap;

/// Mirror World Compressor
/// Compresses N entities into R regional super-vQbits
/// 
/// USE CASES:
/// ✅ Coarse scanning to find hot regions
/// ✅ UI visualization at planetary scale
/// ✅ Long-term storage compression
/// 
/// NOT FOR:
/// ❌ vChip collapse operations (use substrate_query instead)
/// ❌ Safety-critical conflict detection
/// ❌ Final decision making
pub struct MirrorWorldCompressor {
    n_regions: usize,
    grid_resolution: f64,
}

impl MirrorWorldCompressor {
    /// Create compressor with specified number of regions
    /// Default: 100 regions (10x10 global grid)
    pub fn new(n_regions: usize) -> Self {
        let grid_resolution = 360.0 / (n_regions as f64).sqrt();
        Self { n_regions, grid_resolution }
    }
    
    pub fn n_regions(&self) -> usize {
        self.n_regions
    }
    
    /// Compress N entities into R regional super-vQbits
    /// Returns (flattened regional vqbits, aircraft count per region)
    pub fn compress(
        &self,
        vqbits: &[[f64; 8]],
        positions: &[[f64; 3]], // lat, lon, alt
    ) -> (Vec<f64>, HashMap<usize, usize>) {
        let n = vqbits.len();
        
        // Initialize regional accumulators
        let mut regional_sums = vec![[0.0f64; 8]; self.n_regions];
        let mut regional_counts = vec![0usize; self.n_regions];
        let mut regional_max_risk = vec![0.0f64; self.n_regions];
        
        // Assign each entity to a region and accumulate
        for i in 0..n {
            let region_id = self.assign_region(positions[i][0], positions[i][1]);
            
            // Sum dimensions (for averaging)
            for d in 0..8 {
                regional_sums[region_id][d] += vqbits[i][d];
            }
            
            // Track max risk (D5) - conservative for safety
            if vqbits[i][5] > regional_max_risk[region_id] {
                regional_max_risk[region_id] = vqbits[i][5];
            }
            
            regional_counts[region_id] += 1;
        }
        
        // Compute regional averages
        let mut regional_vqbits = vec![[0.0f64; 8]; self.n_regions];
        for r in 0..self.n_regions {
            if regional_counts[r] > 0 {
                for d in 0..8 {
                    regional_vqbits[r][d] = regional_sums[r][d] / regional_counts[r] as f64;
                }
                // Override D5 with MAX risk (conservative)
                regional_vqbits[r][5] = regional_max_risk[r];
                // D7 uncertainty increases with entity count
                regional_vqbits[r][7] = (regional_counts[r] as f64 / 100.0).min(1.0);
            }
        }
        
        // Flatten to 1D array
        let flattened: Vec<f64> = regional_vqbits
            .iter()
            .flat_map(|r| r.iter().cloned())
            .collect();
        
        // Build count map
        let mut count_map = HashMap::new();
        for (r, &count) in regional_counts.iter().enumerate() {
            if count > 0 {
                count_map.insert(r, count);
            }
        }
        
        (flattened, count_map)
    }
    
    /// Decompress regional vQbits back to entity-level
    /// Returns (vqbit, region_id) for each position
    pub fn decompress(
        &self,
        regional_vqbits: &[f64],
        n_regions: usize,
        positions: &[[f64; 3]],
    ) -> Vec<([f64; 8], usize)> {
        let n = positions.len();
        
        // Parse flattened regional data back to 2D
        let regional: Vec<[f64; 8]> = regional_vqbits
            .chunks(8)
            .take(n_regions)
            .map(|chunk| {
                let mut arr = [0.0; 8];
                for (i, &v) in chunk.iter().enumerate() {
                    if i < 8 {
                        arr[i] = v;
                    }
                }
                arr
            })
            .collect();
        
        let mut result = Vec::with_capacity(n);
        
        for i in 0..n {
            let region_id = self.assign_region(positions[i][0], positions[i][1]);
            
            // Start with regional average
            let mut vqbit = if region_id < regional.len() {
                regional[region_id]
            } else {
                [0.0; 8]
            };
            
            // Add local perturbation for D0/D1 (position within region)
            let (lat_offset, lon_offset) = self.compute_local_offset(
                positions[i][0],
                positions[i][1],
                region_id,
            );
            vqbit[0] += lon_offset * 0.01;
            vqbit[1] += lat_offset * 0.01;
            
            // Clamp to valid range
            for d in 0..8 {
                vqbit[d] = vqbit[d].clamp(-1.0, 1.0);
            }
            
            result.push((vqbit, region_id));
        }
        
        result
    }
    
    /// Assign a lat/lon position to a region ID
    fn assign_region(&self, lat: f64, lon: f64) -> usize {
        let grid_size = (self.n_regions as f64).sqrt() as usize;
        
        // Normalize to 0..1 range
        let lat_norm = (lat + 90.0) / 180.0;
        let lon_norm = (lon + 180.0) / 360.0;
        
        let lat_idx = (lat_norm * grid_size as f64).floor() as usize;
        let lon_idx = (lon_norm * grid_size as f64).floor() as usize;
        
        let lat_idx = lat_idx.min(grid_size - 1);
        let lon_idx = lon_idx.min(grid_size - 1);
        
        (lat_idx * grid_size + lon_idx).min(self.n_regions - 1)
    }
    
    /// Compute local offset within a region (for decompression refinement)
    fn compute_local_offset(&self, lat: f64, lon: f64, region_id: usize) -> (f64, f64) {
        let grid_size = (self.n_regions as f64).sqrt() as usize;
        let region_lat_idx = region_id / grid_size;
        let region_lon_idx = region_id % grid_size;
        
        // Region boundaries
        let lat_min = region_lat_idx as f64 * self.grid_resolution - 90.0;
        let lon_min = region_lon_idx as f64 * self.grid_resolution - 180.0;
        
        // Offset within region (0..1)
        let lat_offset = (lat - lat_min) / self.grid_resolution;
        let lon_offset = (lon - lon_min) / self.grid_resolution;
        
        // Center and scale to -0.5..0.5
        (lat_offset - 0.5, lon_offset - 0.5)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_compress_decompress_roundtrip() {
        let compressor = MirrorWorldCompressor::new(100);
        
        let vqbits = vec![
            [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8],
            [0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85],
        ];
        let positions = vec![
            [40.0, -74.0, 35000.0],
            [40.1, -74.1, 36000.0],
        ];
        
        let (compressed, counts) = compressor.compress(&vqbits, &positions);
        
        // Should have 100 regions * 8 dims = 800 values
        assert_eq!(compressed.len(), 800);
        
        // Both aircraft should be in same region
        assert_eq!(counts.len(), 1);
        assert_eq!(*counts.values().next().unwrap(), 2);
        
        // Decompress
        let decompressed = compressor.decompress(&compressed, 100, &positions);
        assert_eq!(decompressed.len(), 2);
        
        // Both should have same region
        assert_eq!(decompressed[0].1, decompressed[1].1);
    }
    
    #[test]
    fn test_max_risk_preserved() {
        let compressor = MirrorWorldCompressor::new(100);
        
        // Two aircraft, one with high risk
        let vqbits = vec![
            [0.0, 0.0, 0.0, 0.0, 0.0, 0.2, 0.0, 0.0], // low risk
            [0.0, 0.0, 0.0, 0.0, 0.0, 0.9, 0.0, 0.0], // high risk
        ];
        let positions = vec![
            [0.0, 0.0, 0.0],
            [0.1, 0.1, 0.0], // same region
        ];
        
        let (compressed, _) = compressor.compress(&vqbits, &positions);
        
        // Find the D5 value for the occupied region
        // Region 0 should have the max risk (0.9), not average (0.55)
        let region_0_d5 = compressed[5]; // D5 of region 0
        assert!((region_0_d5 - 0.9).abs() < 0.01, 
            "D5 should be MAX (0.9), got {region_0_d5}");
    }
}
