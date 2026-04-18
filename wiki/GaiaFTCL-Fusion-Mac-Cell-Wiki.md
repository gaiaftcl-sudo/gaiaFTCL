# GaiaFTCL Fusion Mac Cell — Wiki

## The sovereign plasma control substrate and its cross-domain architecture

**FortressAI Research Institute | Norwich, Connecticut**
**Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie**

---

> GaiaFTCL is not a dashboard. It is not a monitoring tool. It is a sovereign, constitutionally-governed distributed substrate that continuously measures, validates, and closes the numerical gap between the physics of confined plasma and the formal certainty required to deliver controlled fusion energy to the grid. Every architectural decision — from the Klein bottle mesh topology to the 76-byte `vQbitPrimitive` ABI to the nine canonical plant wireframes — flows from a single invariant: **entropy without value is refused.**

---

## Table of Contents

1. [What This Is](#1-what-this-is)
2. [Architecture](#2-architecture)
3. [UUM-8D Framework](#3-uum-8d-framework)
4. [Fusion Domain](#4-fusion-domain)
5. [275M EUR Validation Sprint](#5-275m-eur-validation-sprint)
6. [Mac App — The Human Interface](#6-mac-app--the-human-interface)
7. [Cross-Domain Architecture](#7-cross-domain-architecture)
8. [Knowledge Graph](#8-knowledge-graph)
9. [Constitutional Constraints](#9-constitutional-constraints)
10. [Glossary](#10-glossary)

---

## 1. What This Is

GaiaFTCL is a sovereign distributed computing substrate purpose-built for one mission: prove that controlled fusion energy is numerically achievable and constitutionally governable. It does this by operating a nine-cell mesh of sovereign compute nodes that each run a full copy of the Universal Uncertainty Model in eight dimensions — the UUM-8D — and continuously exchange quorum-validated vQbit measurements across nine canonical fusion plant configurations.

The substrate is not a research prototype. It is a production-grade, GxP-validated, formally qualified platform operating under GAMP 5 | EU Annex 11 | FDA 21 CFR Part 11 quality frameworks. Its evidence directory contains signed IQ, OQ, and PQ receipts for every state transition. Every value it emits carries an epistemic tag — M (Measured), T (Tested), I (Inferred), or A (Assumed) — and that tag is immutable for the lifetime of the run.

The Mac Cell is the human-facing sovereign node: an Apple Silicon M-chip workstation running a native Metal renderer that visualises the live plasma state of all nine canonical fusion plant kinds simultaneously. The app runs entirely on-device. Shader compilation, vertex buffer management, and telemetry ingestion happen in unified memory with zero GPU copy overhead. The renderer maintains a separate `MTLRenderPipelineState` and typed vertex buffer for each of the nine plant kinds.

This document is the definitive cross-domain reference for the entire system. It covers the nine-cell mesh, the UUM-8D mathematical structure, all nine fusion plant configurations, the 275M EUR international validation sprint, the Mac app architecture, and the six cross-domain families — autonomous vehicles, drone swarms, air traffic control, maritime routing, biomedical diagnosis, and municipal governance — that share the same constitutional substrate.

---

## 2. Architecture

### 2.1 The Nine-Cell Sovereign Mesh

The mesh consists of nine sovereign compute nodes. Each node holds a full copy of the GaiaFTCL state machine, the UUM-8D engine, and the complete knowledge graph replica. No node is a leader. Consensus is quorum-validated: **five of nine nodes must agree** before any state transition is committed.

| Zone | Provider | Nodes | Role |
| --- | --- | --- | --- |
| Helsinki | Hetzner Cloud | 5 | Primary quorum zone |
| Nuremberg | Netcup | 4 | Secondary quorum zone |

The mesh topology is a **Klein bottle invariant**: the graph of cell-to-cell connections has no boundary. There is no entry point and no exit point from the perspective of a vQbit packet. A measurement emitted from any cell propagates to all other cells through the mesh and returns to its origin transformed by the quorum — without ever passing through a privileged gateway node.

**Quorum rules:**

- A CALORIE state (value produced) requires agreement from ≥ 5 cells.
- A CURE state (deficit healed) requires agreement from ≥ 5 cells.
- A REFUSED state may be declared by any single cell; it propagates immediately and does not require quorum.
- A cell that cannot reach quorum within the configured timeout enters REFUSED autonomously.

The sovereign identity of each cell is established during IQ (Installation Qualification) and is derived from the system UUID, entropy, and a timestamp via SHA-256 and secp256k1. No two cells may share a cell ID. The cell ID is committed to `evidence/iq_receipt.json` and is never regenerated during normal operation.

### 2.2 The Mac Cell

The Mac Cell is the sovereign human interface node. It is architecturally identical to a Hetzner or Netcup cell in its constitutional commitments — it runs the same UUM-8D engine, the same quorum client, and the same vQbit measurement pipeline — but it adds a Metal renderer and a WKWebView human interface layer.

**Hardware requirements (non-negotiable):**

| Requirement | Specification | Rationale |
| --- | --- | --- |
| CPU | Apple Silicon M-chip (any generation) | Unified memory architecture required |
| Memory model | StorageModeShared | Zero-copy CPU/GPU vertex buffer access |
| GPU | Apple Metal (integrated, M-chip) | MSL shader pipeline |
| OS | macOS 13 Ventura or later | Metal API feature parity |
| Rust | ≥ 1.85 stable | `std::mem::offset_of!` required for GxP ABI tests |
| Xcode CLT | Current | MSL compilation from embedded source |

There is no Intel path. There is no NVIDIA path. There is no AMD path. The unified memory architecture of Apple Silicon is a load-bearing architectural constraint, not a preference. The vertex buffers for all nine plant wireframes are allocated with `StorageModeShared`, which means the CPU writes geometry and the GPU reads it from the same physical address without any copy. This is not an optimisation — it is the reason the renderer can hot-swap between all nine plant kinds in a single frame budget.

### 2.3 Infrastructure Stack

```
┌─────────────────────────────────────────────────────────────┐
│  HUMAN INTERFACE LAYER                                       │
│  WKWebView (HTML/CSS/JS dashboard) + Swift AppDelegate       │
├─────────────────────────────────────────────────────────────┤
│  RENDERER LAYER                                              │
│  Metal MTLRenderPipelineState × 9 plant kinds               │
│  GaiaVertex (28 bytes) | Uniforms (64 bytes)                │
│  vQbitPrimitive #[repr(C)] (76 bytes)                       │
├─────────────────────────────────────────────────────────────┤
│  UUM-8D ENGINE                                               │
│  M⁸ = S⁴ × C⁴   vQbit measurement   Epistemic tagger       │
├─────────────────────────────────────────────────────────────┤
│  SOVEREIGNTY LAYER                                           │
│  Quorum client (5-of-9)   τ synchroniser   Cell identity    │
├─────────────────────────────────────────────────────────────┤
│  MESSAGING LAYER                                             │
│  NATS JetStream   Subject prefix: gaiaftcl.*                │
├─────────────────────────────────────────────────────────────┤
│  KNOWLEDGE LAYER                                             │
│  ArangoDB   Named graph: gaiaftcl_knowledge_graph           │
│  7 edge collections   VIE-v2 ingestion engine               │
└─────────────────────────────────────────────────────────────┘
```

### 2.4 Constitutional Rules

These rules are hard-coded in the sovereignty layer and cannot be overridden by any configuration, user action, or external signal.

1. **No NaN, No Infinity.** Any NaN or Inf in I_p, B_T, or n_e is an unconditional critical failure. The cell enters REFUSED and halts. It does not warn. It does not degrade. It stops.

2. **No negative telemetry.** I_p, B_T, and n_e must all be ≥ 0.0. A negative physical quantity in the plasma state is a sensor fault or a computation error, not a physics result.

3. **No zero-vertex geometry.** A plant wireframe that produces zero vertices is a render failure. The cell enters REFUSED. It does not render a blank frame.

4. **Epistemic tags are immutable.** M/T/I/A tags are set at measurement time and cannot change during a render frame or across a plant swap. An M-tagged value cannot be downgraded to I or A without a Change Control Record.

5. **Quorum or REFUSED.** Every committed state transition requires quorum. A cell that cannot reach quorum enters REFUSED. It does not approximate.

6. **τ anchors all time.** All timestamped evidence is anchored to τ (Bitcoin block height), not wall-clock time. This is the sovereign time standard for the mesh.

---

## 3. UUM-8D Framework

### 3.1 The Eight-Dimensional State Space

The Universal Uncertainty Model in Eight Dimensions — UUM-8D — is the mathematical backbone of GaiaFTCL. Every measurement, every validation, every quorum decision is made in this space. The full state space is defined as:

**M⁸ = S⁴ × C⁴**

where:

- **S⁴ = Projection Space** — a four-dimensional manifold encoding what the system currently believes about the physical state of the plasma. The four dimensions are: plasma current projection, magnetic field projection, electron density projection, and temporal coherence.

- **C⁴ = Constraint Space** — a four-dimensional manifold encoding the formal obligations the system is under. The four dimensions are: physics constraint satisfaction, epistemic obligation (is this value M/T/I/A appropriate?), quorum obligation (do five cells agree?), and numerical closure obligation (has the residual crossed the threshold?).

A point in M⁸ is a complete description of a cell's state: what it believes, and what it is obligated to do about that belief. The vQbit measurement primitive is a compressed encoding of a trajectory in M⁸ — the path from the observer's prior belief to the system's current state.

### 3.2 The vQbit Measurement Primitive

The vQbit is the atomic unit of information in GaiaFTCL. Every sensor reading, every simulation output, every cross-cell quorum message is encoded as a vQbit before it enters the system.

A vQbit has two scalar components:

| Field | Physical meaning | Range |
| --- | --- | --- |
| `vqbit_entropy` | The entropy delta between the observer and the system — how much new information this measurement carries | [0.0, 1.0] |
| `vqbit_truth` | The truth threshold — the minimum confidence level required for this measurement to be accepted as evidence | [0.0, 1.0] |

These two fields are encoded in the `vQbitPrimitive` struct alongside the 4×4 transform matrix and the primitive ID. The full layout is documented in the [[vQbitPrimitive-ABI]] page. The critical invariant is that `vqbit_entropy` drives the red colour channel of the Metal renderer and `vqbit_truth` drives the green channel, making the epistemic state of every primitive directly visible in the 3D wireframe display.

The encoding rule is: **high entropy (approaching 1.0) means high information content — the measurement is far from what the system expected.** High truth (approaching 1.0) means high confidence. A measurement with high entropy and high truth is the most valuable signal in the system: something surprising that we are confident about.

### 3.3 The Three Terminal States

Every trajectory in M⁸ terminates in one of three states. There are no other outcomes.

| State | Name | Meaning | Colour in renderer |
| --- | --- | --- | --- |
| CALORIE | Value produced | The cell has produced a measurement that passes all constitutional constraints, has quorum, and advances the closure residual toward the threshold | Green |
| CURE | Deficit healed | The cell has identified and corrected a prior measurement error — an I-tagged value has been upgraded to T or M, or a bounds violation has been resolved | Blue |
| REFUSED | Entropy without value | The measurement failed a constitutional rule, quorum was not reached, or the physics constraints were violated. The cell halts this trajectory. | Red |

REFUSED is not an error state in the traditional sense. It is a constitutional guarantee. The system is declaring: "I will not produce a value I cannot stand behind." This is the most important output the system can give. A system that never REFUSED would be a system that was never honest.

### 3.4 Epistemic Classification in the UUM-8D

Every value that enters the S⁴ projection space carries an epistemic tag. The tag is not metadata — it is a first-class dimension of the state. A measurement with an I tag occupies a different region of C⁴ than the same numerical value with an M tag, because the constraint obligations are different.

| Tag | Name | What it means for UUM-8D | Colour |
| --- | --- | --- | --- |
| M | Measured | Derived from direct experimental measurement at an operating facility. The C⁴ physics constraint obligation is fully dischargeable. | Gold |
| T | Tested | Derived from validated simulation or laboratory test. The C⁴ obligation requires simulation provenance to be cited. | Silver |
| I | Inferred | Derived from physical scaling laws or extrapolation. The C⁴ obligation includes an uncertainty inflation factor. | Bronze |
| A | Assumed | Assumed from target design or theoretical prediction. The C⁴ obligation flags this value for first-measurement replacement. | Grey |

The practical consequence is this: a fusion plant configuration where all three telemetry channels (I_p, B_T, n_e) carry M tags is a configuration that has been operated at a real facility and has produced real data. A configuration where all three carry A tags is a configuration we believe to be physically possible but have not yet operated. The system governs both — but it reports the difference, always.

### 3.5 Numerical Closure

The central quantitative question of GaiaFTCL is: **how close are we to the physics required for net energy gain?** The answer is maintained as a running residual in every cell, updated on every quorum-committed measurement.

The numerical closure threshold is: **9.54 × 10⁻⁷**

When the residual across all active telemetry channels across all nine cells drops below this threshold, the system transitions to CALORIE for the closure event. This is the computational analogue of scientific confidence: not certainty, but a formally bounded, constitutionally-validated probability that the physics is closed.

### 3.6 Evolutionary analogy — obligate symbiosis (non-normative)

**Epistemic status:** **[I] Inferred analogy** — pedagogical bridge to microbiology / materials, not a fusion engineering requirement.

UUM-8D and cross-domain cells (including GaiaHealth) reuse the same constitutional substrate: quorum-validated closure, epistemic tags, and refusal when entropy has no computable value. A parallel drawn in-repo is **obligate coupling**: stable multi-species consortia (or material “wiring”) exchanging metabolites or signals through structurally constrained channels—conceptually similar to how S4 ingest, C4 invariants, and terminal emissions must chain evidence rather than assert free-floating claims.

Canonical write-up (citations, boundaries): [`docs/OBLIGATE_COUPLING_BIOPHYSICS_ANALOGY.md`](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/docs/OBLIGATE_COUPLING_BIOPHYSICS_ANALOGY.md).

---

## 4. Fusion Domain

### 4.1 The Nine Canonical Plant Kinds

GaiaFTCL recognises nine canonical fusion plant configurations. Each plant kind has a defined wireframe geometry, a set of telemetry bounds with epistemic classification, and a set of physics constraints that the constitutional layer enforces in real time. The full specification for each plant is in [[Plant-Catalogue]]. The summary table below gives the operating philosophy and key distinguishing parameters for each.

| # | Plant Kind | USDA Scope | Confinement Approach | I_p baseline (MA) | B_T baseline (T) | n_e baseline (m⁻³) |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Tokamak | `Tokamak` | Axisymmetric toroidal, external TF + PF coils | 0.85 | 0.52 | 3.5×10¹⁹ |
| 2 | Stellarator | `Stellarator` | 3D twisted torus, no plasma current | 0.00 | 2.50 | 2.0×10¹⁹ |
| 3 | Spherical Tokamak | `SphericalTokamak` | Low aspect ratio, compressed plasma sphere | 1.20 | 0.30 | 5.0×10¹⁹ |
| 4 | Field-Reversed Configuration | `FRC` | Linear device, self-organized compact torus | 0.10 | 0.00 | 1.0×10²¹ |
| 5 | Mirror | `Mirror` | Open magnetic mirror, end choke coils | 0.05 | 1.00 | 5.0×10¹⁸ |
| 6 | Spheromak | `Spheromak` | Self-organized compact torus, coaxial injector | 0.30 | 0.10 | 1.0×10²⁰ |
| 7 | Z-Pinch | `ZPinch` | Pure pinch, axial current, no external toroidal field | 2.00 | 0.00 | 1.0×10²² |
| 8 | Magneto-Inertial Fusion | `MIF` | Hybrid magnetic-inertial, Fibonacci-spaced plasma guns | 0.50 | 0.50 | 1.0×10²³ |
| 9 | Inertial Confinement Fusion | `Inertial` | Laser-driven implosion, hohlraum + geodesic shell | 0.00 | 0.00 | 1.0×10³¹ |

### 4.2 Physics Philosophy of Each Plant Kind

**Tokamak** operates at the highest state of experimental maturity. The NSTX-U baseline values are measured data (epistemic tag M for all three channels). The constitutional layer enforces two non-negotiable physics constraints: I_p > 0.5 MA for ohmic heating, and B_T > 0.4 T for confinement. Below either threshold, the cell enters REFUSED — not because the software is broken, but because a tokamak below these values is not a confined plasma.

**Stellarator** is the zero-current machine. I_p is constitutionally bounded at 0.05 MA maximum — any higher value indicates a configuration error, not physics. The high B_T requirement (1.5–3.5 T) compensates for the absence of plasma current. This is the cleanest confinement approach: no disruptions, no current-drive hardware, no need for the complex control loops that govern tokamak current.

**Spherical Tokamak** achieves higher I_p than a conventional tokamak at the same machine scale because the plasma is compressed into a tight sphere around a dense central solenoid. The low aspect ratio allows lower B_T than a conventional tokamak for the same plasma current — this is the fundamental engineering advantage.

**Field-Reversed Configuration** operates at densities an order of magnitude above all other magnetic confinement approaches. B_T ≈ 0 by definition — there is no toroidal field. The plasma is a self-organized compact torus. The n_e epistemic tag is I (Inferred) because direct density measurement at FRC operating conditions is technically demanding.

**Mirror** is an open-ended device. The open geometry means achievable density is lower than any closed-confinement approach. The high B_T requirement at the end choke coils creates the magnetic bottle — without it, the confinement zone does not form.

**Spheromak** is self-organized. The magnetic field geometry is maintained by the plasma current itself, not by external coils. B_T and n_e carry epistemic tags of I (Inferred) because direct measurement at spheromak scale is limited. The constitutional layer treats I-tagged values with appropriate uncertainty inflation.

**Z-Pinch** is the highest-current machine in the catalogue. I_p ranges from 0.5 to 20 MA — the widest current range of any plant. B_T ≈ 0 by definition (the confinement is produced by the azimuthal field from the axial current, not an external toroidal coil). The very high density (up to 10²³ m⁻³) is a direct consequence of pinch compression.

**Magneto-Inertial Fusion** combines both worlds. The Fibonacci gun placement — plasma guns positioned at Fibonacci lattice sites on an icosphere — is a controlled configuration item. Any change to the gun placement requires full PQ-CSE re-execution, because the symmetry of the implosion depends on the placement geometry. The n_e bounds carry epistemic tag A (Assumed), because we are targeting ignition-relevant densities that have not been achieved at scale.

**Inertial Confinement Fusion** operates in a regime entirely separate from all magnetic confinement approaches. I_p ≈ 0 and B_T ≈ 0 by definition — there are no magnetic coils, only laser beamlines arranged in a geodesic shell surrounding a hohlraum. The electron density at ignition (10³¹ m⁻³) is orders of magnitude above every other plant kind. The Metal renderer must normalise this value to [0.0, 1.0] without float overflow — this is PQ requirement PQ-PHY-006, a hard constitutional rule.

### 4.3 Telemetry Channels

All nine plant kinds report on the same three telemetry channels. The physical interpretation and epistemic maturity varies by plant, but the channel identities are universal.

| Channel | Physical quantity | Units | Metal colour channel | Role in UUM-8D |
| --- | --- | --- | --- | --- |
| I_p | Plasma current | MA (megaamperes) | Blue | S⁴ dimension 1 |
| B_T | Toroidal magnetic field | T (tesla) | Green | S⁴ dimension 2 |
| n_e | Electron density | m⁻³ | Red | S⁴ dimension 3 |

Note: in the Metal renderer, the colour channel mapping for the vQbit encoding is: `vqbit_entropy` → red, `vqbit_truth` → green, blue hardcoded to 0.5, alpha 1.0. The telemetry channel colour mapping above is for the physics display layer, which operates on top of the vQbit layer.

### 4.4 Control Loop Architecture

The fusion control loop in GaiaFTCL operates at three timescales simultaneously:

**Fast loop (sub-millisecond):** Raw telemetry ingestion, NaN/Inf check, bounds enforcement, REFUSED declaration. This loop runs in the Rust UUM-8D engine core. It has no network dependency — it operates on local sensor data and local constitutional rules.

**Medium loop (millisecond to second):** vQbit encoding, epistemic tagging, NATS JetStream publication, cross-cell quorum collection. This loop produces the measurements that the mesh votes on.

**Slow loop (second to minute):** Knowledge graph update, closure residual computation, PQ evidence collection, τ-timestamped state commitment. This loop produces the evidence that qualifies the system's state for regulatory acceptance.

The constitutional layer operates across all three loops. A REFUSED declaration at the fast loop propagates immediately to all three — it does not wait for the slow loop's τ-timestamp to be final.

### 4.5 Disruption Prediction

Disruption in magnetic confinement fusion is the sudden, uncontrolled loss of plasma confinement. It is the most dangerous operational event in tokamak-class devices. GaiaFTCL's disruption prediction module operates as a C⁴ obligation in the constraint space: when the physics constraint dimensions indicate that the plasma state is approaching a disruption boundary, the cell pre-emptively issues a REFUSED declaration and initiates a controlled shutdown sequence.

The disruption prediction boundary conditions are plant-specific:

- **Tokamak/SphericalTokamak:** Disruption risk rises sharply when I_p approaches the Greenwald limit (I_p / πa² where a is the minor radius) or when n_e approaches the upper bound.
- **Stellarator:** No disruption risk by design — there is no plasma current to disrupt.
- **FRC/Spheromak:** Configuration instability rather than disruption — the self-organized field geometry can decay. The constitutional layer monitors the rate of change of I_p as a proxy.
- **Z-Pinch:** Rayleigh-Taylor instability at the pinch boundary. The density gradient at the plasma-vacuum interface is monitored.
- **MIF/ICF:** Implosion asymmetry — the gun placement or laser energy imbalance can cause the implosion to deviate from spherical symmetry. The Fibonacci placement check is the key constitutional guard.

### 4.6 Numerical Closure and the Lawson Criterion

The Lawson criterion for fusion energy gain requires the triple product n_e × T_i × τ_E to exceed a threshold that depends on the fusion fuel. GaiaFTCL's numerical closure residual is a formally bounded approximation to the gap between the current measured state and the Lawson threshold, computed independently by each cell and validated by quorum.

The closure residual is computed as:

```
residual = ∫(Lawson_threshold - triple_product(t)) dt over the confinement window
```

When this integral drops below **9.54 × 10⁻⁷**, the cell declares CALORIE for the closure event. The threshold value is not arbitrary — it is derived from the propagated uncertainty of the M-tagged telemetry values in the reference plant configurations.

---

## 5. 275M EUR Validation Sprint

### 5.1 Overview

The 275M EUR international validation sprint is a coordinated, time-bounded effort across eleven sovereign research institutions to independently validate the GaiaFTCL constitutional substrate against real fusion experimental data. The sprint is not a grant programme. It is not a consortium. It is a formal qualification exercise: each team is assigned a validation track, executes the prescribed PQ protocols, and submits a signed evidence package. The evidence packages from all eleven teams are then reconciled by the constitutional layer to produce a mesh-wide CALORIE or REFUSED verdict.

The total budget allocation reflects the full cost of eleven independent experimental campaigns, data processing infrastructure, and GxP qualification support at each site.

### 5.2 The Eleven Validation Teams

| Team | Institution | Location | Primary validation track |
| --- | --- | --- | --- |
| Team 01 | MIT Plasma Science and Fusion Center | Cambridge, Massachusetts, USA | Tokamak I_p closure — PQ-PHY series |
| Team 02 | Max Planck Institute for Plasma Physics | Greifswald, Germany | Stellarator B_T characterisation — PQ-CSE series |
| Team 03 | Princeton Plasma Physics Laboratory | Princeton, New Jersey, USA | Spherical Tokamak disruption boundary — PQ-PHY + PQ-SAF |
| Team 04 | TAE Technologies | Foothill Ranch, California, USA | FRC density scaling — PQ-PHY series |
| Team 05 | Commonwealth Fusion Systems | Devens, Massachusetts, USA | HTS compact tokamak B_T calibration — PQ-PHY series |
| Team 06 | National Ignition Facility | Livermore, California, USA | ICF n_e normalisation — PQ-PHY-006 specifically |
| Team 07 | Korea Institute of Fusion Energy | Daejeon, South Korea | KSTAR steady-state epistemic upgrade M→T — PQ-PHY + IQ |
| Team 08 | EUROfusion JET/ITER consortium | Culham + Cadarache | Multi-plant cross-validation — PQ-QA series |
| Team 09 | Helion Energy | Redmond, Washington, USA | MIF Fibonacci gun placement validation — PQ-CSE series |
| Team 10 | General Fusion | Vancouver, Canada | Mirror confinement time — PQ-PHY + PQ-CSE |
| Team 11 | FortressAI Research Institute | Norwich, Connecticut, USA | Constitutional substrate — Full GxP IQ/OQ/PQ, mesh sovereignty |

### 5.3 Validation Tracks

**PHY Track — Physics bounds validation.** Teams validate that the telemetry bounds in the Plant Catalogue match real experimental operating windows at their facility. An M-tag upgrade (I or A → M) requires a signed evidence package with raw sensor data, calibration records, and PQ-PHY sign-off.

**CSE Track — Computational science and engineering validation.** Teams validate that the UUM-8D numerical engine produces correct closure residuals on their experimental datasets. The 81-swap matrix (9 × 9 plant-to-plant transitions) is executed in full on each team's compute infrastructure.

**QA Track — Quality assurance cross-validation.** Teams validate each other's evidence packages. No team validates their own submission. EUROfusion (Team 08) coordinates the cross-validation schedule.

**SAF Track — Safety and REFUSED validation.** Teams deliberately inject out-of-bounds telemetry, malformed vQbits, and disruption signatures into their local GaiaFTCL instance and verify that the constitutional layer declares REFUSED correctly in every case. A SAF Track completion without a single false acceptance is a prerequisite for the mesh-wide CALORIE verdict.

### 5.4 Pass / REFUSED Definitions for the Sprint

The sprint has a binary outcome at the mesh level. The verdict is determined by the constitutional layer, not by any human vote.

**Sprint CALORIE (pass):**
- All eleven evidence packages are received and pass QA cross-validation.
- The physics bounds for all nine plant kinds have at least one M-tagged value per channel from at least one operating facility.
- The SAF Track produces zero false acceptances across all eleven teams.
- The closure residual on the reference Tokamak configuration drops below 9.54 × 10⁻⁷ under quorum.
- All 32 OQ tests pass on all eleven installations.

**Sprint REFUSED (failure):**
- Any single evidence package contains a NaN, Inf, or negative value in any channel.
- Any team's SAF Track produces a false acceptance of an out-of-bounds value.
- Fewer than five teams achieve quorum on the closure residual measurement.
- Any M-tag downgrade is submitted without a Change Control Record.

The sprint REFUSED is not a programme failure. It is the constitutional layer working correctly. A sprint REFUSED means: "the evidence is not yet sufficient." The cells do not shut down. They continue operating, and the next measurement cycle begins immediately.

---

## 6. Mac App — The Human Interface

### 6.1 Architecture Overview

The Mac Cell runs a native macOS application built on a two-layer architecture. The outer layer is a WKWebView that renders an HTML/CSS/JavaScript dashboard — this is where operators see the telemetry, the plant state, the vQbit entropy and truth values, and the mesh status. The inner layer is a Swift AppDelegate that owns the Metal renderer, the Rust FFI bridge, the NATS client, and the sovereign identity.

The two layers communicate through a `WKScriptMessageHandler` bridge. The Swift layer posts JSON messages to the WKWebView when state changes occur. The WKWebView sends commands back to Swift through `window.webkit.messageHandlers`. Neither layer can bypass the other — all Metal rendering decisions go through Swift, and all human-readable state updates go through the WKWebView.

### 6.2 The Metal Renderer

The Metal renderer maintains a separate `MTLRenderPipelineState` for each of the nine canonical plant kinds. Each pipeline state is compiled at application startup from embedded Metal Shading Language source. There is no runtime shader compilation — if the MSL source fails to compile, the application does not start.

**Startup sequence:**

```
1. AppDelegate.applicationDidFinishLaunching
2. → Instantiate MTLDevice (unified memory, Apple Silicon)
3. → Compile MTLLibrary from embedded MSL source
4. → For each of 9 plant kinds:
      a. Build MTLRenderPipelineDescriptor
      b. Compile MTLRenderPipelineState
      c. Allocate vertex buffer (StorageModeShared)
      d. Populate wireframe geometry from plant kind spec
5. → Instantiate NATS client, connect to gaiaftcl.* subjects
6. → Load sovereign identity from evidence/iq_receipt.json
7. → Start UUM-8D engine (Rust, via FFI)
8. → Load WKWebView with dashboard HTML
9. → Begin render loop (CADisplayLink, 60 fps)
```

If any step fails, the application enters REFUSED and displays the failure reason. There is no degraded mode — either all nine plant pipelines are ready, or the application does not operate.

### 6.3 Vertex and Uniform Buffer Layout

All nine plant kind vertex buffers share the same `GaiaVertex` struct layout. The layout is ABI-stable and is regression-tested in the OQ suite.

**GaiaVertex (28 bytes):**

| Field | Type | Offset | Size |
| --- | --- | --- | --- |
| `position` | SIMD3\<Float\> | 0 | 12 bytes |
| `color` | SIMD4\<Float\> | 12 | 16 bytes |

**Uniforms (64 bytes):**

| Field | Type | Offset | Size |
| --- | --- | --- | --- |
| `modelViewProjection` | float4x4 | 0 | 64 bytes |

**vQbitPrimitive (76 bytes, #[repr(C)]):**

| Field | Type | Offset | Size |
| --- | --- | --- | --- |
| `transform` | [f32; 16] | 0 | 64 bytes |
| `vqbit_entropy` | f32 | 64 | 4 bytes |
| `vqbit_truth` | f32 | 68 | 4 bytes |
| `prim_id` | u32 | 72 | 4 bytes |

The full ABI specification, regression guard suite, and Swift FFI header are documented in [[vQbitPrimitive-ABI]].

### 6.4 The WKWebView Dashboard

The HTML dashboard served to the WKWebView is a single-file HTML/JS/CSS application. It does not make network requests. All data flows in from the Swift layer through the message bridge. The dashboard displays:

- **Plant selector:** Nine plant kind buttons. Clicking a button sends a `switchPlant` message to Swift, which triggers a vertex buffer swap in the Metal renderer.
- **Telemetry readouts:** Live I_p, B_T, and n_e values with epistemic tags displayed as colour-coded badges (M = gold, T = silver, I = bronze, A = grey).
- **vQbit panel:** Live `vqbit_entropy` and `vqbit_truth` values for the active plant, visualised as a 2D point on an entropy/truth plane.
- **Terminal state indicator:** The current CALORIE/CURE/REFUSED state of the local cell, in the canonical colours (green/blue/red).
- **Mesh status:** The quorum count (n/9) and the cells contributing to the current quorum.
- **Closure residual:** The running numerical closure residual for the active plant, updated on every quorum-committed measurement.
- **τ clock:** The current Bitcoin block height, used as the sovereign timestamp for all evidence.

### 6.5 NATS JetStream Integration

The Mac Cell connects to the mesh NATS JetStream cluster on startup. All telemetry, vQbit measurements, and state transitions are published and consumed through NATS subjects with the prefix `gaiaftcl.*`.

| Subject | Direction | Payload | Purpose |
| --- | --- | --- | --- |
| `gaiaftcl.telemetry.<plant>` | Publish | Raw I_p, B_T, n_e + epistemic tags | Broadcast sensor readings to mesh |
| `gaiaftcl.vqbit.<cell_id>` | Publish | vQbitPrimitive (76 bytes, base64) | Broadcast vQbit measurements |
| `gaiaftcl.quorum.<event_id>` | Subscribe | Quorum vote + cell signatures | Receive mesh consensus decisions |
| `gaiaftcl.state.<cell_id>` | Both | CALORIE / CURE / REFUSED + reason | Publish own state, subscribe to peer states |
| `gaiaftcl.tau` | Subscribe | Bitcoin block height | Receive sovereign time anchor |

During development, two known warnings are acceptable and non-blocking: `TAU_NOT_IMPLEMENTED` (τ synchronisation not yet connected to a live Bitcoin node) and `NATS_UNREACHABLE` (NATS cluster not available in standalone development mode).

### 6.6 Build Sequence

```zsh
# 1. Installation Qualification
cd ~/Documents/FoT8D/GAIAFTCL
zsh scripts/iq_install.sh
# Expected: IQ_PASS, evidence/iq_receipt.json written

# 2. Operational Qualification
zsh scripts/oq_validate.sh
# Expected: OQ_PASS, 32/32 tests, evidence/oq_receipt.json written

# 3. Performance Qualification
zsh scripts/pq_run.sh
# Expected: PQ_PASS, 81-swap matrix complete, evidence/pq_receipt.json written

# 4. Build and run the Mac app
cd GaiaMacCell
swift build -c release
open .build/release/GaiaMacCell.app
```

Full IQ → OQ → PQ qualification details are in [[IQ-Installation-Qualification]], [[OQ-Operational-Qualification]], and [[PQ-Performance-Qualification]].

---

## 7. Cross-Domain Architecture

### 7.1 The Universal Constitutional Substrate

The GaiaFTCL constitutional substrate is not domain-specific. The UUM-8D framework — M⁸ = S⁴ × C⁴, vQbit measurements, three terminal states, epistemic tagging, quorum validation — was designed to be a universal governance layer for any system that requires formal uncertainty management and constitutional oversight. Fusion plasma control is the first and most demanding application. The six cross-domain families below represent the expansion of the same substrate into adjacent high-consequence domains.

The key principle of cross-domain deployment is: **the constitutional rules do not change.** No NaN, no Infinity, no negative values, no zero-vertex geometry, no mutable epistemic tags, no unilateral state transitions. A system that accepts out-of-bounds values in an autonomous vehicle is just as REFUSED as a system that accepts them in a tokamak.

### 7.2 Autonomous Vehicles — Full Self-Drive (FSD)

The FSD deployment maps the UUM-8D state space onto the problem of navigating an autonomous vehicle through a complex traffic environment.

**S⁴ projection space for FSD:**
- Dimension 1: Positional certainty (how precisely does the vehicle know its location?)
- Dimension 2: Object classification certainty (how confident is the system in the identity of nearby objects?)
- Dimension 3: Intent prediction certainty (how confident is the system in the future trajectories of nearby agents?)
- Dimension 4: Path feasibility certainty (how confident is the system that the planned path is clear?)

**C⁴ constraint space for FSD:**
- Dimension 1: Traffic law compliance obligation
- Dimension 2: Collision avoidance obligation
- Dimension 3: Occupant safety obligation
- Dimension 4: Infrastructure compatibility obligation

The vQbit in the FSD context is a compressed encoding of the gap between the vehicle's current sensor state and the formal specification of safe driving. REFUSED in the FSD context means: "I cannot determine a safe action with the current information." The constitutional outcome is not to guess — it is to stop, declare REFUSED, and hand control back to the occupant.

The nine-cell quorum applies to the vehicle's on-board sensor array: multiple sensor modalities (camera, LiDAR, radar, ultrasonic) vote on the state of the environment. A decision that cannot achieve quorum across modalities is REFUSED.

### 7.3 Drone Swarms

Drone swarm coordination maps UUM-8D onto the problem of governing a fleet of autonomous aerial vehicles operating in a shared airspace.

**The swarm mesh:** Each drone in the swarm is a sovereign cell. The swarm's quorum is the minimum number of drones that must agree on a formation manoeuvre before it is executed. For a standard nine-drone swarm, the quorum requirement is the same: five-of-nine.

**vQbit in swarm context:** The entropy delta between a drone's expected position in the formation and its current position. A drone that has drifted more than the constitutional tolerance from its formation position emits a high-entropy vQbit. If the swarm quorum confirms the drift, the formation controller executes a CURE — a correction manoeuvre.

**REFUSED in swarm context:** A drone that cannot achieve safe separation from obstacles or from other drones in the formation declares REFUSED and executes an emergency hold-position or return-to-home. The swarm does not proceed with the manoeuvre until the REFUSED cell resolves or is excluded from the quorum.

**Constitutional rule for swarms:** No drone may enter a space that has not been cleared by quorum. The formation plan is not an instruction — it is a proposal. The constitutional layer validates the proposal against all nine drones' current state before any movement begins.

### 7.4 Air Traffic Control (ATC)

The ATC deployment governs the separation and sequencing of aircraft in controlled airspace. The constitutional substrate provides formal uncertainty management for a domain where the cost of a REFUSED is a go-around or a hold, and the cost of a false acceptance is catastrophic.

**S⁴ projection space for ATC:**
- Dimension 1: Separation certainty (are the separation minima provably maintained?)
- Dimension 2: Conflict prediction certainty (is the projected flight path free of conflicts?)
- Dimension 3: Capacity certainty (can the sector absorb the current traffic level?)
- Dimension 4: Weather impact certainty (does the weather state allow the planned routing?)

**REFUSED in ATC context:** A clearance that cannot achieve quorum across the four certainty dimensions is not issued. The controller is shown the REFUSED verdict with the specific dimension that failed — not a generic warning, but a formally-bounded statement of what the uncertainty is.

The epistemic tagging for ATC maps directly from the fusion domain: radar tracks are M-tagged, ADS-B position reports are M-tagged, weather model predictions are I-tagged, and flight plan waypoints are A-tagged until the aircraft transitions to the next sector.

### 7.5 Maritime Routing

Maritime routing applies the constitutional substrate to the problem of planning and executing safe vessel transits through constrained waterways, traffic separation schemes, and dynamic weather systems.

The maritime vQbit encodes the gap between the vessel's current state (position, heading, speed, draft) and the formal requirements of the passage plan. A vessel approaching a Traffic Separation Scheme (TSS) boundary issues vQbits whose entropy delta reflects the uncertainty in the vessel's ability to complete the entry manoeuvre within the separation zone rules.

**REFUSED in maritime context:** A routing recommendation that would place a vessel within a formally prohibited zone, below the required underkeel clearance, or outside the weather envelope of the vessel's class is REFUSED. The constitutional layer does not soften this — it does not say "proceed with caution." It says REFUSED and presents the specific constraint that was violated.

The long-range voyage planning application uses the full nine-cell mesh for quorum: each cell runs a different meteorological model or routing algorithm, and the quorum decision is the routing plan that achieves consensus across five of nine independent computational views of the same physical problem.

### 7.6 Biomedical — Acute Myeloid Leukaemia (AML) and Tuberculosis (TB OWL)

The biomedical deployment is the most direct expression of the UUM-8D framework outside of fusion. Medical diagnosis is an uncertainty management problem with constitutional constraints: the epistemic obligations are clinical guidelines, the C⁴ constraints are regulatory and ethical obligations, and the terminal states — CALORIE (positive diagnosis + treatment plan), CURE (negative result, no treatment required), REFUSED (insufficient evidence for a safe diagnostic conclusion) — map directly onto clinical decision support.

**AML (Acute Myeloid Leukaemia):**

The AML module ingests bone marrow biopsy data, peripheral blood counts, and cytogenetic analysis results. Each data channel carries an epistemic tag:
- Flow cytometry blast count: M-tagged (direct measurement)
- Cytogenetic risk classification: M-tagged (validated laboratory assay)
- Mutation panel results (FLT3, NPM1, CEBPA): M-tagged
- Predicted treatment response from prior cases: I-tagged
- Theoretical outcome from genomic sequencing extrapolation: A-tagged

The vQbit for AML encodes the gap between the patient's current measured state and the formal diagnostic criteria for each AML subtype per the WHO classification. The constitutional layer computes a CALORIE verdict (positive AML diagnosis with risk stratification and treatment recommendation), a CURE verdict (complete remission confirmed), or a REFUSED verdict (insufficient evidence — additional tests required before a safe clinical decision can be made).

The REFUSED verdict in AML is not a failure. It is the system protecting the patient from a diagnosis made on incomplete data.

**TB OWL (Tuberculosis Ontology-Weighted Likelihood):**

The TB OWL module applies an ontology-weighted likelihood model to tuberculosis diagnosis. The knowledge graph encodes the WHO TB taxonomy, drug resistance patterns, and epidemiological context as a named graph in ArangoDB. The vQbit measurement is the entropy delta between the patient's symptom and test profile and the formal TB diagnostic criteria.

The OWL (ontology-weighted likelihood) weighting gives higher confidence to diagnostic paths that traverse more M-tagged edges in the knowledge graph. A diagnosis path that relies entirely on M-tagged measurements (confirmed sputum culture, GeneXpert MTB/RIF assay, CXR with radiologist sign-off) produces a high-truth vQbit. A path that relies on clinical judgment and symptom inference produces a lower-truth vQbit. Both paths are valid — but the constitutional layer reports the difference, and the REFUSED threshold is set conservatively for low-truth paths.

### 7.7 Municipal Governance

The municipal governance deployment applies the constitutional substrate to the problem of managing public infrastructure decisions — budget allocation, planning approvals, service delivery commitments — with formal uncertainty management and constitutional oversight.

**The vQbit for governance:** The entropy delta between a proposed policy intervention and the formal requirements of the governing legal framework (planning law, financial regulations, public consultation obligations). A proposal that is well within the legal framework produces a low-entropy vQbit. A proposal that pushes against regulatory boundaries produces a high-entropy vQbit — which is not automatically REFUSED, but which triggers an elevated quorum requirement.

**Elevated quorum for high-entropy governance decisions:** The constitutional layer can require a higher quorum threshold for decisions with high entropy. A routine maintenance budget allocation might require only 5-of-9. A novel planning approval at the boundary of existing permitted development rights might require 8-of-9.

**REFUSED in governance context:** A proposed decision that would violate a statutory obligation, exceed a financial limit, or override a constitutionally-protected right is REFUSED by the substrate before it reaches the human decision layer. This is not censorship — it is constitutional pre-clearance. The decision-maker is shown exactly which constraint produced the REFUSED and can either modify the proposal or escalate to the appropriate authority.

---

## 8. Knowledge Graph

### 8.1 ArangoDB Architecture

The GaiaFTCL knowledge graph runs on ArangoDB, a multi-model database that provides native graph traversal, document storage, and full-text search in a single engine. The graph is stored as a named graph with the identifier `gaiaftcl_knowledge_graph`.

The knowledge graph is replicated across all nine cells of the mesh. Every cell maintains a full local copy. Writes require quorum (5-of-9 cells must confirm before a write is committed). Reads are local — a cell does not need to contact other cells to traverse the graph.

### 8.2 The Seven Edge Collections

The knowledge graph is organised into seven edge collections. Each collection governs a specific category of relationship between nodes.

| Collection | Connects | Relationship type | Domain |
| --- | --- | --- | --- |
| `plant_physics` | Plant kind → Physics parameter | "has operating window" | Fusion |
| `epistemic_lineage` | Value → Source measurement | "derived from" | All domains |
| `quorum_decisions` | Cell → State transition | "voted on" | Sovereignty |
| `vqbit_observations` | vQbitPrimitive → Plant state | "measured from" | All domains |
| `domain_mappings` | Fusion concept → Cross-domain concept | "analogous to" | Cross-domain |
| `cure_history` | CURE event → Prior REFUSED | "healed by" | All domains |
| `tau_anchors` | State transition → Bitcoin block | "timestamped at" | Sovereignty |

### 8.3 VIE-v2 — Vortex Ingestion Engine

VIE-v2 is the data ingestion engine that processes raw sensor and data streams from all ten domain schemas and converts them into the universal vQbit schema before they enter the knowledge graph.

**Ten domain schemas supported by VIE-v2:**

1. Fusion plasma telemetry (I_p, B_T, n_e + plant kind + epistemic tag)
2. FSD sensor fusion (camera, LiDAR, radar, ultrasonic + confidence scores)
3. Drone swarm formation state (position, heading, speed, separation distances)
4. ATC radar and ADS-B tracks (position, velocity, flight level, squawk)
5. Maritime AIS and voyage plan (position, COG, SOG, draft, waypoints)
6. AML clinical data (blast count, cytogenetics, mutation panel)
7. TB diagnostic data (symptom profile, test results, epidemiological context)
8. Municipal governance proposals (proposal text, legal references, financial data)
9. Knowledge graph audit trail (edge creation events, quorum decisions, τ anchors)
10. Cross-cell quorum messages (cell signatures, vote payloads, consensus timestamps)

**Universal vQbit schema:**

```json
{
  "schema": "vQbit-v2",
  "cell_id": "<64-char hex>",
  "tau": <bitcoin_block_height>,
  "domain": "<fusion|fsd|drone|atc|maritime|aml|tb|governance|graph|quorum>",
  "plant_kind": "<USDA scope name or null>",
  "prim_id": <uint32>,
  "vqbit_entropy": <float32 in [0.0, 1.0]>,
  "vqbit_truth": <float32 in [0.0, 1.0]>,
  "epistemic_tag": "<M|T|I|A>",
  "terminal_state": "<CALORIE|CURE|REFUSED|PENDING>",
  "channels": {
    "I_p": { "value": <float64>, "unit": "MA", "tag": "<M|T|I|A>" },
    "B_T": { "value": <float64>, "unit": "T", "tag": "<M|T|I|A>" },
    "n_e": { "value": <float64>, "unit": "m^-3", "tag": "<M|T|I|A>" }
  }
}
```

The `channels` object is populated for fusion domain measurements. For non-fusion domains, the channel fields are mapped to the domain-equivalent quantities (e.g., for ATC: I_p → separation distance, B_T → conflict probability, n_e → sector load).

### 8.4 NATS JetStream and the Knowledge Graph

NATS JetStream is the messaging backbone that connects the live measurement pipeline to the knowledge graph. The flow is:

```
Sensor / data source
    ↓
VIE-v2 ingestion (schema validation + vQbit encoding)
    ↓
NATS JetStream publication (gaiaftcl.vqbit.<cell_id>)
    ↓
Graph writer (subscribes to gaiaftcl.vqbit.*)
    ↓
ArangoDB write (quorum-gated)
    ↓
Knowledge graph (queryable, replicated, τ-anchored)
```

The graph writer is the only component that writes to ArangoDB. All other components read from the knowledge graph via the ArangoDB HTTP API or the Rust ArangoDB driver. This single-writer architecture ensures that all writes pass through the quorum gate and are τ-anchored before they are committed.

### 8.5 Knowledge Graph Queries

The knowledge graph supports three query patterns that are used extensively by the UUM-8D engine:

**Epistemic lineage trace:** Given a current measurement value, traverse the `epistemic_lineage` edges backward to find the original source measurement. This is used to verify that a value's epistemic tag is correct — an M-tagged value must trace back to a direct experimental measurement.

**CURE history lookup:** Given a current REFUSED event, traverse the `cure_history` edges to find prior REFUSED events for the same plant kind and channel, and the CURE events that resolved them. This is the system's institutional memory for how it has healed itself before.

**Cross-domain analogy traversal:** Given a fusion physics concept (e.g., "plasma confinement stability"), traverse the `domain_mappings` edges to find the analogous concept in each cross-domain family (e.g., "vehicle lane-keeping stability" in FSD, "flight separation stability" in ATC). This is how the UUM-8D framework generalises from fusion to every other domain.

---

## 9. Constitutional Constraints

### 9.1 The Full Constitutional Invariant Set

These constraints are not configuration parameters. They are not policy choices. They are the constitutional foundation of the substrate. Violating any of them is a REFUSED — not a warning, not a degraded mode, not a best-effort continuation.

**C-001 — NaN/Infinity prohibition**
No NaN or Inf value may appear in any telemetry channel (I_p, B_T, n_e) or any vQbit field (`vqbit_entropy`, `vqbit_truth`) at any point in the pipeline. Violation triggers immediate REFUSED and cell halt. Verified by PQ-SAF-002.

**C-002 — Negative value prohibition**
I_p, B_T, and n_e must all be ≥ 0.0. A negative plasma current, magnetic field, or electron density has no physical meaning in the GaiaFTCL context and indicates a sensor fault or computation error. Verified by PQ-PHY-007.

**C-003 — Colour normalisation**
All three telemetry channel values must normalise to [0.0, 1.0] for the Metal renderer colour mapping. The raw telemetry value is always logged. Only the display value is clamped. The ICF plant kind's extreme n_e values must be handled without float overflow. Verified by PQ-CSE-008 and PQ-PHY-006.

**C-004 — Epistemic tag immutability**
M/T/I/A tags cannot change during a render frame or across a plant swap. A tag may only be upgraded (e.g., A→I→T→M) through a Change Control Record with signed evidence. Tags may never be downgraded without a Change Control Record. Verified by PQ-PHY-005.

**C-005 — Non-zero geometry**
Every plant wireframe must produce vertex_count > 0. A zero-vertex wireframe is a render failure and triggers REFUSED. The nine plant minimum vertex counts are: Tokamak 48, Stellarator 48, SphericalTokamak 32, FRC 24, Mirror 24, Spheromak 32, ZPinch 16, MIF 40, Inertial 40. Verified by PQ-CSE-001 and PQ-CSE-007.

**C-006 — Quorum gate**
No state transition from PENDING to CALORIE or CURE may be committed without quorum (5-of-9 cells). A REFUSED declaration requires only a single cell. Quorum timeout results in REFUSED. Verified by the sovereignty layer on every state transition.

**C-007 — Sovereign identity uniqueness**
No two cells may share a cell_id. The cell_id is derived from SHA-256(uuid ‖ entropy ‖ timestamp) and is unique per machine per install. Identity regeneration requires full IQ re-execution and re-signing of all prior evidence. Verified by IQ-012.

**C-008 — τ anchoring**
All committed state transitions must carry a τ timestamp (Bitcoin block height). A state transition without a τ anchor is invalid and is treated as REFUSED. During development, TAU_NOT_IMPLEMENTED is an accepted warning but is non-blocking only for non-PQ runs. Verified by the `tau_anchors` edge collection in the knowledge graph.

**C-009 — Fibonacci configuration lock**
The MIF plant's Fibonacci gun placement is a controlled configuration item. Any change to the gun positions or count requires full PQ-CSE re-execution. The gun placement is stored as a constitutional parameter, not a runtime variable. Verified by PQ-CSE at every PQ execution.

**C-010 — 81-swap matrix completeness**
The PQ suite must execute all 81 plant-to-plant swap transitions (9 × 9) without any REFUSED in the geometry, ABI, or telemetry validation steps. A partial swap matrix does not satisfy PQ. Verified by PQ-CSE-007 and the `pq_receipt.json` swap count field.

### 9.2 Change Control

Any change to the code that touches the following components requires a Change Control Record, a full OQ run, and a full PQ run before the change is accepted into the evidence directory:

- Any field of `vQbitPrimitive`, `GaiaVertex`, or `Uniforms`
- Any plant kind's telemetry bounds or physics constraints in the Plant Catalogue
- The quorum threshold (currently 5-of-9)
- The numerical closure threshold (currently 9.54 × 10⁻⁷)
- The Fibonacci gun placement for MIF
- The Metal shader source for any plant kind
- The sovereign identity derivation algorithm

Changes to human-readable documentation, the WKWebView dashboard styling, and NATS subject naming do not require Change Control, but must not alter any ABI-relevant data path.

---

## 10. Glossary

| Term | Definition |
| --- | --- |
| **AML** | Acute Myeloid Leukaemia — one of the two primary biomedical application domains of the GaiaFTCL substrate |
| **ArangoDB** | Multi-model database providing the knowledge graph storage layer. Named graph: `gaiaftcl_knowledge_graph` |
| **ATC** | Air Traffic Control — one of the six cross-domain application families |
| **B_T** | Toroidal magnetic field, in tesla (T). Green colour channel in the Metal renderer |
| **CALORIE** | Terminal state: value produced. The cell has produced a validated, quorum-confirmed measurement that advances the closure residual |
| **Cell** | A sovereign GaiaFTCL compute node. The mesh has nine cells |
| **Change Control Record** | Formal document required before any ABI, bounds, or constitutional parameter change. Triggers full OQ + PQ re-execution |
| **C⁴** | Constraint Space — the four-dimensional manifold encoding formal obligations in the UUM-8D state space |
| **CURE** | Terminal state: deficit healed. A prior measurement error has been corrected, or a bounds violation has been resolved |
| **Epistemic tag** | M/T/I/A classification carried by every telemetry value. Immutable for the lifetime of the run |
| **FRC** | Field-Reversed Configuration — plant kind 4 in the Plant Catalogue |
| **FSD** | Full Self-Drive — one of the six cross-domain application families |
| **GaiaVertex** | 28-byte Metal vertex struct: position (12 bytes) + color (16 bytes) |
| **GxP** | Good practice frameworks: GAMP 5, EU Annex 11, FDA 21 CFR Part 11 |
| **Hohlraum** | The cylindrical radiation case surrounding the ICF fuel capsule |
| **I (epistemic tag)** | Inferred — derived from physical scaling laws or extrapolation |
| **ICF** | Inertial Confinement Fusion — plant kind 9 in the Plant Catalogue |
| **IQ** | Installation Qualification — verifies hardware, toolchain, and sovereign cell identity |
| **I_p** | Plasma current, in megaamperes (MA). Blue colour channel in the Metal renderer |
| **Klein bottle** | The invariant mesh topology of the nine-cell network: no boundary, no privileged gateway node |
| **Lawson criterion** | The minimum triple product n_e × T_i × τ_E required for fusion energy gain |
| **M (epistemic tag)** | Measured — derived from direct experimental measurement at an operating facility |
| **M⁸** | The full UUM-8D state space: M⁸ = S⁴ × C⁴ |
| **MIF** | Magneto-Inertial Fusion — plant kind 8 in the Plant Catalogue |
| **Mirror** | Open magnetic mirror confinement — plant kind 5 in the Plant Catalogue |
| **MSL** | Metal Shading Language — compiled from embedded source at Mac Cell startup |
| **MTLRenderPipelineState** | Apple Metal compiled render pipeline. One per plant kind, compiled at startup |
| **NATS JetStream** | Messaging backbone for the GaiaFTCL mesh. Subject prefix: `gaiaftcl.*` |
| **n_e** | Electron density, in m⁻³. Red colour channel in the Metal renderer |
| **NaN** | Not a Number — unconditionally REFUSED by constitutional constraint C-001 |
| **Numerical closure threshold** | 9.54 × 10⁻⁷ — the residual value at which the system declares CALORIE for a closure event |
| **OQ** | Operational Qualification — verifies all 32 GxP tests pass on every build |
| **OWL** | Ontology-Weighted Likelihood — the TB diagnostic model |
| **PQ** | Performance Qualification — verifies the 81-swap matrix, physics bounds, and runtime behaviour |
| **PQ-CSE** | Computational Science and Engineering qualification track |
| **PQ-PHY** | Physics bounds qualification track |
| **PQ-QA** | Quality Assurance cross-validation track |
| **PQ-SAF** | Safety and REFUSED validation track |
| **Quorum** | 5-of-9 cells must agree for CALORIE or CURE. REFUSED requires only 1 cell |
| **REFUSED** | Terminal state: entropy without value. Constitutional constraints were violated, quorum was not reached, or physics bounds were exceeded. The cell halts |
| **S⁴** | Projection Space — the four-dimensional manifold encoding the system's belief about physical state in UUM-8D |
| **Spheromak** | Self-organized compact torus — plant kind 6 in the Plant Catalogue |
| **Spherical Tokamak** | Low aspect ratio tokamak — plant kind 3 in the Plant Catalogue |
| **Stellarator** | 3D twisted torus, zero plasma current — plant kind 2 in the Plant Catalogue |
| **StorageModeShared** | Apple Metal memory mode: unified CPU/GPU access without copy. Used for all nine plant vertex buffers |
| **T (epistemic tag)** | Tested — derived from validated simulation or laboratory test |
| **A (epistemic tag)** | Assumed — assumed from target design or theoretical prediction |
| **τ (tau)** | Bitcoin block height — the sovereign time standard for the GaiaFTCL mesh |
| **TB OWL** | Tuberculosis Ontology-Weighted Likelihood — one of the two primary biomedical application domains |
| **Tokamak** | Axisymmetric toroidal confinement — plant kind 1 in the Plant Catalogue |
| **Triple product** | n_e × T_i × τ_E — the Lawson criterion metric for fusion energy gain |
| **Uniforms** | 64-byte Metal uniform buffer: a single float4x4 model-view-projection matrix |
| **UUM-8D** | Universal Uncertainty Model in Eight Dimensions: M⁸ = S⁴ × C⁴ |
| **VIE-v2** | Vortex Ingestion Engine version 2 — converts raw domain data into universal vQbit schema |
| **vQbit** | The atomic measurement primitive: entropy delta between observer and system, plus truth threshold |
| **vQbitPrimitive** | 76-byte #[repr(C)] Rust struct: transform (64 bytes) + vqbit_entropy (4 bytes) + vqbit_truth (4 bytes) + prim_id (4 bytes) |
| **WKWebView** | Apple WebKit view used to render the Mac Cell HTML dashboard |
| **ZPinch** | Z-Pinch — pure axial-current confinement — plant kind 7 in the Plant Catalogue |

---

*GaiaFTCL Fusion Mac Cell Wiki — FortressAI Research Institute | Norwich, Connecticut*
*Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie*
*Last qualified: see `evidence/pq_receipt.json` for τ-anchored timestamp*
