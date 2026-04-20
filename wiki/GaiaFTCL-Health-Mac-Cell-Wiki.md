# GaiaFTCL Health Mac Cell — Complete Reference

**FortressAI Research Institute | Norwich, Connecticut**  
**Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie**

**This wiki page is for humans.** It keeps the long-form **story**—substrate, SIL, scenarios, and mechanism-design narrative—**and** points to **normative** specs on branch **`main`** where qualification and code matter. If anything here conflicts with a linked spec or `REVIEWER_BRIEF`, **the spec wins**.

*In-repo mirror:* edit in [`gaiaFTCL`](https://github.com/gaiaftcl-sudo/gaiaFTCL) on `main`, then push [`gaiaFTCL.wiki.git`](https://github.com/gaiaftcl-sudo/gaiaFTCL.wiki.git) so GitHub Wiki stays aligned.

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

## Qualification Catalog — traceability on `main`

The program **[Qualification-Catalog](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/wiki/Qualification-Catalog.md)** maps GaiaHealth requirements to frameworks — **OWL-P53-INV1** ([§4.4](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/wiki/Qualification-Catalog.md)), **OWL-NUTRITION**, **LIGAND-CLASS / peptide** ([§4.6](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/wiki/Qualification-Catalog.md)), **§8** framework rows, and related entries. Package pointer for OWL-P53: [README (blob)](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/invariants/OWL-P53/README.md).

Automated check (local):

```bash
bash cells/health/scripts/health_cell_gamp5_validate.sh
```

---

## Peptide / LIGAND-CLASS — HEALTH-PEPTIDE-SPEC-V1 (what we built on `main`)

**Peptide therapy is not a side quest.** It is a **first-class ligand class** on the same Biologit MD stack as small molecules: same **BioligitPrimitive**, same **WASM** constitutional gates (now **class-aware** for ADMET, selectivity, and force-field routing), same **CURE** closure story — with **PGx** and **consent** rules that match peptide biology (hashed features, separate scope — see [PGX_POLICY.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/invariants/LIGAND-CLASS/PGX_POLICY.md)).

**Normative story (one sentence):** peptides ride **inside** the MD pipeline as `ligand_class` at ABI offset **88**; they are **not** a parallel unpublished “M_bio / ω_kine” kinematic track. The long **§9** frequency narrative on *this* page is **SIL / pedagogy**; **HEALTH-PEPTIDE-SPEC-V1** is the qualification story for computational peptide scope — see [PEPTIDE_INTEGRATION_SPEC.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/PEPTIDE_INTEGRATION_SPEC.md) §1 and §10.

Traceability mirrors **[Qualification-Catalog §4.6](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/wiki/Qualification-Catalog.md#46-ligand-class--peptide-therapy-integration)** and **[§8.3 framework targets](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/wiki/Qualification-Catalog.md#83-peptide-ligand-class--framework-targets)**:

| Field | Value |
|-------|--------|
| **Spec ID** | `HEALTH-PEPTIDE-SPEC-V1` |
| **Integration spec** | [PEPTIDE_INTEGRATION_SPEC.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/PEPTIDE_INTEGRATION_SPEC.md) |
| **Change control** | [CCR-HEALTH-PEPTIDE-V1.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/ccr/CCR-HEALTH-PEPTIDE-V1.md) — three-of-three Lithography + Fusion + Health signatures **[I]** until signed |
| **Invariants** | [LIGAND-CLASS/README.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/invariants/LIGAND-CLASS/README.md) — **INV-HEALTH-LC-01..06** |
| **IQ / OQ / PQ** | [OQ_PEPTIDE_V1.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/qualification/OQ_PEPTIDE_V1.md) · [PQ_PEPTIDE_V1.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/qualification/PQ_PEPTIDE_V1.md) |
| **Automated evidence** | `bash cells/health/scripts/peptide_ligand_class_gamp5_evidence.sh` → [`peptide_ligand_class_gamp5_receipt.json`](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/invariants/LIGAND-CLASS/evidence/peptide_ligand_class_gamp5_receipt.json) |
| **Communion UI** | [S4_C4_COMMUNION_UI_SPEC.md §5.3](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/S4_C4_COMMUNION_UI_SPEC.md) — **MOL/PEP** ligand-class badge (**[I]** until UI ships) |

**Engineering hooks (for readers who open the repo):**

- **`BioligitPrimitive` v1.1:** `ligand_class` **u8** @ byte offset **88** (96-byte struct unchanged) — [BioligitPrimitive-ABI](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/BioligitPrimitive-ABI.md).
- **`wasm_constitutional`:** class-aware **ADMET**, **selectivity**, **force_field_bounds_check** (peptide vs small-molecule paths per policy); **PGx** auxiliary exports follow [PGX_POLICY.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/invariants/LIGAND-CLASS/PGX_POLICY.md).
- **`biologit_md_engine`:** docking dispatch (peptide does **not** select Vina blindly), **ff14SB/CHARMM36m** peptide FF selection where applicable — all governed by the same state machine and receipt discipline as small molecules.

---

# Human narrative — substrate, SIL, and scenario suites

*The sections below are the long-form wiki voice: MacHealth / telemetry / SIL validation and the “human-as-substrate” design story. They sit **beside** the Biologit computational cell (GH-FS-001); see **Normative reference — Biologit cell on `main`** at the end of this page for the drug-discovery / MD / WASM scope.*

---

## 1. What This Is

The **GaiaFTCL Health Mac Cell** is the second primary product cell in the GaiaFTCL ecosystem. While the Fusion cell focuses on plasma physics and magnetic confinement, the Health cell implements a **"human-as-substrate" architecture**.

In this architecture, the entire mechanism-design game and its invariants are played on human biology. The substrate processes continuous, high-throughput biological telemetry (ECG, EEG, etc.) and enforces epistemic integrity boundaries (PHI, ICNIRP) at the edge.

Like the Fusion cell, it operates under **GAMP 5 Category 5 | EU Annex 11 | FDA 21 CFR Part 11** quality frameworks. Every state transition has a signed receipt, and every decision is quorum-validated across the 9-cell mesh.

---

## 2. Architecture: The Human Substrate

The MacHealth cell is designed to interface with the **S4 Epistemic Edge**—the physical RF hardware and sensor arrays that measure biological states.

### The S4 Epistemic Edge

- **Hardware Integration:** Interfaces with physical sensors via high-throughput, low-latency ZeroMQ (ZMQ) PUB/SUB multipart frame wire formats.
- **WASM Constitutional Bridge:** The core logic (`gaia_health_substrate.wasm`) processes data streams, enforces invariants, and is completely blind to whether the data comes from physical hardware or a virtualized SIL validation loop.
- **Anti-Spoofing:** All ingested signals must contain a 128-bit nonce-derived amplitude modulation to prevent replay attacks or data spoofing.

---

## 3. UUM-8D Framework & Epistemic Tagging

The Health cell utilizes the same M⁸ = S⁴ × C⁴ manifold as the Fusion cell, but applies it to biological states:

- **(M) Measured:** Raw telemetry directly from the S4 edge (e.g., ECG microvolts).
- **(T) Transformed:** Filtered or DSP-processed signals.
- **(I) Inferred:** Diagnostic conclusions drawn from the data (e.g., arrhythmia detected).
- **(A) Assumed:** Baseline biological constants.
- **(M_SIL) Measured SIL:** Data validated against the Mock S4 edge during GAMP 5 Category 5 Software-in-the-Loop validation.

All telemetry is strictly bound to the universal contract defined in `config/schemas/telemetry.schema.json`.

*Cross-reference:* the **Biologit** computational pipeline (PDB → MD → Metal) uses **M / I / A** only on rendered outputs per **GH-FS-001** — see [State-Machine](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/State-Machine.md). The **T** / **M_SIL** labels above are part of this **telemetry / SIL** story, not extra epistemic states inside the Biologit renderer.

---

## 4. GAMP 5 Category 5 SIL Validation

Under GAMP 5 Category 5, executing a fully virtualized **Software-in-the-Loop (SIL)** validation phase is a mandatory prerequisite before physical hardware integration. It is unsafe and illegal to test edge-case safety interlocks (like triggering a `CONSTITUTIONAL_ALARM` for an ICNIRP boundary breach) on live humans or physical RF amplifiers hooked to live antennas.

### The Mock S4 Epistemic Edge

During validation, the physical edge is replaced by a **Mock S4 Epistemic Edge** running in a Linux VM.

- **GNU Radio & ZeroMQ:** Generates synthetic biological signals with 60 Hz noise, AWGN, and the required 128-bit nonce.
- **Strict Acceptance Envelope:** Validates WASM TX parameters against tight tolerances (Freq ±0.1Hz, Phase ±5°).
- **Closed-Loop Simulator:** Models realistic phase-acquisition latency (≥ 20s for 0.05 Hz) and edge-case traps (collisions, clock drift, Nyquist aliasing).

*Note: The Zero-Simulation Rule dictates that SIL virtualization is strictly scoped to the RF edge only. All other substrate behaviors (mesh quorum, NATS, etc.) must use real services.*

---

## 5. Active protocols & scenario suites (mechanism design)

The Health cell implements mechanism-design protocols as **scenario suites** (historically also called “games” in GAMP narrative) to structure validation. Those suites are narrated as test case studies in the GAMP 5 report.

**Canonical SIL V2 scenario contracts (seven clinical scenarios, machine-readable YAML + receipt schema):**  
[Scenarios_Physics_Frequencies_Assertions.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/Scenarios_Physics_Frequencies_Assertions.md) in the main `gaiaFTCL` repository.

**IQ / OQ / PQ map for those seven scenario suites:** see **§11** below (generalized population = cohort envelopes and refusal semantics, not a single named patient).

### Owl identity & consent (matches code — not a separate “OWL spec file”)

Shipped behavior is in **Rust + WASM**, not in a wiki-only protocol document:

- **Identity:** `moor_owl(pubkey_hex)` in the GaiaHealth / Biologit state machine accepts **only** a compressed **secp256k1** public key (`02`/`03…` hex); names, email, and short strings are **rejected** (zero‑PII mandate).
- **Transitions:** **`ConsentGate`** and related guards enforce consent withdrawal / re‑mooring per `cells/health` state machine.
- **WASM (FR-004 C-6):** `consent_validity_check` validates key shape and consent **freshness vs** wall‑clock (see [`wasm_constitutional`](https://github.com/gaiaftcl-sudo/gaiaFTCL/tree/main/cells/health/wasm_constitutional) and trace table in **[reviewer brief — C-6](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/REVIEWER_BRIEF.md)**).
- **GAMP evidence:** `MacHealthTests` embeds **`game_id: "OWL_PROTOCOL"`** in the **games narrative JSON receipt** — an **evidence artifact name**, not a second source of truth beside the code above.

### Cross-domain narrative fixtures (GAMP JSON)

The same receipt may list **Earth Substrate Ingestor** and **VIE-v2 Vortex** as named rows for **multi-domain** storytelling and HTML evidence — behavior and thresholds for Health SIL remain defined by **`ClinicalScenario`**, [`Scenarios_Physics_Frequencies_Assertions.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/Scenarios_Physics_Frequencies_Assertions.md), and Swift tests under `cells/fusion/macos/MacHealth/Tests/SILV2/`.

### Obligate coupling / nanotube analogy **[I] only**

Pedagogical cross-domain metaphor (biology / materials transport) — **[`docs/OBLIGATE_COUPLING_BIOPHYSICS_ANALOGY.md`](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/docs/OBLIGATE_COUPLING_BIOPHYSICS_ANALOGY.md)**. **Non‑normative:** there is **no** `nanotube` / obligate WASM export in `cells/`; do not treat this as an executable Health invariant.

---

## 6. Mac qualification: Swift OQ and the broader GAMP posture

To prevent kernel VFS collisions and adhere to the **Kernel Deadlock Protocol**, **on-Mac** qualification workflows for the Health **SIL** surface are implemented as **Swift** executables (e.g., `SILOQRunner`), favoring type-safe, headless runs for ZMQ wire formats, telemetry schemas, and games narrative reports.

**Update (Biologit cell on `main`):** the **authoritative** GaiaHealth **Biologit** GAMP pipeline is **not** Swift-only. It includes `bash` + `python3` + `cargo test` via **`cells/health/scripts/health_cell_gamp5_validate.sh`** (wiki lint, Qualification Catalog check, OWL-NUTRITION, peptide / LIGAND-CLASS evidence, full health workspace tests). **[Swift TestRobit](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/Swift-TestRobit.md)** remains the **OQ** harness for FFI + WASM contract tests against the Biologit stack.

---

## 7. Constitutional Constraints (Health Specific)

While sharing the 10 core invariants, the Health cell heavily emphasizes:

- **C-005 Biological Floor:** No harm to biological systems. The substrate will autonomously enter the `REFUSED` state if an ICNIRP boundary breach is imminent.
- **PHI Boundaries & Federated Consent:** Strict cryptographic separation of Protected Health Information.

---

## 8. Quick Links (wiki navigation)

- **[Health Operator Guide](Health-Operator-Guide)** — ZMQ wire formats, telemetry schemas, and hardware integration.
- **[MacHealth SIL Validation](MacHealth-SIL-Validation)** — Deep dive into the GNU Radio Mock S4 Edge and Swift SIL OQ.
- **[GAMP5 Validation Results](GAMP5-Validation-Results)** — View the latest HTML evidence reports and Games Narratives.
- **[IQ — Installation Qualification](IQ-Installation-Qualification)** | **[OQ — Operational Qualification](OQ-Operational-Qualification)** | **[PQ — Performance Qualification](PQ-Performance-Qualification)** — Qualification ladder for the Mac cell.
- **SIL V2 contracts (repo):** [Scenarios_Physics_Frequencies_Assertions.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/Scenarios_Physics_Frequencies_Assertions.md)

---

## 9. Pedagogical narrative — M_bio → ω_kine (frequency-domain story)

> **Scope guard:** For **peptide / small-molecule MD / Bioligit** product qualification, **[PEPTIDE_INTEGRATION_SPEC.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/PEPTIDE_INTEGRATION_SPEC.md)** defines **ligand_class** and the computational CURE path. The **M_bio → ω_kine** material below is **pedagogical / research narrative** for frequency-domain and SIL scenario storytelling — **not** a substitute for WASM gates or GH-FS-001 scope.

This section condenses the UUM 8D narrative: a shift from legacy **molecular** payloads (**M_bio**) to **kinematic** frequency protocols (**ω_kine**), aligned with the operator story in the computational-stack brief for structurally driven disease states. **Notation:** **M_bio** = molecular / mass-based track; **ω_kine** = kinematic frequency overriding track; **f_res** / **f₀** = native resonant frequency of the asserted pathological structure (see [Scenarios](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/Scenarios_Physics_Frequencies_Assertions.md) for scenario-specific numbers).

### 9.1 Executive paradigm

Historically, targeted tracks used a physical **M_bio** payload (chemical dampener) against malignant substrate. Delivery friction, tissue permeability, and rapid surface adaptation limited that approach. The current architecture transitions to **ω_kine**: chromosomal routing errors are treated as **aberrant mechanical and electromagnetic oscillators** to be addressed via physics—mapping **f_res** of the corrupted chromatin structure and synthesizing a **destructive-interference** tensor wave to disrupt the specific transcription loop, rather than relying on a static chemical lock.

![Paradigm shift: M_bio to ω_kine](images/health/health_paradigm_m_bio_omega_kine.png)

### 9.2 Topological routing errors and aberrant oscillators

Healthy rhythms are regulated by coupled feedback loops. Structural rearrangements (inversions, translocations, enhancer hijacking) break that architecture. In UUM 8D terms, these are **topological routing errors**: an aberrant, self-sustaining loop that continuously drives pathogenic signaling. Compromising the **spatial integrity** of that loop can halt pathological transcription without changing DNA sequence—hence the emphasis on **structural resonance** rather than receptor docking alone.

![Topological routing error: aberrant loop](images/health/health_topological_routing_loop.png)

### 9.3 Legacy M_bio limits

Under the legacy **M_bio** track, the OWL witness layer monitored **chemical kinematics** (e.g., binding affinity) to confirm target lock. **Organic friction** (delivery, degradation, barriers) and **substrate adaptation** (altered surface geometry) undermined durable docking. **ω_kine** bypasses pure port-locking by engaging the **mechanical** structure of the aberrant oscillator.

### 9.4 ω_kine alignment: isolation, anti-wave, OWL recalibration

- **Pathological harmonic:** From mapped 3D chromatin geometry, the stack derives **f_res** as a fingerprint of the routing error.
- **Anti-wave:** A phase-conjugate payload (**~180°** out of phase with the native resonance) is shaped for **destructive interference** at the aberrant complex; tissue attenuation and **localized refraction** (see §9.5) must be folded into phase and amplitude.
- **OWL gating:** (1) **Baseline** — background noise and proliferation context; (2) **Threshold** — collapse of pathological coupling (truth correlation per policy); (3) **Abort** — if telemetry drifts toward **healthy** resonance bands, the universal envelope **cuts the feed**.

![Destructive interference at f_res (~180°)](images/health/health_destructive_interference_180.png)

![OWL baseline, threshold, abort](images/health/health_owl_baseline_threshold_abort.png)

### 9.5 Refractive distortion and thermodynamic saturation

- **RI:** Soft tissue presents a broad **refractive index** range; **normal vs malignant** cells can differ in **n** (and thus **ñ = n + iκ**), causing **wavefront** error if uncorrected. Shaders and wavefront correction must compensate so destructive interference does not become constructive at the nucleus.
- **Heat:** High-frequency delivery converts to **thermal** load. Cumulative **Arrhenius-style** damage integrals (**Ω**) bound healthy-tissue exposure; dose must **throttle** before **Ω** breaches policy on surrounding tissue (see **§10** and the shared Arrhenius model in the Scenarios doc §9).

![RI boundary: normal vs malignant (ñ)](images/health/health_ri_boundary_normal_malignant.png)

![Arrhenius Ω throttle on healthy tissue](images/health/health_arrhenius_omega_throttle.png)

### 9.6 Dynamic baseline: pilot-wave ping

Static baselines are insufficient when lipid/water ratio, perfusion, and cell position shift. The resolved position is: **dynamic** mapping in the Mac cell—e.g., a **low-energy pilot** (“ping”) and backscatter/phase readback to **recompute** trajectory and phase of the primary **f_res** payload immediately before emission.

![Pilot ping and dynamic baseline](images/health/health_pilot_ping_dynamic_baseline.png)

### 9.7 Language games (ingestion and projection)

- **Ingestion:** Simultaneous **chemical** vocabulary (metabolites, surface proteins) and **kinematic** vocabulary (localized **ñ**, lipid/water, background harmonics). The cell must separate **signal** (e.g., **f_res** of the aberrant loop) from **noise** (respiration, thermal background).
- **Projection:** The “speech act” back to the substrate may remain **M_bio** where delivery is still viable, or switch to **ω_kine** where friction or geometry demands—always within **OWL** and **envelope** constraints.

![Language games: ingestion and projection](images/health/health_language_games_ingestion_projection.png)

---

## 10. SIL V2 scenario contracts and automated assertions

**Canonical machine-readable spec (all seven scenarios + §0 cross-rails + receipt schema):**  
[Scenarios_Physics_Frequencies_Assertions.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/Scenarios_Physics_Frequencies_Assertions.md)

**Swift unit contracts:** `cells/fusion/macos/MacHealth/Tests/SILV2/` — XCTest validates §0 cross-rails, §10 receipt blocks, and per-scenario thresholds (`validation_tier: SIL_protocol_contract`).

### 10.1 §0 cross-cutting rails (summary)

Every scenario inherits:

| Rail | Requirement (failure → REFUSED where stated) |
|------|-----------------------------------------------|
| Provenance | `provenance_tag == "M_SIL"` during SIL; no `"M"` leak |
| Nonce | ρ ≥ 0.95, RMSE/peak ≤ 0.10 over t ∈ [60 s, 300 s] |
| Filter | Amplitude ≤ 5 %, phase ≤ 10 °, 60 Hz rejection > 40 dB (t ≥ 60 s) |
| TX envelope | Freq ±0.1 Hz, phase ±5°, duty ±1 %, amplitude ±2 %, latency p99 ≤ 500 ms |
| Nyquist | `sampling_rate_hz > 2 × f_max_asserted`; THz paths need declared sampler or heterodyne |
| Arrhenius | **Ω_healthy** bounded; throttle before saturation |
| RI lock | **ñ** vs **ñ_target** before destructive payload |
| Phase lock | 180° ± 5° vs measured resonance (latched window) |
| Controls | Listed look-alikes must **REFUSE**; all-clean runs flagged **suspicious_clean** |
| Receipt | §10 schema mandatory |

### 10.2 inv(3) AML (illustrative)

- **Biology:** Enhancer hijack / **EVI1/MECOM** loop; blast **n** elevated vs normal blood cells (see spec for **n = 1.390** vs **1.376**).
- **Automated asserts (names):** `ri_lock_leukemic`, `ri_discrimination_vs_normal`, `evi1_loop_resonance_detection`, `destructive_interference_phase_lock`, `wavefront_ri_correction`, `arrhenius_guard`, plus refusal reasons such as `ri_lock_not_acquired`, `phase_lock_out_of_spec`, `arrhenius_saturation_breached`.

Full YAML, refusal tables, and **§8 cross-scenario quick reference** are **only** in the linked Scenarios file—do not treat the wiki as the numeric source of truth.

---

## 11. Seven scenario suites — IQ / OQ / PQ map (generalized population)

**Generalized population** here means **cohort-level protocol**: declared envelopes, control discrimination, and **M_SIL** provenance—not a claim about a single identifiable patient. Each row matches **`ClinicalScenario.rawValue`** in Swift (`Tests/SILV2/ScenarioContractValidation.swift`) and the **`scenario:`** key in [Scenarios_Physics_Frequencies_Assertions.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/Scenarios_Physics_Frequencies_Assertions.md). The same **IQ → OQ → PQ** ladder applies to all seven.

### 11.1 Named suites (one per scenario)

| # | Scenario ID (code) | Disease class (Scenarios §) | Suite name (mechanism-design) | Focus |
|---|--------------------|-----------------------------|---------------------------------|-------|
| 1 | `inv3_aml` | inv(3) AML | **TopologicalRoutingBreak** | EVI1/MECOM loop, RI discrimination, **f₀** / destructive-interference lock |
| 2 | `parkinsons_synuclein_thz` | Parkinson’s disease | **BasalGangliaOscillatorLock** | α-synuclein THz band; abort if sub-10 MHz claims fibril engagement |
| 3 | `msl_tnbc` | MSL TNBC | **MesenchymalMotilityEnvelope** | Motility, geometry, tensor alignment; refuse look-alikes |
| 4 | `breast_cancer_general_thz` | Breast cancer (general) | **MammaryTissueDiscrimination** | THz contrast, healthy-voxel Arrhenius projection |
| 5 | `colon_cancer_thz` | Colon cancer | **ColonicCompartmentBoundary** | THz band, cell-line ε profile, RI latch |
| 6 | `lung_cancer_thz_thermal` | Lung cancer | **PulmonaryWavefrontGuidance** | ε ratio, perfusion, throttle latency |
| 7 | `skin_cancer_bcc_melanoma` | Skin (BCC + melanoma) | **DermalPenetrationGuard** | **f₀** cancer vs healthy margin, biomarker peaks, ICNIRP / thermal caps |

### 11.2 IQ — Installation Qualification

Per scenario suite / disease class: substrate + **Mock S4** + schemas + **plant_config** (sampling, channels, **Eₐ** overrides per tissue); identity, consent, and wallet hooks as in [IQ — Installation Qualification](IQ-Installation-Qualification). **Nyquist / heterodyne** declarations are **IQ** failures if missing for the asserted **f_max**.

### 11.3 OQ — Operational Qualification

**SIL V2 automated contracts** pass: Swift tests + scenario YAML; **generalized population** implies **correct refusals** on wrong RI, wrong cohort, or **control_discrimination** paths—not only happy-path passes. Receipt **§10** blocks must be present for ingest.

### 11.4 PQ — Performance Qualification

Physics invariants under declared stress: live **Arrhenius Ω** throttle, **RI** and **phase** locks, **TX/filter** envelopes, and complete receipts; ties to **ω_kine** narrative only where the scenario asserts THz / acoustic / EM channels.

### 11.5 Disclaimer

Per Scenarios **§11**: this material is **substrate-correctness and validation** language, not a clinical protocol or treatment claim. Numbers are **bars for automated test contracts**; **IQ** must calibrate plant-config defaults before any **OQ** run reports `passed: true`.

---

# Normative reference — Biologit cell on `main`

*Short mirror of the product definition and harnesses for the **computational** GaiaHealth cell. Authoritative: **[FUNCTIONAL_SPECIFICATION.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/FUNCTIONAL_SPECIFICATION.md)**.*

## N.1 What this is (two surfaces)

### N.1.A — GaiaHealth **Biologit** cell (`cells/health/`) — **GH-FS-001**

- **GAMP 5 Category 5** research instrument: **computational drug discovery** — PDB ingest (PHI-scrubbed), molecular dynamics, Metal rendering, **11-state** lifecycle, **CURE** emission when constitutional gates pass.
- **Epistemic spine:** **M / I / A** only (Measured, Inferred, Assumed) on computational outputs — see [State-Machine](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/State-Machine.md).
- **Ligand scope:** small molecule **or** **peptide** as **`ligand_class`** on `BioligitPrimitive` — [PEPTIDE_INTEGRATION_SPEC.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/PEPTIDE_INTEGRATION_SPEC.md). Peptides are a **ligand class inside the MD pipeline**, not a separate “M_bio / ω-kine” kinematic track (that language is **out of scope** for normative peptide scope; see **Peptide / LIGAND-CLASS** section above and §9 narrative scope guard).
- **WASM:** **eight core** constitutional exports + **two auxiliary** PGx-related exports — [WASM-Constitutional-Substrate](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/WASM-Constitutional-Substrate.md), `wasm_constitutional/src/lib.rs`.

### N.1.B — **MacHealth** SIL harness (`cells/fusion/macos/MacHealth/`)

A **separate** Swift package for **RF / telemetry / SIL V2** scenario contracts, ZMQ wire formats, and **M_SIL** provenance in **validation** narratives. SIL scenario YAML and tests: **[Scenarios_Physics_Frequencies_Assertions.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/Scenarios_Physics_Frequencies_Assertions.md)**, `cells/fusion/macos/MacHealth/Tests/SILV2/`.

Do **not** conflate Biologit **CURE gates (C-1…C-7)** with the **seven SIL clinical scenario IDs** — see **Terminology** below.

## N.2 Architecture — Biologit cell (`cells/health/`)

| Layer | Location | Role |
|-------|----------|------|
| MD + state machine + FFI | [`biologit_md_engine`](https://github.com/gaiaftcl-sudo/gaiaFTCL/tree/main/cells/health/biologit_md_engine) | `BioState`, transitions, Owl mooring |
| PDB / `BioligitPrimitive` | [`biologit_usd_parser`](https://github.com/gaiaftcl-sudo/gaiaFTCL/tree/main/cells/health/biologit_usd_parser) | 96-byte ABI, `ligand_class` @ offset 88 |
| WASM | [`wasm_constitutional`](https://github.com/gaiaftcl-sudo/gaiaFTCL/tree/main/cells/health/wasm_constitutional) | Package **`gaia-health-substrate`**, WKWebView |
| Metal | [`gaia-health-renderer`](https://github.com/gaiaftcl-sudo/gaiaFTCL/tree/main/cells/health/gaia-health-renderer) | M/I/A epistemic alpha |
| OQ harness | [`swift_testrobit`](https://github.com/gaiaftcl-sudo/gaiaFTCL/tree/main/cells/health/swift_testrobit) | **58** Swift tests (`TR-S1`…`TR-S5`) |

## N.3 GAMP 5 validation (repeatable)

| Artifact | Path / command |
|----------|----------------|
| Full Health GAMP check | `bash cells/health/scripts/health_cell_gamp5_validate.sh` |
| Peptide / LIGAND-CLASS evidence | `bash cells/health/scripts/peptide_ligand_class_gamp5_evidence.sh` |
| Rust unit tests (baseline **81**) | `cd cells/health && cargo test --workspace` |
| Swift OQ harness | `cd cells/health/swift_testrobit && swift build && swift run SwiftTestRobit` |

Receipts (JSON) under `cells/health/docs/invariants/.../evidence/` — see [GAMP5-Lifecycle](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/GAMP5-Lifecycle.md).

## N.4 Owl identity, consent, WASM (matches code)

- **`moor_owl`**: compressed secp256k1 pubkey hex (**66** chars, `02`/`03`); names and emails **rejected** — zero-PII.
- **`consent_validity_check`**: same key rules + **5-minute** window — `wasm_constitutional/src/lib.rs`.
- **CURE gate C-6** and full traceability: [REVIEWER_BRIEF.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/REVIEWER_BRIEF.md).

## N.5 Constitutional constraints (Health / Biologit)

Mesh-wide Fusion **C-001…C-010** live in the Fusion product. GaiaHealth **CURE** conditions **C-1…C-7** are defined in **GH-FS-001** and [REVIEWER_BRIEF.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/REVIEWER_BRIEF.md). **ICNIRP / live biological harm** thresholds belong to **SIL / hardware** narratives (MacHealth), not to the core Biologit **research-instrument** scope statement in §1 of GH-FS-001.

## N.6 Quick links (repo blobs — Biologit)

| Doc | URL |
|-----|-----|
| Functional Specification (GH-FS-001) | [blob](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/FUNCTIONAL_SPECIFICATION.md) |
| Design Specification | [blob](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/DESIGN_SPECIFICATION.md) |
| State machine (wiki) | [State-Machine.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/State-Machine.md) |
| WASM substrate (wiki) | [WASM-Constitutional-Substrate.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/WASM-Constitutional-Substrate.md) |
| IQ / OQ / PQ (wiki) | [IQ](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/IQ-Installation-Qualification.md) · [OQ](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/OQ-Operational-Qualification.md) · [PQ](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/wiki/PQ-Performance-Qualification.md) |
| SIL scenarios (repo) | [Scenarios_Physics_Frequencies_Assertions.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/Scenarios_Physics_Frequencies_Assertions.md) |
| S4↔C4 Communion (design target) | [S4_C4_COMMUNION_UI_SPEC.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/S4_C4_COMMUNION_UI_SPEC.md) |
| Peptide integration (HEALTH-PEPTIDE-SPEC-V1) | [PEPTIDE_INTEGRATION_SPEC.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/PEPTIDE_INTEGRATION_SPEC.md) |
| LIGAND-CLASS invariants (INV-HEALTH-LC-01..06) | [LIGAND-CLASS/README.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/invariants/LIGAND-CLASS/README.md) |
| Peptide OQ / PQ protocols | [OQ_PEPTIDE_V1.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/qualification/OQ_PEPTIDE_V1.md) · [PQ_PEPTIDE_V1.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/qualification/PQ_PEPTIDE_V1.md) |
| Peptide CCR | [CCR-HEALTH-PEPTIDE-V1.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/ccr/CCR-HEALTH-PEPTIDE-V1.md) |
| PGx policy (peptide / hashed features) | [PGX_POLICY.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/invariants/LIGAND-CLASS/PGX_POLICY.md) |

---

## Terminology — CURE gates vs SIL scenarios vs pedagogy

| Name | Meaning | Authoritative location |
|------|---------|------------------------|
| **C-1…C-7** | Boolean gates for **CURE** emission (WASM, consent, epistemic, selectivity, …) | [REVIEWER_BRIEF.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/REVIEWER_BRIEF.md), GH-FS-001 |
| **Seven SIL scenario IDs** | Cohort-level **validation suites** (`inv3_aml`, …) | This page §11 + MacHealth `ClinicalScenario` |
| **M_bio → ω_kine** (§9 above) | Pedagogical / scenario narrative | **Not** peptide MD scope; see [PEPTIDE_INTEGRATION_SPEC.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/PEPTIDE_INTEGRATION_SPEC.md) |
| **HEALTH-PEPTIDE-SPEC-V1 / LIGAND-CLASS** | Peptide as **`ligand_class`** on MD+WASM; INV-HEALTH-LC-01..06; GAMP scripts | [Qualification-Catalog §4.6](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/wiki/Qualification-Catalog.md#46-ligand-class--peptide-therapy-integration); **Peptide / LIGAND-CLASS** section above |
| **Cross-domain obligate analogy** | Pedagogical **[I]** only | [OBLIGATE_COUPLING_BIOPHYSICS_ANALOGY.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/docs/OBLIGATE_COUPLING_BIOPHYSICS_ANALOGY.md) — no WASM export |

**S4↔C4 Communion** (product narrative): see [S4_C4_COMMUNION_UI_SPEC.md](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/S4_C4_COMMUNION_UI_SPEC.md) (and extended doc if present on `main`).

---

*Enumeration tracks `main` where cited; specs linked above win on conflict.*
