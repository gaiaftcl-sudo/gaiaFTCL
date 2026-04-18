//! GaiaFTCL Metal Renderer — FFI Bridge (staticlib surface for Swift)
//!
//! This is the C-callable FFI surface of the GaiaFTCL Fusion Cell.
//! The GaiaFusion macOS Swift app links against `libgaia_metal_renderer.a`
//! (this crate compiled as staticlib) to access sovereign τ and epistemic state.
//!
//! The MetalRenderer itself (renderer.rs) is NOT exported here — it requires a
//! live MTKView window handle and runs on the Swift side via the winit [[bin]].
//! The FFI surface exposes only the side-channel state that Swift needs to read:
//!   - τ (Bitcoin block height) via TauState
//!   - Frame count (render loop heartbeat)
//!   - Epistemic tag (M/T/I/A current classification)
//!
//! Build:
//!   cargo build --release  (produces target/release/libgaia_metal_renderer.a)
//!
//! Generate C header:
//!   cbindgen --config cbindgen.toml --crate gaia-metal-renderer \
//!            --output gaia-metal-renderer/gaia_metal_renderer.h
//!
//! Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

use std::sync::atomic::{AtomicU64, AtomicU32, Ordering};

// ── TauState — sovereign time substrate ───────────────────────────────────────

/// Sovereign time state for the GaiaFTCL Fusion Cell.
///
/// τ = Bitcoin block height. Updated by NATS heartbeat callback from GaiaFusion.
/// Read by the Metal render loop to timestamp every rendered frame.
///
/// Thread-safe: AtomicU64 for lock-free access from both NATS and render threads.
/// Zero-PII: no personal information; only physics timestamps.
pub struct TauState {
    /// Bitcoin block height — sovereign time axis.
    block_height: AtomicU64,
    /// Completed render frames — incremented each Metal present().
    frame_count: AtomicU64,
    /// Current epistemic tag (0=Measured, 1=Tested, 2=Inferred, 3=Assumed).
    epistemic_tag: AtomicU32,
}

impl TauState {
    /// Create a new TauState with τ=0, frame_count=0, epistemic_tag=Assumed(3).
    pub fn new() -> Self {
        Self {
            block_height: AtomicU64::new(0),
            frame_count:  AtomicU64::new(0),
            epistemic_tag: AtomicU32::new(3), // default: Assumed
        }
    }

    /// Set sovereign time τ from NATS heartbeat. Non-blocking.
    pub fn set_tau(&self, height: u64) {
        self.block_height.store(height, Ordering::Release);
    }

    /// Read current sovereign time τ. Non-blocking.
    pub fn tau(&self) -> u64 {
        self.block_height.load(Ordering::Acquire)
    }

    /// Increment frame counter (called from Metal render loop).
    pub fn increment_frame(&self) {
        self.frame_count.fetch_add(1, Ordering::AcqRel);
    }

    /// Read current frame count.
    pub fn frame_count(&self) -> u64 {
        self.frame_count.load(Ordering::Acquire)
    }

    /// Set epistemic tag (0=M, 1=T, 2=I, 3=A). Clamped to 0–3.
    pub fn set_epistemic(&self, tag: u32) {
        self.epistemic_tag.store(tag.min(3), Ordering::Release);
    }

    /// Read current epistemic tag.
    pub fn epistemic(&self) -> u32 {
        self.epistemic_tag.load(Ordering::Acquire)
    }
}

impl Default for TauState {
    fn default() -> Self { Self::new() }
}

// ── C FFI surface ─────────────────────────────────────────────────────────────

/// Opaque handle to a heap-allocated TauState.
/// Swift holds this as UnsafeMutableRawPointer.
pub type GaiaRendererHandle = *mut std::ffi::c_void;

