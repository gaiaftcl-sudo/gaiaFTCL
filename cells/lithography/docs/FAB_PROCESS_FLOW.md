# M8 Fab Process Flow

**Document ID:** GL-FAB-001
**Revision:** 1.0
**Parent:** [`DESIGN_SPECIFICATION.md`](DESIGN_SPECIFICATION.md)
**Controlled item:** CI-M8-FAB
**Classification:** Manufacturing procedure. Reviewed jointly by GaiaLithography cell owner and the engaged foundry. Changes require a revalidation lot.

---

## 0 — Purpose

This document defines the end-to-end manufacturing flow from RTL freeze through packaged, tested, and shipped silicon for all three M8 tiers. It is the instruction set the foundry, OSAT (outsourced semiconductor assembly and test), and GaiaLithography fab operations team use to produce a qualified M8 lot.

Every step has an owner, a pass criterion, a rejection state, and a NATS event emitted as a `LithoPrimitive(event_class=FAB_STEP)`.

---

## 1 — Overall Flow Diagram

```
       ┌────────────┐
       │  IDLE      │
       └─────┬──────┘
             │ owl_bind
       ┌─────▼──────┐
       │  MOORED    │
       └─────┬──────┘
             │ pdk_freeze
       ┌─────▼──────┐
       │ PDK_BOUND  │
       └─────┬──────┘
             │ floorplan_commit
       ┌─────▼──────┐
       │ FLOORPLAN  │
       └─────┬──────┘
             │ pnr_complete
       ┌─────▼──────┐
       │  ROUTED    │
       └─────┬──────┘
             │ sta_clean & drc_clean & lvs_clean
       ┌─────▼──────┐        mask_failure
       │  SIGNOFF   ├───────────────────┐
       └─────┬──────┘                   │
             │ ccr_signed               ▼
       ┌─────▼──────┐             ┌──────────────┐
       │ TAPEOUT_   │             │MASK_REJECTED │──→ back to FLOORPLAN
       │ LOCKED     │             └──────────────┘
       └─────┬──────┘
             │ wafer_out
       ┌─────▼──────┐
       │  SHIPPED   │
       └────────────┘

  Any state ──hmmu_fail──→ HMMU_BREACH (safety terminal)
```

---

## 2 — Stage Definitions

### 2.1 IDLE → MOORED

**Owner:** GaiaLithography cell operator.

**Activities:**
- Operator presents an Owl Protocol identity to the fab orchestrator.
- Orchestrator verifies the key against the fab's eFuse-backed public-key directory.
- Cell lot record is created; `lot_id` assigned (monotonic).

**Pass criterion:** Owl signature verified; identity whitelisted for the intended tier.

**NATS event:** `gaiaftcl.lithography.fab.moor`, `event_code=0x01`.

**On reject:** remain in IDLE; publish `event_code=0xFF` with reason string.

### 2.2 MOORED → PDK_BOUND

**Owner:** GaiaLithography + engaged foundry (TSMC / GlobalFoundries / SkyWater).

**Activities:**
- Foundry PDK version locked. Examples:
  - M8-Cell C4/NPU: **TSMC N3P 1.4a**.
  - M8-Cell S4: **TSMC N4P 2.1b**.
  - M8-Edge: **GlobalFoundries 22FDX 4.0** or **SkyWater sky130 0.22**.
- PDK hash (SHA-256 over all deck files, DRC rules, SPICE models, LEF/LIB) recorded.
- Process assumptions (Vt flavor, metal stack count, DVD/low-leakage option) committed.

**Pass criterion:** PDK hash matches the copy escrowed in GaiaLithography's compliance vault.

**NATS event:** `gaiaftcl.lithography.fab.pdk_bound`, payload carries `pdk_hash`.

**On reject:** MASK_REJECTED if the PDK hash diverges from escrow (indicates tampering).

### 2.3 PDK_BOUND → FLOORPLAN

**Owner:** GaiaLithography physical-design team.

**Activities:**
- Block-level floorplan committed per chiplet (S4 cluster, C4 tensor, NPU, HMMU).
- Power-domain and clock-domain boundaries drawn.
- Die area budget met (see per-chiplet area in [`M8_CHIPLET_IP_PORTFOLIO.md`](M8_CHIPLET_IP_PORTFOLIO.md)).
- μbump array registered against the Torsion interposer landing grid ([`TORSION_INTERPOSER.md`](TORSION_INTERPOSER.md)).

**Tooling:** OpenROAD `floorplan` flow + Magic VLSI for interposer planning.

**Pass criterion:**
- Utilization target 60–70 % per block.
- No DRC violation at floorplan level.
- μbump pitch compliance (20 μm rev 1).

**NATS event:** `gaiaftcl.lithography.fab.floorplan`.

### 2.4 FLOORPLAN → ROUTED

