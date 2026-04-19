# M8 Tier Classifications

**Document ID:** GL-TIER-001
**Revision:** 1.0
**Parent:** [`DESIGN_SPECIFICATION.md`](DESIGN_SPECIFICATION.md)

---

## 0 — Principle

Three deployment tiers. One ISA. One memory model. One chiplet family. Tier differentiation is purely a **packaging** decision — never a redesign.

| Tier | Name | Target application | Power | Interposer stitching |
|------|------|-------------------|-------|----------------------|
| 1 | **M8-Edge** | Sensors, wearables, actuators | < 5 W | Monolithic (no interposer) |
| 2 | **M8-Cell** | Fab gateway, tokamak controller, maglev stage | 50–150 W | 2.5D SiP, single package |
| 3 | **M8-Core** | Community server, brain stem | 1000 W+ | 2.5D/3D multi-package stitched |

---

## 1 — Tier 1: M8-Edge

### 1.1 Target applications

- Smart IoT sensors (temperature, vibration, chemical)
- Localized medical wearables running the Owl Protocol
- Industrial edge sensors on the fab floor, pipeline, or grid
- Agricultural sensors (soil moisture, leaf reflectance)
- Wildfire / earthquake early-warning probes

### 1.2 Chiplet layout

Monolithic die — no interposer. Cost-optimized for volume manufacture.

| Block | Count | Notes |
|-------|-------|-------|
| S4 RISC-V E-core (3-stage in-order) | 2 | 1 GHz typical |
| C4 Tensor block (minimal) | 1 | χ ≤ 64; 4 MB SRAM |
| NPU/NATS subset | 1 | Single-subject parser, 10 GbE or BLE radio |
| LPDDR5 | 4 GB | On-package UMA |
| HMMU lite | 1 | 4-page owner-token table |

### 1.3 Function envelope

- **Does not** run the full OpenUSD simulation.
- Ingests local telemetry.
- Performs a localized tensor contraction against a **cached constraint invariant** (fetched on boot from the nearest M8-Cell).
- Fires a NATS message on the gateway link when state deviates from the invariant by more than a configured threshold.

### 1.4 Thermal

- Passive cooling only.
- Junction-to-ambient ≤ 50 °C at 5 W.
- Operating range: −40 °C to +85 °C (industrial).

### 1.5 Form factor

- 10 mm × 10 mm QFN or BGA package.
- Single-layer PCB integration feasible.

### 1.6 Unit cost target

- < $5 at 1 M units/year.
- Enables ubiquitous deployment across Gaia sensor networks.

---

## 2 — Tier 2: M8-Cell

### 2.1 Target applications

- **GaiaLithography fab gateway** — direct control of lithography tools, steppers, inspection gear.
- **GaiaFusion** — magnetic-levitation stages, tokamak poloidal-coil current control.
- **GaiaHealth** — local MD simulation, patient-side inference, OR/ICU edge compute.
- **Franklin Guardian** — the sovereign-identity gateway.
- Autonomous vehicle compute; surgical robotics; semiconductor-grade metrology.

### 2.2 Chiplet layout

2.5D SiP on the Torsion Interposer. Single package.

| Block | Count | Notes |
|-------|-------|-------|
| S4 CVA6 application core | 16 | 4 clusters × 4 cores @ 2.4 GHz |
| C4 Tensor Chiplet (full) | 4 | χ ≤ 1024; 48 MB SRAM each; 3.2 TFLOP bf16 each |
| NPU/NATS chiplet (full) | 1 | 4 × 100 GbE, Owl crypto, JetStream broker |
| HBM3e stack | 2–3 | 48–72 GB UMA; 2.4–3.6 TB/s |
| HMMU | 1 | 64 k-page owner-token table, full SECDED |
| Torsion Interposer | — | ≥ 6 TB/s aggregate |

### 2.3 Function envelope

- **Full UUM 8D vector evaluation in nanoseconds.**
- S4 cores handle the OS, logging, user-space applications, and non-critical paths.
- C4 cores constantly read the **exact same HBM3e physical addresses**, evaluating the 50 kHz state changes without memory copying.
- NPU/NATS publishes truth-threshold events on-wire with < 40 ns latency from C4 comparator assertion.

### 2.4 Thermal

- Active cooling: vapor-chamber heat-spreader + blower fan, or liquid cold-plate for datacenter variants.
- Junction-to-ambient ≤ 70 °C at 150 W.
- Operating range: 0 °C to +70 °C (commercial / datacenter).

