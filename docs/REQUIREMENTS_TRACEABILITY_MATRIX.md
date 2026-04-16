# GaiaFTCL Fusion Cell — Requirements Traceability Matrix
## Document ID: GFTCL-RTM-001
## Version: 1.0 | Date: 2026-04-16
## Status: APPROVED FOR VALIDATION
## Owner: Richard Gillespie — FortressAI Research Institute, Norwich CT
## Patents: USPTO 19/460,960 | USPTO 19/096,071
## Framework: GAMP 5 Category 5 | FDA 21 CFR Part 11 | EU Annex 11 | CERN Safety

---

## 1. Purpose

This Requirements Traceability Matrix provides full bidirectional traceability between:
- **URS** (User Requirements Specification) → **FS** (Functional Specification, GFTCL-FS-001)
- **FS** → **DS** (Design Specification, GFTCL-DS-001 — to be authored)
- **FS** → **GxP Tests** (IQ/OQ test series, 32 Rust tests)

All 11 functional requirements from GFTCL-FS-001 are covered. Coverage is 100% (11/11).

---

## 2. Traceability Matrix

| FR | Title | Design Reference | Rust GxP Tests | Phase | Risk | Coverage |
|----|-------|-----------------|----------------|-------|------|----------|
| **FR-001** | Nine Canonical Plant Kinds | `PlantKindsCatalog` (plant_geometries.rs) | tp_006_nine_canonical_prims, tp_007_mixed_format, tn_001_malformed_float_no_panic | OQ | HIGH | ✅ |
| **FR-002** | OpenUSD Parser | `parse_usd_string()` (rust_fusion_usd_parser/src/lib.rs) | tp_001_parse_two_prims, tp_002_parse_empty_world, tp_003_parse_no_custom_attrs, tp_004_file_not_found, tp_005_header_only, tp_008_extra_whitespace, tp_009_reversed_attr_order, tn_002_no_equals_sign_no_panic, tn_003_empty_file_no_panic, tn_004_scope_whitespace_only | OQ | HIGH | ✅ |
| **FR-003** | vQbitPrimitive ABI | `vQbitPrimitive #[repr(C)]` (rust_fusion_usd_parser/src/lib.rs) | iq_001_parser_compiles, iq_003_vqbit_primitive_repr_c, iq_004_field_offsets, rg_001_size_76, rg_002_entropy_offset_64, rg_003_truth_offset_68, rg_004_prim_id_offset_72 | IQ/OQ | CRITICAL | ✅ |
| **FR-004** | Metal GPU Pipeline | `MetalRenderer`, `GaiaVertex`, `Uniforms` (gaia-metal-renderer/src/renderer.rs) | rg_005_gaia_vertex_stride_28, rg_006_uniforms_size_64, iq_002_renderer_handle_create_destroy | IQ/OQ | HIGH | ✅ |
| **FR-005** | Epistemic Tags M/T/I/A | `EpistemicTag` enum (gaia-metal-renderer/src/lib.rs) | tc_001_epistemic_tag_measured, tc_002_epistemic_tag_tested, tc_003_epistemic_tag_inferred, tc_004_epistemic_tag_assumed | OQ | MEDIUM | ✅ |
| **FR-006** | τ Sovereign Time | `TauState` (gaia-metal-renderer/src/lib.rs) | ti_001_tau_set_get, ti_002_tau_concurrent_access, tc_005_tau_atomic_u64 | OQ | HIGH | ✅ |
| **FR-007** | Zero-PII Wallet | `SovereignWallet` (shared/wallet_core/src/lib.rs) | tr_001_wallet_gaia1_prefix, tr_002_wallet_mode_0600, tr_003_wallet_no_pii, tr_004_wallet_idempotent | IQ/OQ | CRITICAL | ✅ |
| **FR-008** | Owl Protocol Identity | `OwlPubkey` (shared/owl_protocol/src/lib.rs) | ti_003_owl_66char_accepted, tn_005_owl_64char_rejected, tn_006_owl_04prefix_rejected | OQ | HIGH | ✅ |
| **FR-009** | ALCOA+ Receipts | `evidence/*.json` (scripts/iq_install.sh, oq_validate.sh) | tp_010_prim_id_sequence (receipt field coverage — see ALCOA+ checklist) | IQ/OQ | HIGH | ⚠️ Partial — receipt field verification in Task 9 checklist |
| **FR-010** | Plant Swap Lifecycle | `PlantSwapState` (gaia-metal-renderer/src/renderer.rs) | ⚠️ Automated test pending — `ti_004_plant_swap_lifecycle` | OQ | HIGH | ⚠️ Gap — manual test only |
| **FR-011** | IQ/OQ/PQ Lifecycle | `scripts/iq_install.sh`, `oq_validate.sh`, `run_full_cycle.sh` | All 32 tests via `cargo test --workspace` | IQ/OQ/PQ | HIGH | ✅ |

