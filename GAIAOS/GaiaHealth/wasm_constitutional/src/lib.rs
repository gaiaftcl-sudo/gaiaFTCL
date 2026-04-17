use wasm_bindgen::prelude::*;

const PHI: f64 = 1.6180339887498948482;
const EPSILON: f64 = 1e-9;

#[wasm_bindgen]
pub fn binding_constitutional_check() -> bool { true }

#[wasm_bindgen]
pub fn admet_bounds_check() -> bool { true }

#[wasm_bindgen]
pub fn phi_boundary_check(current_window: f64, previous_window: f64) -> bool {
    if previous_window <= 0.0 {
        return false;
    }
    let ratio = (current_window / previous_window).abs();
    (ratio - PHI).abs() <= EPSILON
}

#[wasm_bindgen]
pub fn calculate_fractal_coordinate(depth: i32, index: i32) -> f64 {
    let phi_power = PHI.powi(depth);
    let offset = (index as f64) * PHI;
    (phi_power + offset).fract()
}

#[wasm_bindgen]
pub fn enforce_zero_overlap_packing(previous_state: f64) -> f64 {
    (previous_state + PHI).fract()
}

/// Strict Base-Phi Validation Logic for the vQbit Measurement Core
/// Validates that a given quantum state magnitude strictly aligns with a Phi-harmonic
/// at the specified recursion depth (the B-2 Truth Threshold).
#[wasm_bindgen]
pub fn vqbit_strict_base_phi_validate(state_magnitude: f64, depth: i32) -> bool {
    if state_magnitude < 0.0 {
        return false;
    }
    
    // The quantum harmonic grid size at this recursion depth
    let quanta = PHI.powi(-depth);
    
    // Scale the state to the grid
    let scaled = state_magnitude / quanta;
    let nearest_harmonic = scaled.round();
    
    // Calculate deviation from the perfect Phi-harmonic
    let deviation = (scaled - nearest_harmonic).abs();
    
    // The state is valid only if it rests exactly on the harmonic (within EPSILON)
    deviation <= EPSILON
}

/// Collapses a raw measurement into the nearest valid Base-Phi harmonic state.
#[wasm_bindgen]
pub fn vqbit_collapse_to_phi_harmonic(raw_measurement: f64, depth: i32) -> f64 {
    let quanta = PHI.powi(-depth);
    let nearest_harmonic = (raw_measurement / quanta).round();
    nearest_harmonic * quanta
}

#[wasm_bindgen]
pub fn epistemic_chain_validate() -> bool { true }

#[wasm_bindgen]
pub fn consent_validity_check() -> bool { true }

#[wasm_bindgen]
pub fn force_field_bounds_check() -> bool { true }

#[wasm_bindgen]
pub fn selectivity_check() -> bool { true }

#[wasm_bindgen]
pub fn get_epistemic_tag() -> i32 { 0 }

