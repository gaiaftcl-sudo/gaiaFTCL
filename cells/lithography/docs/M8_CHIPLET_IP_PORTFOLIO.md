# M8 Chiplet IP Portfolio

**Document ID:** GL-CIP-001
**Revision:** 1.0
**Parent:** [`DESIGN_SPECIFICATION.md`](DESIGN_SPECIFICATION.md)
**Controlled items:** CI-M8-S4 · CI-M8-C4 · CI-M8-NPU · CI-M8-HBM

---

## 0 — Purpose

This document fully specifies each of the four chiplet IP blocks that compose the M8 substrate. A single foundry tapeout per chiplet IP is reused across all three deployment tiers (Edge, Cell, Core). No chiplet is re-spun per tier — tier scaling happens exclusively by chiplet **count** on the Torsion Interposer.

---

## 1 — S4 Compute Chiplet (CI-M8-S4)

### 1.1 Overview

Open-source RISC-V application cluster. Runs Linux/Darwin kernels, servers I/O interrupts, and handles external network stacks. The S4 chiplet is **explicitly non-deterministic** — it can panic, page-out, or hot-swap without affecting C4 evaluation, because the HMMU enforces memory isolation.

### 1.2 Core complement

- Core IP: **CVA6 (Ariane)** RISC-V 64-bit, RV64GC, 6-stage in-order, 5 PMP regions extended to 16 via the HMMU shim.
- Cache: 32 KB L1-I + 32 KB L1-D per core; 1 MB shared L2 per cluster of 4.
- Vector extension: RVV 1.0 with 512-bit VLEN (compatible with Apple AMX-style programming model).

### 1.3 Tier-specific counts

| Tier | Core count | Cluster configuration |
|------|-----------|----------------------|
| M8-Edge | 2 × CVA6 E-cores (in-order, 3-stage cost-reduced) | Single cluster, no L2 |
| M8-Cell | 16 × CVA6 full cores | 4 clusters × 4 cores |
| M8-Core | 64–128 × CVA6 full cores | Via 4–8 M8-Cell packages stitched |

### 1.4 Process node

- **TSMC N5 / N4** for M8-Cell and M8-Core.
- **GlobalFoundries 22FDX** (or SkyWater sky130) for M8-Edge monolithic die to drive cost below $5 per unit at volume.

### 1.5 Power

| Configuration | Power (typ) |
|---------------|-------------|
| 2-core E variant @ 1 GHz | 0.8 W |
| 16-core cell variant @ 2.4 GHz | 20–35 W |
| 64-core core variant @ 3.0 GHz | 120–180 W |

### 1.6 Interconnect

- Torsion Interposer link: 2 × 256-bit at 4 GHz = 2 TB/s aggregate.
- HBM3e access is routed through the HMMU; S4 never has a direct HBM path.

### 1.7 Software

- Reference kernel: Linux 6.x with RISC-V support; Darwin port is optional and gated on Apple collaboration.
- Distribution: GaiaOS image built from FoT8D repo. Bootloader: OpenSBI + custom stage-0 enforcing HMMU handshake at boot.

---

## 2 — C4 Tensor Chiplet (CI-M8-C4)

### 2.1 Overview

The **hardwired Matrix Product State (MPS) evaluation engine**. This chiplet is the physical implementation of the vQbit collapse operator. It contains massive localized SRAM arrays to hold the bond dimensions (χ) and a fixed-function contractor that **physically enforces the 0.85 truth threshold**.

### 2.2 Tensor engine

- Bond dimension support: χ up to 1024 (covers the 2048 × 4 × 1024 decomposition of the 8096-D vQbit Hilbert space).
- Datapath: systolic array of 256 × 256 bfloat16 MAC units; 4 arrays per chiplet; 262,144 MACs per array; 1.048 M MACs per chiplet.
- Peak throughput: ~3.2 TFLOPs bfloat16 per chiplet at 1.5 GHz. 4 chiplets in M8-Cell = **12.8 TFLOPs** usable (no memory copy overhead).
- Truth-threshold comparator: hardwired `≥ 0.85` test at SRAM read port; outcome drives a dedicated output pin wired directly to the NPU/NATS chiplet publish fabric.

### 2.3 SRAM

- **48 MB localized SRAM per chiplet**, layered as:
  - 32 MB χ-bank (bond-dimension storage, ECC-protected 8+1)
  - 8 MB virtue-operator bank (Justice / Honesty / Temperance / Prudence projection matrices)
  - 8 MB scratchpad for intermediate contractions
- No off-chiplet DRAM is touched during a single contraction tick; **this is what gives the 50 kHz determinism**.

### 2.4 Process node

- **TSMC N3P** (preferred) or **N2** (stepping 2 onward).

### 2.5 Power

| Configuration | Power (typ) |
|---------------|-------------|
| Minimal C4 (M8-Edge) | 1.5 W at 600 MHz |
| Full C4 (M8-Cell, 4 per package) | 10 W each; 40 W total |
| Full C4 (M8-Core, 16–32 per package) | 160–320 W total |

### 2.6 Truth-threshold hardwire

The threshold value `0.85` is stored as a 32-bit fixed-point constant (`0x00D9999A` in Q0.31) **hard-wired in metal** inside the comparator. **It cannot be modified by software.** The only way to change the threshold is a mask change (metal-1 + comparator block), which requires:

1. CCR signed by all three cell owners (Fusion, Health, Lithography)
2. Full OQ re-qualification
3. Full PQ re-qualification on next shuttle

This is intentional: it makes the truth threshold a **physical constant**, in the same sense that Planck's constant is a physical constant — no software exploit or kernel panic can alter it.

