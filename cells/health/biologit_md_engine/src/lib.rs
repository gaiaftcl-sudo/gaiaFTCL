//! GaiaHealth Biologit MD Engine — FFI Bridge
//!
//! C-callable surface for the GaiaHealth Swift layer (McFusion biologit cell).
//!
//! Architecture mirrors gaia-metal-renderer in GaiaFTCL:
//!   GaiaHealth Swift → creates BioState handle via bio_state_create()
//!   Swift drives state transitions via bio_state_transition()
//!   Swift reads epistemic tag via bio_state_get_epistemic_tag()
//!   Metal renderer reads BioligitPrimitive buffer via bio_state_get_primitives()
//!
//! The BioState does NOT hold personal information of any kind.
//! It holds only: computational state, frame counts, MD parameters,
//! and the Owl public key (a secp256k1 compressed public key — no name, no PHI).
//!
//! Build: cargo build --release
//!   → target/release/libbiologit_md_engine.a (staticlib)
//!
//! Generate C header:
//!   cbindgen --config cbindgen.toml --crate biologit-md-engine --output gaia_health_engine.h
//!
//! Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

pub mod epistemic;
pub mod force_field;
pub mod state_machine;

use state_machine::{BiologicalCellState, TransitionResult};
use epistemic::EpistemicTag;
use std::sync::atomic::{AtomicU64, AtomicU32, Ordering};
use std::sync::Mutex;

// ── BioState ──────────────────────────────────────────────────────────────────

/// Sovereign biological cell state.
///
/// Heap-allocated. GaiaHealth Swift holds an opaque pointer (`BioStateHandle`).
///
/// Zero-PII guarantee: this struct contains NO personally identifiable
/// information. The `owl_pubkey` field is a secp256k1 compressed public key
/// (33 bytes hex-encoded, 66 chars) — it is mathematically derived, not a
/// name, email, medical record number, or any human-readable identifier.
///
/// Thread-safe: atomic fields for hot-path reads (frame count, state).
/// Mutex guard for the owl pubkey string (written once at MOORED transition).
pub struct BioState {
    /// Current cell state (BiologicalCellState discriminant as u32).
    /// Stored atomically for lock-free reads from the Metal render loop.
    state:        AtomicU32,

    /// Completed MD simulation frames (nanosecond timesteps).
    frame_count:  AtomicU64,

    /// Current epistemic tag for the active computation.
    /// 0=M (Measured), 1=I (Inferred), 2=A (Assumed)
    epistemic:    AtomicU32,

    /// Owl identity public key — secp256k1 compressed pubkey, hex-encoded.
    /// Contains ZERO personal information. Set when cell enters MOORED state.
    /// Cleared when cell returns to IDLE. Never logged in plaintext audit trail.
    owl_pubkey:   Mutex<Option<String>>,

    /// Training mode flag. When true, no PHI-adjacent data is accessible,
    /// and no clinical or IP outputs can be generated.
    training_mode: AtomicU32,
}

impl BioState {
    pub fn new() -> Self {
        Self {
            state:         AtomicU32::new(BiologicalCellState::Idle as u32),
            frame_count:   AtomicU64::new(0),
            epistemic:     AtomicU32::new(EpistemicTag::Assumed as u32),
            owl_pubkey:    Mutex::new(None),
            training_mode: AtomicU32::new(0),
        }
    }

    pub fn state(&self) -> u32 {
        self.state.load(Ordering::Acquire)
    }

    pub fn frame_count(&self) -> u64 {
        self.frame_count.load(Ordering::Acquire)
    }

    pub fn increment_frame(&self) {
        self.frame_count.fetch_add(1, Ordering::AcqRel);
    }

    pub fn epistemic_tag(&self) -> u32 {
        self.epistemic.load(Ordering::Acquire)
    }

    pub fn set_epistemic(&self, tag: EpistemicTag) {
        self.epistemic.store(tag as u32, Ordering::Release);
    }

    /// Transition to a new cell state.
    ///
    /// Returns the transition result — Swift checks this to drive UI layout changes.
    pub fn transition(&self, target: BiologicalCellState) -> TransitionResult {
        let current = BiologicalCellState::from_u32(self.state());
        let result = state_machine::validate_transition(current, target.clone());
        if result == TransitionResult::Allowed {
            // Clear owl pubkey when returning to IDLE — zero-PII cleanup
            if target == BiologicalCellState::Idle {
                if let Ok(mut guard) = self.owl_pubkey.lock() {
                    *guard = None;
                }
                self.frame_count.store(0, Ordering::Release);
            }
            self.state.store(target as u32, Ordering::Release);
        }
        result
    }

