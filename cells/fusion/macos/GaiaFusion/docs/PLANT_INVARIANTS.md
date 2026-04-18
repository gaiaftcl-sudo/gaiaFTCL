# GaiaFusion Plant Invariants — Physics Reference

**Document Version:** 1.1  
**Last Updated:** 2026-04-13  
**Purpose:** Canonical physics constraints for all 9 magnetic confinement fusion plant topologies

---

## Overview

This document defines the **operational parameter bounds** for each fusion plant topology supported by GaiaFusion. These invariants are:

1. **Physics-based:** Derived from real-world fusion experiments and engineering limits
2. **Safety-critical:** Violations trigger REFUSED terminal state
3. **Validated:** Cross-referenced with published literature and facility designs
4. **Immutable:** Changes require full PQ re-execution (CI-002)

**Source Files:**
- `GaiaFusion/Resources/usd/plants/*/timeline_v2.json` — Telemetry schema + bounds
- `GFTCL-PQ-002` Section 4 — Physics invariants for PQ validation

---

## 1. Tokamak

### Physical Description

**Magnetic Confinement:** Axisymmetric toroidal chamber with external toroidal field coils and internal plasma current generating poloidal field.

**Key Physics:**
- β_N = β / (I_p / aB_T) — Normalized beta (stability limit)
- q = (2πa²B_T) / (μ₀R₀I_p) — Safety factor (MHD stability)
- τ_E ∝ I_p B_T — Energy confinement time scaling

### Telemetry Bounds

| Parameter | Symbol | Min | Nominal | Max | Unit | Physics Basis |
|---|---|---|---|---|---|---|
| Plasma Current | I_p | 0.5 | 15.0 | 30.0 | MA | Toroidal current sustaining plasma |
| Toroidal Magnetic Field | B_T | 1.0 | 5.5 | 13.0 | T | External coil-generated field |
| Electron Density | n_e | 0.1 | 1.0 | 3.0 | 10²⁰ m⁻³ | Core plasma density |

### Invariants

| INV-ID | Statement | Validation Method |
|---|---|---|
| **INV-TOK-001** | I_p / B_T ratio must remain within operational limits for stability (βN < 4.0) | Telemetry bounds check |
| **INV-TOK-002** | Safety factor q(a) > 2.0 at plasma edge | Calculated from I_p, B_T, geometry |
| **INV-TOK-003** | Electron density must not exceed Greenwald limit: n_G = I_p / (π a²) | Density vs. current check |

### Reference Facilities

- **ITER:** I_p = 15 MA, B_T = 5.3 T, n_e = 1.0 × 10²⁰ m⁻³
- **JET:** I_p = 5 MA, B_T = 3.8 T
- **SPARC:** I_p = 8.7 MA, B_T = 12.2 T (under construction)

---

## 2. Stellarator

### Physical Description

**Magnetic Confinement:** 3D-shaped toroidal coils creating helical twist; no plasma current required.

**Key Physics:**
- No disruptions (inherently stable)
- Bootstrap current < 5% (external current drive unnecessary)
- Quasi-isodynamic or quasi-axisymmetric field optimization

### Telemetry Bounds

| Parameter | Symbol | Min | Nominal | Max | Unit | Physics Basis |
|---|---|---|---|---|---|---|
| Plasma Current | I_p | 0.0 | 0.05 | 0.2 | MA | Minimal bootstrap current |
| Toroidal Magnetic Field | B_T | 1.5 | 2.5 | 5.0 | T | Twisted external field |
| Electron Density | n_e | 0.05 | 0.5 | 2.0 | 10²⁰ m⁻³ | Lower density operation |

### Invariants

| INV-ID | Statement | Validation Method |
|---|---|---|
| **INV-STEL-001** | I_p must remain near-zero (< 0.2 MA) | Telemetry bounds check |
| **INV-STEL-002** | External field twist must be non-zero (verified by coil geometry) | Geometry analysis |
| **INV-STEL-003** | No current-driven instabilities (disruption-free operation) | Terminal state monitor |

### Reference Facilities

- **Wendelstein 7-X:** I_p ≈ 0 MA (bootstrap only), B_T = 2.5 T, n_e = 1.0 × 10²⁰ m⁻³
- **LHD (Large Helical Device):** B_T = 3.0 T, n_e = 0.5 × 10²⁰ m⁻³
- **Heliotron J:** Helical-axis stellarator

