# Plant Catalogue

The nine canonical fusion plant kinds supported by GaiaFTCL. Each kind has a defined wireframe topology, telemetry operating window, and epistemic classification for each telemetry channel.

**Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie**

---

## Epistemic Classification

Every telemetry value carries a tag that records how well-established it is.

| Tag | Name | Meaning |
| --- | --- | --- |
| M | Measured | Derived from direct experimental measurement at an operating facility |
| T | Tested | Derived from validated simulation or laboratory test |
| I | Inferred | Derived from physical scaling laws or extrapolation |
| A | Assumed | Assumed from target design or theoretical prediction |

Tags are read-only at runtime. A channel tagged M may not be re-tagged I or A without a Change Control Record.

---

## Telemetry Channels

| Channel | Physical quantity | Units | Colour mapping |
| --- | --- | --- | --- |
| I_p | Plasma current | MA (megaamperes) | Blue channel |
| B_T | Toroidal magnetic field | T (tesla) | Green channel |
| n_e | Electron density | m⁻³ | Red channel |

---

## 1. Tokamak

**Confinement approach:** Axisymmetric toroidal confinement via external TF and PF coils.

**Wireframe geometry:** Nested torus + PF coil stack + D-shaped TF loops. Minimum 48 vertices, 96 indices.

**USDA scope name:** `Tokamak`

**Telemetry bounds (NSTX-U baseline):**

| Channel | Baseline | Min | Max | Unit | Epistemic |
| --- | --- | --- | --- | --- | --- |
| I_p | 0.85 | 0.50 | 2.00 | MA | M |
| B_T | 0.52 | 0.40 | 1.00 | T | M |
| n_e | 3.5×10¹⁹ | 1×10¹⁹ | 1×10²⁰ | m⁻³ | M |

**Physics constraints:**
- I_p > 0.5 MA required for ohmic heating
- B_T > 0.4 T required for confinement
- n_e below 1×10¹⁹ m⁻³ is too thin for confinement; above 1×10²⁰ m⁻³ risks disruption

---

## 2. Stellarator

**Confinement approach:** 3D twisted torus geometry. No plasma current — confinement is entirely from twisted external coils.

**Wireframe geometry:** Twisted vessel + modular coil windings. Minimum 48 vertices, 96 indices.

**USDA scope name:** `Stellarator`

**Telemetry bounds:**

| Channel | Baseline | Min | Max | Unit | Epistemic |
| --- | --- | --- | --- | --- | --- |
| I_p | 0.00 | 0.00 | 0.05 | MA | T |
| B_T | 2.50 | 1.50 | 3.50 | T | M |
| n_e | 2.0×10¹⁹ | 5×10¹⁸ | 5×10¹⁹ | m⁻³ | T |

**Physics constraints:**
- I_p > 0.05 MA indicates a configuration error — stellarators do not drive plasma current
- High B_T (1.5–3.5 T) is required because there is no plasma current to assist confinement

---

## 3. Spherical Tokamak

**Confinement approach:** Low aspect ratio tokamak. The plasma is a tight sphere around a dense central solenoid rather than a wide torus.

**Wireframe geometry:** Cored sphere + dense central solenoid + asymmetric TF coils. Minimum 32 vertices, 64 indices.

**USDA scope name:** `SphericalTokamak`

**Telemetry bounds:**

| Channel | Baseline | Min | Max | Unit | Epistemic |
| --- | --- | --- | --- | --- | --- |
| I_p | 1.20 | 0.80 | 2.50 | MA | M |
| B_T | 0.30 | 0.20 | 0.60 | T | M |
| n_e | 5.0×10¹⁹ | 2×10¹⁹ | 2×10²⁰ | m⁻³ | M |

**Physics constraints:**
- Low aspect ratio allows lower B_T than a conventional tokamak for the same plasma current
- Higher I_p than tokamak for the same machine size because the plasma is more compressed

---

## 4. Field-Reversed Configuration (FRC)

**Confinement approach:** Linear device, no significant toroidal field. The plasma is a self-organized compact torus inside a straight cylinder.

**Wireframe geometry:** Cylinder + end formation coils + confinement rings. Minimum 24 vertices, 48 indices.

**USDA scope name:** `FRC`

**Telemetry bounds:**

| Channel | Baseline | Min | Max | Unit | Epistemic |
| --- | --- | --- | --- | --- | --- |
| I_p | 0.10 | 0.01 | 0.50 | MA | T |
| B_T | 0.00 | 0.00 | 0.10 | T | T |
| n_e | 1.0×10²¹ | 1×10²⁰ | 1×10²² | m⁻³ | I |

**Physics constraints:**
- B_T ≈ 0 by definition — FRC is a field-reversed configuration, no toroidal field
- Very high density operation; n_e orders of magnitude above tokamak

---

## 5. Mirror

**Confinement approach:** Open magnetic mirror. End choke coils create regions of high field that reflect escaping particles back into the confinement zone.

**Wireframe geometry:** Sparse central field rings + dense end choke coils. Minimum 24 vertices, 48 indices.

**USDA scope name:** `Mirror`

**Telemetry bounds:**

| Channel | Baseline | Min | Max | Unit | Epistemic |
| --- | --- | --- | --- | --- | --- |
| I_p | 0.05 | 0.00 | 0.20 | MA | T |
| B_T | 1.00 | 0.50 | 3.00 | T | M |
| n_e | 5.0×10¹⁸ | 1×10¹⁸ | 1×10¹⁹ | m⁻³ | I |

