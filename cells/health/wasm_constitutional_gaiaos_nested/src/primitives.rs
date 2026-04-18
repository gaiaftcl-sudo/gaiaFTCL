use wasm_bindgen::prelude::*;

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct vQbitPrimitive {
    pub transform: [f32; 16], // 64 bytes
    pub vqbit_entropy: f32,   // 4 bytes
    pub vqbit_truth: f32,     // 4 bytes
    pub prim_id: u32,         // 4 bytes
} // Total: 76 bytes

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct BioligitPrimitive {
    pub molecular_identity: [u32; 4],   // 16 bytes
    pub spatial: [f32; 3],              // 12 bytes
    pub thermodynamics: f32,            // 4 bytes
    pub epistemic_tag: u32,             // 4 bytes
    pub force_field_context: [f32; 15], // 60 bytes
} // Total: 96 bytes

#[test]
fn test_primitive_sizes() {
    assert_eq!(std::mem::size_of::<vQbitPrimitive>(), 76);
    assert_eq!(std::mem::size_of::<BioligitPrimitive>(), 96);
}
