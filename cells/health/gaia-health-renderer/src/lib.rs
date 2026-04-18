//! GaiaHealth Metal Renderer — FFI Bridge
//!
//! C-callable surface for GaiaHealth Swift (McFusion biologit cell).
//!
//! Mirrors gaia-metal-renderer in GaiaFTCL but drives molecular dynamics
//! visualization with M/I/A epistemic coloring at the shader level.
//!
//! Swift creates a GaiaHealthRendererHandle, submits BioligitPrimitive buffers,
//! and reads the current epistemic tag to update the ConstitutionalHUD opacity.
//!
//! Build: cargo build --release --target aarch64-apple-darwin
//!   → target/aarch64-apple-darwin/release/libgaia_health_renderer.a
//!
//! Generate C header:
//!   cbindgen --config cbindgen.toml --crate gaia-health-renderer --output gaia_health_renderer.h
//!
//! Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

pub mod renderer;
pub mod shaders;

use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};

/// GaiaHealth renderer state (non-Metal fields only — Metal objects in renderer.rs).
pub struct GaiaHealthRenderer {
    /// Current epistemic tag driving shader alpha (0=M, 1=I, 2=A).
    pub epistemic_tag:  AtomicU32,
    /// Frame counter for MD playback.
    pub frame_count:    AtomicU64,
    /// Cell state discriminant — drives MTLLoadActionClear on every frame.
    pub cell_state:     AtomicU32,
    /// Training mode — disables export of rendered frames.
    pub training_mode:  AtomicU32,
}

impl GaiaHealthRenderer {
    pub fn new() -> Self {
        Self {
            epistemic_tag:  AtomicU32::new(2), // default: Assumed
            frame_count:    AtomicU64::new(0),
            cell_state:     AtomicU32::new(0), // IDLE
            training_mode:  AtomicU32::new(0),
        }
    }

    pub fn set_epistemic_tag(&self, tag: u32) {
        self.epistemic_tag.store(tag.min(2), Ordering::Release);
    }

    pub fn increment_frame(&self) {
        self.frame_count.fetch_add(1, Ordering::AcqRel);
    }
}

impl Default for GaiaHealthRenderer {
    fn default() -> Self { Self::new() }
}

// ── C FFI surface ─────────────────────────────────────────────────────────────

pub type GaiaHealthRendererHandle = *mut std::ffi::c_void;

/// Create a GaiaHealthRenderer. Returns opaque handle.
///
/// # Safety
/// Caller owns the handle. Must call `gaia_health_renderer_destroy` exactly once.
#[unsafe(no_mangle)]
pub extern "C" fn gaia_health_renderer_create() -> GaiaHealthRendererHandle {
    Box::into_raw(Box::new(GaiaHealthRenderer::new())) as GaiaHealthRendererHandle
}

/// Destroy a GaiaHealthRenderer.
///
/// # Safety
/// Handle must be valid, non-null, not yet destroyed.
#[unsafe(no_mangle)]
pub extern "C" fn gaia_health_renderer_destroy(handle: GaiaHealthRendererHandle) {
    if handle.is_null() { return; }
    unsafe { drop(Box::from_raw(handle as *mut GaiaHealthRenderer)); }
}

/// Set the current epistemic tag (0=M, 1=I, 2=A).
/// The Metal shader reads this to switch between opaque / translucent / stippled rendering.
///
/// # Safety
/// Handle must be valid and non-null.
#[unsafe(no_mangle)]
pub extern "C" fn gaia_health_renderer_set_epistemic(
    handle: GaiaHealthRendererHandle,
    tag: u32,
) {
    if handle.is_null() { return; }
    unsafe { (*(handle as *const GaiaHealthRenderer)).set_epistemic_tag(tag) }
}

/// Read current epistemic tag.
///
/// # Safety
/// Handle must be valid and non-null.
#[unsafe(no_mangle)]
pub extern "C" fn gaia_health_renderer_get_epistemic(handle: GaiaHealthRendererHandle) -> u32 {
    if handle.is_null() { return 2; }
    unsafe { (*(handle as *const GaiaHealthRenderer)).epistemic_tag.load(Ordering::Acquire) }
}

/// Advance the MD frame counter.
///
/// # Safety
/// Handle must be valid and non-null.
#[unsafe(no_mangle)]
pub extern "C" fn gaia_health_renderer_tick_frame(handle: GaiaHealthRendererHandle) {
    if handle.is_null() { return; }
    unsafe { (*(handle as *const GaiaHealthRenderer)).increment_frame() }
}

/// Read current MD frame count.
///
/// # Safety
/// Handle must be valid and non-null.
#[unsafe(no_mangle)]
pub extern "C" fn gaia_health_renderer_get_frame_count(handle: GaiaHealthRendererHandle) -> u64 {
    if handle.is_null() { return 0; }
    unsafe { (*(handle as *const GaiaHealthRenderer)).frame_count.load(Ordering::Acquire) }
}

// ── GxP Tests ─────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn iq_002_renderer_initializes_to_assumed() {
        let r = GaiaHealthRenderer::new();
        assert_eq!(r.epistemic_tag.load(Ordering::Acquire), 2);
    }

    #[test]
    fn tp_014_set_get_epistemic_tag_roundtrip() {
        let r = GaiaHealthRenderer::new();
        r.set_epistemic_tag(0); // M
        assert_eq!(r.epistemic_tag.load(Ordering::Acquire), 0);
        r.set_epistemic_tag(1); // I
        assert_eq!(r.epistemic_tag.load(Ordering::Acquire), 1);
    }

    #[test]
    fn tn_006_null_handle_no_panic() {
        gaia_health_renderer_set_epistemic(std::ptr::null_mut(), 0);
        assert_eq!(gaia_health_renderer_get_epistemic(std::ptr::null_mut()), 2);
        gaia_health_renderer_tick_frame(std::ptr::null_mut());
        assert_eq!(gaia_health_renderer_get_frame_count(std::ptr::null_mut()), 0);
    }

    #[test]
    fn tp_015_frame_counter_increments() {
        let r = GaiaHealthRenderer::new();
        r.increment_frame();
        r.increment_frame();
        assert_eq!(r.frame_count.load(Ordering::Acquire), 2);
    }

    #[test]
    fn tc_012_epistemic_clamped_to_2() {
        let r = GaiaHealthRenderer::new();
        r.set_epistemic_tag(99); // out of range
        assert_eq!(r.epistemic_tag.load(Ordering::Acquire), 2); // clamped to Assumed
    }
}