### 2.7 Bond dimension programming

The χ loadout is written to the χ-bank by the NPU/NATS chiplet via HMMU-gated writes. The S4 chiplet **cannot** write to the χ-bank. Only the NPU can (and only after HMMU approves the transfer). This prevents a compromised OS from poisoning the tensor state.

---

## 3 — NPU / NATS Chiplet (CI-M8-NPU)

### 3.1 Overview

Hardware-encoded NATS JetStream broker. DMA engines parse NATS subjects at line rate without waking the S4 CPU. This is the **only chiplet with a direct external PHY connection**.

### 3.2 Functional blocks

- **Ethernet/optical PHY:** 4 × 100 GbE (optionally 1 × 400 GbE) on M8-Cell; 1 × 10 GbE on M8-Edge.
- **Subject parser:** FPGA-style LUT+ternary-CAM pipeline matching NATS subjects (`gaiaftcl.fusion.heartbeat`, `gaiaftcl.health.binding_event`, `gaiaftcl.lithography.hmmu_breach`, …) at wire speed.
- **JetStream consumer/producer engines:** hardware ack/nack, deduplication, retention window enforcement. Target: 10 M msgs/sec at M8-Cell.
- **DMA engine:** writes payload directly to HMMU-allocated Unified Memory addresses. No S4 CPU involvement.
- **Owl Protocol crypto accelerator:** secp256k1 sign/verify in 40 ns; SHA-256 at 200 Gbps.

### 3.3 Process node

- **TSMC N3P**; same die can be binned to N5 for M8-Edge cost variant.

### 3.4 Power

| Configuration | Power (typ) |
|---------------|-------------|
| M8-Edge subset (10 GbE, single-subject) | 0.4 W |
| M8-Cell full (100 GbE × 4) | 8–15 W |
| M8-Core (per NPU; 4–8 per package) | 8–15 W each |

### 3.5 Direct C4 wire

The NPU/NATS chiplet has a **dedicated point-to-point wire** to each C4 tensor chiplet. When the C4 comparator asserts the truth-threshold line, the NPU publishes the corresponding NATS subject **within 40 ns**. This wire is the physical backbone of the FoT8D real-time invariant model.

---

## 4 — HBM3e Memory Stacks (CI-M8-HBM)

### 4.1 Overview

High-Bandwidth Memory (HBM3e) modules placed directly on the silicon interposer. Provides the Unified Memory pool that all chiplets (S4, C4, NPU) share. **Every access is mediated by the HMMU.** No chiplet has a "bypass" path.

### 4.2 Sourcing

- **SK Hynix HBM3e** (primary), **Micron HBM3e** (second source).
- Per-stack: 8-Hi, 24 GB capacity, 1.2 TB/s bandwidth.
- Later steppings can adopt 12-Hi 36 GB stacks or HBM4 without interposer redesign (same micro-bump footprint).

### 4.3 Stack counts per tier

| Tier | Stack count | Capacity | Aggregate BW |
|------|-------------|----------|--------------|
| M8-Edge | 0 (uses LPDDR5 instead) | 4 GB LPDDR5 | 51.2 GB/s |
| M8-Cell | 2–3 stacks | 48–72 GB | 2.4–3.6 TB/s |
| M8-Core | 16+ stacks (pooled across stitched dies) | 512 GB+ | 19.2 TB/s+ |

### 4.4 ECC policy

All HBM3e traffic is SECDED ECC-protected. Uncorrectable errors raise a `gaiaftcl.lithography.hbm_uce` NATS event and force the affected page into **HMMU quarantine** — all owner tokens for that page are invalidated until a scrubbing cycle completes.

### 4.5 Thermal

HBM3e stacks share the CoWoS heat-spreader with the compute chiplets. Target: < 85 °C junction at TDP.

---

## 5 — Optional Future Chiplets

The interposer bandwidth budget allows for two future chiplet slots per package. Planned candidates:

- **CI-M8-QRNG** — quantum-random-number-generator chiplet for Owl Protocol entropy.
- **CI-M8-CRYO** — cryogenic I/O chiplet for future superconducting-qubit co-processors (research-tier only).
- **CI-M8-PHOT** — silicon-photonic optical interconnect for M8-Core inter-rack communication.

These are **not required for the MVP tape-out** and are listed here only so the interposer floorplan reserves the physical landing sites.

---

## 6 — Chiplet Interconnect Budget

All chiplets communicate exclusively over the Torsion Interposer. Raw bandwidth budget, M8-Cell configuration:

| Link | Width × rate | Bandwidth |
|------|--------------|-----------|
| S4 ↔ HBM3e (via HMMU) | 1024 b × 6.4 GT/s | 820 GB/s |
| C4[0..3] ↔ HBM3e (via HMMU) | 4 × 1024 b × 6.4 GT/s | 3.28 TB/s |
| NPU ↔ HBM3e (via HMMU) | 512 b × 6.4 GT/s | 410 GB/s |
| NPU ↔ C4[0..3] direct | 4 × 64 b × 4 GT/s | 128 GB/s |
| HMMU control fabric | 64 b × 2 GT/s | 16 GB/s |

Total cross-interposer traffic, worst case: ~4.7 TB/s. Torsion Interposer is specified for ≥ 6 TB/s aggregate (50 % headroom). See [`TORSION_INTERPOSER.md`](TORSION_INTERPOSER.md).

---

*Controlled item changes to any chiplet IP require a CCR signed by GaiaLithography + GaiaFusion + GaiaHealth cell owners.*