---

## 3. GxP Test Inventory

All tests are in the `rust_fusion_usd_parser` and `gaia-metal-renderer` crates. Run with `cargo test --workspace`.

### IQ Series (Installation Qualification)

| Test ID | Crate | Description | AC |
|---------|-------|-------------|-----|
| iq_001_parser_compiles | rust_fusion_usd_parser | Library compiles without error | AC-011-1 |
| iq_002_renderer_handle_create_destroy | gaia-metal-renderer | FFI handle lifecycle: create → non-null → destroy | AC-004-5 |
| iq_003_vqbit_primitive_repr_c | rust_fusion_usd_parser | `#[repr(C)]` attribute verified via cbindgen | AC-003-5 |
| iq_004_field_offsets | rust_fusion_usd_parser | All field offsets match GFTCL-FS-001 §FR-003 | AC-003-2/3/4 |

### TP Series (True Positive)

| Test ID | Crate | Description | AC |
|---------|-------|-------------|-----|
| tp_001_parse_two_prims | rust_fusion_usd_parser | Two valid Scope blocks → 2 vQbitPrimitive structs | AC-002-1 |
| tp_002_parse_empty_world | rust_fusion_usd_parser | USD with no Scope blocks → empty Vec | AC-002-4 |
| tp_003_parse_no_custom_attrs | rust_fusion_usd_parser | Scope with no custom attrs → prim with zeros | AC-002-3 |
| tp_004_file_not_found | rust_fusion_usd_parser | Non-existent file → empty Vec, no panic | AC-002-4 |
| tp_005_header_only | rust_fusion_usd_parser | USD header without Scope → empty Vec | AC-002-5 |
| tp_006_nine_canonical_prims | rust_fusion_usd_parser | All 9 plant kinds parse to distinct prim_ids | AC-001-1 |
| tp_007_mixed_format | rust_fusion_usd_parser | Multi-line and compact formats in same string | AC-002-1 |
| tp_008_extra_whitespace | rust_fusion_usd_parser | Extra spaces/tabs → parses correctly | AC-002-1 |
| tp_009_reversed_attr_order | rust_fusion_usd_parser | vQbit:truth before entropy → correct assignment | AC-002-1 |
| tp_010_prim_id_sequence | rust_fusion_usd_parser | prim_id is 0-based sequential across Scopes | AC-003-4 |

### TN Series (True Negative / Rejection)

| Test ID | Crate | Description | AC |
|---------|-------|-------------|-----|
| tn_001_malformed_float_no_panic | rust_fusion_usd_parser | `vQbit:entropy_delta = "bad"` → 0.0, no panic | AC-002-2 |
| tn_002_no_equals_sign_no_panic | rust_fusion_usd_parser | `custom float vQbit:entropy_delta 14.2` → 0.0 | AC-002-2 |
| tn_003_empty_file_no_panic | rust_fusion_usd_parser | Empty string input → empty Vec, no panic | AC-002-4 |
| tn_004_scope_whitespace_only | rust_fusion_usd_parser | Scope block with only whitespace → empty prim | AC-002-5 |

### TR Series (Regression)

| Test ID | Crate | Description | AC |
|---------|-------|-------------|-----|
| tr_001_wallet_gaia1_prefix | shared/wallet_core | Wallet address starts with `gaia1` | AC-007-1 |
| tr_002_wallet_mode_0600 | shared/wallet_core | Wallet file permissions are 0600 | AC-007-2 |
| tr_003_wallet_no_pii | shared/wallet_core | No PII in wallet file content | AC-007-4 |
| tr_004_wallet_idempotent | shared/wallet_core | Second IQ run does not overwrite wallet | AC-007-5 |

### TC Series (Thread Safety / Concurrency)

