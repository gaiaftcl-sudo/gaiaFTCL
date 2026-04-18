# GaiaHealth — reviewer brief (Biologit cell)

| Field | Value |
|-------|--------|
| **Scope** | Engineering + GxP doc review (`cells/health/` + macOS app path below) |
| **Out of scope** | Clinical decision support (GH-FS-001); communion items marked *design target* |

## Canonical paths

| Asset | Path |
|-------|------|
| Rust / WASM / TestRobit | [`cells/health/`](../README.md) (this tree) |
| macOS Swift app | [`cells/fusion/macos/MacHealth/`](../../fusion/macos/MacHealth/) |
| GH-FS / GH-DS / GH-RTM | [`FUNCTIONAL_SPECIFICATION.md`](FUNCTIONAL_SPECIFICATION.md), [`DESIGN_SPECIFICATION.md`](DESIGN_SPECIFICATION.md), [`REQUIREMENTS_TRACEABILITY_MATRIX.md`](REQUIREMENTS_TRACEABILITY_MATRIX.md) |
| S4↔C4 communion (abbrev + extended) | [`S4_C4_COMMUNION_UI_SPEC.md`](S4_C4_COMMUNION_UI_SPEC.md), [`COMMUNION_UI_ARCHITECTURE_EXTENDED.md`](COMMUNION_UI_ARCHITECTURE_EXTENDED.md) |
| M8 substrate | [`docs/M8_S4_C4_SUBSTRATE_CONTEXT.md`](../../../docs/M8_S4_C4_SUBSTRATE_CONTEXT.md) |
| Obligate-coupling analogy | [`docs/OBLIGATE_COUPLING_BIOPHYSICS_ANALOGY.md`](../../../docs/OBLIGATE_COUPLING_BIOPHYSICS_ANALOGY.md) |

---

## Seven CURE conditions (FR-004) — traceability

CLI reference (when `gaiaftcl` built): `gaiaftcl health cure check` — seven gates **C-1…C-7**.

| ID | Gate | In-repo verification (typical) |
|----|------|----------------------------------|
| **C-1** | Epistemic chain (M or I on path) | Rust: `epistemic.rs` `permits_cure()`, tests `tp_006`, `tp_007`, `tc_005`, `tc_006`; Swift: `EpistemicTests` TR-S4-009 / TR-S4-010 |
| **C-2** | Binding ΔG favorable | WASM `binding_constitutional_check` — `ConstitutionalTests` TR-S5-009 |
| **C-3** | ADMET threshold | WASM `admet_bounds_check` — TR-S5-002, TR-S5-010 |
| **C-4** | Simulation time ≥ requirement | `force_field.rs` / state machine — `tc_009_simulation_too_short_rejected` (minimum sim time discipline) |
| **C-5** | Constitutional (WASM exports) | `ConstitutionalTests` TR-S5-001…008 (8 exports) + functional calls |
| **C-6** | Consent window | WASM `consent_validity_check` — TR-S5-005 |
| **C-7** | Selectivity | WASM `selectivity_check` — TR-S5-007 |

**Note:** Full end-to-end `health cure check` JSON is produced by the **GaiaFTCL CLI** when integrated; this cell ships **Rust + Swift TestRobit** evidence that underpin the same gates.

---

## SIL V2 — seven clinical scenario contracts (MacHealth)

**Swift** (`cells/fusion/macos/MacHealth/Tests/SILV2/`): `ClinicalScenario.allCases.count == 7` — one contract suite per indication:

| # | Scenario ID | Notes |
|---|-------------|--------|
| 1 | `inv3_aml` | INV3 AML |
| 2 | `parkinsons_synuclein_thz` | THz / synuclein band |
| 3 | `msl_tnbc` | TNBC |
| 4 | `breast_cancer_general_thz` | Breast |
| 5 | `colon_cancer_thz` | Colon |
| 6 | `lung_cancer_thz_thermal` | Lung |
| 7 | `skin_cancer_bcc_melanoma` | Skin |

Run: `cd cells/fusion/macos/MacHealth && swift test` — **`ClinicalScenarioContractTests`** + **`MacHealthTests`** must pass (22 tests total in last green run).

---

## Build / test commands (evidence for PR)

```bash
cd cells/health && cargo test --workspace
# Last green: 57 Rust tests (26 + 11 + 8 + 12)
cd cells/fusion/macos/MacHealth && swift test
# Last green: 22 Swift tests (13 SIL scenario + 9 MacHealth)
# Optional when CLI present:
# gaiaftcl health cure check
```

Paste exit codes and test counts in the PR description.

---

**© 2026 Richard Gillespie — FortressAI Research Institute**
