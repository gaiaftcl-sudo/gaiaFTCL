# OQ — Operational Qualification

Operational Qualification proves that the software does what it is designed to do. Every automated test must pass on every build. OQ is run via `zsh scripts/oq_validate.sh` and produces a machine-readable receipt.

**Document reference:** GFTCL-OQ-001
**Framework:** GAMP 5 | EU Annex 11 | FDA 21 CFR Part 11
**Prerequisite:** IQ complete and `evidence/iq_receipt.json` present.

---

## Running OQ

```zsh
cd ~/Documents/FoT8D/GAIAFTCL
zsh scripts/oq_validate.sh
```

OQ runs `cargo test --workspace` and collects the results into `evidence/oq_receipt.json`. All 32 tests must pass. A single failure produces `OQ_FAIL` and blocks PQ.

**Expected result:**
```
OPERATIONAL QUALIFICATION COMPLETE
32/32 tests passed
Result: OQ_PASS
Receipt: evidence/oq_receipt.json
```

---

## The 32-Test GxP Suite

Tests are organised into seven series. Each series is described below with its purpose and — for the TP series — the specific plant kind it covers.

---

### IQ Series — Installation Qualification Guards (2 tests)

These tests run in the Rust test harness to verify that the build environment itself is correctly established. They are distinct from the shell-level IQ checks and verify the compiled binary rather than the environment.

| Test ID | Name | What it verifies |
| --- | --- | --- |
| IQ-001 | `iq_001_parser_compiles` | The `rust_fusion_usd_parser` crate compiles without error |
| IQ-003 | `iq_003_vqbit_primitive_repr_c` | `size_of::<vQbitPrimitive>() == 76` — ABI is correct |

---

### TP Series — Parsing Tests (10 tests)

The TP series covers the USD parser. Tests TP-006 through TP-010 are directly tied to the nine canonical plant kinds.

| Test ID | Name | Plant kind / scope | What it verifies |
| --- | --- | --- | --- |
| TP-001 | `tp_001_parse_two_prims` | Generic | Parses two `def Scope` blocks; correct `prim_id`, `vqbit_entropy`, `vqbit_truth` |
| TP-002 | `tp_002_parse_empty_world` | Generic | Empty world produces zero primitives, no panic |
| TP-003 | `tp_003_parse_no_custom_attrs` | Generic | Scope with no attributes produces defaults (0.0, 0.0) |
| TP-004 | `tp_004_file_not_found` | Generic | Non-existent file returns `Err`, error message contains "Failed to open USD file" |
| TP-005 | `tp_005_header_only` | Generic | File with header only produces zero primitives |
| TP-006 | `tp_006_nine_canonical_prims` | **All 9 plant kinds** | Parses all nine canonical plant scopes from one file; verifies correct `prim_id` sequence (0–8), `vqbit_entropy` values (0.1–0.9), `vqbit_truth` values (0.91–0.99) |
| TP-007 | `tp_007_mixed_format` | Generic | One-liner compact scope and multi-line scope in same file both parse correctly |
| TP-008 | `tp_008_extra_whitespace` | Generic | Extra whitespace around `=` does not break parsing |
| TP-009 | `tp_009_reversed_attr_order` | Generic | `truth_threshold` before `entropy_delta` in file parses correctly |
| TP-010 | `tp_010_prim_id_sequence` | Generic | Three sequential scopes receive `prim_id` 0, 1, 2 in order |

**TP-006 detail — All nine plant kinds in one test:**

The test file contains one scope per plant kind, in order: Tokamak, Stellarator, FRC, Spheromak, Mirror, Inertial, SphericalTokamak, ZPinch, MIF. Each scope is a one-liner with both attributes. The test asserts:
- Exactly 9 primitives returned
- `prim_id` sequence is 0 through 8
- `vqbit_entropy` for primitive `i` is `(i+1) × 0.1` within 1e-5
- `vqbit_truth` for primitive `i` is `0.91 + i × 0.01` within 1e-5

---

### TN Series — Negative / Robustness Tests (4 tests)

These tests confirm the parser never panics on malformed input and handles edge cases gracefully.

| Test ID | Name | What it verifies |
| --- | --- | --- |
| TN-001 | `tn_001_malformed_float_no_panic` | Non-numeric value for `entropy_delta` silently defaults to 0.0; `truth_threshold` on next line still parses correctly |
| TN-002 | `tn_002_no_equals_sign_no_panic` | Attribute keyword mentioned in comment (no `=` sign) does not panic; field stays at default |
| TN-003 | `tn_003_empty_file_no_panic` | Completely empty file returns empty list, no panic |
| TN-004 | `tn_004_scope_whitespace_only` | Scope block containing only whitespace produces one primitive with default values |

---

### TR Series — Type and Layout Tests (4 tests)

These tests verify the ABI layout of the two key structs used by the Metal renderer. A failure here means the Rust layout does not match the Metal shader or the Swift FFI layer.

| Test ID | Name | What it verifies |
| --- | --- | --- |
| TR-001 | `tr_001_gaia_vertex_size` | `size_of::<GaiaVertex>() == 28` (position 12 B + color 16 B) |
| TR-002 | `tr_002_gaia_vertex_field_offsets` | `position` at offset 0, `color` at offset 12 |
| TR-003 | `tr_003_uniforms_size` | `size_of::<Uniforms>() == 64` (float4x4 = 16 × f32) |
| TR-004 | `tr_004_vqbit_primitive_passthrough` | `vQbitPrimitive` is importable from the renderer crate and its `prim_id`, `vqbit_entropy`, `vqbit_truth` fields default to zero |

