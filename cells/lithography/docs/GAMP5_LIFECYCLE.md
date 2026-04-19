# GAMP 5 Lifecycle — GaiaLithography Silicon Cell

**Document ID:** GL-GAMP5-001
**Revision:** 1.0
**Parent:** [`DESIGN_SPECIFICATION.md`](DESIGN_SPECIFICATION.md)
**Classification:** Regulatory compliance framework. Maps directly to ISPE GAMP 5 2nd Edition and FDA 21 CFR Part 11 where applicable.

**Reviewer summary (IQ / OQ / PQ one-pager):** [`IQ_OQ_PQ_LITHOGRAPHY_CELL.md`](IQ_OQ_PQ_LITHOGRAPHY_CELL.md)

---

## 0 — Purpose

This document maps the GaiaLithography silicon cell onto the **ISPE GAMP 5 Good Automated Manufacturing Practice** framework, 2nd Edition (2022). It is the regulatory counterpart to [`FAB_PROCESS_FLOW.md`](FAB_PROCESS_FLOW.md).

Because GaiaLithography silicon underpins GaiaFusion (fusion-plant control) and GaiaHealth (therapeutic-discovery-grade MD), it inherits the strictest compliance posture of any consuming cell — **GAMP 5 Category 5: Custom Applications**. Every lifecycle artifact specified in GAMP 5 has a concrete deliverable in this cell.

---

## 1 — Category Classification

| GAMP 5 Category | Applicability to GaiaLithography |
|-----------------|----------------------------------|
| Cat 1: Infrastructure | OS kernel, network stack, foundry tooling |
| Cat 3: Non-configured | n/a (we configure everything) |
| Cat 4: Configured | Commercial EDA tools (KLayout, netgen, STA) treated here |
| **Cat 5: Custom** | **Chiplet RTL, HMMU, LithoPrimitive ABI, Xvqbit ISA, Franklin Guardian hooks** |

The Xvqbit instruction extension, HMMU IP, and the three-cell CCR governance model are all Category 5. They are validated end-to-end with a V-model; no vendor-supplied validation package substitutes.

---

## 2 — V-Model Mapping

```
   URS  ──────────────────────────────────  UAT / PQ
        \                                 /
         FS  ──────────────────────  OQ
             \                      /
              DS  ──────────  IQ
                  \          /
                   IMPLEMENTATION
                   (RTL, firmware, toolchain)
```

### 2.1 URS — User Requirements Specification

**Document:** [`DESIGN_SPECIFICATION.md`](DESIGN_SPECIFICATION.md), §1–3 (purpose, x86-problem statement, principles).

Defines the business / mission requirements: replace x86 paradigm, match Apple M-series UMA, enforce the 0.85 truth threshold in hardware, support three tiers from a single ISA.

### 2.2 FS — Functional Specification

**Document:** [`FUNCTIONAL_SPECIFICATION.md`](FUNCTIONAL_SPECIFICATION.md) (state machine, event taxonomy, control flows).

Translates URS into testable functional statements: every LithoPrimitive event, every Xvqbit opcode, every state transition.

### 2.3 DS — Design Specification

**Documents:**
- [`M8_CHIPLET_IP_PORTFOLIO.md`](M8_CHIPLET_IP_PORTFOLIO.md) — chiplet-level DS.
- [`TORSION_INTERPOSER.md`](TORSION_INTERPOSER.md) — package-level DS.
- [`HMMU_SPECIFICATION.md`](HMMU_SPECIFICATION.md) — safety-block DS.
- [`M8_ISA.md`](M8_ISA.md) — ISA DS.
- [`LITHO_PRIMITIVE_ABI.md`](LITHO_PRIMITIVE_ABI.md) — data DS.

### 2.4 Implementation

- RTL: SystemVerilog sources under `cells/lithography/rtl/` (to be added).
- Firmware: Rust + C under `cells/lithography/firmware/`.
- Toolchain: GaiaOS image with the Xvqbit-aware LLVM toolchain.

### 2.5 IQ — Installation Qualification

**Deliverable:** `cells/lithography/qualification/iq/` test pack.

IQ confirms the silicon, firmware, and toolchain are installed correctly. Covers:

