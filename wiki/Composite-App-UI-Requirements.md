# Composite App — UI Requirements

## What the GaiaFTCL Mac Cell Must Be, Look Like, and Contain

**Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie**

> This page is a functional requirements specification. It defines what the composite application must present to the operator. It does not prescribe implementation — the three-layer architecture (Metal renderer + WKWebView + WASM) is the system as built. PQ validates the full integrated stack. This document defines what passing looks like from the human side of the glass.

---

## 1. The Three Layers and Why Each Exists

The composite app is three layers operating as one. Each layer has a job it cannot delegate to the others.

```
┌──────────────────────────────────────────────────────────────────┐
│  LAYER 1: WKWebView Dashboard (Next.js)                          │
│  The human control surface. Plant selector, telemetry readouts,  │
│  vQbit panels, terminal state indicators, mesh status, τ clock.  │
│  Lives on top. Transparent or opaque by zone.                    │
├──────────────────────────────────────────────────────────────────┤
│  LAYER 2: WASM Module (gaiafusion_substrate.wasm, ~134 KB)       │
│  Runs inside the WKWebView. Executes the UUM-8D numerical core   │
│  in the browser context. Computes closure residuals, epistemic   │
│  tags, and CALORIE/CURE/REFUSED verdicts for the web layer.      │
│  Feeds the dashboard with computed state without a network call. │
├──────────────────────────────────────────────────────────────────┤
│  LAYER 3: Metal Viewport (Rust, via gaia-metal-renderer)         │
│  Native GPU rendering of the 9 plant wireframe geometries.       │
│  60 fps. StorageModeShared. Occupies the lower portion of the    │
│  window. The dashboard sits above or overlays it.                │
└──────────────────────────────────────────────────────────────────┘
```

**Why not collapse this into one layer?**

The Metal renderer cannot compute UUM-8D residuals — it is a GPU geometry engine, not a numerical processor. The WASM module cannot drive Metal — it runs in a sandboxed JS context. The WKWebView cannot render physics-accurate 3D plant geometry at 60 fps natively. Each layer does exactly one thing it does better than the other two. PQ validates all three together, because a failure in any layer fails the composite system.

---

## 2. Window Layout

The composite app opens to a single window: **1280 × 720 pixels minimum**, resizable. The window is divided into two horizontal zones.

```
┌─────────────────────────────────────────────────────────────────┐
│  HEADER BAR (48 px)                                             │
│  GaiaFTCL logo · Plant selector (9 tabs) · Cell identity chip  │
│  τ (Bitcoin block height) · CALORIE / CURE / REFUSED badge      │
├──────────────────────────────┬──────────────────────────────────┤
│                              │  TELEMETRY PANEL (right, 320 px) │
│                              │                                  │
│   METAL VIEWPORT             │  I_p ·  B_T · n_e               │
│   (primary, fills left       │  vQbit entropy/truth plane       │
│    and centre)               │  Epistemic tag badges (M/T/I/A)  │
│                              │  Closure residual bar            │
│   9 plant wireframes,        │  Mesh status (n/9 quorum)        │
│   rotating at 60 fps         │  Domain selector                 │
│                              │  Evidence status                 │
│                              │                                  │
└──────────────────────────────┴──────────────────────────────────┘
│  STATUS BAR (32 px)                                             │
│  Rust crate versions · OQ pass count · IQ cell_id (truncated)  │
└─────────────────────────────────────────────────────────────────┘
```

The Metal viewport fills the left and centre of the window. The telemetry panel on the right is rendered by the WKWebView layer. The header bar and status bar are also WKWebView. No pixel of the Metal surface is covered by an opaque web element unless the operator explicitly enables a full-overlay mode.

---

## 3. Header Bar — Mandatory Contents

The header bar is always visible. Its contents are mandatory — a build that omits any of these elements does not pass PQ-UI.

| Element | What it shows | Source |
| --- | --- | --- |
| **GaiaFTCL wordmark** | Static: "GaiaFTCL" in the system's display font | Static |
| **Plant selector** | Nine tabs labelled: Tokamak · Stellarator · SphericalTokamak · FRC · Mirror · Spheromak · ZPinch · MIF · Inertial | User interaction → Swift → Metal geometry swap |
| **Cell identity chip** | First 8 characters of `cell_id` from `evidence/iq_receipt.json`, prefixed "CELL:" | IQ receipt |
| **τ clock** | Bitcoin block height, formatted as "τ=<height>" | NATS `gaiaftcl.tau` or TAU_NOT_IMPLEMENTED placeholder |
| **Terminal state badge** | CALORIE (green) / CURE (blue) / REFUSED (red) — current state of the local cell | WASM UUM-8D engine |

