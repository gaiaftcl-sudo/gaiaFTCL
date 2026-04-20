# GaiaFTCL Health Mac Cell — Complete Reference

**FortressAI Research Institute | Norwich, Connecticut**  
**Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie**

This page is the **in-repo mirror** of the GitHub wiki page **GaiaFTCL Health Mac Cell Wiki** (`gaiaFTCL.wiki.git`). Edit here on `main`, then push the [wiki clone](https://github.com/gaiaftcl-sudo/gaiaFTCL.wiki.git) so GitHub stays aligned.

---

## Media — GaiaHealth video artifacts (poster → MP4)

Posters and MP4s live on branch **`main`** in [`docs/media/videos/gaiahealth/`](https://github.com/gaiaftcl-sudo/gaiaFTCL/tree/main/docs/media/videos/gaiahealth). GitHub Wiki does not render `<video>`; use **clickable poster → raw MP4** (same pattern as the [Silicon cell wiki](https://github.com/gaiaftcl-sudo/gaiaFTCL/wiki/GaiaFTCL-Lithography-Silicon-Cell-Wiki)). **Optional:** embedded players on [GitHub Pages — health catalog](https://gaiaftcl-sudo.github.io/gaiaFTCL/gaiahealth-cell-media.html) · [full index](https://gaiaftcl-sudo.github.io/gaiaFTCL/).

### GH-VID-KINE-001 — Code as physics (kinematic pipeline)

[![Poster: Code as physics](https://raw.githubusercontent.com/gaiaftcl-sudo/gaiaFTCL/main/docs/media/videos/gaiahealth/poster-code-as-physics.png)](https://raw.githubusercontent.com/gaiaftcl-sudo/gaiaFTCL/main/docs/media/videos/gaiahealth/code-as-physics-gaiahealth-kinematic-pipeline.mp4)

**Play:** [MP4 (raw)](https://raw.githubusercontent.com/gaiaftcl-sudo/gaiaFTCL/main/docs/media/videos/gaiahealth/code-as-physics-gaiahealth-kinematic-pipeline.mp4) · [wiki](https://github.com/gaiaftcl-sudo/gaiaFTCL/wiki/Code-as-Physics-GaiaHealth-Kinematic-Pipeline) · [blob](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/docs/media/videos/gaiahealth/code-as-physics-gaiahealth-kinematic-pipeline.mp4)

- **SHA-256 (MP4):** `c9f64c276a5f19d4ced52e599751322b61a261124b0586cf527b62fc453ec456`

### GH-VID-CURE-001 — Engineering the CURE (11-state machine)

[![Poster: Engineering the CURE](https://raw.githubusercontent.com/gaiaftcl-sudo/gaiaFTCL/main/docs/media/videos/gaiahealth/poster-engineering-the-cure.png)](https://raw.githubusercontent.com/gaiaftcl-sudo/gaiaFTCL/main/docs/media/videos/gaiahealth/Engineering_the_CURE__The_GaiaHealth_State_Machine.mp4)

**Play:** [MP4 (raw)](https://raw.githubusercontent.com/gaiaftcl-sudo/gaiaFTCL/main/docs/media/videos/gaiahealth/Engineering_the_CURE__The_GaiaHealth_State_Machine.mp4) · [blob](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/docs/media/videos/gaiahealth/Engineering_the_CURE__The_GaiaHealth_State_Machine.mp4)

- **SHA-256 (MP4):** `3e5cd07ef293952ce442ac943fbd7e0941ac5d7e5f41bd0e0d027775fb819b1b` — *re-encoded H.264/AAC on `main` so the blob stays under GitHub’s 100 MiB limit while preserving wiki `raw.githubusercontent.com` links (see [`docs/media/videos/gaiahealth/README.md`](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/docs/media/videos/gaiahealth/README.md)).*

---

## Qualification Catalog — program traceability

The program **[Qualification-Catalog](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/wiki/Qualification-Catalog.md)** maps GaiaHealth requirements to frameworks. It includes **OWL-P53-INV1**, **OWL-NUTRITION**, **LIGAND-CLASS / peptide** ([§4.6](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/wiki/Qualification-Catalog.md)), and **§8** framework rows. Automated check (local):

```bash
bash cells/health/scripts/health_cell_gamp5_validate.sh
```

---

## 1. What this is (two surfaces)

### 1.A — GaiaHealth **Biologit** cell (`cells/health/`) — **GH-FS-001**

Authoritative product definition: **[Functional Specification](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/FUNCTIONAL_SPECIFICATION.md)**.

- **GAMP 5 Category 5** research instrument: **computational drug discovery** — PDB ingest (PHI-scrubbed), molecular dynamics, Metal rendering, **11-state** lifecycle, **CURE** emission when constitutional gates pass.
- **Epistemic spine:** **M / I / A** only (Measured, Inferred, Assumed) on computational outputs — see [State-Machine](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/State-Machine.md).
- **Ligand scope:** small molecule **or** **peptide** as **`ligand_class`** on `BioligitPrimitive` — [PEPTIDE_INTEGRATION_SPEC.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/PEPTIDE_INTEGRATION_SPEC.md). Peptides are a **ligand class inside the MD pipeline**, not a separate “M_bio / ω-kine” kinematic track (that unpublished terminology is **out of scope** for normative requirements; see §9 below).
- **WASM:** **eight core** constitutional exports + **two auxiliary** PGx-related exports — [WASM-Constitutional-Substrate](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/WASM-Constitutional-Substrate.md), `wasm_constitutional/src/lib.rs`.

### 1.B — **MacHealth** SIL harness (`cells/fusion/macos/MacHealth/`)

A **separate** Swift package for **RF / telemetry / SIL V2** scenario contracts, ZMQ wire formats, and **M_SIL** provenance in **validation** narratives. It is **not** the same codebase as the Biologit cell’s Rust crates, but shares constitutional *ideas* (Owl, refusal). SIL scenario YAML and tests: **[Scenarios_Physics_Frequencies_Assertions.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/Scenarios_Physics_Frequencies_Assertions.md)**, `cells/fusion/macos/MacHealth/Tests/SILV2/`.

Do **not** conflate Biologit **CURE gates (C-1…C-7)** with the **seven SIL clinical scenario IDs** — see §12.

---

## 2. Architecture — Biologit cell (`cells/health/`)

| Layer | Location | Role |
|-------|----------|------|
| MD + state machine + FFI | [`biologit_md_engine`](https://github.com/gaiaftcl-sudo/gaiaFTCL/tree/main/cells/health/biologit_md_engine) | `BioState`, transitions, Owl mooring |
| PDB / `BioligitPrimitive` | [`biologit_usd_parser`](https://github.com/gaiaftcl-sudo/gaiaFTCL/tree/main/cells/health/biologit_usd_parser) | 96-byte ABI, `ligand_class` @ offset 88 |
| WASM | [`wasm_constitutional`](https://github.com/gaiaftcl-sudo/gaiaFTCL/tree/main/cells/health/wasm_constitutional) | Package **`gaia-health-substrate`**, WKWebView |
| Metal | [`gaia-health-renderer`](https://github.com/gaiaftcl-sudo/gaiaFTCL/tree/main/cells/health/gaia-health-renderer) | M/I/A epistemic alpha |
| OQ harness | [`swift_testrobit`](https://github.com/gaiaftcl-sudo/gaiaFTCL/tree/main/cells/health/swift_testrobit) | **58** Swift tests (`TR-S1`…`TR-S5`) |

There is **no** requirement that all qualification be “Swift-only”: the GAMP pipeline above is **`bash` + `python3` + `cargo test`** per `health_cell_gamp5_validate.sh`.

---

## 3. UUM-8D & epistemic tagging (Biologit)

The Health **Biologit** cell uses the same cross-cell commitment to **signed receipts** and **epistemic discipline**. For **computational outputs** in scope of GH-FS-001, tags are **M, I, A** only. **T** (Tested) and **M_SIL** appear in **SIL / MacHealth** validation docs as **provenance** labels — not as extra Metal epistemic pipeline states for the Biologit renderer.

---

## 4. GAMP 5 validation (repeatable)

| Artifact | Path / command |
|----------|----------------|
| Full Health GAMP check | `bash cells/health/scripts/health_cell_gamp5_validate.sh` |
| Peptide / LIGAND-CLASS evidence | `bash cells/health/scripts/peptide_ligand_class_gamp5_evidence.sh` |
| Rust unit tests (baseline **81**) | `cd cells/health && cargo test --workspace` |
| Swift OQ harness | `cd cells/health/swift_testrobit && swift build && swift run SwiftTestRobit` |

Receipts (JSON) under `cells/health/docs/invariants/.../evidence/` and `cells/health/evidence/` as applicable — see [GAMP5-Lifecycle](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/GAMP5-Lifecycle.md).

---

## 5. Owl identity, consent, WASM (matches code)

- **`moor_owl`**: compressed secp256k1 pubkey hex (**66** chars, `02`/`03`); names and emails **rejected** — zero-PII.
- **`consent_validity_check`**: same key rules + **5-minute** window — `wasm_constitutional/src/lib.rs`.
- **CURE gate C-6** and full traceability: [REVIEWER_BRIEF.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/REVIEWER_BRIEF.md).

---

## 6. “Swift only” — **superseded**

Older narrative claimed **all** Mac qualification for Health was Swift-only. The **authoritative** Biologit GAMP posture includes **`health_cell_gamp5_validate.sh`** (wiki lint, Qualification Catalog check, OWL-NUTRITION, peptide evidence, `cargo test --workspace`). Swift TestRobit remains the **OQ** harness for FFI + WASM contract tests.

---

## 7. Constitutional constraints (Health / Biologit)

Mesh-wide Fusion **C-001…C-010** live in the Fusion product. GaiaHealth **CURE** conditions **C-1…C-7** are defined in **GH-FS-001** and [REVIEWER_BRIEF.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/REVIEWER_BRIEF.md). **ICNIRP / live biological harm** thresholds belong to **SIL / hardware** narratives (MacHealth), not to the core Biologit **research-instrument** scope statement in §1 of GH-FS-001.

---

## 8. Quick links (Biologit)

| Doc | URL |
|-----|-----|
| Functional Specification (GH-FS-001) | [blob](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/FUNCTIONAL_SPECIFICATION.md) |
| Design Specification | [blob](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/DESIGN_SPECIFICATION.md) |
| State machine (wiki) | [State-Machine.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/State-Machine.md) |
| WASM substrate (wiki) | [WASM-Constitutional-Substrate.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/WASM-Constitutional-Substrate.md) |
| IQ / OQ / PQ (wiki) | [IQ](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/IQ-Installation-Qualification.md) · [OQ](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/OQ-Operational-Qualification.md) · [PQ](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/PQ-Performance-Qualification.md) |
| SIL scenarios (repo) | [Scenarios_Physics_Frequencies_Assertions.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/Scenarios_Physics_Frequencies_Assertions.md) |
| S4↔C4 Communion (design target) | [S4_C4_COMMUNION_UI_SPEC.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/S4_C4_COMMUNION_UI_SPEC.md) |

---

## 9. Superseded narrative — M_bio → ω_kine (do not use for normative peptide / MD scope)

Earlier wiki drafts described an **M_bio → ω_kine** frequency-overriding story. **Peptide integration** is now specified as a **ligand class** on the existing MD stack (**HEALTH-PEPTIDE-SPEC-V1**). Do **not** treat **M_bio / ω-kine** as published substrate terminology for qualification — see **[PEPTIDE_INTEGRATION_SPEC.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/PEPTIDE_INTEGRATION_SPEC.md)** §1 and §10.

---

## 10–11. SIL V2 scenario contracts (MacHealth)

Machine-readable spec: **[Scenarios_Physics_Frequencies_Assertions.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/Scenarios_Physics_Frequencies_Assertions.md)**.

Swift XCTest contracts: **`cells/fusion/macos/MacHealth/Tests/SILV2/`** (e.g. `ScenarioContractValidation.swift`, `ClinicalScenarioContractTests.swift`).

**Disclaimer (from Scenarios doc):** substrate validation language — **not** a clinical protocol or treatment claim unless separately qualified.

---

## 12. Terminology — **CURE gates (C-1…C-7)** vs **seven SIL scenarios**

| Name | Meaning | Authoritative location |
|------|---------|------------------------|
| **C-1…C-7** | Boolean gates for **CURE** emission (WASM, consent, epistemic, selectivity, …) | [REVIEWER_BRIEF.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/REVIEWER_BRIEF.md), GH-FS-001 |
| **Seven SIL scenario IDs** | Cohort-level **validation suites** (`inv3_aml`, …) | Scenarios doc + MacHealth `ClinicalScenario` |
| **Cross-domain obligate analogy** | Pedagogical **[I]** only | Not a WASM export; see repo `docs/OBLIGATE_COUPLING_BIOPHYSICS_ANALOGY.md` if present |

---

*Enumeration tracks `main`; specs linked above win on conflict.*
