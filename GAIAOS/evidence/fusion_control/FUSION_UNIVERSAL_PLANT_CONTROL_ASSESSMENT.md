# Architectural Frameworks for Universal Fusion Plant Control

**A global assessment of multi-concept confinement, plug-and-play middleware, and macOS-native computational acceleration**

**S⁴ classification:** strategic / bibliographic synthesis. **C⁴:** if this document disagrees with `MAC_FUSION_MESH_CELL_PORTS.md`, substrate compose, or live HTTP/DB receipts, **the substrate wins**. External links are **literature pointers**, not claims that GaiaFTCL has integrated a given vendor stack unless sealed in repo + deployment evidence.

**GaiaFTCL port correction (overrides any generic “industry default” wording below):** see `deploy/mac_cell_mount/MAC_FUSION_MESH_CELL_PORTS.md` and `services/gaiaos_ui_web/app/lib/macFusionCellPorts.ts`. In this monorepo, **8803** is **MCP ingress** (`fot_mcp_gateway` / wallet-gate path), **not** a generic “streaming” port. **8900** is `**gaiaos_ui_tester_mcp`** upstream for the gateway. **4222** is **NATS** on the mesh wire. **8910** / **14222** are **S⁴ loopback** (Fusion UI / NATS tunnel local bind).

---

## Abstract

