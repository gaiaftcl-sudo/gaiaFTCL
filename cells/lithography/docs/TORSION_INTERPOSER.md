# Torsion Interposer Specification

**Document ID:** GL-TORSION-001
**Revision:** 1.0
**Parent:** [`DESIGN_SPECIFICATION.md`](DESIGN_SPECIFICATION.md)
**Controlled item:** CI-M8-TORSION
**Classification:** Package-level substrate. Any change to micro-bump pitch, stack-up, or bandwidth budget requires unanimous CCR.

---

## 0 — Purpose

The **Torsion Interposer** is the proprietary 2.5D / 3D die-stitching substrate on which all M8 chiplets are assembled. It is the GaiaLithography analog of Apple's UltraFusion and TSMC's CoWoS-L — but tuned specifically for the deterministic-latency requirements of the vQbit tensor evaluation loop.

The name "Torsion" comes from the topological property the interposer must preserve: **the die-to-die routes form a closed graph with no timing-variance cycle larger than one tensor tick**. In other words, whatever else happens on the substrate, the C4 chiplets see a jitter-bounded view of HBM3e that keeps the 50 kHz tick deterministic.

---

## 1 — Scope

The interposer hosts:

- Up to 8 S4 CVA6 compute chiplet tiles (one tile = one 4-core cluster).
- Up to 4 C4 tensor chiplets.
- Exactly 1 NPU/NATS chiplet per M8-Cell; up to 8 per M8-Core.
- 2 to 3 HBM3e stacks (M8-Cell) or 16+ HBM3e stacks pooled (M8-Core).
- 32 to 48 HMMU IP instances (one per HBM3e channel).
- Optional landing sites for CI-M8-QRNG, CI-M8-CRYO, CI-M8-PHOT.

Not hosted on the interposer: external PHY transceivers (handled by NPU), motherboard interfaces (routed to BGA/LGA pads on the substrate underside).

---

## 2 — Stack-Up

### 2.1 M8-Cell substrate (2.5D)

From bottom to top:

| Layer | Name | Material | Thickness | Function |
|-------|------|----------|-----------|----------|
| L0 | BGA/LGA balls | SAC305 solder | 0.45 mm | Motherboard interface |
| L1 | Organic substrate | ABF / BT | 0.8 mm | Power delivery, low-speed I/O fanout |
| L2 | TIV (through-interposer vias) | Copper | 0.1 mm | Interposer power feed |
| L3 | Silicon interposer base | TSMC CoWoS-L | 100 μm | Mechanical substrate |
| L4 | RDL (redistribution) | Cu / low-k | 4 layers, 6 μm total | High-speed die-to-die routes |
| L5 | μBump layer | SnAg | 20 μm pitch | Chiplet attach |
| L6 | Chiplet KGD | — | — | S4 / C4 / NPU / HBM3e |
| L7 | Heat-spreader lid | Cu-W alloy | 1.2 mm | Thermal cap (integrated vapor chamber) |

Overall package thickness target: **3.6 mm** ± 0.15 mm.

### 2.2 M8-Core substrate (2.5D + 3D stitch)

M8-Core stitches multiple M8-Cell packages. The stitch is implemented as:

- Base: custom reinforced organic substrate (150 mm × 150 mm, 8-layer).
- Mid: multiple CoWoS-L tiles sharing a **bridge die** ("Torsion bridge") that carries die-to-die lanes at ≥ 2.5 TB/s per stitch.
- Top: shared integrated heat-spreader with cold-plate mounting bosses (OCP-standard).

The Torsion bridge is itself a passive silicon die (no transistors, only interconnect) fabricated on TSMC N16 — the cheapest node that still supports the μbump pitch required.

### 2.3 M8-Edge substrate

M8-Edge has **no interposer**. The monolithic die is attached directly to an organic 10 mm × 10 mm BGA via standard flip-chip bumping. This is how the M8-Edge hits the sub-$5 cost target.

---

## 3 — Micro-Bump Specification

| Parameter | Value | Notes |
|-----------|-------|-------|
| Pitch | 20 μm | TSMC CoWoS-L reference |
| Bump diameter | 10 μm | |
| Height post-reflow | 12 μm | |
| Bump count per C4 chiplet | ~28,000 | 200 × 140 array |
| Bump count per S4 cluster | ~18,000 | 150 × 120 array |
| Bump count per HBM3e stack | 6,144 | Per JEDEC HBM3e spec |
| Bump count per NPU | ~22,000 | High PHY fanout |
| Total bumps on M8-Cell interposer | ~450,000 | Sum including power/ground |