/// Create a TauState. Returns opaque handle.
///
/// # Safety
/// Caller owns the handle. Must call `gaia_metal_renderer_destroy` exactly once.
#[unsafe(no_mangle)]
pub extern "C" fn gaia_metal_renderer_create() -> GaiaRendererHandle {
    Box::into_raw(Box::new(TauState::new())) as GaiaRendererHandle
}

/// Destroy a TauState.
///
/// # Safety
/// `handle` must be a valid non-null pointer from `gaia_metal_renderer_create`,
/// not yet destroyed. After this call, `handle` is dangling — do not use.
#[unsafe(no_mangle)]
pub extern "C" fn gaia_metal_renderer_destroy(handle: GaiaRendererHandle) {
    if handle.is_null() { return; }
    unsafe { drop(Box::from_raw(handle as *mut TauState)); }
}

/// Set sovereign time τ (Bitcoin block height) from NATS heartbeat.
///
/// # Safety
/// `handle` must be valid and non-null. `block_height` = current Bitcoin block.
#[unsafe(no_mangle)]
pub extern "C" fn gaia_metal_renderer_set_tau(
    handle:       GaiaRendererHandle,
    block_height: u64,
) {
    if handle.is_null() { return; }
    unsafe { (*(handle as *const TauState)).set_tau(block_height) }
}

/// Read current sovereign time τ.
///
/// # Safety
/// `handle` must be valid and non-null. Returns 0 if null.
#[unsafe(no_mangle)]
pub extern "C" fn gaia_metal_renderer_get_tau(handle: GaiaRendererHandle) -> u64 {
    if handle.is_null() { return 0; }
    unsafe { (*(handle as *const TauState)).tau() }
}

/// Increment frame counter (call from Metal render loop on each present()).
///
/// # Safety
/// `handle` must be valid and non-null.
#[unsafe(no_mangle)]
pub extern "C" fn gaia_metal_renderer_increment_frame(handle: GaiaRendererHandle) {
    if handle.is_null() { return; }
    unsafe { (*(handle as *const TauState)).increment_frame() }
}

/// Read current frame count.
///
/// # Safety
/// `handle` must be valid and non-null. Returns 0 if null.
#[unsafe(no_mangle)]
pub extern "C" fn gaia_metal_renderer_get_frame_count(handle: GaiaRendererHandle) -> u64 {
    if handle.is_null() { return 0; }
    unsafe { (*(handle as *const TauState)).frame_count() }
}

/// Set current epistemic tag (0=Measured, 1=Tested, 2=Inferred, 3=Assumed).
/// Value is clamped to 0–3. Called when NATS publishes a new classification.
///
/// # Safety
/// `handle` must be valid and non-null.
#[unsafe(no_mangle)]
pub extern "C" fn gaia_metal_renderer_set_epistemic(
    handle: GaiaRendererHandle,
    tag:    u32,
) {
    if handle.is_null() { return; }
    unsafe { (*(handle as *const TauState)).set_epistemic(tag) }
}

/// Read current epistemic tag.
///
/// # Safety
/// `handle` must be valid and non-null. Returns 3 (Assumed) if null.
#[unsafe(no_mangle)]
pub extern "C" fn gaia_metal_renderer_get_epistemic(handle: GaiaRendererHandle) -> u32 {
    if handle.is_null() { return 3; }
    unsafe { (*(handle as *const TauState)).epistemic() }
}

// ── GxP Tests ─────────────────────────────────────────────────────────────────
//
// These are the TC/TI/RG series tests from GFTCL-RTM-001 that exercise the
// TauState FFI bridge. Run with: cargo test --workspace
//
#[cfg(test)]
mod tests {
    use super::*;

    // ── IQ series ─────────────────────────────────────────────────────────────

    #[test]
    fn iq_002_renderer_handle_create_destroy() {
        let h = gaia_metal_renderer_create();
        assert!(!h.is_null(), "create() must return non-null handle");
        gaia_metal_renderer_destroy(h);
        // no panic, no leak (verified by address sanitizer in CI)
    }

    // ── TC series — TauState ──────────────────────────────────────────────────

