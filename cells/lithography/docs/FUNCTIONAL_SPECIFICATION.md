# GaiaLithography — Functional Specification

**Document ID:** GL-FS-001
**Revision:** 1.0
**Parent:** [`DESIGN_SPECIFICATION.md`](DESIGN_SPECIFICATION.md)
**Classification:** Functional contract. The V-model FS layer between URS and DS.

---

## 0 — Purpose

The Functional Specification defines **what** the GaiaLithography cell does at the level of observable behavior — independent of how it is implemented. Every statement here is testable from outside the silicon package via NATS subjects, register reads, or structural measurement.

This document is the authoritative reference for downstream validation: anything not enumerated here is out of scope for the cell.

---

## 1 — Actors and Boundaries

### 1.1 External actors

| Actor | Interface | Role |
|-------|-----------|------|
| GaiaFusion cell | NATS (`gaiaftcl.lithography.tensor.>`), Xvqbit ISA | Consumer of tensor tick events and C4 compute |
| GaiaHealth cell | NATS, Xvqbit ISA | Consumer of tensor ticks for MD simulation |
| Franklin Guardian cell | NATS (audit subjects), Owl Protocol signing | Audit and identity gateway |
| Cell operator (human) | GaiaLithography console; Owl identity | Lot management |
| Foundry | PDK delivery; GDSII ingress; KGD wafer certs | Manufacturing |
| OSAT | Assembled package egress | Assembly and test |

### 1.2 System boundary

The cell boundary is the outer shell of the M8 package (BGA/LGA pads on M8-Cell; SHV/OCP rails on M8-Core; QFN/BGA pads on M8-Edge) plus the GaiaLithography fab-floor orchestrator and its Owl-Protocol credentialing system.

Everything outside this boundary (motherboard, power supply, datacenter rack, network fabric) is **not** part of the cell. The cell provides contractual guarantees to the outside world through the interfaces in §1.1.

---

## 2 — Functional Requirements (FR)

### 2.1 Compute functions

- **FR-C-01:** The cell SHALL execute any valid RV64GCV program on the S4 chiplet without modification.
- **FR-C-02:** The cell SHALL execute any valid Xvqbit instruction (opcode map in `M8_ISA.md` §2) with the semantics declared therein.
- **FR-C-03:** The C4 chiplet SHALL complete a tensor tick within 20 μs at the 50 kHz target rate.
- **FR-C-04:** The cell SHALL expose the `vchip_*` MCP tool surface (via NPU+S4 cooperation) bit-identically to the GAIA-1 Virtual Chip simulator.

### 2.2 Memory functions

- **FR-M-01:** The cell SHALL provide a single unified memory pool addressable by S4, C4, and NPU chiplets, mediated by the HMMU.
- **FR-M-02:** The cell SHALL guarantee that no S4 instruction sequence produces a write to a page whose owner token is not `S4_RW` or `UNOWNED`.
- **FR-M-03:** The cell SHALL signal uncorrectable ECC events within 80 ns by transitioning the affected page to `QUARANTINE` and publishing a `gaiaftcl.lithography.hmmu_breach` event.

### 2.3 I/O functions

- **FR-I-01:** The NPU chiplet SHALL provide 4 × 100 GbE PHY (M8-Cell), 1 × 10 GbE (M8-Edge), or per-cell equivalent (M8-Core).
- **FR-I-02:** The NPU SHALL sustain 10 M NATS messages/sec parsing at wire speed without waking the S4.
- **FR-I-03:** The NPU SHALL complete an Owl Protocol secp256k1 sign-or-verify in ≤ 40 ns.

### 2.4 Safety functions

- **FR-S-01:** The 0.85 truth threshold SHALL be a mask-metal constant and SHALL NOT be modifiable by software.
- **FR-S-02:** The HMMU SHALL emit a NATS breach event within 80 ns of detecting any unauthorized cross-owner access.
- **FR-S-03:** The cell SHALL self-halt if the HMMU OTT parity check fails.
- **FR-S-04:** Any failed boot handshake SHALL leave the package non-operational until a signed recovery sequence is applied.

### 2.5 Lifecycle functions