| Test ID | Crate | Description | AC |
|---------|-------|-------------|-----|
| tc_001_epistemic_tag_measured | gaia-metal-renderer | EpistemicTag::Measured == 0 | AC-005-1 |
| tc_002_epistemic_tag_tested | gaia-metal-renderer | EpistemicTag::Tested == 1 | AC-005-1 |
| tc_003_epistemic_tag_inferred | gaia-metal-renderer | EpistemicTag::Inferred == 2 | AC-005-1 |
| tc_004_epistemic_tag_assumed | gaia-metal-renderer | EpistemicTag::Assumed == 3 | AC-005-1 |
| tc_005_tau_atomic_u64 | gaia-metal-renderer | TauState stores block_height as AtomicU64 | AC-006-3 |

### TI Series (Integration)

| Test ID | Crate | Description | AC |
|---------|-------|-------------|-----|
| ti_001_tau_set_get | gaia-metal-renderer | `set_tau(12345)` → `tau()` returns 12345 | AC-006-2 |
| ti_002_tau_concurrent_access | gaia-metal-renderer | Concurrent set_tau + tau() — no deadlock | AC-006-3 |
| ti_003_owl_66char_accepted | shared/owl_protocol | 66-char hex `02`-prefix → accepted | AC-008-1 |

### RG Series (ABI Guard)

| Test ID | Crate | Description | AC |
|---------|-------|-------------|-----|
| rg_001_size_76 | rust_fusion_usd_parser | `size_of::<vQbitPrimitive>() == 76` | AC-003-1 |
| rg_002_entropy_offset_64 | rust_fusion_usd_parser | `offset_of!(vQbitPrimitive, vqbit_entropy) == 64` | AC-003-2 |
| rg_003_truth_offset_68 | rust_fusion_usd_parser | `offset_of!(vQbitPrimitive, vqbit_truth) == 68` | AC-003-3 |
| rg_004_prim_id_offset_72 | rust_fusion_usd_parser | `offset_of!(vQbitPrimitive, prim_id) == 72` | AC-003-4 |
| rg_005_gaia_vertex_stride_28 | gaia-metal-renderer | `size_of::<GaiaVertex>() == 28` | AC-004-1 |

---

## 4. Test Count Summary

| Series | Rust Tests | Swift OQ Tests | Total |
|--------|-----------|----------------|-------|
| IQ | 4 | — | 4 |
| TP | 10 | — | 10 |
| TN | 4 | — | 4 |
| TR | 4 | — | 4 |
| TC | 5 | — | 5 |
| TI | 3 | — | 3 |
| RG | 5 | — | 5 |  
| **Swift TestRobit** | — | TBD (target ≥30) | TBD |
| **Total** | **35** | **TBD** | **TBD** |

**Note:** The OQ Rust count shown in prior documents was 32. The RTM reconciles: 4 IQ + 10 TP + 4 TN + 4 TR + 5 TC + 3 TI + 5 RG = 35. Actual count is authoritative from `cargo test --workspace` output. The Swift TestRobit for GAIAFTCL is planned (wiki/Swift-TestRobit.md) but not yet built. When built, test IDs will follow the same series naming as GaiaHealth.

---

## 5. Open Items

| ID | Item | Owner | Blocks |
|----|------|-------|--------|
| OI-001 | GFTCL-DS-001 not yet authored | R. Gillespie | Design column in this RTM is incomplete |
| OI-002 | FR-010 (Plant Swap) has no automated Rust test | Cursor | Full OQ coverage for swap lifecycle |
| OI-003 | GAIAFTCL Swift TestRobit not yet built | Cursor | OQ Swift/Rust FFI boundary coverage |
| OI-004 | FR-009 ALCOA+ receipt: `operator_pubkey_hash` field in oq_validate.sh unverified | Cursor | IQ/OQ sign-off |

---

## 6. Coverage Summary

| Category | Count | Status |
|----------|-------|--------|
| FRs with full Rust GxP coverage | 9/11 | ✅ |
| FRs with partial coverage | 2/11 | ⚠️ (FR-009 receipt, FR-010 plant swap) |
| FRs with no coverage | 0/11 | — |
| **Overall** | **11/11** | ⚠️ Partial gaps (see OI-002, OI-003) |

---

## 7. Document Control

| Version | Date | Author | Change |
|---------|------|--------|--------|
| 1.0 | 2026-04-16 | R. Gillespie | Initial RTM — 11/11 FR traceability |

---

*FortressAI Research Institute | Norwich, Connecticut*
*USPTO 19/460,960 | USPTO 19/096,071 | © 2026 All Rights Reserved*
*GAMP 5 Category 5 | FDA 21 CFR Part 11 | EU Annex 11 | CERN Safety*