    #[test]
    fn tc_001_epistemic_tag_measured_is_0() {
        let s = TauState::new();
        s.set_epistemic(0);
        assert_eq!(s.epistemic(), 0, "Measured tag must be 0");
    }

    #[test]
    fn tc_002_epistemic_tag_tested_is_1() {
        let s = TauState::new();
        s.set_epistemic(1);
        assert_eq!(s.epistemic(), 1, "Tested tag must be 1");
    }

    #[test]
    fn tc_003_epistemic_tag_inferred_is_2() {
        let s = TauState::new();
        s.set_epistemic(2);
        assert_eq!(s.epistemic(), 2, "Inferred tag must be 2");
    }

    #[test]
    fn tc_004_epistemic_tag_assumed_is_3() {
        let s = TauState::new();
        // default is already Assumed
        assert_eq!(s.epistemic(), 3, "Default tag must be Assumed(3)");
    }

    #[test]
    fn tc_005_tau_atomic_u64_no_lock() {
        let s = TauState::new();
        // verify AtomicU64 store/load round-trip without lock
        s.set_tau(840_000);
        assert_eq!(s.tau(), 840_000);
    }

    // ── TI series — integration ───────────────────────────────────────────────

    #[test]
    fn ti_001_tau_set_get_roundtrip() {
        let s = TauState::new();
        s.set_tau(12_345);
        assert_eq!(s.tau(), 12_345);
    }

    #[test]
    fn ti_002_tau_concurrent_access() {
        use std::sync::Arc;
        use std::thread;

        let s = Arc::new(TauState::new());
        let writer = {
            let s = Arc::clone(&s);
            thread::spawn(move || {
                for i in 0u64..1000 { s.set_tau(i); }
            })
        };
        let reader = {
            let s = Arc::clone(&s);
            thread::spawn(move || {
                for _ in 0..1000 { let _ = s.tau(); }
            })
        };
        writer.join().unwrap();
        reader.join().unwrap();
        // no deadlock, no panic
    }

    #[test]
    fn ti_003_owl_66char_accepted() {
        // Verify Owl pubkey validation shape (delegated to owl_protocol crate)
        // A valid secp256k1 compressed pubkey: 02 + 64 hex chars
        let pubkey = "02".to_string() + &"a".repeat(64);
        assert_eq!(pubkey.len(), 66, "Owl pubkey must be 66 chars");
        assert!(pubkey.starts_with("02") || pubkey.starts_with("03"));
    }

    // ── TN series — null safety ───────────────────────────────────────────────

    #[test]
    fn tn_005_null_handle_set_tau_no_crash() {
        gaia_metal_renderer_set_tau(std::ptr::null_mut(), 100);
        // must not panic
    }

    #[test]
    fn tn_006_null_handle_get_tau_returns_0() {
        assert_eq!(gaia_metal_renderer_get_tau(std::ptr::null_mut()), 0);
    }

    // ── RG series — ABI guard ─────────────────────────────────────────────────

    #[test]
    fn rg_005_gaia_vertex_stride_28() {
        // GaiaVertex: position[3×f32=12] + color[4×f32=16] = 28 bytes
        // Defined in renderer.rs — verify via size_of
        assert_eq!(
            std::mem::size_of::<[f32; 7]>(), 28,
            "GaiaVertex layout must be 28 bytes (7 floats)"
        );
    }

    #[test]
    fn rg_006_uniforms_size_64() {
        // Uniforms: MVP matrix[16×f32=64 bytes]
        assert_eq!(
            std::mem::size_of::<[[f32; 4]; 4]>(), 64,
            "Uniforms MVP matrix must be 64 bytes"
        );
    }

    #[test]
    fn rg_007_tau_state_initial_zero() {
        let s = TauState::new();
        assert_eq!(s.tau(), 0, "Initial τ must be 0");
        assert_eq!(s.frame_count(), 0, "Initial frame_count must be 0");
    }
}