#[wasm_bindgen]
pub fn invariant_status_check() -> bool { true }

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_phi_boundary_check() {
        let prev = 100.0;
        let curr = prev * PHI;
        assert!(phi_boundary_check(curr, prev));
        assert!(!phi_boundary_check(curr + 0.1, prev));
    }

    #[test]
    fn test_zero_overlap_packing() {
        let state1 = 0.5;
        let state2 = enforce_zero_overlap_packing(state1);
        let state3 = enforce_zero_overlap_packing(state2);
        
        // Ensure they are bounded [0, 1) and isolated by Phi
        assert!(state2 >= 0.0 && state2 < 1.0);
        assert!(state3 >= 0.0 && state3 < 1.0);
        assert!((state2 - state1).abs() > 0.1); // Basic isolation check
    }

    #[test]
    fn test_strict_base_phi_validation() {
        // At depth 2, the quanta is PHI^(-2) = 1 / (1.618...^2) ≈ 0.381966
        let depth = 2;
        let quanta = PHI.powi(-depth);
        
        // A perfect harmonic should pass
        let perfect_state = quanta * 3.0; // 3rd harmonic
        assert!(vqbit_strict_base_phi_validate(perfect_state, depth));
        
        // A state with noise should fail
        let noisy_state = perfect_state + 0.05;
        assert!(!vqbit_strict_base_phi_validate(noisy_state, depth));
        
        // A collapsed state should pass
        let collapsed = vqbit_collapse_to_phi_harmonic(noisy_state, depth);
        assert!(vqbit_strict_base_phi_validate(collapsed, depth));
    }

    #[test]
    fn test_vqbit_mesh_memory() {
        let mut memory = VQbitMeshMemory::new(10, 5);
        assert_eq!(memory.vqbit_count(), 10);
        assert_eq!(memory.bioligit_count(), 5);
        
        // Simulate host writing noisy data to memory
        let depth = 2;
        let quanta = (PHI.powi(-depth)) as f32;
        let perfect_state = quanta * 3.0;
        
        // Access internal vector for testing
        memory.vqbits[0].vqbit_entropy = perfect_state + 0.05; // Noisy
        memory.vqbits[0].vqbit_truth = perfect_state - 0.05;   // Noisy
        
        // Collapse all in-place
        memory.collapse_all_to_phi_harmonic(depth);
        
        // Ensure the state in memory is now a perfect harmonic
        // Need to use f32 for validation to avoid f32->f64 precision issues
        let expected_quanta_f64 = PHI.powi(-depth);
        let entropy_f64 = memory.vqbits[0].vqbit_entropy as f64;
        let nearest_harmonic = (entropy_f64 / expected_quanta_f64).round();
        let deviation = (entropy_f64 / expected_quanta_f64 - nearest_harmonic).abs();
        
        // Use a slightly larger epsilon for f32->f64 conversion tests
        assert!(deviation <= 1e-6, "Deviation too high: {}", deviation);
    }
}

/// Unified Memory Primitive for Zero-Copy Sovereign Mesh
/// This allows the host environment (Swift/JS) to directly access the
/// Phi-scaled vQbit states in the WASM linear memory without copying.
#[wasm_bindgen]
pub struct VQbitMeshMemory {
    vqbits: Vec<primitives::vQbitPrimitive>,
    bioligits: Vec<primitives::BioligitPrimitive>,
}

#[wasm_bindgen]
impl VQbitMeshMemory {
    #[wasm_bindgen(constructor)]
    pub fn new(vqbit_count: usize, bioligit_count: usize) -> VQbitMeshMemory {
        let default_vqbit = primitives::vQbitPrimitive {
            transform: [0.0; 16],
            vqbit_entropy: 0.0,
            vqbit_truth: 0.0,
            prim_id: 0,
        };
        
        let default_bioligit = primitives::BioligitPrimitive {
            molecular_identity: [0; 4],
            spatial: [0.0; 3],
            thermodynamics: 0.0,
            epistemic_tag: 0,
            force_field_context: [0.0; 15],
        };
        
        VQbitMeshMemory {
            vqbits: vec![default_vqbit; vqbit_count],
            bioligits: vec![default_bioligit; bioligit_count],
        }
    }

    /// Returns a raw pointer to the vQbit memory buffer.
    pub fn vqbit_ptr(&self) -> *const primitives::vQbitPrimitive {
        self.vqbits.as_ptr()
    }

    /// Returns a raw pointer to the Bioligit memory buffer.
    pub fn bioligit_ptr(&self) -> *const primitives::BioligitPrimitive {
        self.bioligits.as_ptr()
    }

    pub fn vqbit_count(&self) -> usize {
        self.vqbits.len()
    }

    pub fn bioligit_count(&self) -> usize {
        self.bioligits.len()
    }

    /// Applies Phi-harmonic collapse to all vQbit entropy and truth states in the unified memory in-place.
    pub fn collapse_all_to_phi_harmonic(&mut self, depth: i32) {
        let quanta = (PHI.powi(-depth)) as f32;
        for q in self.vqbits.iter_mut() {
            let nearest_entropy = (q.vqbit_entropy / quanta).round();
            q.vqbit_entropy = nearest_entropy * quanta;
            
            let nearest_truth = (q.vqbit_truth / quanta).round();
            q.vqbit_truth = nearest_truth * quanta;
        }
    }
}
pub mod primitives;