**Owner:** GaiaLithography P&R team.

**Activities:**
- Placement and global/detailed routing.
- Clock tree synthesis; OCV (on-chip variation) derating applied.
- DRC and LVS iterative closure.
- Preliminary STA at typical corner.

**Tooling:** OpenROAD `global_placement` → `detailed_placement` → `global_route` → `detailed_route`; DRC via **KLayout**; LVS via **netgen**.

**Pass criterion:** zero DRC, zero LVS, STA slack ≥ 0 at TT corner.

**NATS event:** `gaiaftcl.lithography.fab.routed`.

### 2.5 ROUTED → SIGNOFF

**Owner:** GaiaLithography signoff + foundry compliance.

**Activities:**
- Multi-corner STA (SS/TT/FF × −40/25/125 °C × V_min/V_max).
- IR-drop analysis (static + dynamic) across power grid.
- EM (electromigration) analysis on top-level power metals.
- ESD / latchup verification against foundry deck.
- Formal equivalence check between RTL and post-PR netlist.
- **HMMU formal properties P-HMMU-01 through P-HMMU-05 re-proven** on the post-PR netlist (see [`HMMU_SPECIFICATION.md`](HMMU_SPECIFICATION.md) §10.2).

**Pass criteria:**
- STA slack ≥ 0 across all corners.
- IR-drop ≤ 5 % of nominal rail voltage.
- EM under foundry limit for 10-year life.
- Formal equivalence PASS.
- HMMU property re-proof PASS on new netlist.

**NATS event:** `gaiaftcl.lithography.fab.signoff`.

**On reject:** MASK_REJECTED; return to FLOORPLAN.

### 2.6 SIGNOFF → TAPEOUT_LOCKED

**Owner:** CCR committee (GaiaLithography + GaiaFusion + GaiaHealth cell owners).

**Activities:**
- GDSII file generated.
- SHA-256 of the GDSII computed and recorded.
- CCR (Change Control Record) signed by all three cell owners.
- Signatures attached to a `LithoPrimitive(event_class=TAPEOUT)`.

**Pass criterion:** three valid secp256k1 signatures from whitelisted cell-owner keys.

**NATS event:** `gaiaftcl.lithography.tapeout.locked`.

After this point the GDSII hash is **immutable**. Any modification, even a whitespace change to the file, produces a new hash and forces the lot to re-enter SIGNOFF.

### 2.7 TAPEOUT_LOCKED → SHIPPED

**Owner:** Foundry + OSAT.

**Activities:**
- GDSII release to foundry via the foundry's secure customer-ID channel.
- Mask-making, lithography, etch, metallization — standard foundry flow.
- Wafer-level KGD test (see [`TORSION_INTERPOSER.md`](TORSION_INTERPOSER.md) §8.1).
- Interposer assembly (CoWoS-L) at TSMC back-end or licensed OSAT.
- Package-level test (PLT): power-on, JTAG, Ethernet link-up, HMMU-BIST suite.
- Final marking, serialization, shipping to GaiaLithography's fulfillment hub.

**Pass criterion:** every packaged unit passes PLT. Failing units are scrapped or returned for root-cause analysis.

**NATS event:** `gaiaftcl.lithography.fab.ship`, payload carries unit serial number.

---

## 3 — Operational Qualification (OQ) Gate

Before the lot exits TAPEOUT_LOCKED, an **OQ batch** of at least 30 units from the engineering wafer must pass the full OQ test suite. Failure of any OQ test block holds the lot at SIGNOFF until root-caused.

OQ test modules:

| Suite | Document reference |
|-------|-------------------|
| HMMU-OQ-01..07 | [`HMMU_SPECIFICATION.md`](HMMU_SPECIFICATION.md) §8 |
| Chiplet BIST | [`M8_CHIPLET_IP_PORTFOLIO.md`](M8_CHIPLET_IP_PORTFOLIO.md) (per chiplet §) |
| Interposer coupon | [`TORSION_INTERPOSER.md`](TORSION_INTERPOSER.md) §8.3 |
| Xvqbit ISA regression | [`M8_ISA.md`](M8_ISA.md) (run full opcode sweep) |
| LithoPrimitive RG / IQ | [`LITHO_PRIMITIVE_ABI.md`](LITHO_PRIMITIVE_ABI.md) §3 |
| Thermal soak | 96 h at 90 % TDP; failure rate ≤ 50 ppm |
| Burn-in | 168 h at 1.1× V_nominal, 110 °C; target failure rate ≤ 100 ppm |

---

## 4 — Performance Qualification (PQ) Gate

PQ is performed on the **first production lot** of each tier and mirrors the live workload the cell will run:

