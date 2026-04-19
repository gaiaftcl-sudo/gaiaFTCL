# GaiaLithography Wiki — Home

Welcome to the **GaiaLithography** cell wiki. This cell designs, qualifies, and ships the **M8 vQbit silicon** — the physical substrate on which GaiaFusion (plasma) and GaiaHealth (molecular dynamics) execute.

**Patents:** USPTO 19/460,960 · USPTO 19/096,071 — © 2026 Richard Gillespie.

---

## Getting Started

If you are new to the cell, read in this order:

1. [`../README.md`](../README.md) — cell overview and relationship to sibling cells.
2. [`../docs/DESIGN_SPECIFICATION.md`](../docs/DESIGN_SPECIFICATION.md) — the architectural master document (URS).
3. [`../docs/FUNCTIONAL_SPECIFICATION.md`](../docs/FUNCTIONAL_SPECIFICATION.md) — the "what" the cell does.
4. [`../docs/M8_CHIPLET_IP_PORTFOLIO.md`](../docs/M8_CHIPLET_IP_PORTFOLIO.md) — the four chiplet IP blocks.
5. [`../docs/M8_TIER_CLASSIFICATIONS.md`](../docs/M8_TIER_CLASSIFICATIONS.md) — how Edge / Cell / Core scale from one ISA.
6. [`../docs/HMMU_SPECIFICATION.md`](../docs/HMMU_SPECIFICATION.md) — the safety-critical memory block.
7. [`../docs/TORSION_INTERPOSER.md`](../docs/TORSION_INTERPOSER.md) — the 2.5D/3D die-stitching substrate.
8. [`../docs/M8_ISA.md`](../docs/M8_ISA.md) — the Xvqbit instruction extension.
9. [`../docs/LITHO_PRIMITIVE_ABI.md`](../docs/LITHO_PRIMITIVE_ABI.md) — the 128-byte event ABI.
10. [`../docs/FAB_PROCESS_FLOW.md`](../docs/FAB_PROCESS_FLOW.md) — the manufacturing sequence.
11. [`../docs/GAMP5_LIFECYCLE.md`](../docs/GAMP5_LIFECYCLE.md) — GAMP 5 Category 5 compliance map.
12. [`../docs/IQ_OQ_PQ_LITHOGRAPHY_CELL.md`](../docs/IQ_OQ_PQ_LITHOGRAPHY_CELL.md) — **IQ / OQ / PQ** reviewer summary (full V-model in GAMP5_LIFECYCLE).

**Full repo wiki (GitHub):** [GaiaFTCL-Lithography-Silicon-Cell-Wiki](https://github.com/gaiaftcl-sudo/gaiaFTCL/wiki/GaiaFTCL-Lithography-Silicon-Cell-Wiki) — short mirror on `main`: [`wiki/M8_Lithography_Silicon_Cell_Wiki.md`](../../../wiki/M8_Lithography_Silicon_Cell_Wiki.md).

---

## Quick Reference

### Chiplet portfolio

- **S4** — RISC-V CVA6 RV64GCV cluster. Linux/Darwin kernel + user space. Non-deterministic domain.
- **C4** — Hardwired MPS tensor engine. 48 MB SRAM. 0.85 truth threshold in metal.
- **NPU** — Hardware NATS JetStream broker + secp256k1 Owl crypto. 4×100 GbE (Cell).
- **HBM3e** — 24 GB / 1.2 TB/s per stack (SK Hynix primary, Micron second source).

### Tier classifications

| Tier | Power | Chiplets | Target |
|------|-------|----------|--------|
| M8-Edge | < 5 W | Monolithic 2× S4e + 1× C4-min + LPDDR5 | IoT, wearables |
| M8-Cell | 50–150 W | 16× S4 + 4× C4 + 1× NPU + 2–3× HBM3e | Fusion gateway, fab controller |
| M8-Core | 1000 W+ | 4–8× stitched M8-Cell packages | Community server, brain stem |

### State machine

```
IDLE → MOORED → PDK_BOUND → FLOORPLAN → ROUTED → SIGNOFF → TAPEOUT_LOCKED → SHIPPED
                                                      └──→ MASK_REJECTED
         └──→ HMMU_BREACH (safety terminal)
```

### Key invariants

- **INV-M8-001:** Same ISA across all three tiers.
- **INV-M8-002:** Truth threshold 0.85 is a mask-metal constant.
- **INV-M8-003:** No S4 instruction can write to C4-owned memory (HMMU-enforced).
- **INV-M8-004:** Every substrate event is a signed LithoPrimitive on NATS.
- **INV-M8-005:** Tape-out requires three-of-three CCR signatures (Lithography + Fusion + Health).

---

## Cross-Cell Links

- **Sibling cells:**
  - Fusion (plasma physics): [`../../fusion/README.md`](../../fusion/README.md)
  - Health (molecular dynamics): [`../../health/README.md`](../../health/README.md)
- **Shared theory:** vQbit 8096-D Hilbert space — `/wiki/vQbit-Theory.md`
- **Primitive ABIs:**
  - `vQbitPrimitive` (76 B, fusion/health): `/cells/fusion/docs/vQbitPrimitive-ABI.md`
  - `BioligitPrimitive` (96 B, health): `/cells/health/wiki/BioligitPrimitive-ABI.md`
  - `LithoPrimitive` (128 B, this cell): [`../docs/LITHO_PRIMITIVE_ABI.md`](../docs/LITHO_PRIMITIVE_ABI.md)

---

## Glossary

- **M8** — Model 8 of the vQbit silicon substrate; the first tape-out in the GaiaLithography cell.
- **Chiplet** — a known-good die designed to be stitched onto a larger package via an interposer.
- **CoWoS-L** — TSMC's Chip-on-Wafer-on-Substrate Local-silicon-interconnect packaging; the baseline Torsion Interposer technology.
- **HMMU** — Hardware Memory Management Unit; the safety block enforcing S4↔C4 memory isolation.
- **OTT** — Owner Token Table; the HMMU's per-page ownership registry.
- **Xvqbit** — the vQbit instruction-set extension on top of RV64GCV.
- **χ (chi)** — bond dimension of the Matrix Product State decomposition; ≤ 1024 on M8.
- **Owl Protocol** — the secp256k1-based identity protocol used across the FoT8D substrate.
- **UMA** — Unified Memory Architecture.
- **CCR** — Change Control Record.
- **KGD** — Known-Good Die (wafer-level-tested chiplet before assembly).
- **OSAT** — Outsourced Semiconductor Assembly and Test.

---

## Roadmap Snapshot

- **Rev 1 (2027):** MVP tape-out on TSMC CoWoS-L; M8-Cell first.
- **Rev 2 (2028):** CoWoS-N migration; 9 μm pitch; 2× interposer bandwidth.
- **Rev 3 (2029):** Backside power delivery; photonic chiplet (CI-M8-PHOT).
- **Rev 4 (2030+):** SoIC-X 3D face-to-face C4 over HMMU.

See [`../docs/TORSION_INTERPOSER.md`](../docs/TORSION_INTERPOSER.md) §9 for the full roadmap.

---

*This wiki is a navigation hub. Authoritative content lives in the `docs/` tree. When in doubt, follow the links.*