The terminal state badge is the most important element in the header. It must never be absent. During TAU_NOT_IMPLEMENTED development mode, the badge must show the WASM-computed state even without a live τ anchor.

---

## 4. Metal Viewport — What It Must Render

The Metal viewport is the reason this application exists. It must render the wireframe geometry of the currently selected plant kind at 60 fps on Apple Silicon, using the `GaiaVertex` struct (28 bytes, StorageModeShared).

### 4.1 Per-Plant Wireframe Requirements

Each of the nine plant kinds has a minimum geometry specification. The Metal renderer must produce at least these many vertices per plant. Fewer vertices triggers REFUSED (constitutional constraint C-005).

| Plant kind | USDA scope | Min vertices | Min indices | Visual character |
| --- | --- | --- | --- | --- |
| Tokamak | `Tokamak` | 48 | 96 | Nested torus + PF coil stack + D-shaped TF loops |
| Stellarator | `Stellarator` | 48 | 96 | Twisted vessel + modular coil windings, visible helical symmetry |
| Spherical Tokamak | `SphericalTokamak` | 32 | 64 | Cored sphere + dense central solenoid + asymmetric TF coils |
| FRC | `FRC` | 24 | 48 | Cylinder + end formation coils + confinement rings |
| Mirror | `Mirror` | 24 | 48 | Sparse central field rings + dense end choke coils |
| Spheromak | `Spheromak` | 32 | 64 | Spherical flux conserver + coaxial injector |
| Z-Pinch | `ZPinch` | 16 | 32 | Cylinder + electrode plates + spoke structure |
| MIF | `MIF` | 40 | 80 | Icosphere target + radial plasma guns at Fibonacci lattice sites |
| Inertial | `Inertial` | 40 | 80 | Geodesic shell + hohlraum cylinder + inward beamlines |

### 4.2 Vertex Colour Encoding

The vertex colour carries live epistemic state. The Metal shader passes vertex colour through directly (fragment_main returns in.color). The WASM layer computes the vQbit values and posts them to the WKWebView message bridge, which calls into Swift to update the vertex buffer.

| Colour channel | Source field | Meaning |
| --- | --- | --- |
| Red (R) | `vqbit_entropy` clamped to [0,1] | How much new information this measurement carries |
| Green (G) | `vqbit_truth` clamped to [0,1] | Confidence in the measurement |
| Blue (B) | Hardcoded 0.5 | Sovereign blue — indicates the Metal pipeline is live |
| Alpha (A) | Hardcoded 1.0 | Fully opaque |

A plant rendering all-black means `vqbit_entropy = 0.0` and `vqbit_truth = 0.0` — the UUM-8D engine has no information. This is valid during startup and should display with the hardcoded blue channel visible (0.0, 0.0, 0.5, 1.0 = a dark blue). It is not a REFUSED condition.

### 4.3 Plant Swap Behaviour

When the operator clicks a plant tab in the header bar, the sequence is:

1. WKWebView sends `switchPlant: { kind: "Stellarator" }` to Swift via `WKScriptMessageHandler`
2. Swift calls `renderer.upload_geometry()` with the new plant's vertex and index arrays
3. On the next `RedrawRequested` event, the renderer draws the new plant geometry
4. The WKWebView dashboard updates the telemetry panel with the new plant's channel values and epistemic tags
5. The WASM module recomputes the vQbit encoding for the new plant's baseline telemetry values
6. The header bar terminal state badge reflects the new plant's CALORIE/CURE/REFUSED state

The swap must complete within one display frame budget (16.7 ms at 60 fps). No loading spinner. No blank frame. If the new plant's geometry is not ready, the renderer holds the previous geometry until it is — it does not render zero vertices.

---

## 5. Telemetry Panel — Mandatory Contents

The telemetry panel is the operator's real-time window into the plant's physical state and the UUM-8D engine's assessment of it. Every element listed below is mandatory.

### 5.1 Channel Readouts

Three channel readouts, always visible, always current:

```
┌─────────────────────────────────┐
│  I_p   0.85 MA   [M]  ●  Blue  │
│  B_T   0.52 T    [M]  ●  Green │
│  n_e   3.5×10¹⁹  [M]  ●  Red  │
└─────────────────────────────────┘
```