---

## 3. Field-Reversed Configuration (FRC)

### Physical Description

**Magnetic Confinement:** Compact torus with self-organized reversed internal field; minimal external B_T.

**Key Physics:**
- High-β operation (β ~ 1, plasma pressure dominates magnetic pressure)
- Elongated plasma (E = length / diameter ratio > 2)
- Self-generated poloidal field via azimuthal current

### Telemetry Bounds

| Parameter | Symbol | Min | Nominal | Max | Unit | Physics Basis |
|---|---|---|---|---|---|---|
| Plasma Current | I_p | 0.1 | 0.5 | 2.0 | MA | Azimuthal current in closed field lines |
| Toroidal Magnetic Field | B_T | 0.0 | 0.0 | 0.1 | T | Minimal external field |
| Electron Density | n_e | 0.5 | 2.0 | 10.0 | 10²⁰ m⁻³ | High-β compact plasma |

### Invariants

| INV-ID | Statement | Validation Method |
|---|---|---|
| **INV-FRC-001** | External B_T must be near-zero (< 0.1 T) | Telemetry bounds check |
| **INV-FRC-002** | High electron density permitted (up to 10 × 10²⁰ m⁻³) | Density bounds check |
| **INV-FRC-003** | Plasma β ~ 1 (high-β regime) | Calculated from pressure / magnetic field |

### Reference Facilities

- **C-2W (TAE Technologies):** I_p ~ 0.5 MA, n_e ~ 2.0 × 10²⁰ m⁻³
- **Helion Trenta:** Compact FRC with pulsed fusion

---

## 4. Spheromak

### Physical Description

**Magnetic Confinement:** Compact torus with self-generated toroidal + poloidal fields (no external toroidal coils).

**Key Physics:**
- Taylor relaxation (minimum energy state)
- λ = μ₀j / B approximately constant (force-free field)
- Self-organization via helicity conservation

### Telemetry Bounds

| Parameter | Symbol | Min | Nominal | Max | Unit | Physics Basis |
|---|---|---|---|---|---|---|
| Plasma Current | I_p | 0.05 | 0.3 | 1.0 | MA | Toroidal + poloidal current |
| Toroidal Magnetic Field | B_T | 0.0 | 0.1 | 0.5 | T | Self-generated field |
| Electron Density | n_e | 0.1 | 1.0 | 5.0 | 10²⁰ m⁻³ | Compact torus |

### Invariants

| INV-ID | Statement | Validation Method |
|---|---|---|
| **INV-SPHM-001** | Toroidal field must be self-generated (B_T ≈ internal field) | Magnetic diagnostics |
| **INV-SPHM-002** | Taylor state maintained (λ constant across plasma) | Force-free field analysis |
| **INV-SPHM-003** | No external toroidal field coils required | Geometry verification |

### Reference Facilities

- **HIT-SI (Univ. of Washington):** Self-organized spheromak
- **CTFusion:** Commercial spheromak development

---

## 5. Reversed-Field Pinch (RFP)

### Physical Description

**Magnetic Confinement:** Toroidal with high plasma current and reversed toroidal field at plasma edge.

**Key Physics:**
- q(a) < 0 (safety factor reverses at boundary)
- Dynamo effect sustains field reversal
- Magnetic turbulence (resistive MHD)

### Telemetry Bounds

| Parameter | Symbol | Min | Nominal | Max | Unit | Physics Basis |
|---|---|---|---|---|---|---|
| Plasma Current | I_p | 0.5 | 2.0 | 5.0 | MA | High toroidal current |
| Toroidal Magnetic Field | B_T | 0.1 | 0.5 | 1.5 | T | Reversed edge field |
| Electron Density | n_e | 0.2 | 1.0 | 3.0 | 10²⁰ m⁻³ | Moderate density |

### Invariants

| INV-ID | Statement | Validation Method |
|---|---|---|
| **INV-RFP-001** | Toroidal field must reverse at plasma edge (B_T changes sign) | Edge magnetic probe |
| **INV-RFP-002** | High plasma current (I_p / B_T ratio > 1) | Current / field ratio |
| **INV-RFP-003** | q(a) < 0 at separatrix | Safety factor calculation |