The 20 μm pitch is the current CoWoS-L tooling limit. A migration to **CoWoS-N** (9 μm pitch) is planned for rev 2 — this enables a 4× increase in die-to-die bandwidth without growing the interposer area. Rev 1 does not require it.

---

## 4 — Bandwidth Budget

### 4.1 Aggregate interposer bandwidth

| Configuration | Aggregate | Measured bottleneck |
|---------------|-----------|---------------------|
| M8-Cell | ≥ 6.0 TB/s | Cross-sectional bandwidth across the central chiplet row |
| M8-Core | ≥ 25 TB/s pooled | Sum across all stitch bridges |

### 4.2 Per-link budget (M8-Cell)

| Link | Width | Rate | Bandwidth |
|------|-------|------|-----------|
| S4 ↔ HMMU (per cluster) | 1024 b | 6.4 GT/s | 820 GB/s |
| C4 ↔ HMMU (per chiplet) | 1024 b | 6.4 GT/s | 820 GB/s |
| NPU ↔ HMMU | 512 b | 6.4 GT/s | 410 GB/s |
| HMMU ↔ HBM3e (per channel) | 128 b | 9.6 GT/s | 153 GB/s |
| NPU ↔ C4 direct (per C4) | 64 b | 4.0 GT/s | 32 GB/s |
| HMMU control fabric | 64 b | 2.0 GT/s | 16 GB/s |
| Breach-wire (NPU ingress) | 1 b | — | 1 bit × chiplet count |

Total required: ~4.7 TB/s. Budget: 6.0 TB/s. Headroom: **27.7 %**.

### 4.3 Signal integrity

- SERDES used for inter-chiplet lanes ≥ 8 GT/s.
- Parallel LVDS for < 8 GT/s and for the dedicated breach wire.
- Crosstalk budget: < −35 dB at 3.2 GHz on adjacent 1-mm segments.
- Equalization: CTLE + 5-tap DFE on SERDES; no FFE needed at this pitch.

---

## 5 — Power Delivery

### 5.1 Rails

| Rail | Voltage | Current (M8-Cell typ) | Current (M8-Core typ) | Source |
|------|---------|----------------------|----------------------|--------|
| VDD_S4 | 0.8 V | 25 A | 200 A | Per-cluster integrated voltage regulator (IVR) |
| VDD_C4 | 0.75 V | 50 A | 400 A | Dedicated low-noise IVR per chiplet |
| VDD_NPU | 0.8 V | 15 A | 100 A | Integrated |
| VDD_HMMU | 0.8 V | 3 A | 20 A | Shared with chiplet serving it |
| VDD_HBM | 1.1 V | 5 A per stack | 5 A per stack | Board-level buck |
| VDDQ_HBM | 0.4 V | 8 A per stack | 8 A per stack | Board-level buck |
| VDD_INTERPOSER | 0.8 V | 10 A | 40 A | Powers RDL repeaters |

### 5.2 Decoupling

- Deep-trench capacitors on the interposer: 5 μF per chiplet.
- MIM capacitors in RDL: 100 nF per 1 mm² under each chiplet.
- Backside power delivery (BSPD) is **not** used in rev 1; planned for rev 3 on CoWoS-N migration.

### 5.3 Power gating

Each chiplet has an independent power gate controlled by the HMMU. If a chiplet asserts B-PARITY (HMMU fault), its gate is opened and the chiplet is quiesced; remaining chiplets continue operation. This prevents a single-chiplet fault from taking down the full package.

---

## 6 — Thermal

### 6.1 Heat-flux map (M8-Cell, 150 W TDP)

| Region | TDP | Area | Flux |
|--------|-----|------|------|
| C4 chiplets (4) | 40 W | 4 × 120 mm² = 480 mm² | 83 W/cm² |
| S4 cluster | 30 W | 160 mm² | 187 W/cm² |
| NPU | 12 W | 90 mm² | 133 W/cm² |
| HBM3e stacks | 20 W | 2 × 80 mm² | 125 W/cm² |
| HMMU array | 8 W | distributed | ~5 W/cm² |
| Passive/misc | 40 W | — | — |