- **FR-L-01:** The cell SHALL progress through states IDLE → MOORED → PDK_BOUND → FLOORPLAN → ROUTED → SIGNOFF → TAPEOUT_LOCKED → SHIPPED per `FAB_PROCESS_FLOW.md`.
- **FR-L-02:** The cell SHALL transition to MASK_REJECTED on any signoff failure and return to FLOORPLAN.
- **FR-L-03:** The cell SHALL transition to HMMU_BREACH (safety terminal) on any hard breach during OQ and SHALL NOT tape out.
- **FR-L-04:** Every state transition SHALL emit a `LithoPrimitive(event_class=FAB_STEP)` on the appropriate NATS subject.

### 2.6 Event / audit functions

- **FR-A-01:** The cell SHALL publish every HMMU breach, fab-step, tape-out, tensor snapshot, and thermal event on the subject taxonomy defined in `LITHO_PRIMITIVE_ABI.md` §5.
- **FR-A-02:** Every event SHALL carry an Owl Protocol publisher fingerprint and a CRC-32C integrity field.
- **FR-A-03:** The cell SHALL retain a 1024-entry on-die event ring readable by the S4 without wake of the C4 chiplet.

---

## 3 — State Machine (Formal)

### 3.1 States

```
{IDLE, MOORED, PDK_BOUND, FLOORPLAN, ROUTED, SIGNOFF,
 TAPEOUT_LOCKED, SHIPPED, MASK_REJECTED, HMMU_BREACH}
```

### 3.2 Legal transitions

```
IDLE            --owl_bind-->           MOORED
MOORED          --pdk_freeze-->         PDK_BOUND
PDK_BOUND       --floorplan_commit-->   FLOORPLAN
FLOORPLAN       --pnr_complete-->       ROUTED
ROUTED          --signoff_clean-->      SIGNOFF
SIGNOFF         --ccr_signed-->         TAPEOUT_LOCKED
TAPEOUT_LOCKED  --wafer_out-->          SHIPPED
SIGNOFF         --signoff_fail-->       MASK_REJECTED
MASK_REJECTED   --rework-->             FLOORPLAN
{any}           --hmmu_fail_oq-->       HMMU_BREACH   (sticky)
```

### 3.3 Forbidden transitions

- No direct MOORED → ROUTED (PDK must be bound before routing).
- No direct ROUTED → TAPEOUT_LOCKED (signoff is required).
- No exit from HMMU_BREACH (safety terminal; lot scrapped).
- No SHIPPED → anything (terminal success).

### 3.4 Event emission

Every transition emits exactly one `LithoPrimitive(event_class=FAB_STEP)` with:
- `event_code` = transition-specific code.
- `tick_id` = monotonic lot tick counter.
- `timestamp_ns` = GNSS-disciplined fab-floor time.

---

## 4 — Control Flows

### 4.1 Normal tensor-tick flow (runtime)

1. **Telemetry ingress.** External sensor publishes a NATS message targeting `gaiaftcl.*.heartbeat`.
2. **NPU parse.** NPU subject-parser matches the subject, allocates an HBM page with token `NPU_RW`, DMAs payload in.
3. **Hand-off.** NPU issues `TOK_TRANSITION(NPU_RW→C4_RW)`. HMMU flips token and raises C4 ready line.
4. **C4 tick.** C4 claims the range, reads tensor state, contracts, asserts truth-threshold line.
5. **Publish.** NPU publishes `gaiaftcl.lithography.tensor.*` with the LithoPrimitive snapshot within 40 ns of C4 assertion.
6. **Release.** C4 issues `TOK_RELEASE`. HMMU flips to `NPU_RO` / `S4_RO`.
7. **Audit snoop.** S4 reads the snapshot via the read-only snoop lane; no write, no ownership flip.

Whole-loop wall-clock target: **≤ 20 μs** at 50 kHz.

### 4.2 Breach flow

1. S4 (or any non-owner chiplet) issues a write against a page it does not own.
2. HMMU port drops the write before any HBM3e toggle.
3. HMMU writes a BLOG entry, flips token to `BREACH` (sticky).
4. Dedicated breach wire signals NPU; NPU publishes `gaiaftcl.lithography.hmmu_breach.*` within 80 ns.
5. If `FATAL_ON_BREACH` set, S4 receives `SIGBUS` and offending process is terminated.
6. Lot subsystem increments `hmmu_breach_count` counter; if OQ is active, test marked FAIL.