| IQ Test | Purpose | Pass criterion |
|---------|---------|----------------|
| IQ-L-001 | PDK hash matches escrow | SHA-256 equal to vault copy |
| IQ-L-002 | GDSII hash matches CCR | SHA-256 equal to signed record |
| IQ-L-003 | Package serial is whitelisted | Serial present in FoT8D registry |
| IQ-L-004 | Xvqbit `misa` bit 21 reads 1 | Instruction discoverable |
| IQ-L-005 | NPU Owl pubkey fingerprint matches expected | eFuse-programmed key verified |
| IQ-L-006 | HMMU boot handshake succeeds | OTT transitions from 0xF to UNOWNED |
| IQ-L-007 | LithoPrimitive schema_hash matches RG-L-011 | Compile-time hash match |
| IQ-L-008 | NATS subjects on `gaiaftcl.lithography.>` observed on boot | Boot event captured |

### 2.6 OQ — Operational Qualification

**Deliverable:** `cells/lithography/qualification/oq/` test pack.

OQ exercises every functional path. Full list in [`FAB_PROCESS_FLOW.md`](FAB_PROCESS_FLOW.md) §3. Highlights:

- Full HMMU-OQ-01..07 breach suite ([`HMMU_SPECIFICATION.md`](HMMU_SPECIFICATION.md) §8).
- Full Xvqbit opcode sweep ([`M8_ISA.md`](M8_ISA.md) §2).
- Thermal soak 96 h at 90 % TDP.
- Burn-in 168 h at 1.1× V, 110 °C.
- Ethernet PHY BER at 1e-15 over 24 h continuous.
- LithoPrimitive RG-L-001..011 + IQ-L-001..004 passing on the bring-up target.

### 2.7 PQ — Performance Qualification

**Deliverable:** `cells/lithography/qualification/pq/` test pack.

PQ validates the silicon against its actual consuming-cell workloads. See [`FAB_PROCESS_FLOW.md`](FAB_PROCESS_FLOW.md) §4. PQ is gated by: GaiaFusion plasma control, GaiaHealth MD, and Franklin Guardian identity binding running concurrently at PQ-defined load for 24 h.

### 2.8 UAT — User Acceptance Testing

Carried out by the consuming cell owners:
- GaiaFusion acceptance: a sign-off that the M8-Cell package delivers 50 kHz deterministic tokamak-coil control with ≤ 200 ns tick jitter.
- GaiaHealth acceptance: a sign-off that a 72-hour MD sweep produces no HMMU breaches and the therapeutic leaderboard is reproducible bit-for-bit across reruns.
- Franklin Guardian acceptance: a sign-off that Owl Protocol crypto ops complete in ≤ 40 ns and the identity-binding throughput meets the target of 10 M operations/hour.

---

## 3 — Risk Management (ICH Q9 / GAMP 5 Appendix M3)

### 3.1 Risk matrix

| Hazard | Severity | Likelihood | Risk | Control |
|--------|----------|------------|------|---------|
| HMMU allows S4 write to C4 page | Catastrophic | Very low | Hard | Mask-locked invariants + formal P-HMMU-01; OQ-HMMU-001 gate |
| 0.85 threshold altered in software | Catastrophic | Impossible | — | Threshold is mask-metal constant |
| GDSII tampering post-CCR | Critical | Low | Medium | SHA-256 + three-of-three signature + three-node notarization |
| PDK tampering | Critical | Low | Medium | PDK hash escrow; lot rejected on mismatch |
| Side-channel attack on virtue operators | High | Medium | Medium | HMMU read-only snoop lane + power-masked CAM |
| HBM3e bit rot | Moderate | Medium | Low | SECDED + scrub + quarantine |
| Foundry single-source dependency | Moderate | Medium | Medium | Second-source commitments; escrow |
| Counterfeit inbound chiplet | Critical | Low | Medium | KGD provenance check + serial whitelisting |
| Thermal runaway | Critical | Low | Medium | On-die thermal diodes + HMMU-coordinated throttle |
| Owl key compromise | Critical | Low | High | Key rotation policy + HSM + multi-party signing |

### 3.2 Residual risk acceptance

Residual risks are reviewed quarterly by the CCR committee. Any new risk rated "Hard" blocks `TAPEOUT_LOCKED` until mitigation is in place.

---

## 4 — Change Control (GAMP 5 §8)

Two change-control classes:

### 4.1 Editorial CCR

Documentation edits, typo fixes, clarifications that do not change silicon or firmware behavior. Requires:
- Single cell-owner signature.
- Log entry on `gaiaftcl.lithography.ccr.editorial`.