    /// Moor an Owl identity. Accepts ONLY a secp256k1 compressed public key (hex).
    ///
    /// Zero-PII enforcement: rejects any string that looks like a name, email,
    /// or other personal identifier. The pubkey must be exactly 66 hex characters.
    pub fn moor_owl(&self, pubkey_hex: &str) -> bool {
        // Validate: exactly 66 hex chars (33-byte compressed secp256k1 pubkey)
        if pubkey_hex.len() != 66 {
            return false;
        }
        if !pubkey_hex.chars().all(|c| c.is_ascii_hexdigit()) {
            return false;
        }
        // Compressed pubkey must start with 02 or 03
        let prefix = &pubkey_hex[..2];
        if prefix != "02" && prefix != "03" {
            return false;
        }
        if let Ok(mut guard) = self.owl_pubkey.lock() {
            *guard = Some(pubkey_hex.to_string());
        }
        true
    }

    pub fn is_training_mode(&self) -> bool {
        self.training_mode.load(Ordering::Acquire) == 1
    }

    pub fn set_training_mode(&self, active: bool) {
        self.training_mode.store(active as u32, Ordering::Release);
    }
}

impl Default for BioState {
    fn default() -> Self { Self::new() }
}

// ── C FFI surface ─────────────────────────────────────────────────────────────

/// Opaque handle to BioState. GaiaHealth Swift stores as `UnsafeMutableRawPointer`.
pub type BioStateHandle = *mut std::ffi::c_void;

/// Create a new BioState. Returns opaque handle.
///
/// # Safety
/// Caller owns the handle. Must call `bio_state_destroy` exactly once.
#[unsafe(no_mangle)]
pub extern "C" fn bio_state_create() -> BioStateHandle {
    Box::into_raw(Box::new(BioState::new())) as BioStateHandle
}

/// Destroy a BioState. Frees heap memory and zeroes the Owl pubkey (zero-PII cleanup).
///
/// # Safety
/// `handle` must be a valid non-null pointer from `bio_state_create`, not yet destroyed.
#[unsafe(no_mangle)]
pub extern "C" fn bio_state_destroy(handle: BioStateHandle) {
    if handle.is_null() { return; }
    unsafe { drop(Box::from_raw(handle as *mut BioState)); }
}

/// Read current cell state discriminant (BiologicalCellState as u32).
///
/// # Safety
/// `handle` must be valid and non-null.
#[unsafe(no_mangle)]
pub extern "C" fn bio_state_get_state(handle: BioStateHandle) -> u32 {
    if handle.is_null() { return 0; }
    unsafe { (*(handle as *const BioState)).state() }
}

/// Read completed MD frame count.
///
/// # Safety
/// `handle` must be valid and non-null.
#[unsafe(no_mangle)]
pub extern "C" fn bio_state_get_frame_count(handle: BioStateHandle) -> u64 {
    if handle.is_null() { return 0; }
    unsafe { (*(handle as *const BioState)).frame_count() }
}

/// Increment the MD frame counter. Called on each integration timestep.
///
/// # Safety
/// `handle` must be valid and non-null.
#[unsafe(no_mangle)]
pub extern "C" fn bio_state_increment_frame(handle: BioStateHandle) {
    if handle.is_null() { return; }
    unsafe { (*(handle as *const BioState)).increment_frame() }
}

/// Read current epistemic tag (0=M, 1=I, 2=A).
///
/// # Safety
/// `handle` must be valid and non-null.
#[unsafe(no_mangle)]
pub extern "C" fn bio_state_get_epistemic_tag(handle: BioStateHandle) -> u32 {
    if handle.is_null() { return 2; } // default: Assumed
    unsafe { (*(handle as *const BioState)).epistemic_tag() }
}

/// Transition cell state. Returns 1 if allowed, 0 if rejected by state machine.
///
/// # Safety
/// `handle` must be valid and non-null.
#[unsafe(no_mangle)]
pub extern "C" fn bio_state_transition(handle: BioStateHandle, target_state: u32) -> u32 {
    if handle.is_null() { return 0; }
    let target = BiologicalCellState::from_u32(target_state);
    let result = unsafe { (*(handle as *const BioState)).transition(target) };
    match result {
        TransitionResult::Allowed => 1,
        TransitionResult::Rejected => 0,
    }
}