### 2.5 Form factor

- 55 mm × 55 mm BGA or LGA package with CoWoS-L substrate.
- Standard socket form factor compatible with existing DDR5/PCIe motherboards as a drop-in upgrade.

### 2.6 Unit cost target

- < $2,000 at 100 k units/year.
- Targets the Apple Silicon price ladder while matching M4 Pro / Max performance in the C4 tensor path.

---

## 3 — Tier 3: M8-Core

### 3.1 Target applications

- Replaces Hetzner cloud racks and similar colocation compute.
- Global graph inference (the full Agentic Knowledge Graph).
- Structural OpenUSD parsing at planetary scale.
- Sovereign consensus (the FoT8D substrate's equivalent of the Bitcoin mempool but for truth claims).
- Real-time evaluation of the 275 M EUR fusion sprint telemetry.

### 3.2 Chiplet layout

Massive 2.5D/3D stitched package — multiple M8-Cell packages welded by the Torsion Interposer into a single coherent machine.

| Block | Count | Notes |
|-------|-------|-------|
| M8-Cell packages | 4 to 8 | Stitched by the Torsion Interposer (> 2.5 TB/s die-to-die) |
| Aggregate S4 CVA6 cores | 64 to 128 | |
| Aggregate C4 chiplets | 16 to 32 | Combined ≥ 50 TFLOP bf16 |
| NPU/NATS chiplets | 4 to 8 | One per cell package |
| HBM3e capacity | 512 GB to 1 TB | Pooled across the stitched fabric |
| Optional photonic chiplet (CI-M8-PHOT) | 1 | For cross-rack optical interconnect |

### 3.3 Function envelope

Because of the die-to-die interposer, the **Darwin/Linux kernel and the Franklin Guardian engine see one single unified machine** with thousands of tensor ALUs. It can evaluate global ecosystem constraints in real-time — this is the brain stem of the entire FoT8D network.

### 3.4 Thermal

- Liquid cooling mandatory (cold-plate on the package lid; system-level CDU).
- Junction-to-ambient ≤ 80 °C at 1 kW sustained.
- Rack integration: 2U / 4U chassis options; compatible with OCP rack standards.

### 3.5 Form factor

- ~150 mm × 150 mm multi-chip module on a reinforced substrate.
- Motherboard integration: custom, but electrically compatible with standard PCIe Gen6 host interconnect for legacy fallback.

### 3.6 Unit cost target

- $20,000 to $40,000 at 10 k units/year.
- Priced against NVIDIA HGX H200 and AMD MI300 platforms; differentiated by the HMMU safety invariant and the native vQbit ABI.

---

## 4 — Cross-Tier Invariants

The following invariants hold across **all three tiers** and are enforced by the shared chiplet IP:

| Invariant | Mechanism |
|-----------|-----------|
| Same ISA (M8 RISC-V + vQbit extension) | Shared S4 and C4 chiplets |
| Same memory model (UMA via HMMU) | HMMU IP is identical across tiers |
| Same truth threshold (0.85) | Hardwired in C4 comparator; mask-locked |
| Same primitive ABIs (`vQbitPrimitive` 76 B; `BioligitPrimitive` 96 B; `LithoPrimitive` 128 B) | Enforced by cbindgen + regression tests |
| Same NATS subject taxonomy | Hardware subject-parser LUT is identical |
| Same Owl Protocol crypto (secp256k1) | Shared NPU crypto accelerator |

**Consequence:** GaiaFusion and GaiaHealth binaries run unchanged across all three tiers. Only the workload partitioner — which decides how much of the problem fits on the chiplet count available — differs.

---

## 5 — Tier Decision Matrix

When selecting a tier for a new deployment, consult this table:

| Question | If YES → | If NO → |
|----------|----------|---------|
| Is the device battery-powered or sub-$50? | M8-Edge | continue |
| Does the workload fit in 64 GB UMA? | M8-Cell | continue |
| Does the workload require > 10 TFLOP bf16 sustained OR cross-rack coherence? | M8-Core | re-evaluate |

For borderline cases (e.g. edge + occasional heavy workloads) the canonical answer is: **choose the smaller tier and offload heavy work over NATS to an M8-Cell or M8-Core in the same fabric**. The unified ABI makes this transparent to the application.

---

*Tier boundaries may be re-evaluated on each chiplet rev. Boundary changes require a CCR signed by GaiaLithography + the affected application cell owner.*