### 4.2 Architectural CCR

Any change that touches RTL, firmware, ABI, or the Xvqbit ISA. Requires:
- Three cell-owner signatures (Lithography + Fusion + Health).
- Updated regression pass (RG-L-*, IQ-L-*, P-HMMU-*).
- OQ + PQ re-qualification on the next production lot.
- Log entry on `gaiaftcl.lithography.ccr.architectural`.

Architectural CCRs are immutable once signed — their hash is notarized to the Franklin Guardian ledger.

---

## 5 — Electronic Records (21 CFR Part 11)

Every GaiaLithography NATS event is an electronic record. Part-11 compliance is delivered via:

1. **Identification:** each record is signed by the publisher's Owl Protocol secp256k1 key (`publisher_pubkey_fp` field in LithoPrimitive).
2. **Integrity:** `crc32c` over the payload, plus 64-byte ECDSA signature in the NATS header for audit-grade subjects.
3. **Audit trail:** full event ring persisted to the Franklin Guardian ledger; immutable append-only.
4. **Record retention:** 10 years minimum for fab events; indefinite for GDSII hashes and CCRs.
5. **Access control:** subjects routed through the NATS account hierarchy; only authorized roles can subscribe to `gaiaftcl.lithography.hmmu_breach.>` and `gaiaftcl.lithography.tapeout.>`.
6. **Time accuracy:** timestamps derived from a GNSS-disciplined oscillator on the lithography fab floor, published hourly for audit.

---

## 6 — Training & Roles

| Role | Responsibilities | Training requirement |
|------|------------------|---------------------|
| Cell Operator | Lot bring-up, MOORED→SHIPPED drive | GaiaLithography SOP-001..007 |
| Physical-Design Engineer | Floorplan through SIGNOFF | GAMP 5 Cat 5 training + OpenROAD certification |
| Signoff Engineer | STA / IR / EM signoff | GAMP 5 Cat 5 + foundry-specific signoff deck |
| CCR Signer (cell owner) | Architectural CCR approvals | GAMP 5 management-level + FoT8D constitution training |
| Fab QA | IQ/OQ/PQ execution and records | GAMP 5 Cat 5 + ISO 9001 lead auditor preferred |
| FA Engineer | Root-cause analysis | Standard FA + GAMP 5 Cat 5 deviation-handling training |

Training records are electronic records; they are subject to the same Part-11 controls as fab events.

---

## 7 — Periodic Review

- **Lot review:** every production lot reviewed at exit, producing a lot-closeout record on `gaiaftcl.lithography.fab.closeout`.
- **Quarterly quality review:** CCR committee reviews OQ/PQ trends, risk matrix, open deviations.
- **Annual product review:** per GAMP 5 §13; cross-cell impact assessment.
- **Revalidation trigger:** any Architectural CCR; any foundry PDK major update; any HMMU property re-proof failure; any three consecutive lots missing first-pass yield target.

---

## 8 — Deviation Handling

Every deviation produces a LithoPrimitive on `gaiaftcl.lithography.deviation.>`. Flow:

1. Capture: event emitted at the moment of deviation.
2. Triage: FA engineer assigns class (MINOR / MAJOR / CRITICAL) within 24 h.
3. Investigation: root-cause analysis within 10 business days.
4. CAPA (Corrective And Preventive Action): recorded and tracked to closure.
5. Trend analysis: quarterly review for recurring patterns.

A MAJOR or CRITICAL deviation on an HMMU property re-opens the OQ gate for the affected lot.

---

## 9 — Cross-References

- Process flow (manufacturing actions per stage): [`FAB_PROCESS_FLOW.md`](FAB_PROCESS_FLOW.md)
- HMMU OQ test catalog: [`HMMU_SPECIFICATION.md`](HMMU_SPECIFICATION.md) §8
- Event record format: [`LITHO_PRIMITIVE_ABI.md`](LITHO_PRIMITIVE_ABI.md)
- Governance across cells: `/DESIGN_SPECIFICATION.md` (repo root)

---

*GaiaLithography is the cell where the FoT8D substrate acquires its physical form. GAMP 5 Category 5 discipline is non-negotiable — everything above this cell (GaiaFusion, GaiaHealth, Franklin Guardian) trusts this compliance posture as an axiom.*