---

### TC Series — Geometry Conversion Tests (4 tests)

These tests verify the default cube geometry used when no USD file has been loaded. The cube is the baseline geometry for all nine plant kinds before their specific wireframe is uploaded.

| Test ID | Name | What it verifies |
| --- | --- | --- |
| TC-001 | `tc_001_default_geometry_vertex_count` | Default geometry returns exactly 8 unique vertices |
| TC-002 | `tc_002_default_geometry_index_count` | Default geometry returns exactly 36 indices (6 faces × 2 triangles × 3 vertices) |
| TC-003 | `tc_003_default_geometry_indices_in_range` | Every index is less than the vertex count — no out-of-bounds GPU access |
| TC-004 | `tc_004_vertex_new_roundtrip` | `GaiaVertex::new()` stores position and colour exactly as given |

---

### TI Series — Integration Tests (3 tests)

These tests verify the mapping from `vQbitPrimitive` fields to vertex colours. This mapping applies to all nine plant kinds.

| Test ID | Name | What it verifies |
| --- | --- | --- |
| TI-001 | `ti_001_vqbit_primitive_color_mapping` | `vqbit_entropy` → red channel, `vqbit_truth` → green channel, blue hardcoded 0.5, alpha 1.0 |
| TI-002 | `ti_002_vqbit_entropy_clamped_above_one` | `vqbit_entropy = 1.5` clamps to 1.0 for colour; does not overflow |
| TI-003 | `ti_003_vqbit_truth_clamped_below_zero` | `vqbit_truth = -0.3` clamps to 0.0 for colour; no negative colour channel |

---

### RG Series — Regression Guards (5 tests)

These tests lock the ABI byte layout. If any of these fail, it means a change was made to a struct that breaks the Metal vertex descriptor, the uniform buffer binding, or the Swift FFI boundary. Any such change requires an explicit decision and corresponding updates to the Metal shader or FFI header.

| Test ID | Name | What it guards | Failure implication |
| --- | --- | --- | --- |
| RG-001 | `rg_001_vertex_stride_28_bytes` | `GaiaVertex` stride = 28 bytes | `MTLVertexDescriptor` stride in `renderer::new()` must be updated |
| RG-002 | `rg_002_uniforms_stride_64_bytes` | `Uniforms` stride = 64 bytes | Metal `buffer(1)` binding must be updated |
| RG-003 | `rg_003_vqbit_primitive_repr_c_size` | `vQbitPrimitive` size = 76 bytes | Swift FFI boundary is broken; `gaia_metal_renderer.h` must be regenerated |
| RG-004 | `rg_004_vqbit_field_offsets` | `transform` at 0, `vqbit_entropy` at 64, `vqbit_truth` at 68, `prim_id` at 72 | Swift layer reads wrong memory; full re-qualification required |
| RG-005 | `rg_005_iq_004_field_offsets` | Same field offsets verified from the parser crate | Parser and renderer crate agree on ABI layout |

---

## OQ Acceptance Criteria

| Criterion | Requirement |
| --- | --- |
| Test count | Exactly 32 tests executed |
| Pass rate | 100% — zero failures permitted |
| Known warnings (non-blocking) | `TAU_NOT_IMPLEMENTED` and `NATS_UNREACHABLE` are acceptable during development |
| Receipt | `evidence/oq_receipt.json` written with `result: OQ_PASS` |

---

## OQ per Plant Kind — Coverage Summary

| Plant kind | Covered by |
| --- | --- |
| Tokamak | TP-006 (parsing), TI-001/002/003 (colour mapping), RG-003/004 (ABI) |
| Stellarator | TP-006 (parsing), TI-001/002/003 (colour mapping), RG-003/004 (ABI) |
| Spherical Tokamak | TP-006 (parsing), TI-001/002/003 (colour mapping), RG-003/004 (ABI) |
| FRC | TP-006 (parsing), TI-001/002/003 (colour mapping), RG-003/004 (ABI) |
| Mirror | TP-006 (parsing), TI-001/002/003 (colour mapping), RG-003/004 (ABI) |
| Spheromak | TP-006 (parsing), TI-001/002/003 (colour mapping), RG-003/004 (ABI) |
| Z-Pinch | TP-006 (parsing), TI-001/002/003 (colour mapping), RG-003/004 (ABI) |
| MIF | TP-006 (parsing), TI-001/002/003 (colour mapping), RG-003/004 (ABI) |
| Inertial | TP-006 (parsing), TI-001/002/003 (colour mapping), RG-003/004 (ABI) |

Note: OQ covers the parser and the renderer ABI for all nine plants. Continuous render, physics bounds, and swap lifecycle are covered in [[PQ-Performance-Qualification]].

---

## OQ Evidence

`evidence/oq_receipt.json` — written by `oq_validate.sh` on every successful OQ run. Must be present before PQ begins.

```json
{
  "schema": "GFTCL-OQ-001",
  "timestamp": "2026-04-13T...",
  "rust_tests_passed": 32,
  "rust_tests_total": 32,
  "warnings": ["TAU_NOT_IMPLEMENTED", "NATS_UNREACHABLE"],
  "result": "OQ_PASS"
}
```