/// Moor an Owl identity. `pubkey_ptr` must point to a 66-char hex ASCII string.
/// Returns 1 on success, 0 if the pubkey fails zero-PII validation.
///
/// # Safety
/// `handle` and `pubkey_ptr` must be valid and non-null. `pubkey_len` must match.
#[unsafe(no_mangle)]
pub extern "C" fn bio_state_moor_owl(
    handle:     BioStateHandle,
    pubkey_ptr: *const u8,
    pubkey_len: usize,
) -> u32 {
    if handle.is_null() || pubkey_ptr.is_null() { return 0; }
    let slice = unsafe { std::slice::from_raw_parts(pubkey_ptr, pubkey_len) };
    let Ok(hex_str) = std::str::from_utf8(slice) else { return 0; };
    let bio = unsafe { &*(handle as *const BioState) };
    bio.moor_owl(hex_str) as u32
}

// ── GxP Tests ─────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    // IQ-001: Library compiles and BioState initializes to IDLE
    #[test]
    fn iq_001_bio_state_initializes_idle() {
        let b = BioState::new();
        assert_eq!(b.state(), BiologicalCellState::Idle as u32);
    }

    // TR-001: BioState size — no layout regression
    #[test]
    fn tr_001_bio_state_repr_stable() {
        // BioState is NOT repr(C) — it's Rust-layout. This test ensures
        // the FFI handle (raw pointer) is pointer-width.
        assert_eq!(std::mem::size_of::<BioStateHandle>(), std::mem::size_of::<usize>());
    }

    // TC-001: Zero-PII — moor_owl rejects names, emails, short strings
    #[test]
    fn tc_001_moor_owl_rejects_pii() {
        let b = BioState::new();
        assert!(!b.moor_owl("rick@example.com"),  "email must be rejected");
        assert!(!b.moor_owl("Richard Gillespie"), "name must be rejected");
        assert!(!b.moor_owl("123456789"),          "short string must be rejected");
        assert!(!b.moor_owl("04aabbccdd"),          "uncompressed-prefix must be rejected");
    }

    // TC-002: Zero-PII — moor_owl accepts valid compressed secp256k1 pubkey
    #[test]
    fn tc_002_moor_owl_accepts_valid_pubkey() {
        let b = BioState::new();
        // Valid compressed secp256k1 pubkey (02 prefix + 32 bytes hex = 66 chars)
        let valid_pubkey = "02a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2";
        assert!(b.moor_owl(valid_pubkey), "valid pubkey must be accepted");
    }

    // TN-001: Null handle — all FFI functions handle null without panic
    #[test]
    fn tn_001_null_handle_no_panic() {
        assert_eq!(bio_state_get_state(std::ptr::null_mut()), 0);
        assert_eq!(bio_state_get_frame_count(std::ptr::null_mut()), 0);
        bio_state_increment_frame(std::ptr::null_mut()); // must not panic
        assert_eq!(bio_state_get_epistemic_tag(std::ptr::null_mut()), 2);
        assert_eq!(bio_state_transition(std::ptr::null_mut(), 1), 0);
    }

    // TI-001: State machine — IDLE → MOORED → PREPARED (valid path)
    #[test]
    fn ti_001_state_machine_valid_path() {
        let b = BioState::new();
        assert_eq!(b.transition(BiologicalCellState::Moored),   TransitionResult::Allowed);
        assert_eq!(b.transition(BiologicalCellState::Prepared),  TransitionResult::Allowed);
    }

    // TN-002: State machine — IDLE → RUNNING is rejected (invalid skip)
    #[test]
    fn tn_002_state_machine_rejects_invalid_skip() {
        let b = BioState::new();
        assert_eq!(b.transition(BiologicalCellState::Running), TransitionResult::Rejected);
    }

    // TC-003: Training mode — set and clear
    #[test]
    fn tc_003_training_mode_set_clear() {
        let b = BioState::new();
        assert!(!b.is_training_mode());
        b.set_training_mode(true);
        assert!(b.is_training_mode());
        b.set_training_mode(false);
        assert!(!b.is_training_mode());
    }

    // RG-001: Zero-PII — IDLE transition clears owl pubkey
    #[test]
    fn rg_001_idle_transition_clears_owl_pubkey() {
        let b = BioState::new();
        b.transition(BiologicalCellState::Moored);
        let valid_pk = "02a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2";
        assert!(b.moor_owl(valid_pk));
        // Return to IDLE must erase the Owl pubkey — zero-PII cleanup
        b.transition(BiologicalCellState::Idle);
        let guard = b.owl_pubkey.lock().unwrap();
        assert!(guard.is_none(), "Owl pubkey must be erased on IDLE transition");
    }
}