### 4.3 Fab-step advance

1. Cell operator triggers the next step via the GaiaLithography console.
2. Console signs the command with the operator's Owl key.
3. Orchestrator verifies signature, validates preconditions, and publishes a `LithoPrimitive(FAB_STEP)`.
4. Any downstream subscriber (audit, QA, CCR notary) captures the event for record.

### 4.4 Mask rejection

1. SIGNOFF check fails (STA negative slack; DRC nonzero; HMMU property re-proof fails).
2. Orchestrator transitions to `MASK_REJECTED`; publishes `gaiaftcl.lithography.mask_rejected.*` with a root-cause code.
3. Corrective action is attached to an editorial CCR (if minor) or architectural CCR (if RTL change).
4. Lot returns to `FLOORPLAN`.

### 4.5 Tape-out lock

1. SIGNOFF succeeds; GDSII is frozen and SHA-256 computed.
2. Three-of-three CCR signatures gathered over the hash.
3. Orchestrator publishes `gaiaftcl.lithography.tapeout.locked` with signatures embedded in the LithoPrimitive `tapeout` union.
4. Hash replicated to three Franklin Guardian notarization nodes.
5. Foundry release gate opens; wafer release authorized.

---

## 5 — Interfaces

### 5.1 NATS subject tree (authoritative)

See `LITHO_PRIMITIVE_ABI.md` §5. Summary:

| Root | Purpose |
|------|---------|
| `gaiaftcl.lithography.fab.*` | Lifecycle transitions |
| `gaiaftcl.lithography.hmmu_breach.*` | Safety-critical breaches |
| `gaiaftcl.lithography.tensor.*` | C4 snapshots |
| `gaiaftcl.lithography.thermal.*` | Chiplet temperature / power |
| `gaiaftcl.lithography.tapeout.*` | Mask-locking events |
| `gaiaftcl.lithography.mask_rejected.*` | Rejection records |
| `gaiaftcl.lithography.oq.*` / `.pq.*` | Qualification results |
| `gaiaftcl.lithography.ccr.*` | Change-control records |
| `gaiaftcl.lithography.deviation.*` | GAMP 5 deviations |
| `gaiaftcl.lithography.boot.*` | Boot handshakes |

### 5.2 ISA interface

Xvqbit — full opcode map in `M8_ISA.md`. Discovery via `misa` bit 21 and `mvqbit_caps` CSR.

### 5.3 MCP tool interface

S4 firmware exposes the same seven MCP tools as the GAIA-1 Virtual Chip simulator, routed to Xvqbit opcodes:

```
vchip_init         → vq.init + vq.bondset
vchip_run_program  → vq.run
vchip_collapse     → vq.collapse
vchip_bell_state   → vq.bell
vchip_grover       → vq.grover
vchip_coherence    → vq.coherence
vchip_status       → vq.status
```

### 5.4 HTTP fallback

For operator / debug use, an HTTP/JSON gateway mirrors the MCP tool surface on a private management interface. This gateway is **disabled by default** and must be explicitly enabled by the operator via a signed Owl command. It is not available on production field units.

### 5.5 PHY interfaces

| Tier | External PHY |
|------|--------------|
| M8-Edge | 1 × 10 GbE (or BLE for wearables) |
| M8-Cell | 4 × 100 GbE (optional 1 × 400 GbE) |
| M8-Core | 8 × 100 GbE or 2 × 400 GbE; optional CI-M8-PHOT optical |

### 5.6 Debug interface

JTAG / cJTAG on a dedicated test-pad ring. Gated by an Owl-signed debug token. Production units have the debug ring blown via eFuse.

---

## 6 — Functional Timing Budget