- **GaiaFusion workload:** 72-hour continuous 50 kHz tokamak poloidal-coil invariant evaluation.
- **GaiaHealth workload:** 72-hour molecular-dynamics therapeutic-discovery sweep at 10 Hz frame rate.
- **Franklin Guardian workload:** 1 M identity-binding operations per hour for 24 h.
- **Mixed workload:** all three simultaneously for 24 h.

**Pass criteria:**
- Zero HMMU breaches (B-CROSS, B-UCE, B-PARITY) in the 24 h mixed run.
- C4 tick-rate jitter ≤ 200 ns (99.99 %-ile).
- NPU publish latency ≤ 80 ns (99.99 %-ile) end-to-end from C4 comparator assertion.
- Thermal within spec across the full workload.

PQ failure blocks product launch for that tier; the lot is diverted to engineering-sample supply only.

---

## 5 — Supply Chain

### 5.1 Primary suppliers

| Service | Primary | Second source |
|---------|---------|---------------|
| N3P wafer | TSMC Fab 18 (Tainan) | — (single source at N3P) |
| N4P wafer | TSMC Fab 12A (Hsinchu) | Samsung SF4 (rev 2) |
| 22FDX wafer | GlobalFoundries Fab 1 (Dresden) | — |
| sky130 wafer | SkyWater Technology (Bloomington, MN) | — |
| HBM3e | SK Hynix M16 (Icheon) | Micron B58R (Boise) |
| CoWoS-L assembly | TSMC AP6 | ASE Group (Kaohsiung) |
| Final test (FT) | ASE Group | Amkor Technology |
| Organic substrate | Ibiden (Japan) | Unimicron (Taiwan) |
| Cu-W heat lid | Mitsui Mining | Hitachi Metals |

### 5.2 Sovereign-supply constraint

At least one of the second-source vendors for each critical material must be located in a GaiaLithography-aligned jurisdiction (EU, US, Japan, South Korea, or Taiwan). No single-nation dependency in the critical path. This is an **operational constraint** for GaiaLithography, not a technical spec — but it is enforced via the lot-acceptance process.

### 5.3 Escrow

- PDK copies are escrowed at the GaiaLithography compliance vault (off-site, encrypted).
- GDSII hashes are replicated to three geographically distinct notarization nodes (FoT8D Franklin Guardian substrate).
- Foundry customer-ID credentials are stored in an HSM with dual-control access.

---

## 6 — Yield Targets

| Tier | First-pass yield target | Mature-yield target |
|------|-------------------------|---------------------|
| M8-Edge | 85 % at 6 months | ≥ 95 % |
| M8-Cell | 55 % at 6 months | ≥ 80 % |
| M8-Core | 40 % at 6 months | ≥ 65 % (dominated by stitch yield) |

Yield is recorded at every test gate (wafer sort → KGD → post-assembly → package test → final test) and published on `gaiaftcl.lithography.fab.yield` at the end of each lot.

---

## 7 — Failure Analysis (FA) Loop

Units that fail at OQ or PQ are diverted to the FA lab. Standard FA flow:

1. Electrical retest to confirm failure mode.
2. Non-destructive analysis: X-ray, acoustic microscopy.
3. Destructive decap + scanning electron microscopy if needed.
4. Root cause categorized as: DESIGN / PROCESS / SUPPLY / ASSEMBLY.
5. Corrective action attached to the CCR for the next lot.

FA turnaround target: ≤ 10 business days from fail to root-cause report.

---

## 8 — Regulatory & Compliance

- **GAMP 5** Category 5 lifecycle: fully custom-computed system. See [`GAMP5_LIFECYCLE.md`](GAMP5_LIFECYCLE.md) for the formal V-model mapping.
- **ISO 9001** quality management at the OSAT.
- **IATF 16949** (automotive variant) for M8-Cell units destined for AV / surgical-robotics use.
- **IEC 62443** (industrial cyber) for fab-floor controller deployments.
- Export control: GaiaLithography M8 silicon is subject to **US ECCN 3A090** review when destined for entities in restricted jurisdictions. The cell operator is responsible for pre-shipment screening.

---

## 9 — Cross-References

- PDK details and chiplet specs: [`M8_CHIPLET_IP_PORTFOLIO.md`](M8_CHIPLET_IP_PORTFOLIO.md)
- Package assembly: [`TORSION_INTERPOSER.md`](TORSION_INTERPOSER.md)
- OQ gate details: [`HMMU_SPECIFICATION.md`](HMMU_SPECIFICATION.md) §8
- Audit lifecycle: [`GAMP5_LIFECYCLE.md`](GAMP5_LIFECYCLE.md)
- Event payload format: [`LITHO_PRIMITIVE_ABI.md`](LITHO_PRIMITIVE_ABI.md)

---

*Every wafer that leaves the foundry has a full provenance chain: Owl identity → PDK hash → GDSII hash → CCR signatures → OQ pass → PQ pass → unit serial. If any link is missing, the unit is not saleable.*
