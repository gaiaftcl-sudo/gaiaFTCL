# OWL-NUTRITION — reconciliation gap table (Phase 0)

**Date:** 2026-04-20  
**Read-only pass against `main` (FoT8D).**  
**Terminal:** `CALORIE` — foundation files present; gaps tagged **`[I]`**.

---

## 1. Architectural decision: Communion UI vs GaiaHealth extension

**Recorded in:** [`NUTRITION_COMMUNION_ARCH_DECISION.md`](NUTRITION_COMMUNION_ARCH_DECISION.md)

**Summary:** **(b) GaiaHealth-internal extension** recommended for v1 documentation and UI spec authorship; **(a) CCR merge into `S4_C4_COMMUNION_UI_SPEC.md`** deferred until nutrition surfaces are stable and three-cell CCR can absorb new §5.x numbering.

---

## 2. OpenUSD / game-loop asset inventory (GaiaHealth / nutrition)

| Asset class | On `main`? | Paths / notes |
|-------------|------------|-----------------|
| **GaiaHealth-specific OpenUSD** | **No** | No `*.usd` / `*.usda` under `cells/health/` in search. |
| **Fusion plant USD (reference)** | **Yes** | `cells/fusion/macos/GaiaFusion/GaiaFusion/Resources/usd/plants/*/root.usda` — plasma game loop; **not** nutrition. |
| **OWL-NUTRITION OpenUSD bridge** | **[I]** | Phase 7 [`OPENUSD_INTEGRATION.md`](../../cells/health/docs/invariants/OWL-NUTRITION/OPENUSD_INTEGRATION.md) is **spec-only** until assets exist. |

---

## 3. Namespace grep — nutrition / OWL-NUTRITION

| Query | Result |
|-------|--------|
| `nutrition` / `OWL-NUTRITION` under `cells/health/docs/` | **No** pre-existing OWL-NUTRITION package before this program. |
| `GH-OWL-*` | OWL-P53, GH-OWL-UNIFIED-FREQ-001 (referenced, file **[I]**), GH-S4C4-COMM-001. |

---

## 4. Trace to GH-FS-001 (FR-001 … FR-004+)

| FR | Relevance to OWL-NUTRITION | Gap / action |
|----|----------------------------|--------------|
| **FR-001** | Lifecycle states apply to **any** GaiaHealth feature branch; nutrition UI uses same state machine when integrated. | **[I]** wire MacHealth states to nutrition panels. |
| **FR-002** | Transition enforcement unchanged. | None. |
| **FR-003** | Epistemic M/I/A (and T in communion) for all nutrition outputs. | Map food log / lab to epistemic tags in schemas (Phase 2). |
| **FR-004** | C-1…C-7 are **small-molecule CURE** gates today. | **Nutrition is not a second CURE path in GH-FS-001 v1.0** — OWL-NUTRITION traces to **communion / extended modality** and future FR amendment **or** separate **invariant receipt** narrative under C4. Document as **GH-FS-001 CC** (change control) candidate — **`[I]` orphan risk closed** by explicit trace in `INVARIANT_FAMILY_SPEC.md`. |

---

## 5. Trace to C-1 … C-7 (REVIEWER_BRIEF)

Nutrition invariant **projection receipts** align with **constitutional closure** themes, not the seven **CURE** chemistry gates directly:

| C-* | Nutrition mapping |
|-----|-------------------|
| **C-1** | Epistemic chain must include **M** or **I** for “held” nutrition claims where GH-FS epistemic rules apply; **A**-only chains remain **[I]** for clinical claims. |
| **C-5** | WASM constitutional exports must pass for any sealed projection. |
| **C-6** | Consent / Owl gate for operator-submitted data. |
| Others | **N/A** to pure nutrition unless combined with small-molecule CURE path — document per scenario. |

---

## 6. Communion UI spec — section map (actual vs planned screens)

| Planned screen (original OWL-NUTRITION brief) | Exists on `main`? | Actual anchor |
|-----------------------------------------------|---------------------|---------------|
| §5.2.6 Nutrition Intake | **No** (number invented) | Map to [`S4_C4_COMMUNION_UI_SPEC.md`](../../cells/health/docs/S4_C4_COMMUNION_UI_SPEC.md) **§3** multi-modal ingest + extended doc; GaiaHealth-specific UI spec TBD. |
| §5.3 C4 Registry extension | **No** as §5.3 | **§4** C4 registry themes in same spec. |
| §5.9 / §5.10 Settings / Dashboard | **No** | **[I]** — [`NUTRITION_UI_SPEC.md`](../../cells/health/docs/invariants/OWL-NUTRITION/NUTRITION_UI_SPEC.md) (Phase 1). |

---

## 7. Swift / Rust filename map

| Planned path (brief) | Actual |
|---------------------|--------|
| `cells/health/macos/GaiaHealth/...` | **Does not exist.** |
| macOS Health app per REVIEWER_BRIEF | [`cells/fusion/macos/MacHealth/`](../../cells/fusion/macos/MacHealth/) — **canonical** for Swift UI work. |
| WASM | [`cells/health/wasm_constitutional/src/lib.rs`](../../cells/health/wasm_constitutional/src/lib.rs) |

---

## 8. vQbit / ingest kinds (grep)

| Kind (brief) | Present in Health Rust? |
|--------------|-------------------------|
| `sensor_frame`, `instrument_run`, `narrative`, `scan` | **Not** found as string enums — communion docs describe narratives; **implementation `[I]`**. |
| `food_log`, `lab_panel`, `microbiome_sample` | **Not** found — **Phase 2 schema + `[I]`** Rust mapping. |

---

## 9. OWL-P53 template mirror

[`cells/health/docs/invariants/OWL-P53/`](../../cells/health/docs/invariants/OWL-P53/) exists with IQ/OQ/PQ, evidence layout, frequency policy pattern — **use as template** for OWL-NUTRITION directory layout.

---

## 10. Receipt

**Phase 0 deliverables:** this file + [`NUTRITION_COMMUNION_ARCH_DECISION.md`](NUTRITION_COMMUNION_ARCH_DECISION.md) + OpenUSD inventory (§2).  
**State:** `CALORIE(nutrition-phase-0): reconciliation complete.`