### Reference Facilities

- **RFX-mod (Italy):** I_p = 2.0 MA, B_T = 0.5 T
- **MST (Univ. of Wisconsin):** I_p = 0.5 MA

---

## 6. Magnetic Mirror

### Physical Description

**Magnetic Confinement:** Open-ended cylinder with strong magnetic field at ends (mirror ratio R > 2).

**Key Physics:**
- Open field lines (plasma escapes at ends)
- Mirror ratio R = B_max / B_min determines confinement
- Loss cone (particles with v_|| / v_⊥ < certain angle escape)

### Telemetry Bounds

| Parameter | Symbol | Min | Nominal | Max | Unit | Physics Basis |
|---|---|---|---|---|---|---|
| Plasma Current | I_p | 0.0 | 0.0 | 0.05 | MA | Minimal current |
| Toroidal Magnetic Field | B_T | 1.0 | 3.0 | 10.0 | T | Axial mirror field |
| Electron Density | n_e | 0.01 | 0.1 | 1.0 | 10²⁰ m⁻³ | Low-density open field |

### Invariants

| INV-ID | Statement | Validation Method |
|---|---|---|
| **INV-MIR-001** | Mirror ratio R > 2 for adequate confinement | Field strength at ends vs. center |
| **INV-MIR-002** | Plasma current near-zero (no toroidal confinement) | Current measurement |
| **INV-MIR-003** | Open field lines (particles escape at ends) | Loss cone analysis |

### Reference Facilities

- **2XIIB (LLNL, historical):** B_T = 2.0 T, R = 2.0
- **GDT (Russia):** Gas dynamic trap variant

---

## 7. Tandem Mirror

### Physical Description

**Magnetic Confinement:** Central solenoid with strong magnetic mirror plugs at ends; electrostatic potential improves confinement.

**Key Physics:**
- Ambipolar potential well traps ions
- End plugs reduce axial losses
- Central cell + plug operation

### Telemetry Bounds

| Parameter | Symbol | Min | Nominal | Max | Unit | Physics Basis |
|---|---|---|---|---|---|---|
| Plasma Current | I_p | 0.0 | 0.01 | 0.1 | MA | Minimal |
| Toroidal Magnetic Field | B_T | 1.0 | 5.0 | 15.0 | T | Strong end plugs |
| Electron Density | n_e | 0.05 | 0.5 | 2.0 | 10²⁰ m⁻³ | Central cell + plugs |

### Invariants

| INV-ID | Statement | Validation Method |
|---|---|---|
| **INV-TM-001** | End plug field strength > central cell field (B_plug > B_center) | Magnetic field profile |
| **INV-TM-002** | Electrostatic potential well must confine ions | Potential measurement |
| **INV-TM-003** | Minimal plasma current (no toroidal confinement) | Current measurement |

### Reference Facilities

- **TMX (LLNL, historical):** B_T = 1.0 T (central), 2.0 T (plugs)
- **GAMMA 10 (Japan):** Tandem mirror with thermal barrier

---

## 8. Spherical Tokamak

### Physical Description

**Magnetic Confinement:** Low-aspect-ratio tokamak (A < 2) with compact "cored apple" shape.

**Key Physics:**
- High bootstrap current fraction (> 50%)
- High natural β limit (β_N > 5)
- Compact design for power plants

### Telemetry Bounds

| Parameter | Symbol | Min | Nominal | Max | Unit | Physics Basis |
|---|---|---|---|---|---|---|
| Plasma Current | I_p | 0.5 | 3.0 | 10.0 | MA | High current, low aspect ratio |
| Toroidal Magnetic Field | B_T | 0.5 | 1.5 | 3.0 | T | Moderate field |
| Electron Density | n_e | 0.2 | 2.0 | 8.0 | 10²⁰ m⁻³ | High-β capability |

### Invariants

| INV-ID | Statement | Validation Method |
|---|---|---|
| **INV-ST-001** | Aspect ratio A < 2.0 (R₀ / a) | Geometry check |
| **INV-ST-002** | High bootstrap fraction (> 50% of I_p) | Bootstrap current calculation |
| **INV-ST-003** | β_N > 5 achievable (high natural stability) | Stability analysis |

