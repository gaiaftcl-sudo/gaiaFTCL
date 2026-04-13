# GaiaFusion Plant Control System — Operator's Guide

**Document ID:** GFTCL-OG-001  
**Document Version:** 1.1  
**Last Updated:** 2026-04-13  
**Status:** Controlled  
**Target Audience:** Fusion physicists, control engineers, plant operators, QA/safety teams

**Patents:** USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Installation and Qualification](#2-installation-and-qualification)
3. [User Interface Components](#3-user-interface-components)
4. [Plant Topologies](#4-plant-topologies) — 4.1 Tokamak · 4.2 Stellarator · 4.3 FRC · 4.4 Spheromak · 4.5 RFP · 4.6 Mirror · 4.7 Tandem Mirror · 4.8 Spherical Tokamak · 4.9 MIF/Inertial
5. [Telemetry Parameters](#5-telemetry-parameters) — I_p · B_T · n_e
6. [Epistemic Classification System](#6-epistemic-classification-system)
7. [Plant Swap Protocol](#7-plant-swap-protocol)
8. [Terminal States](#8-terminal-states) — CALORIE · CURE · REFUSED
9. [Mesh Status and Quorum](#9-mesh-status-and-quorum)
10. [Bitcoin τ Synchronization](#10-bitcoin-τ-synchronization)
11. [Safety Features](#11-safety-features)
12. [Troubleshooting](#12-troubleshooting)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. System Overview

### What is GaiaFusion?



**GaiaFusion** is a sovereign plant control visualization system for magnetic confinement fusion facilities. It provides:

- **Real-time telemetry visualization** for plasma parameters (I_p, B_T, n_e)
- **Nine canonical plant topologies** (tokamak, stellarator, FRC, spheromak, etc.)
- **Mesh synchronization** with 9 remote cells + Mac leaf (10-cell quorum)
- **Bitcoin-based emergent time (τ)** for cryptographic sovereignty proof
- **NATS messaging** for distributed telemetry ingestion
- **Fail-safe behaviors** with REFUSED states for out-of-bounds conditions

### Key Features

| Feature | Description |
|---|---|
| **Metal Rendering** | Hardware-accelerated wireframe geometry via Rust + Metal FFI |
| **Plant Swap** | Live switching between 9 fusion plant configurations |
| **Epistemic Tags** | M/T/I/A classification for measurement uncertainty |
| **SubGame Z** | Diagnostic eviction when mesh quorum lost |
| **Wallet-Gate** | Ethereum-style address for cell identity + authorization |

---

## 2. Installation and Qualification

GaiaFusion follows the **GAMP 5 / EU Annex 11 / FDA 21 CFR Part 11** validation lifecycle. Each Mac cell must complete three qualification phases before use in production or CERN environments.

### IQ — Installation Qualification

Run **once per machine** to verify prerequisites and generate the cell's sovereign wallet identity.

```zsh
cd GAIAOS/macos/GaiaFusion
zsh scripts/iq_install.sh
```

The IQ script verifies:
- macOS ≥ 13 Ventura, Xcode CLT, Rust ≥ 1.85, cbindgen, Metal GPU, Git
- Apple HIG compliance (dark mode detection, accent colour)
- Disk ≥ 2 GB, RAM ≥ 8 GB
- Generates secp256k1 sovereign wallet identity at `~/.gaiaftcl/`
- Presents licence agreement — accepting binds the wallet as this cell's identity

**Output:** `evidence/iq/iq_receipt.json`

### OQ — Operational Qualification

Run **after every build** to verify the compiled system functions correctly.

```zsh
zsh scripts/oq_validate.sh
```

The OQ script verifies:
- Rust renderer builds for `aarch64-apple-darwin` (debug + release)
- Static library size < 5 MB (zero-bloat guarantee — no OpenUSD)
- C header contains `gaia_metal_renderer_set_tau` and `gaia_metal_renderer_get_tau`
- Full GxP Rust test suite passes (≥ 14 tests)
- Swift build and full Swift test suite pass
- NATS (:4222) and Bitcoin heartbeat (:8850) reachability
- Git tree has no merge conflict markers

**Output:** `evidence/oq/oq_receipt.json`

### PQ — Performance Qualification

Run **for CERN sign-off** to execute all 41 validation protocols across 5 teams.

```zsh
zsh scripts/run_full_pq_validation.sh
```

| Phase | Team | Tests | Protocols |
|---|---|---|---|
| PHY | Physics | 8 | PQ-PHY-001 to PQ-PHY-008 |
| CSE | Control Systems | 12 | PQ-CSE-001 to PQ-CSE-012 |
| QA | Software Quality | 10 | PQ-QA-001 to PQ-QA-010 |
| SAF | Safety | 8 | PQ-SAF-001 to PQ-SAF-008 |
| TAU | Bitcoin τ Sync | 3 | PQ-TAU-001 to PQ-TAU-003 |
| **Total** | | **41** | |

**Output:** `evidence/pq_validation/receipts/master_pq_receipt_*.json`

**Note:** PQ-TAU tests require live NATS connectivity and Bitcoin heartbeat service. Ensure the SSH tunnel is established before running PQ.

**Full PQ specification:** [`evidence/GFTCL-PQ-002_v1.0.md`](../evidence/GFTCL-PQ-002_v1.0.md)

---

## 3. User Interface Components

### Main Viewport

The **central viewport** displays a 3D wireframe representation of the active fusion plant. The wireframe is color-coded by telemetry and terminal state:

- **Green:** CALORIE (normal operation)
- **Yellow:** CURE (degraded but functional)
- **Red:** REFUSED (out-of-bounds, safety violation)

### Telemetry Panel

Displays three primary plasma parameters:

| Parameter | Symbol | Unit | Typical Range | Epistemic Tag |
|---|---|---|---|---|
| Plasma Current | I_p | MA (megaamperes) | 0 - 30 | [M/T/I/A] |
| Toroidal Magnetic Field | B_T | T (tesla) | 0 - 13 | [M/T/I/A] |
| Electron Density | n_e | 10²⁰ m⁻³ | 0 - 10 | [M/T/I/A] |

**Example Display:**

```
I_p:  15.2 MA  [M] ← Measured
B_T:   5.5 T   [T] ← Tested
n_e:   1.0 × 10²⁰ m⁻³  [I] ← Inferred
```

### Plant Selector

Dropdown menu or picker for switching between plant types:

1. Tokamak
2. Stellarator
3. Field-Reversed Configuration (FRC)
4. Spheromak
5. Reversed-Field Pinch (RFP)
6. Magnetic Mirror
7. Tandem Mirror
8. Spherical Tokamak
9. Field-Reversed Configuration (alternate alias)

### Mesh Status Indicator

Shows the health of all 10 cells in the sovereign mesh:

```
Mesh Quorum: 10/10 ✓
- gaiaftcl-hcloud-hel1-01: ✓ (Primary Head)
- gaiaftcl-hcloud-hel1-02: ✓
- ...
- gaiaftcl-mac-fusion-leaf: ✓
```

### Bitcoin τ Display

Shows the current Bitcoin block height (emergent time):

```
Bitcoin τ: 840,125 ± 0 blocks
Last Update: 2026-04-13T17:30:00Z
```

---

## 4. Plant Topologies

### 4.1 Tokamak

**Geometry:** Toroidal chamber with 16 toroidal field coils  
**Magnetic Confinement:** External coils create toroidal + poloidal fields  
**Key Feature:** Plasma current (I_p) sustains internal poloidal field

**Wireframe Appearance:**
- Outer torus (vacuum vessel)
- 16 vertical toroidal field coils (D-shaped)
- Inner poloidal field coil ring

**Operational Parameters:**
- I_p: 0.5 - 30.0 MA
- B_T: 1.0 - 13.0 T
- n_e: 0.1 - 3.0 × 10²⁰ m⁻³

**Physics Notes:**
- Most common fusion reactor design (ITER, JET, SPARC)
- Requires active current drive or inductive startup
- q-factor (safety factor) must be > 1 for stability

---

### 4.2 Stellarator

**Geometry:** Twisted toroidal coils (helical symmetry)  
**Magnetic Confinement:** 3D-shaped external coils with no plasma current  
**Key Feature:** I_p ≈ 0 (steady-state operation without current drive)

**Wireframe Appearance:**
- Helically twisted torus
- Non-axisymmetric coil structure
- 5-10 field periods

**Operational Parameters:**
- I_p: 0.0 - 0.2 MA
- B_T: 1.5 - 5.0 T
- n_e: 0.05 - 2.0 × 10²⁰ m⁻³

**Physics Notes:**
- No disruptions (inherently stable)
- Expensive to build due to complex 3D coil shapes
- Example: Wendelstein 7-X

---

### 4.3 Field-Reversed Configuration (FRC)

**Geometry:** Elongated, compact torus  
**Magnetic Confinement:** Self-organized reversed magnetic field  
**Key Feature:** External B_T ≈ 0, plasma creates internal field

**Wireframe Appearance:**
- Elongated cylindrical plasma
- Minimal external coils
- Field reversal at separatrix

**Operational Parameters:**
- I_p: 0.1 - 2.0 MA
- B_T: 0.0 - 0.1 T
- n_e: 0.5 - 10.0 × 10²⁰ m⁻³

**Physics Notes:**
- High-β (plasma pressure / magnetic pressure ratio)
- Compact design (attractive for small reactors)
- Example: TAE Technologies, Helion Energy

---

### 4.4 Spheromak

**Geometry:** Spherical torus with self-generated fields  
**Magnetic Confinement:** Toroidal + poloidal currents in plasma  
**Key Feature:** No external toroidal field coils (self-organized)

**Wireframe Appearance:**
- Compact spherical plasma
- Minimal support structure
- Internal current pathways

**Operational Parameters:**
- I_p: 0.05 - 1.0 MA
- B_T: 0.0 - 0.5 T (self-generated)
- n_e: 0.1 - 5.0 × 10²⁰ m⁻³

**Physics Notes:**
- Self-organizing magnetic structure
- Potential for low-cost fusion
- Example: CTFusion, HIT-SI

---

### 4.5 Reversed-Field Pinch (RFP)

**Geometry:** Toroidal with reversed edge magnetic field  
**Magnetic Confinement:** High plasma current, reversed B_T at edge  
**Key Feature:** q(a) < 0 (safety factor reverses at plasma boundary)

**Wireframe Appearance:**
- Toroidal chamber
- Strong poloidal field coils
- Edge field reversal zone

**Operational Parameters:**
- I_p: 0.5 - 5.0 MA
- B_T: 0.1 - 1.5 T
- n_e: 0.2 - 3.0 × 10²⁰ m⁻³

**Physics Notes:**
- Lower magnetic field than tokamak (lower coil stress)
- Prone to magnetic turbulence
- Example: RFX-mod

---

### 4.6 Magnetic Mirror

**Geometry:** Straight cylinder with magnetic "plugs" at ends  
**Magnetic Confinement:** Axial field with peak at ends (mirror ratio)  
**Key Feature:** Open field lines (plasma escapes at ends)

**Wireframe Appearance:**
- Cylindrical plasma region
- Strong end coils (Yin-Yang or baseball coils)
- Open field lines

**Operational Parameters:**
- I_p: 0.0 - 0.05 MA
- B_T: 1.0 - 10.0 T
- n_e: 0.01 - 1.0 × 10²⁰ m⁻³

**Physics Notes:**
- Poor confinement due to end losses
- Historically abandoned for fusion energy
- Still used for plasma physics research

---

### 4.7 Tandem Mirror

**Geometry:** Central cell with electrostatic end plugs  
**Magnetic Confinement:** Magnetic mirror + electrostatic potential  
**Key Feature:** End plugs improve confinement over simple mirror

**Wireframe Appearance:**
- Central solenoid (main confinement region)
- Strong magnetic end plugs
- Potential well at ends

**Operational Parameters:**
- I_p: 0.0 - 0.1 MA
- B_T: 1.0 - 15.0 T
- n_e: 0.05 - 2.0 × 10²⁰ m⁻³

**Physics Notes:**
- Ambipolar potential traps ions
- Better than simple mirror, still challenging for net energy
- Example: TMX at LLNL

---

### 4.8 Spherical Tokamak

**Geometry:** Low-aspect-ratio tokamak (A < 2)  
**Magnetic Confinement:** Compact torus with high β capability  
**Key Feature:** "Cored apple" shape, high bootstrap current fraction

**Wireframe Appearance:**
- Very compact toroidal plasma
- Thick center stack (small major radius)
- D-shaped cross-section

**Operational Parameters:**
- I_p: 0.5 - 10.0 MA
- B_T: 0.5 - 3.0 T
- n_e: 0.2 - 8.0 × 10²⁰ m⁻³

**Physics Notes:**
- High natural stability (high β_N)
- Compact design (power plant advantage)
- Example: NSTX, MAST, ST40

---

### 4.9 MIF / Inertial (Magnetized Inertial Fusion)

**Geometry:** Cylindrical or spherical target with magnetized fuel  
**Magnetic Confinement:** Hybrid — applied field slows thermal conduction during implosion  
**Key Feature:** Pulsed operation; imploding liner or laser drives compression of pre-magnetized target

**Wireframe Appearance:**
- Cylindrical liner or spherical chamber
- External coil providing seed magnetic field
- Compression driver (rails, explosives, or laser)

**Operational Parameters:**
- I_p: 0.0 – 20.0 MA (pulsed, liner current)
- B_T: 0.1 – 1000+ T (seed field → compressed field at ignition)
- n_e: 10²⁶ – 10³² m⁻³ (ignition-density; orders of magnitude above MCF)

**Physics Notes:**
- Intermediate between inertial confinement fusion (ICF) and magnetic confinement fusion (MCF)
- The magnetic seed field suppresses thermal transport during compression
- Pulsed — each shot is a discrete fusion event, not steady-state
- n_e at ignition is extreme (compare: tokamak n_e ~ 10²⁰ m⁻³)
- Examples: Sandia Z-Machine (z-pinch MIF), Helion Energy, General Fusion (acoustic compression)

**Operator Note:** MIF/Inertial plants use the `mif` or `inertial` canonical identifier in PlantKindsCatalog. The renderer maps the plant to a cylindrical wireframe geometry. Telemetry bounds are pre-shot (seed field regime); post-shot ignition values are not tracked in the control system.

---

## 5. Telemetry Parameters

### Plasma Current (I_p)

**Definition:** Total toroidal current flowing through the plasma (amperes)

**Physics Significance:**
- Sustains internal poloidal magnetic field
- Drives magnetic shear (stability)
- Related to confinement time via Lawson criterion

**Measurement Method:**
- Rogowski coils around plasma (direct current measurement)
- Magnetic diagnostics (inferred from flux surfaces)

**Typical Values:**
- Small tokamaks: 0.1 - 1.0 MA
- Large tokamaks (ITER): 15 - 30 MA
- Stellarators: ~0 MA (no ohmic current)

**Safety Limits:**
- Exceeding design I_p can cause coil damage
- Too low I_p → loss of confinement
- Sudden loss (disruption) → structural damage

---

### Toroidal Magnetic Field (B_T)

**Definition:** External magnetic field in toroidal direction (tesla)

**Physics Significance:**
- Primary confinement field
- Determines plasma β limit (β = plasma pressure / magnetic pressure)
- Sets fusion power density (P_fusion ∝ B_T^4)

**Measurement Method:**
- Hall probes
- Rogowski coils
- Calculated from coil currents

**Typical Values:**
- Small experiments: 1 - 3 T
- Large tokamaks: 5 - 13 T (ITER: 5.3 T)
- Superconducting tokamaks: up to 20 T (SPARC)

**Safety Limits:**
- Exceeding coil rating → quench (superconducting magnets)
- Field asymmetry → locked modes
- Loss of field → plasma collapse

---

### Electron Density (n_e)

**Definition:** Number of electrons per cubic meter (m⁻³)

**Physics Significance:**
- Determines collision frequency (classical transport)
- Related to fusion power (P_fusion ∝ n_e^2)
- High density → better confinement (up to Greenwald limit)

**Measurement Method:**
- Interferometry (line-integrated density)
- Thomson scattering (localized density profile)
- Reflectometry (edge density)

**Typical Values:**
- Low-density experiments: 10^19 m⁻³
- High-performance plasmas: 10^20 m⁻³
- Greenwald limit: n_G = I_p / (π a^2) (MA, m)

**Safety Limits:**
- Too high density → disruptions (Greenwald limit)
- Too low density → runaway electrons
- Density asymmetry → MHD instabilities

---

## 6. Epistemic Classification System

GaiaFusion uses a **four-level epistemic tag system** to indicate measurement uncertainty:

| Tag | Name | Definition | Example |
|---|---|---|---|
| **[M]** | Measured | Direct sensor reading | I_p from Rogowski coil |
| **[T]** | Tested | Derived from multiple measurements | q-factor from magnetics |
| **[I]** | Inferred | Model-based calculation | Core temperature from edge |
| **[A]** | Assumed | Placeholder or default value | Pre-shot plasma density |

### Why Epistemic Tags Matter

In fusion control systems, **not all data is created equal**. A [M] value has high confidence, while an [A] value is speculative. Operators must know:

1. **Decision weight:** [M] values should drive control actions; [A] values should not.
2. **Alarm thresholds:** Only trigger alarms on [M] or [T] violations.
3. **Physics validation:** [I] values require cross-checks with [M] data.

### Displaying Epistemic Tags

**UI Example:**

```
┌─────────────────────────────────────┐
│ Plasma Telemetry                    │
├─────────────────────────────────────┤
│ I_p:  15.2 MA  [M] ✓                │  Green = [M]
│ B_T:   5.5 T   [T] ⚠                │  Yellow = [T] or [I]
│ n_e:   1.0 × 10²⁰ m⁻³  [I] ⚠        │
└─────────────────────────────────────┘
```

### Changing Epistemic Classification

Operators can manually override tags (e.g., promote [I] to [M] after validation):

1. Right-click telemetry value
2. Select "Set Epistemic Class"
3. Choose M / T / I / A
4. System logs change for audit

---

## 7. Plant Swap Protocol

### What is a Plant Swap?

A **plant swap** is the process of switching from one fusion topology to another (e.g., tokamak → stellarator). This requires:

1. Unloading current plant geometry
2. Clearing telemetry state
3. Loading new plant USD file
4. Re-initializing renderer
5. Validating new plant operational

### Swap Lifecycle States

```
USER INITIATES SWAP
        ↓
    REQUESTED ────→ (validate target plant exists)
        ↓
    DRAINING ─────→ (unload old geometry + clear state)
        ↓
    COMMITTED ────→ (load new plant USD + parse primitives)
        ↓
    VERIFIED ─────→ (renderer active, telemetry ready)
```

### Operator Actions

**To Initiate Swap:**
1. Select target plant from dropdown
2. Click "Swap Plant" button
3. Monitor lifecycle state in UI

**Swap Duration:**
- Typical: 500 ms - 2 seconds
- Depends on plant complexity (vertex count)

**Cancellation:**
- During DRAINING, press "Cancel Swap"
- System reverts to original plant

### Safety Interlocks

- **Mesh Quorum:** Swap blocked if quorum < 9/10
- **Terminal State:** Swap blocked if current state = REFUSED
- **Telemetry Active:** Swap blocked if live telemetry ingestion ongoing

---

## 8. Terminal States

GaiaFusion operates in one of three terminal states at all times:

### CALORIE (Normal Operation)

**Definition:** System is functioning correctly; telemetry within bounds; no safety violations.

**Visual Indicators:**
- Wireframe color: **Green**
- Status bar: "CALORIE ✓"
- All telemetry values within physics limits

**Operator Action:** None required (normal operation)

---

### CURE (Degraded But Functional)

**Definition:** System is operating with degraded performance; non-critical anomaly detected; requires attention but not immediate shutdown.

**Visual Indicators:**
- Wireframe color: **Yellow**
- Status bar: "CURE ⚠"
- Warning message in UI

**Example Conditions:**
- Mesh quorum = 9/10 (one cell offline)
- Telemetry near upper/lower bounds
- Epistemic tag degradation (M → I)

**Operator Action:** Investigate warning; prepare for potential intervention

---

### REFUSED (Safety Violation)

**Definition:** System has detected a critical safety violation; telemetry out of bounds; mesh quorum lost; immediate action required.

**Visual Indicators:**
- Wireframe color: **Red**
- Status bar: "REFUSED ✗"
- Alarm sound (if enabled)
- Detailed refusal reason in UI

**Example Conditions:**
- I_p exceeds maximum design value (e.g., 35 MA on 30 MA tokamak)
- Mesh quorum < 8/10 (SubGame Z diagnostic eviction)
- NATS connection lost for > 30 seconds
- Unauthorized wallet address (wallet-gate rejection)

**Operator Action:**
1. Read refusal reason in UI
2. Verify telemetry values against physics limits
3. If false alarm: acknowledge and reset
4. If genuine: initiate emergency shutdown protocol
5. Log Non-Conformance Report (NCR)

---

## 9. Mesh Status and Quorum

### What is the Mesh?

GaiaFusion is part of a **10-cell sovereign mesh**:

- **9 remote cells:** Hetzner + Netcup fleet (WAN-connected)
- **1 local cell:** Mac fusion leaf (127.0.0.1 loopback)

Each cell:
- Has a unique wallet address (Ethereum-style 0x...)
- Publishes health status to NATS (`gaiaftcl.fusion.mesh_mooring.v1`)
- Participates in Bitcoin τ synchronization

### Quorum Logic

**Quorum** = number of healthy cells out of 10.

| Quorum | Status | Behavior |
|---|---|---|
| 10/10 | ✅ OPTIMAL | Normal operation, all mesh features available |
| 9/10 | ⚠️ DEGRADED | One cell offline, system functional |
| 8/10 | ⚠️ WARNING | Two cells offline, reduced redundancy |
| < 8/10 | ❌ CRITICAL | SubGame Z fires, diagnostic eviction, telemetry stopped |

### SubGame Z Diagnostic Eviction

**Trigger:** Quorum < 8/10  
**Effect:** System enters REFUSED state, stops telemetry ingestion, alerts operator  
**Rationale:** With < 80% mesh availability, data integrity cannot be guaranteed

**Recovery:**
1. Restore downed cells
2. Wait for quorum ≥ 8/10
3. System automatically exits REFUSED
4. Resume telemetry ingestion

---

## 10. Bitcoin τ Synchronization

### What is Bitcoin τ (Tau)?

**τ** (tau) is the **Bitcoin block height**, used as an immutable time reference across the sovereign mesh. Instead of relying on system clocks (which can drift or be manipulated), GaiaFusion uses Bitcoin's mainnet blockchain as a **global, trustless timestamp**.

### Why Bitcoin Time?

1. **Immutable:** Once a block is mined, its height is permanent
2. **Distributed:** All cells observe the same τ (±2 blocks tolerance)
3. **Sovereign:** No central time authority required
4. **Cryptographic:** Block hashes prove temporal ordering

### How It Works

```
Bitcoin Core (Mainnet)
        ↓ (RPC poll every 30s)
bitcoin-heartbeat service (port 8850)
        ↓ (publish to NATS)
gaiaftcl.bitcoin.heartbeat
        ↓ (subscribe)
Mac GaiaFusion.app
        ↓ (update renderer)
Rust Metal Renderer (self.tau)
```

### Operator View

**τ Display:**

```
Bitcoin τ: 840,125
Last Update: 23 seconds ago
Mesh Δτ: ±1 block
Status: SYNCHRONIZED ✓
```

**Interpretation:**
- **τ = 840,125:** Current Bitcoin block height
- **Last Update: 23s:** Time since last NATS heartbeat received
- **Mesh Δτ: ±1:** All 10 cells within 1 block of each other
- **Status: SYNCHRONIZED:** τ is valid for all cells

### Troubleshooting τ Issues

| Symptom | Cause | Solution |
|---|---|---|
| τ not updating | NATS disconnected | Check network, restart NATS service |
| Δτ > 2 blocks | Cell Bitcoin node lagging | Resync Bitcoin Core on slow cell |
| τ = 0 | bitcoin-heartbeat not running | Deploy service to mesh cells |

---

## 11. Safety Features

### 1. Telemetry Bounds Checking

All telemetry values are validated against physics limits defined in `timeline_v2.json`. Out-of-bounds values trigger **REFUSED** state.

**Example:**
- Tokamak I_p max = 30.0 MA
- If I_p = 35.0 MA → **REFUSED** (coil damage risk)

### 2. Mesh Quorum Monitoring

System continuously monitors 10-cell health. If quorum < 8/10, **SubGame Z** fires, stopping telemetry to prevent bad data ingestion.

### 3. Wallet-Gate Authorization

Only cells with authorized wallet addresses (stored in ArangoDB `authorized_wallets` collection) can access mesh gateway. Unauthorized cells receive **HTTP 402 PAYMENT_REQUIRED**.

### 4. NATS Connection Watchdog

If NATS connection lost for > 30 seconds, system enters **REFUSED** state and displays "NO DATA" (no stale telemetry).

### 5. Epistemic Tag Degradation Alerts

If measured [M] telemetry degrades to [I] or [A], system warns operator of reduced confidence.

### 6. Emergency Disengage

Operator can manually stop telemetry ingestion via "Disengage" button, forcing system into safe idle state.

---

## 12. Troubleshooting

### Common Issues

#### Issue: "NATS Connection Failed"

**Symptoms:** No telemetry updates, mesh status shows 0/10 cells

**Causes:**
- NATS tunnel not established (port 4222 unreachable)
- Firewall blocking connection
- NATS server down on head cell

**Solution:**
1. Verify SSH tunnel: `ssh -L 4222:localhost:4222 root@77.42.85.60`
2. Test NATS connectivity: `telnet localhost 4222`
3. Check head cell NATS status: `ssh root@77.42.85.60 "docker ps | grep nats"`

---

#### Issue: "Mesh Quorum < 8/10"

**Symptoms:** SubGame Z fired, telemetry stopped, REFUSED state

**Causes:**
- Multiple mesh cells offline
- Network partition
- Cells not publishing health status

**Solution:**
1. Run mesh health check: `scripts/verify_mesh_bitcoin_heartbeat.sh`
2. SSH to downed cells and restart services
3. Wait for quorum to recover ≥ 8/10

---

#### Issue: "Bitcoin τ Not Synchronized (Δτ > 2)"

**Symptoms:** τ display shows "OUT OF SYNC ✗"

**Causes:**
- One or more cells have stale Bitcoin node
- Bitcoin Core not synced to mainnet tip
- Network latency between cells

**Solution:**
1. Check Bitcoin Core status on each cell: `bitcoin-cli getblockchaininfo`
2. Verify `"blocks"` matches current mainnet height
3. If behind, wait for sync or restart `bitcoind`

---

#### Issue: "Plant Swap Stuck in DRAINING"

**Symptoms:** Swap initiated but never reaches COMMITTED

**Causes:**
- USD file missing or corrupted
- Renderer failed to release old geometry
- Memory allocation failure

**Solution:**
1. Cancel swap and retry
2. Check USD file exists: `ls -la Resources/usd/plants/[plant]/root.usda`
3. Restart GaiaFusion.app

---

#### Issue: "Wireframe Not Rendering (Black Screen)"

**Symptoms:** 3D viewport blank, no plant geometry

**Causes:**
- Metal renderer initialization failed
- CAMetalLayer not created
- Rust library not linked

**Solution:**
1. Check console for Metal errors: `log stream --predicate 'subsystem == "com.gaiaftcl.fusion"'`
2. Verify Rust library exists: `ls -la MetalRenderer/lib/libgaia_metal_renderer.a`
3. Rebuild Rust renderer: `cd MetalRenderer && bash build_rust.sh`

---

#### Issue: "Telemetry Values Frozen"

**Symptoms:** I_p / B_T / n_e not updating despite NATS connected

**Causes:**
- No telemetry being published to NATS
- Wrong NATS subject subscription
- Epistemic boundary preventing updates

**Solution:**
1. Check NATS traffic: `nats sub "gaiaftcl.fusion.cell.status.v1"`
2. Verify subject names in app settings
3. Check epistemic tags (if all [A], may not update)

---

## Glossary

| Term | Definition |
|---|---|
| **I_p** | Plasma current (MA) |
| **B_T** | Toroidal magnetic field (T) |
| **n_e** | Electron density (10²⁰ m⁻³) |
| **τ (tau)** | Bitcoin block height (emergent time) |
| **Quorum** | Number of healthy mesh cells out of 10 |
| **SubGame Z** | Diagnostic eviction protocol when quorum < 8 |
| **Epistemic Tag** | M/T/I/A classification for measurement uncertainty |
| **Terminal State** | CALORIE / CURE / REFUSED |
| **Plant Swap** | Switching between fusion topologies |
| **Wallet-Gate** | Authorization system using Ethereum-style addresses |
| **NATS** | Messaging substrate for distributed telemetry |

---

**Document End**

For technical support, contact:  
**Email:** research@gaiaftcl.com  
**Documentation:** `/Users/richardgillespie/Documents/FoT8D/GAIAOS/macos/GaiaFusion/docs/`

Norwich — S⁴ serves C⁴.
