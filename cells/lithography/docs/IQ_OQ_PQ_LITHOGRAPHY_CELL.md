# GaiaLithography — Review summary & IQ / OQ / PQ (Silicon Cell)

**Document ID:** GL-IQOQPQ-001  
**Revision:** 1.0  
**Parent:** [`GAMP5_LIFECYCLE.md`](GAMP5_LIFECYCLE.md) (full GAMP 5 mapping)  
**Controlled item:** CI-M8-001  

---

## 0 — Executive review (what this cell is)

**GaiaLithography** is the **silicon fabrication and qualification cell**: it holds the **architectural, physical-design, and compliance** path from **PDK + chiplet IP + interposer** through **DRC/LVS/sign-off** to **tape-out** — the substrate on which **GaiaFusion** and **GaiaHealth** are specified to run.

**Important scope split:**

| Layer | Role |
|--------|------|
| **vQbit / Xvqbit / `vQbitPrimitive`** | **Data and ISA contract** — how measurements and entropy deltas cross the S4/C4 boundary in software and in specified hardware. **One part** of the overall M8 story. |
| **GaiaLithography (this cell)** | **Full stack**: PDK binding, floorplan, route, **HMMU** (S4↔C4 memory isolation), **Torsion Interposer**, chiplet integration (S4 / C4 / NPU / HBM), **LithoPrimitive** (128 B) events, fab flow, **GAMP 5 Category 5** lifecycle. |
| **Leading-edge node (“1 nm class”)** | **PDK / process targets** (e.g. TSMC **N3P**, **N2**, and open **sky130** for bring-up) describe **where** geometry, timing, and power sign-off apply — **not** a claim that a given lot is fabricated until **TAPEOUT_LOCKED** / **SHIPPED** evidence exists for that lot. |

**Foundational equation (from cell README):** **PDK + chiplet library + torsion interposer = M8 substrate** (all three mandatory for a qualified silicon story).

---

## 1 — Installation Qualification (IQ)

IQ proves **the right artifacts, identities, and binaries are installed** before operational testing. Authoritative test IDs live in [`GAMP5_LIFECYCLE.md`](GAMP5_LIFECYCLE.md) §2.5; deliverable path: `cells/lithography/qualification/iq/`.

| ID | Purpose | Pass criterion (summary) |
|----|---------|---------------------------|
| **IQ-L-001** | PDK escrow integrity | PDK hash matches vault |
| **IQ-L-002** | GDSII ↔ CCR | GDSII hash matches signed CCR |
| **IQ-L-003** | Package whitelist | Serial in FoT8D registry |
| **IQ-L-004** | Xvqbit discoverability | `misa` bit 21 = 1 |
| **IQ-L-005** | NPU Owl key | eFuse pubkey fingerprint match |
| **IQ-L-006** | HMMU boot | OTT handshake UNOWNED path |
| **IQ-L-007** | LithoPrimitive schema | `schema_hash` matches RG-L-011 |
| **IQ-L-008** | NATS lithography subjects | `gaiaftcl.lithography.>` on boot |

---

## 2 — Operational Qualification (OQ)

OQ proves **each functional path behaves per spec** on the integrated package. Highlights (full list: [`FAB_PROCESS_FLOW.md`](FAB_PROCESS_FLOW.md) §3, [`HMMU_SPECIFICATION.md`](HMMU_SPECIFICATION.md) §8):

- **HMMU-OQ-01…07** — S4 cannot corrupt C4-owned pages; breach tests fail-closed.
- **Xvqbit opcode sweep** — per [`M8_ISA.md`](M8_ISA.md) §2.
- **Thermal / burn-in / PHY BER** — environmental and link stability (per lifecycle doc).
- **LithoPrimitive** regression group **RG-L-001…011** + IQ gates on bring-up hardware.

**Failure policy:** **HMMU_BREACH** or **MASK_REJECTED** per state machine; OQ must pass before PQ.

---

## 3 — Performance Qualification (PQ)

PQ proves **the silicon meets consuming-cell workloads** under declared concurrent load. Deliverable: `cells/lithography/qualification/pq/`. Gated per [`GAMP5_LIFECYCLE.md`](GAMP5_LIFECYCLE.md) §2.7 and [`FAB_PROCESS_FLOW.md`](FAB_PROCESS_FLOW.md) §4.

| PQ theme | Acceptance target (from lifecycle / UAT linkage) |
|----------|--------------------------------------------------|
| **GaiaFusion** | Deterministic tokamak-adjacent control path at M8-Cell tier (e.g. **≤ 200 ns** tick jitter at **50 kHz** evaluation — see lifecycle UAT wording). |
| **GaiaHealth** | Multi-hour MD / substrate workload **without HMMU breach**; reproducibility of declared leaderboard outputs across reruns. |
| **Concurrent stress** | Fusion + Health + Franklin Guardian identity binding at PQ-defined load for **24 h** minimum (per lifecycle). |
| **Owl / crypto throughput** | Guardian-facing sign-off (e.g. **≤ 40 ns** crypto op latency, **10 M ops/hour** binding — per lifecycle §2.8). |

PQ is **not** satisfied by RTL simulation alone — it requires the **qualified package** running the **combined** acceptance criteria.

---

## 4 — Receipts & records

- IQ/OQ/PQ completion → signed receipts under `cells/lithography/qualification/` (when populated).  
- Architectural changes → **three-of-three CCR** (Lithography + Fusion + Health) per [`GAMP5_LIFECYCLE.md`](GAMP5_LIFECYCLE.md) §4.  
- Electronic records: **Part 11** posture in [`GAMP5_LIFECYCLE.md`](GAMP5_LIFECYCLE.md) §5.

---

## 5 — Cross-references

| Doc | Role |
|-----|------|
| [`README.md`](../README.md) | Cell overview & state machine |
| [`GAMP5_LIFECYCLE.md`](GAMP5_LIFECYCLE.md) | Full V-model & regulatory map |
| [`FAB_PROCESS_FLOW.md`](FAB_PROCESS_FLOW.md) | Manufacturing & PQ flow detail |
| [`HMMU_SPECIFICATION.md`](HMMU_SPECIFICATION.md) | Safety block & OQ catalog |
| [`LITHO_PRIMITIVE_ABI.md`](LITHO_PRIMITIVE_ABI.md) | 128-byte event ABI |

---

*GaiaLithography — FoT8D M8 silicon fabrication substrate. Conformant with GAMP 5 Category 5. Controlled item CI-M8-001.*