### Reference Facilities

- **NSTX-U (Princeton):** I_p = 2.0 MA, B_T = 1.0 T
- **MAST-U (UK):** I_p = 1.0 MA, B_T = 0.6 T
- **ST40 (Tokamak Energy):** I_p = 2.0 MA, B_T = 3.0 T

---

## 9. MIF / Inertial (Magnetized Inertial Fusion)

### Physical Description

**Magnetic Confinement:** Hybrid magnetized–inertial approach. A magnetized plasma target (FRC, spheromak, or liner-embedded plasma) is compressed on a pulsed timescale by a mechanical, plasma, or laser-driven liner, reaching inertial-confinement densities while seed magnetic field suppresses thermal conduction losses.

**Canonical Identifiers:** `mif`, `inertial` (both accepted by `PlantKindsCatalog`; `mif` is canonical)

**Key Physics:**
- Magnetized liner inertial fusion (MagLIF): axial B-field + laser preheat + Z-pinch compression
- FRC/spheromak target compression: magnetic flux conserved during implosion (flux compression)
- Hybrid timescale — liner velocity 0.5–3 km/s (General Fusion) or Z-pinch rise time ~100 ns (MagLIF)
- Seed B ≈ 10–30 T amplified to B_compressed ~ 10³–10⁴ T at ignition via flux conservation (Φ = B·A = const)
- Electron density at ignition 10²⁶–10³² m⁻³ (six orders above tokamak nominal — ICF regime)
- No steady-state plasma current: I_p is pulsed, associated with liner or theta-pinch drive

**Plasma State During Steady Visualization:**
- Pre-compression (CALORIE): seed field sustained, I_p and n_e at MCF-like values
- Compression event: pulsed I_p up to 20 MA (liner drive), n_e rises to ignition-class values
- Post-shot (CURE/REFUSED): energy state logged, plant reset to standby

### Telemetry Bounds

| Parameter | Symbol | Min | Nominal | Max | Unit | Physics Basis |
|---|---|---|---|---|---|---|
| Plasma Current | I_p | 0.0 | 5.0 | 20.0 | MA | Pulsed liner/theta-pinch drive current |
| Seed Toroidal Field | B_seed | 0.1 | 10.0 | 30.0 | T | Pre-compression magnetization |
| Compressed Field (peak) | B_comp | — | ~1 000 | ~10 000 | T | Post-liner flux compression (diagnostic only) |
| Electron Density (pre-compression) | n_e | 0.1 | 2.0 | 10.0 | 10²⁰ m⁻³ | MCF-regime seed plasma |
| Electron Density (at ignition) | n_e_ig | — | — | 10¹² | 10²⁰ m⁻³ | ICF regime (not telemetry-monitored in real time) |

> **Note:** `B_T` in the telemetry schema maps to `B_seed` for MIF. `B_comp` and `n_e_ig` are post-shot evidence values, not real-time bounds. The renderer uses `B_seed` for visualization.

### Invariants

| INV-ID | Statement | Validation Method |
|---|---|---|
| **INV-MIF-001** | Seed field B_seed ≥ 0.1 T must be present before compression pulse fires | Pre-shot field check |
| **INV-MIF-002** | Pulsed I_p must return to zero between shots (no steady current) | Post-shot current decay check |
| **INV-MIF-003** | Flux conservation: B_comp / B_seed ≈ (r_initial / r_final)² within ±20% | Post-shot flux diagnostic |

### Reference Facilities

- **Sandia Z-Machine (MagLIF):** Z-pinch I_p up to 27 MA, B_seed ≈ 15 T, n_e_ig ~ 10³¹ m⁻³
- **General Fusion Magnetized Target Fusion:** Mechanical liner compression of FRC at ~0.7 km/s, B_seed ~ 10 T
- **Helion Energy (Trenta/Polaris):** Colliding FRC approach, I_p ~ 0.2 MA steady + pulsed compression
- **NIF (context reference):** Laser-driven ICF without seed field — not an MIF variant, but n_e_ig scale reference (10³⁰–10³³ m⁻³)
- **OMEGA EP / LLE (MIFEDS):** Laser-driven MIF with external B-field coils