Fusion is moving from pure experiment toward industrial and sovereign energy planning (2025–2026 horizon in public reporting). Investment, PPAs, and diversified confinement concepts (MCF, MIF, ICF) increase pressure for **one operator-facing control architecture** with **interchangeable backends** (facility harness, PCS, live machine). This note aligns that industry framing with **GaiaFTCL’s Fusion limb**: monorepo under `FoT8D` / `GAIAOS/`, **plug-and-play** via `deploy/fusion_cell/config.json`, `deploy/fusion_mesh/fusion_projection.json`, bridges, and **Metal-accelerated** local receipts (`FusionControl`, `default.metallib`, `evidence/fusion_control/long_run_signals.jsonl`.

---

## Global macro-environment (public sources)

- Record private investment and public-private activity in fusion (IAEA/IEA commentary, industry associations, McKinsey “arenas of competition,” etc.).
- Commercial interest: baseload / hyperscale / PPAs as demand signals (reported in trade press).
- Modeling ranges for long-horizon electricity share are **scenario-dependent**, not predictions.

---

## Taxonomy of leading confinement concepts


| Confinement class      | Representative method | Primary mechanism                       | Geometry (schematic)       |
| ---------------------- | --------------------- | --------------------------------------- | -------------------------- |
| Magnetic (MCF)         | Tokamak               | Induced plasma current + toroidal field | Toroidal                   |
| Magnetic (MCF)         | Stellarator           | 3D helical magnetic field               | 3D helix / optimized coils |
| Magneto-inertial (MIF) | FRC                   | Self-organizing compact toroid          | Linear / compact toroid    |
| Magneto-inertial (MIF) | Pulsed compression    | Dynamic magnetic implosion              | Linear / cylindrical       |
| Inertial (ICF)         | Laser-driven          | Target compression                      | Spherical chamber          |
| Inertial (ICF)         | Other drivers         | e.g. projectile / specialized target    | Architecture-specific      |


**Implication:** PCS, protection, and diagnostics interfaces **cannot** be tokamak-only if the product claims universality.

---

## Institutional middleware (public-facing references)

Large facilities standardize on **EPICS**, **CODAC-style** cores, **MARTe2** real-time loops, **FESA** / accelerator-style front-ends, industrial **SCADA** lineages, and **TANGO** in parts of the ecosystem. Third-party integration typically flows through **documented device support**, **real-time frameworks**, and **control system handbooks** (e.g. ITER plant control documentation, CODAC core releases, JACoW / ICALEPCS proceedings).

**GaiaFTCL stance:** bridges (`fusion_projection.json` → `bridges.*.invoke`, TORAX/MARTe2 shell bridges under `deploy/mac_cell_mount/bin/`) are the **wiring surface**; claiming parity with a full CODAC deployment is **S4 until sealed C4**.

---

## GaiaFTCL Fusion limb — implementation binding (C⁴-aligned)


| Path                                                          | Role                                                                                                                                                                                      |
| ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GAIAOS/deploy/fusion_cell/config.json`                       | Cell executor binding (Metal app path vs site subprocess); env for batch cycles                                                                                                           |
| `GAIAOS/deploy/fusion_mesh/fusion_projection.json`            | S⁴ projection: `payment_projection`, `bridges`, `plant_flavor`, `dif_profile` / site labels, benchmark id — **not** a substitute for full 3D plasma visualization unless extended in code |
| `GAIAOS/evidence/fusion_control/long_run_signals.jsonl`       | Append-only batch receipts for regression witness                                                                                                                                         |
| `GAIAOS/services/gaiaos_ui_web/app/lib/macFusionCellPorts.ts` | Canonical **C⁴ / S⁴** port constants for Mac leaf                                                                                                                                         |
| `GAIAOS/services/fusion_control_mac/`                         | Metal receipt harness (`default.metallib`)                                                                                                                                                |
| `GAIAOS/scripts/deploy_dmg_to_mesh.sh`                        | DMG distribution to nine-cell download path (when keys/paths allow)                                                                                                                       |


**Metal / Apple Silicon:** precompiled `metallib`, unified memory — useful for **local deterministic receipts** and UI-adjacent compute; **not** a claim to replace facility RTF/MARTe2 cycles without integration evidence.

---

## Plug-and-play operator surface

- **Same Founder-facing app** (mooring, Fusion S⁴, gateway policy) across **multiple confinement concepts** and **vendor PCS stacks**, with backends swapped via **config + bridges + site OPC/DAQ**.
- **No “mock app” vs “real app” fork** — interchangeable I/O backends; language in Cursor rules: `GAIAOS/.cursor/rules/mac-fusion-tokamak-mesh-packaging.mdc` (filename historical; content is multi-concept).

---

## Testing and evidence (GaiaFTCL)

- **Vitest** (unit), **Playwright** (Fusion S⁴ UI + API contract), **shell regressions** (`test_fusion_mesh_mooring_stack.sh`, `test_fusion_plant_stack_all.sh`, `test_fusion_all_with_sidecar.sh`).
- **GPU path witness:** `gpu_fused_multicycle`, `gpu_wall_us`, `metallib` in JSONL / `last_control_matrix_receipt.json`.

---

## Strategic implications (industry-level, S⁴)

Modular supply chains favor **standard control interfaces** and **pre-integrated components**. Regulatory and safety narratives benefit from **documented, auditable** control lineages — alignment with open-control practice where applicable.

---

## Works cited (as supplied; URLs not re-validated at save time)

1. IEA / fusion industry commentary — e.g. Fusion Industry Association note on IEA innovation reports — `https://www.fusionindustryassociation.org/iea-features-fusion-in-state-of-energy-innovation-2026-report/`
2. IAEA — “Fusion energy in 2025: six global trends” — `https://www.iaea.org/newscenter/news/fusion-energy-in-2025-six-global-trends-to-watch`
3. IAEA World Fusion Outlook 2025 — `https://www-pub.iaea.org/MTCD/publications/PDF/p15935-25-02871E_WFO25_web.pdf`
4. McKinsey MGI — competition arenas — `https://www.mckinsey.com/mgi/our-research/the-race-takes-off-in-the-next-big-arenas-of-competition`
5. Energy Central / fusion outlook commentary — `https://www.energycentral.com/nuclear/post/what-will-2026-bring-for-the-fusion-energy-world-wsiuUvyQIUSO6tC`
6. Wikipedia — list of nuclear fusion companies — `https://en.wikipedia.org/wiki/List_of_nuclear_fusion_companies`
7. World Nuclear Association — fusion power — `https://world-nuclear.org/information-library/current-and-future-generation/nuclear-fusion-power`
8. DOE — Tokamaks explainer — `https://www.energy.gov/science/doe-explainstokamaks`
9. TAE Technologies — press / program materials — `https://tae.com/` (and linked PDFs)
10. Helion — technology articles — `https://www.helionenergy.com/technology/`
11. Tokamak Energy — technology — `https://tokamakenergy.com/our-fusion-energy-and-hts-technology/fusion-energy-technology/`
12. ITER — CODAC architecture / EPICS — `https://www.iter.org/machine/supporting-systems/codac/architecture` , `https://www.iter.org/machine/supporting-systems/codac` , `https://www.iter.org/node/20687/epics-iter` , `https://www.iter.org/machine/supporting-systems/codac/codac-core-system`
13. ITER CODAC Core System release notes (PDF) — `https://www.iter.org/sites/default/files/media/2024-04/codac_core_system_version_7.2_release_no_9uq2cl_v1_1.pdf`
14. JACoW — SDD toolkit / ICALEPCS proceedings — e.g. `https://proceedings.jacow.org/ICALEPCS2013/papers/tuppc003.pdf?n=ICALEPCS2013/papers/TUPPC003.pdf`
15. ITER — Plant Control Design Handbook (PDF) — `https://www.iter.org/sites/default/files/media/2024-04/itr-23-009-plant_control_design_handbook.pdf`
16. MARTe / MARTe2 proceedings — e.g. JACoW ICARLEPCS — `http://wpage.unina.it/detommas/MARTe-Downloads/MARTeFramework.pdf` , `https://proceedings.jacow.org/icalepcs2011/papers/thdault06.pdf`
17. CERN / FAIR / industrial control references — e.g. `https://home.cern/news/news/knowledge-sharing/future-colliders-and-fusion-reactors` , `https://fusionforenergy.europa.eu/news/f4e-and-cern-join-forces-in-fusion-energy-and-particle-physics/`
18. IAEA fusion middleware comparison (PDF) — `https://conferences.iaea.org/event/412/contributions/38172/attachments/21966/37776/Kroeger_FusionMiddlewareIAEA2025.pdf`
19. Commonwealth Fusion Systems — NVIDIA / Siemens digital twin press — `https://cfs.energy/news-and-media/commonwealth-fusion-systems-accelerates-commercial-fusion-with-siemens-and-nvidia-leveraging-ai-powered-digital-twins/`
20. Next Step Fusion — plasma control — `https://nextfusion.org/plasma-control`
21. Apple — Metal overview — `https://developer.apple.com/metal/`
22. Apple — Metal in Simulator — `https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator`
23. MARTe2-components (GitHub) — `https://github.com/aneto0/MARTe2-components`
24. DOE — FES Building Bridges / FIRE collaboratives — `https://www.energy.gov/sites/default/files/2024-12/fes-building-bridges-vision_0.pdf` , `https://www.colorado.edu/researchinnovation/doe-fusion-innovation-research-engine-fire-collaboratives`
25. NATS / DDS / distributed control (general references as in original list — use primary vendor or IEEE papers for engineering detail).

*(Additional URLs from the supplied manuscript can be appended in a second pass; the list above preserves the backbone of institutional and industry pointers.)*

---

## Cross-reference

- Cursor limb rule: `GAIAOS/.cursor/rules/mac-fusion-tokamak-mesh-packaging.mdc`
- Monorepo pointer: `FoT8D/mac-fusion-limb/README.md`
- Catalog summary: `GAIAOS/deploy/fusion_mesh/fusion_virtual_systems_catalog_s4.json` (`user_flow_summary`)

*Norwich — S⁴ serves C⁴.*