**Physics constraints:**
- Open-ended geometry means lower achievable density than closed confinement
- High B_T needed at the mirrors to create the magnetic bottle effect

---

## 6. Spheromak

**Confinement approach:** Self-organized compact torus formed by a coaxial injector. The plasma contains its own toroidal and poloidal fields without external coils threading the plasma.

**Wireframe geometry:** Spherical flux conserver + coaxial injector. Minimum 32 vertices, 64 indices.

**USDA scope name:** `Spheromak`

**Telemetry bounds:**

| Channel | Baseline | Min | Max | Unit | Epistemic |
| --- | --- | --- | --- | --- | --- |
| I_p | 0.30 | 0.10 | 0.80 | MA | T |
| B_T | 0.10 | 0.05 | 0.30 | T | I |
| n_e | 1.0×10²⁰ | 1×10¹⁹ | 1×10²¹ | m⁻³ | I |

**Physics constraints:**
- Self-organization means the magnetic field geometry is maintained by the plasma current itself, not external coils
- B_T and n_e are inferred values — direct measurement at scale is limited

---

## 7. Z-Pinch

**Confinement approach:** Pure pinch. A very high axial current (I_p) creates an azimuthal magnetic field that pinches the plasma inward. No external toroidal field.

**Wireframe geometry:** Cylinder + electrode plates + spoke structure. Minimum 16 vertices, 32 indices.

**USDA scope name:** `ZPinch`

**Telemetry bounds:**

| Channel | Baseline | Min | Max | Unit | Epistemic |
| --- | --- | --- | --- | --- | --- |
| I_p | 2.00 | 0.50 | 20.0 | MA | M |
| B_T | 0.00 | 0.00 | 0.05 | T | T |
| n_e | 1.0×10²² | 1×10²¹ | 1×10²³ | m⁻³ | I |

**Physics constraints:**
- Requires very high plasma current — highest I_p of all nine plant kinds
- B_T ≈ 0 by definition (pinch is produced by the axial current, not an external toroidal coil)
- Very high density operation — density is produced by the pinch compression itself

---

## 8. Magneto-Inertial Fusion (MIF)

**Confinement approach:** Hybrid approach combining magnetic and inertial confinement. Radial plasma jets converge on a magnetized target from multiple Fibonacci-spaced positions.

**Wireframe geometry:** Icosphere target + radial plasma guns at Fibonacci lattice sites. Minimum 40 vertices, 80 indices.

**USDA scope name:** `MIF`

**Telemetry bounds:**

| Channel | Baseline | Min | Max | Unit | Epistemic |
| --- | --- | --- | --- | --- | --- |
| I_p | 0.50 | 0.10 | 5.00 | MA | T |
| B_T | 0.50 | 0.10 | 2.00 | T | I |
| n_e | 1.0×10²³ | 1×10²² | 1×10²⁵ | m⁻³ | A |

**Physics constraints:**
- Targets ignition-relevant densities; n_e bounds are assumed from target design parameters
- The Fibonacci gun placement is a controlled configuration item — any change requires full PQ-CSE re-execution

---

## 9. Inertial Confinement Fusion (ICF)

**Confinement approach:** Laser-driven implosion. Inward-pointing laser beamlines deliver energy symmetrically to a hohlraum, driving a spherical implosion of the fuel capsule.

**Wireframe geometry:** Geodesic shell + hohlraum cylinder + inward beamlines. Minimum 40 vertices, 80 indices.

**USDA scope name:** `Inertial`

**Telemetry bounds:**

| Channel | Baseline | Min | Max | Unit | Epistemic |
| --- | --- | --- | --- | --- | --- |
| I_p | 0.00 | 0.00 | 0.01 | MA | A |
| B_T | 0.00 | 0.00 | 0.01 | T | A |
| n_e | 1.0×10³¹ | 1×10³⁰ | 1×10³² | m⁻³ | A |

**Physics constraints:**
- ICF uses laser drivers, not magnetic confinement. I_p ≈ 0 and B_T ≈ 0 by definition
- Electron density at ignition is extreme — orders of magnitude above all magnetic confinement approaches
- The renderer must normalise n_e to [0.0, 1.0] without float overflow for the red channel (PQ-PHY-006)

---

## Cross-Plant Invariant Rules

These apply to all nine plant kinds at all times.

1. **NaN/Inf prohibition** — Any NaN or Inf in I_p, B_T, or n_e is an unconditional critical failure. The system must enter REFUSED and halt. Verified by PQ-SAF-002.
2. **Negative prohibition** — I_p, B_T, and n_e must be ≥ 0.0. Verified by PQ-PHY-007.
3. **Colour normalisation** — All three values must normalise to [0.0, 1.0] for Metal renderer colour mapping. The raw telemetry value is always logged; only the display value is clamped. Verified by PQ-CSE-008.
4. **Epistemic tag preservation** — M/T/I/A tags must not change during a render frame or across a plant swap. Verified by PQ-PHY-005.
5. **Non-zero geometry** — Every plant wireframe must produce vertex_count > 0. Zero-vertex geometry triggers REFUSED. Verified by PQ-CSE-001 and PQ-CSE-007.