---

## Cross-Plant Comparisons

### Plasma Current (I_p) Range

```
Tokamak           ████████████████████████████████ 0.5 – 30.0 MA
Stellarator       █ 0.0 – 0.2 MA
FRC               ██ 0.1 – 2.0 MA
Spheromak         █ 0.05 – 1.0 MA
RFP               ████ 0.5 – 5.0 MA
Magnetic Mirror    0.0 – 0.05 MA
Tandem Mirror      0.0 – 0.1 MA
Spherical Tokamak ████████ 0.5 – 10.0 MA
MIF / Inertial    █████████████████████ 0.0 – 20.0 MA (pulsed)
```

### Toroidal / Seed Field (B_T / B_seed) Range

```
Tokamak           ██████████████████ 1.0 – 13.0 T
Stellarator       ███████ 1.5 – 5.0 T
FRC               █ 0.0 – 0.1 T
Spheromak         █ 0.0 – 0.5 T
RFP               ██ 0.1 – 1.5 T
Magnetic Mirror   ████████████ 1.0 – 10.0 T
Tandem Mirror     ██████████████████ 1.0 – 15.0 T
Spherical Tokamak ████ 0.5 – 3.0 T
MIF / Inertial    ██████████████████████████████████ 0.1 – 30.0 T seed
                  (B_comp to ~10 000 T at ignition — off chart by design)
```

### Electron Density (n_e) Range — Pre-compression / MCF Regime

```
Tokamak           ████ 0.1 – 3.0 × 10²⁰ m⁻³
Stellarator       ███ 0.05 – 2.0 × 10²⁰ m⁻³
FRC               ████████████ 0.5 – 10.0 × 10²⁰ m⁻³
Spheromak         ██████ 0.1 – 5.0 × 10²⁰ m⁻³
RFP               ████ 0.2 – 3.0 × 10²⁰ m⁻³
Magnetic Mirror   █ 0.01 – 1.0 × 10²⁰ m⁻³
Tandem Mirror     ███ 0.05 – 2.0 × 10²⁰ m⁻³
Spherical Tokamak █████████ 0.2 – 8.0 × 10²⁰ m⁻³
MIF (pre-comp.)   ██ 0.1 – 10.0 × 10²⁰ m⁻³  →  ignition: ~10³² m⁻³ (off chart)
```

---

## Validation Notes

### Physics Literature

All invariants cross-referenced with:

1. **ITER Physics Basis** (Nucl. Fusion 39, 2137, 1999)
2. **Tokamak Energy Confinement Scaling** (ITER IPB98(y,2))
3. **Stellarator Optimization** (J. Nührenberg et al.)
4. **FRC Reviews** (Tuszewski, Phys. Plasmas 15, 056101, 2008)
5. **Spheromak Physics** (Brown, Phys. Plasmas 13, 056103, 2006)
6. **RFP Transport** (RFX-mod results, Nucl. Fusion 49, 2009)
7. **MagLIF Overview** (Slutz et al., Phys. Plasmas 17, 056303, 2010)
8. **Magnetized Target Fusion** (Laberge, J. Fusion Energy 27, 65, 2008)
9. **Helion FRC Compression** (Votroubek et al., J. Fusion Energy 27, 123, 2008)

### Facility Data Sources

- ITER Organization Technical Baseline
- JET / JT-60SA experimental results
- Wendelstein 7-X first plasma campaign
- NSTX-U / MAST operational limits
- TAE Technologies C-2W publications
- Sandia National Laboratories Z-Machine MagLIF experimental database
- General Fusion Magnetized Target Fusion program technical reports
- Helion Energy Trenta device publications

---

## Change Control

Any modification to plant invariants requires:

1. **Physics review** by qualified plasma physicist
2. **PQ re-execution** (GFTCL-PQ-002 tests affected by CI-002)
3. **Update timeline_v2.json** for affected plant
4. **Regression testing** with new bounds
5. **Documentation update** (this file + operator guide)

**Approval Required:**
- Physics Team Lead
- Safety Officer
- QA Manager

---

**Document End**

For questions on physics invariants, contact:  
**Email:** research@gaiaftcl.com

Norwich — S⁴ serves C⁴.