Each readout shows: channel name · current value with unit · epistemic tag badge · colour dot matching the Metal channel assignment. The epistemic tag badge must use the canonical colours:

| Tag | Badge colour | Meaning |
| --- | --- | --- |
| M | Gold (#FFD700) | Measured — experimental data |
| T | Silver (#C0C0C0) | Tested — validated simulation |
| I | Bronze (#CD7F32) | Inferred — scaling law extrapolation |
| A | Grey (#808080) | Assumed — target design value |

If a channel value is NaN or Inf, the readout must show "⚠ INVALID" in red, not the numeric value, and the terminal state badge must immediately switch to REFUSED.

### 5.2 vQbit Entropy/Truth Plane

A 2D scatter plot, 200 × 200 pixels:

- X axis: `vqbit_truth` (0.0 to 1.0) — labelled "TRUTH"
- Y axis: `vqbit_entropy` (0.0 to 1.0) — labelled "ENTROPY"
- A single dot showing the current vQbit position for the active plant
- Quadrant labels:
  - Top-right (high entropy, high truth): "HIGH VALUE" — surprising and confident
  - Top-left (high entropy, low truth): "UNCERTAIN" — surprising but unconfirmed
  - Bottom-right (low entropy, high truth): "CONFIRMED" — expected and verified
  - Bottom-left (low entropy, low truth): "UNKNOWN" — no signal

The dot colour matches the terminal state: green for CALORIE, blue for CURE, red for REFUSED.

### 5.3 Closure Residual Bar

A horizontal progress bar showing the running numerical closure residual for the active plant:

- Full left (100%) = residual at maximum (far from closure)
- Full right (0%) = residual below threshold → CALORIE
- Threshold line at the position corresponding to 9.54 × 10⁻⁷
- Bar colour: red → amber → green as residual approaches threshold
- Below the bar: the numeric residual value in scientific notation, e.g. "2.34 × 10⁻⁵"

### 5.4 Mesh Status

```
MESH  ████████░  8/9 cells
Quorum: ✓ ACHIEVED   (≥5 required)
```

Nine cell indicator dots, filled for cells that have reported in the current window. The quorum status line shows ✓ ACHIEVED (green) if ≥5 cells are in agreement, or ✗ PENDING (amber) if 3-4 cells have reported, or ✗ REFUSED (red) if fewer than 3 cells or if quorum was denied.

### 5.5 Evidence Status

Three GxP status indicators:

```
IQ  ✓  PASS    evidence/iq_receipt.json
OQ  ✓  PASS    32/32 tests
PQ  ✓  PASS    81/81 swaps
```

Read from the evidence directory at startup. If any receipt is absent or shows FAIL, the indicator shows ✗ FAIL in red. The app does not refuse to start on PQ_FAIL — but the UI must display it.

---

## 6. Domain Selector

Below the telemetry panel, a domain selector allows the operator to view the UUM-8D state for any of the seven active domains. The domain selector is not a navigation element — it does not change the Metal renderer. It changes the vQbit readout in the telemetry panel to show the selected domain's current entropy, truth, and terminal state values.

| Domain | Icon | Channel mapping displayed |
| --- | --- | --- |
| Fusion | ⚛ | I_p · B_T · n_e (standard) |
| FSD | 🚗 | Positional certainty · Object certainty · Intent certainty |
| Drone | 🚁 | Formation entropy · Separation truth · Manoeuvre state |
| ATC | ✈ | Separation certainty · Conflict prediction · Sector capacity |
| Maritime | ⚓ | Position certainty · Route clearance · Weather margin |
| AML | 🔬 | Blast count certainty · Cytogenetic certainty · Mutation certainty |
| TB OWL | 🫁 | Symptom match · Test certainty · Epidemiological context |

The active domain is shown with a filled background. Clicking any domain tab posts a `switchDomain` message to the WASM module, which recomputes the vQbit entropy/truth values for that domain's current state and updates the telemetry panel. The Metal renderer always shows the fusion plant — domain switching affects only the UUM-8D numerical display.

---

## 7. Status Bar — Mandatory Contents

The status bar at the bottom of the window is always visible and always shows:

| Element | Format | Source |
| --- | --- | --- |
| Rust renderer version | `renderer v<semver>` | Compiled-in at build time |
| USD parser version | `parser v<semver>` | Compiled-in at build time |
| OQ pass count | `OQ 32/32` | Read from `evidence/oq_receipt.json` |
| Cell identity (truncated) | `CELL: <first 16 chars>` | Read from `evidence/iq_receipt.json` |
| τ status | `τ=<height>` or `τ=PENDING` | NATS or TAU_NOT_IMPLEMENTED placeholder |

---

## 8. WASM Module — What It Must Compute

The WASM module (`gaiafusion_substrate.wasm`) runs inside the WKWebView JavaScript context. It does not have access to Metal or to the filesystem. Its job is to run the UUM-8D numerical engine for the dashboard layer.

### 8.1 Required Exports

The WASM module must export these functions, callable from JavaScript:

| Export | Signature | Purpose |
| --- | --- | --- |
| `compute_vqbit` | `(entropy: f32, truth: f32, plant_kind: u32) → { entropy: f32, truth: f32, state: u32 }` | Compute vQbit encoding and terminal state for given inputs |
| `compute_closure_residual` | `(i_p: f64, b_t: f64, n_e: f64, plant_kind: u32) → f64` | Compute numerical closure residual for given telemetry |
| `validate_bounds` | `(i_p: f64, b_t: f64, n_e: f64, plant_kind: u32) → u32` | Check constitutional bounds: 0=PASS, 1=REFUSED |
| `get_epistemic_tag` | `(channel: u32, plant_kind: u32) → u32` | Return M/T/I/A tag for channel (0=I_p, 1=B_T, 2=n_e) as 0/1/2/3 |
| `constitutional_check` | `(i_p: f64, b_t: f64, n_e: f64) → u32` | Run all constitutional constraints: 0=PASS, 1=NaN/Inf, 2=Negative, 3=Bounds |

### 8.2 The WASM Module Is Not Optional

The WASM module is not a progressive enhancement. It is a constitutional layer component. The following dashboard behaviours depend on it and must not function without it:

- Terminal state badge in the header bar (CALORIE/CURE/REFUSED)
- vQbit entropy/truth plane readout
- Closure residual bar
- Domain selector vQbit recomputation
- Constitutional validation before any out-of-bounds value reaches the telemetry readout display

If the WASM module fails to load or initialise, the header bar terminal state badge must show REFUSED and the dashboard must display: "UUM-8D ENGINE UNAVAILABLE — WASM module failed to initialise. See console for details."

---

## 9. PQ Validation of the Composite App

PQ validates the full integrated stack. The following UI behaviours are PQ acceptance criteria. A UI that passes OQ tests but fails any of these is not PQ-compliant.

### 9.1 PQ-UI Test Matrix

| Test ID | What is tested | Pass criterion | REFUSED trigger |
| --- | --- | --- | --- |
| PQ-UI-001 | Plant selector — all nine tabs | Each tab click produces a Metal geometry swap within one frame budget (16.7 ms) | Tab click with zero-vertex geometry output |
| PQ-UI-002 | Terminal state badge — CALORIE | Badge shows green CALORIE when WASM compute_vqbit returns state=CALORIE | Badge absent or wrong colour |
| PQ-UI-003 | Terminal state badge — REFUSED | Badge shows red REFUSED when constitutional_check returns any non-zero code | Badge shows anything other than REFUSED |
| PQ-UI-004 | Epistemic tag badges | All 27 tags (3 channels × 9 plants) display correct M/T/I/A with correct colour | Any tag missing or mis-coloured |
| PQ-UI-005 | Channel readout — NaN injection | Injecting NaN into any channel shows "⚠ INVALID" and flips badge to REFUSED | NaN renders as a number |
| PQ-UI-006 | ICF n_e normalisation | ICF plant selected → n_e = 10³¹ displays without float overflow in readout or Metal colour | Any overflow, NaN, or Inf in display |
| PQ-UI-007 | Closure residual bar | Bar reaches 100% (rightmost) position and badge shows CALORIE when residual < 9.54×10⁻⁷ | Bar wrong direction or badge does not flip |
| PQ-UI-008 | Mesh status — quorum display | With 5 simulated cell reports, mesh shows "5/9 · Quorum ✓" | Fewer than 5 shown as quorum failure when 5 have reported |
| PQ-UI-009 | Domain selector — all seven domains | Each domain tab shows domain-appropriate channel labels in telemetry panel | Metal viewport changes on domain switch (it must not) |
| PQ-UI-010 | Evidence status — OQ count | Status bar shows "OQ 32/32" when oq_receipt.json contains rust_tests_passed=32 | Any count other than 32/32 shown as PASS |
| PQ-UI-011 | τ display | τ clock shows "τ=PENDING" when TAU_NOT_IMPLEMENTED warning is active | Crash or empty τ field |
| PQ-UI-012 | Cell identity display | Status bar shows correct first 16 characters of cell_id from iq_receipt.json | Wrong cell_id or absent |

### 9.2 The 81-Swap Matrix in the UI

The PQ-CSE 81-swap matrix (9 plants × 9 plants, all transition pairs) must be executable through the UI's plant selector. During the PQ run, a script drives the plant selector through all 81 transitions and verifies that:

- No transition produces zero vertices in the Metal viewport
- No transition causes the terminal state badge to show REFUSED (unless the telemetry bounds for the transition pair are intentionally violated as part of a SAF track test)
- No transition causes the WKWebView to crash or reload
- No transition causes the WASM module to throw a JavaScript exception

The 81-swap matrix is the single most important PQ test for the composite app. It proves that the Metal renderer, the Swift message bridge, the WKWebView dashboard, and the WASM module all handle every possible plant configuration transition correctly.

---

## 10. What the Composite App Must NOT Do

These are constitutional prohibitions for the UI. Any build that exhibits these behaviours fails PQ immediately.

1. **Must not render zero vertices.** The Metal viewport must never display a blank black frame because the plant wireframe produced no geometry. Zero vertices → REFUSED + error message.

2. **Must not display NaN as a number.** If `vqbit_entropy`, `vqbit_truth`, I_p, B_T, or n_e is NaN, the readout must show "⚠ INVALID", not a number. The WASM `constitutional_check` must catch NaN before the display layer.

3. **Must not change the Metal viewport on a domain switch.** Switching the domain selector from Fusion to AML must not change what the Metal renderer is drawing. The Metal renderer always shows fusion plant geometry. The domain selector affects only the UUM-8D dashboard panel.

4. **Must not start without IQ evidence.** If `evidence/iq_receipt.json` is absent, the app must show a startup error: "IQ receipt not found. Run `zsh scripts/iq_install.sh` before starting the application." It must not generate a fresh cell identity at app startup — IQ identity generation is an explicit operator action.

5. **Must not accept a downgraded epistemic tag.** The dashboard must not allow an operator to manually set an M-tagged channel to I or A. The epistemic tag display is read-only. The only path to tag change is a Change Control Record followed by a full OQ + PQ re-run.

6. **Must not approximate when quorum is not reached.** If the mesh status shows fewer than 5 cells in agreement, the terminal state badge must show REFUSED or PENDING — not CALORIE. The UI must not display a confidence value that was not validated by quorum.

7. **Must not use Next.js server-side rendering for live telemetry.** All live telemetry data flows through the WASM module or the Swift message bridge. No live plant state data makes a network request. The Next.js dashboard is loaded once at startup and then operates entirely offline.

---

## 11. Summary: What the Operator Sees

When the GaiaFTCL Mac Cell composite app is running correctly, the operator sees this:

**A 1280 × 720 window divided into three visible zones.** At the top, a header bar with the GaiaFTCL name, nine plant tabs, a cell identity chip, a τ clock, and a terminal state badge in green (CALORIE), blue (CURE), or red (REFUSED).

**In the left two-thirds of the window**, the Metal renderer draws a rotating 3D wireframe of the currently selected fusion plant geometry. The wireframe colours shift in real time as the vQbit entropy and truth values update — red channel brightening when a measurement carries high information content, green channel brightening when confidence is high, blue channel constant at 0.5 as evidence the Metal pipeline is alive.

**In the right third**, the WKWebView telemetry panel shows the three live channel values (I_p, B_T, n_e) with their epistemic tag badges coloured gold, silver, bronze, or grey. Below the channel readouts, the vQbit entropy/truth plane shows a dot moving in real time as the UUM-8D engine recomputes the measurement state. Below that, the closure residual bar creeps toward the green zone as measurements accumulate. Below that, the mesh status shows which cells of the nine-cell mesh are contributing to the current quorum. Below that, the domain selector allows switching between the seven application domains.

**At the bottom**, the status bar confirms the build version, OQ pass count, cell identity, and τ status.

**This is the constitutional substrate made visible.** Every pixel of the interface connects to a formally qualified, GxP-validated measurement. Nothing on screen is decorative. Everything is evidence.

---

*Composite App UI Requirements — GaiaFTCL Mac Cell*
*FortressAI Research Institute | Norwich, Connecticut*
*Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie*