| Operation | Target | Allocation |
|-----------|--------|------------|
| S4 instruction retire (typical) | 0.4 ns | 2.5 GHz CVA6 |
| C4 tensor tick (50 kHz) | 20 μs | 64 cycles × 300 ns including memory fetch |
| HMMU owner-token check | 2 ns | Single-cycle OTT lookup @ 2 GHz |
| NPU breach publish (detect to wire) | 80 ns | OTT lookup + crypto + PHY |
| NPU message ingest (parse to HBM) | 200 ns | Subject parser + DMA |
| Owl sign/verify (secp256k1) | 40 ns | Crypto accelerator pipeline |
| Boot handshake (cold) | 5 ms | ROM stage-0 + chiplet handshakes |
| Xvqbit `vq.step` issue-to-ready | ≤ 200 ns | Reservation station + HMMU gating |

---

## 7 — Non-Functional Requirements (NFR)

- **NFR-P-01 (Performance):** Aggregate C4 tensor throughput ≥ 12 TFLOPs bf16 (M8-Cell).
- **NFR-P-02:** NATS publish latency 99.99 %-ile ≤ 80 ns on breach events.
- **NFR-P-03:** Jitter on C4 tick period ≤ 200 ns (99.99 %-ile) at 50 kHz.
- **NFR-R-01 (Reliability):** M8-Cell MTBF ≥ 50,000 h; M8-Core ≥ 100,000 h (redundant).
- **NFR-R-02:** Post-burn-in infant-mortality ≤ 100 ppm.
- **NFR-S-01 (Security):** No side-channel bit leakage from `C4_RO` virtue matrices under standardized Spectre/Meltdown PoCs.
- **NFR-S-02:** All external event streams are authenticated by Owl Protocol secp256k1.
- **NFR-T-01 (Thermal):** Junction ≤ 95 °C at rated TDP (M8-Cell), ≤ 95 °C (M8-Core with liquid cooling), ≤ 110 °C (M8-Edge passive).
- **NFR-C-01 (Compliance):** GAMP 5 Category 5, 21 CFR Part 11, ISO 9001, IATF 16949 for AV-targeted units.
- **NFR-U-01 (Usability):** ISA is bit-compatible with the GAIA-1 Virtual Chip simulator so every vChip-targeted binary runs unmodified on silicon.

---

## 8 — Traceability

Every FR in §2 traces to:
- At least one DS section (in `DESIGN_SPECIFICATION.md`, `M8_CHIPLET_IP_PORTFOLIO.md`, `HMMU_SPECIFICATION.md`, `TORSION_INTERPOSER.md`, `M8_ISA.md`, or `LITHO_PRIMITIVE_ABI.md`).
- At least one OQ or PQ test in `FAB_PROCESS_FLOW.md`.
- A GAMP 5 V-model artifact in `GAMP5_LIFECYCLE.md`.

The traceability matrix is maintained in `cells/lithography/qualification/traceability_matrix.md` and is updated under change control with each FR-impacting revision.

---

## 9 — Out of Scope

Explicitly **not** covered by this FS:
- Motherboard and enclosure design (consumer cells' responsibility).
- Datacenter-level orchestration (handled by operator infrastructure).
- Operator training curriculum beyond role definitions (see `GAMP5_LIFECYCLE.md` §6).
- Application-level workloads (handled by GaiaFusion, GaiaHealth, Guardian cells).
- Legal-framework scaffolding for sovereign-entity deployments (Franklin Guardian responsibility).

---

## 10 — Cross-References

- URS: [`DESIGN_SPECIFICATION.md`](DESIGN_SPECIFICATION.md) §1–3
- DS: [`M8_CHIPLET_IP_PORTFOLIO.md`](M8_CHIPLET_IP_PORTFOLIO.md), [`HMMU_SPECIFICATION.md`](HMMU_SPECIFICATION.md), [`TORSION_INTERPOSER.md`](TORSION_INTERPOSER.md)
- ISA: [`M8_ISA.md`](M8_ISA.md)
- Event data: [`LITHO_PRIMITIVE_ABI.md`](LITHO_PRIMITIVE_ABI.md)
- Process: [`FAB_PROCESS_FLOW.md`](FAB_PROCESS_FLOW.md)
- Compliance: [`GAMP5_LIFECYCLE.md`](GAMP5_LIFECYCLE.md)

---

*This Functional Specification is the "what" of the cell. Every downstream test artifact is derived from an FR or NFR enumerated here.*