### 6.2 Cooling solutions by tier

| Tier | Solution | Junction target |
|------|----------|-----------------|
| M8-Edge | Passive radiation + PCB ground plane | ≤ 110 °C at 5 W, 85 °C ambient |
| M8-Cell (datacenter) | Vapor-chamber heat-spreader + blower | ≤ 95 °C at 150 W, 35 °C inlet |
| M8-Cell (industrial floor) | Liquid cold-plate (PG25) | ≤ 85 °C at 150 W |
| M8-Core | Direct liquid cold-plate + rack CDU | ≤ 95 °C at 1 kW, 25 °C coolant |

### 6.3 Thermal sensors

Every chiplet has three embedded thermal diodes (center + two hotspots). Readings are aggregated by the NPU and published on `gaiaftcl.lithography.thermal.<chiplet_id>` at 10 Hz. If any reading exceeds the junction target, the HMMU initiates a **thermal throttle** by derating C4 tick frequency down to 25 kHz (preserving determinism at half rate). If temperature continues rising, the package power-gates the non-essential S4 clusters until thermals recover.

---

## 7 — Mechanical

### 7.1 Warpage

Maximum allowed package warpage at 25 °C: 80 μm over the diagonal. Warpage is dominated by the CTE mismatch between the silicon interposer (2.6 ppm/K) and the organic substrate (~16 ppm/K); controlled by:

- Balanced Cu density on every RDL layer (min 40 %, max 60 %).
- Stiffener ring bonded to the substrate edges.
- Controlled-collapse BGA reflow profile.

### 7.2 Drop / shock

M8-Cell is qualified to JEDEC JESD22-B111 Level-III (industrial drop test). M8-Core is not portable and is not drop-qualified; it is rack-integrated.

### 7.3 Socketing

M8-Cell LGA variant uses a custom 2,048-pin socket compatible with a standard ILM (independent loading mechanism). Socket vendors: Foxteq (primary), Lotes (second source).

---

## 8 — Test & Bring-Up

### 8.1 Known-good die (KGD) qualification

No chiplet is attached to the interposer until it has passed full wafer-level KGD test. This is mandatory for die-stitching cost control: a single bad chiplet on an assembled interposer wastes the entire substrate.

- S4: functional + scan + PLL lock + BIST of CVA6 pipelines.
- C4: SRAM BIST (48 MB) + tensor ALU vector sweep + truth-threshold comparator calibration.
- NPU: Ethernet PHY BER ≤ 1e-12 at 100 Gbps + crypto self-test.
- HBM3e: vendor KGD certificate + local ECC training.

### 8.2 Post-assembly BIST

On first boot of an assembled package, the NPU runs `HMMU-BIST-01` through `HMMU-BIST-07` (the OQ suite from `HMMU_SPECIFICATION.md` §8). Any failure at this stage results in a `MASK_REJECTED` state for the unit; it is returned for analysis.

### 8.3 Interposer-only test coupon

Every wafer carries one **Torsion test coupon** — a spare interposer with loopback structures but no chiplets. The coupon is used to characterize RDL yield, TIV resistance, and micro-bump shear strength per lot.

---

## 9 — Roadmap

| Revision | Node | Key change | Target silicon date |
|----------|------|------------|---------------------|
| Rev 1 | CoWoS-L | MVP; 20 μm pitch; 6 TB/s | Q3 2027 |
| Rev 2 | CoWoS-N | 9 μm pitch; 12 TB/s | Q3 2028 |
| Rev 3 | CoWoS-N + BSPD | Backside power; lower VR droop | Q1 2029 |
| Rev 4 | TSMC SoIC-X | 3D face-to-face stack of C4 over HMMU | 2030+ |

---

## 10 — Cross-References

- Interface contract with chiplets: [`M8_CHIPLET_IP_PORTFOLIO.md`](M8_CHIPLET_IP_PORTFOLIO.md)
- Ownership protocol: [`HMMU_SPECIFICATION.md`](HMMU_SPECIFICATION.md)
- Packaging supply chain: [`FAB_PROCESS_FLOW.md`](FAB_PROCESS_FLOW.md)

---

*The Torsion Interposer is the substrate that physically realizes the FoT8D unified-memory model. Every other M8 specification assumes the interposer bandwidth and determinism properties described here.*
