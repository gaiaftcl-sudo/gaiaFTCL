# GAMP5-VQBIT-QUANTUM-IQ-OQ-PQ-001
## The vQbit Kills the Qubit

**Repository anchor:** `/Users/richardgillespie/Documents/AppleGaiaFTCL`
**Hardware IQ anchor:** `docs/reports/GAMP5-IQ-HARDWARE.md`
**Patents:** USPTO 19/460,960 | USPTO 19/096,071
**Closure proof:** Computational Closure of Quantum Algorithms on Classical
Substrates, Gillespie 2026 (Field-of-Fields V2)
**Foundational framework:** UUM-8D: Closure of the Unified Model Problem, Gillespie 2026
**Shor refutation:** Systematic Refutation of Shor's Quantum Limitations via MPS,
Gillespie 2025, FortressAI Research Institute

---


## Section 0: Apple Platform Context — Xcode 26.4 + Distribution + Metered Access

**Document context:** This section covers the Apple platform foundation for
the vQbit VM as a distributable Mac application. It does not modify the GAMP 5
qualification protocol — it governs how the qualified instrument is packaged,
distributed, and accessed.

---

### 0.1 Xcode 26.4 — What Changed for This Build

**Xcode 26.4.1 is the required toolchain.** It ships Swift 6.3, macOS 26.4
SDK, visionOS 26.4 SDK. It fixes Swift compiler stack-allocation bugs in
async functions (particularly `swift_asyncLet_finish`) that directly affect
the three-service sovereign architecture (NATS → vQbit → Franklin).
Use Xcode 26.4 for all qualification builds. Address Sanitizer and Thread
Sanitizer hang on earlier versions against macOS 26.4.

**SceneKit is permanently deprecated** across all Apple platforms as of
Xcode 26. The vQbit VM is on RealityKit. This is the correct and only path.

**RealityKit 4 runs identically across Mac, iPad, iPhone, and Vision Pro.**
The vQbit VM ships once. The 11 fusion research teams run it on any Apple
Silicon Mac. No Vision Pro required for the constitutional measurement path.

**Critical API changes that affect existing code:**

| Change | Impact on vQbit VM |
|--------|-------------------|
| RealityKit Entity is now `@Observable` | C4ProjectionSystem can be replaced with direct SwiftUI observation of ManifoldProjectionStore. Entities observe the store directly. |
| SwiftUI gestures attach directly to entities | Domain portal entities (CircuitFamily, etc.) no longer need RealityView intermediary for tap handling. |
| `ViewAttachmentComponent` is inline | Algorithm family labels and c3_closure bars can be declared inline with RealityKit entity construction. |
| `ManipulationComponent` — still `@available(macOS, unavailable)` | Confirmed in MacOSX26.4.sdk. Do not retry. `InputTargetComponent + CollisionComponent` remains the macOS path. |
| Instruments 15: RealityKit Trace template | PQ-QM-003 (< 100ms closureResidual gate) can now be verified at the Metal level using RealityKit Frames + RealityKit Metrics instruments. |
| RealityKit low-level mesh + texture APIs (Metal compute) | Rust Metal renderer `upload_geometry` path now has a direct RealityKit surface. `GaiaaCellPrimitive` structs can be pushed directly without intermediate buffer copies. |

**Xcode 3D scene debugger** now supports inspecting RealityKit scene content
inline. Use this to verify Franklin's USD stage authorship at wake:
confirm all seven `/World/Quantum/*` prims and six `/World/Domains/Fusion/*`
prims are present before running IQ-QM-005 (domain threshold calibration).
This is the correct verification tool for P1-001 (Franklin wake authorship).

**Foundation Models framework (on-device LLM):**
Franklin's inner monologue narration can use the on-device Apple Intelligence
model for natural language output while the vQbit VM handles constitutional
arithmetic. Clean sovereignty boundary — no cloud call, no external API.
This is the correct architecture for a sovereign instrument.

**NVIDIA CloudXR foveated streaming (visionOS 26.4):**
For the 11-team validation sprint, fusion teams can stream heavy visual
scene content from a remote GaiaFTCL Helsinki/Nuremberg cell while the
constitutional geometry (S4 authoring, C4 projection, checkConstitutional)
runs natively on the local Mac. The local/remote split maps exactly to the
NATS-only process boundary: Franklin + vQbit VM run local, visual scene
streams remote. No architecture change required — the three-process sovereign
design already enforces this split.

---

### 0.2 Business and Academic Position

**Business:**

The vQbit VM is the first interactive application of the FoF 19-algorithm
quantum closure proof. Every quantum computing lab, university physics
department, and national laboratory that wants to validate the closure proof
claims needs this instrument. The addressable market is every institution
currently buying IBM Quantum access, AWS Braket credits, or Azure Quantum
subscriptions — not to replace quantum hardware, but to measure exactly where
quantum hardware adds value and where it does not.

SceneKit deprecation removes a class of competitors from the spatial
visualization space. The vQbit VM is on the only platform Apple is investing
in. Institutions building quantum visualization on deprecated frameworks will
migrate or fall behind.

The DMG ships on any Apple Silicon Mac. No Vision Pro required. No cloud
dependency. No external API key. Sovereign installation. This is a competitive
position no cloud quantum provider can match.

**Academic:**

The vQbit VM converts an abstract mathematical proof into a measurable,
reproducible laboratory instrument. A PhD student studying quantum supremacy
claims can:
- Inject S4 values matching Shor's algorithm at N=15 (D=1024)
- Observe s1_structural = 0.999 in the tensor
- Watch c3_closure = 1.0 (CALORIE — executes within bounds)
- Increment N to 16 — watch bond dimension exceed D_max
- Observe terminal = REFUSED, violation_code = 0x01
- Record the exact frontier measurement as a VQbitRecord (89 bytes)
- Reproduce the result bit-identically on any other Apple Silicon Mac

That is a laboratory result, not a simulation. The vQbit VM produces GAMP 5
qualified evidence by construction. A journal submission citing this
instrument cites a qualified measurement device with an immutable binary log,
not a software demo.

The FoT/Collatz identity (every VQbitRecord is an AKG knowledge node, every
self-review cycle is a distributed consensus round) means the vQbit VM is
also a proof-of-concept for the Field of Truth architecture at scale. The
11-team 275M euro validation sprint is the first live deployment.

---

### 0.3 Distribution — DMG + GitHub LFS

**Apple Developer Program (Individual) — Team ID:** `WWQQB728U5` — use for `codesign` identities tied to this enrollment and for `notarytool --team-id`. (Renewal October 2026; keep billing card current for signing continuity.)

**Distribution format: Signed and notarized DMG via GitHub Releases + LFS.**

```
Repository structure:
  /releases/
    vQbit-VM-1.0.0.dmg        ← tracked with Git LFS
    vQbit-VM-1.0.0.pkg        ← optional: PKG installs LaunchAgents
  /.gitattributes:
    *.dmg filter=lfs diff=lfs merge=lfs -text
    *.pkg filter=lfs diff=lfs merge=lfs -text
    *.usdz filter=lfs diff=lfs merge=lfs -text
```

**LFS storage budget:**
- Free tier: 1GB storage, 1GB/month bandwidth
- Each DMG: ~80-150MB (Swift app + Metal shaders + USD assets)
- Free tier supports early research access (5-10 downloads/day)
- LFS Data Pack ($5/month per 50GB) required at CERN/institutional scale

**Build pipeline (post-qualification):**

```bash
# 1. Build release binary
cd /Users/richardgillespie/Documents/AppleGaiaFTCL/cells/xcode
swift build -c release --scheme GaiaFTCL

# 2. Code sign (Developer ID required for outside-App-Store distribution)
codesign --deep --force --verify --verbose \
  --sign "Developer ID Application: Richard Gillespie (WWQQB728U5)" \
  --entitlements entitlements.plist \
  --options runtime \
  .build/release/GaiaFusion.app

# 3. Create DMG
create-dmg \
  --volname "vQbit VM 1.0 — FortressAI Research Institute" \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "GaiaFusion.app" 150 200 \
  --app-drop-link 450 200 \
  releases/vQbit-VM-1.0.0.dmg \
  .build/release/GaiaFusion.app

# 4. Notarize (required for macOS Gatekeeper on any user's Mac)
xcrun notarytool submit releases/vQbit-VM-1.0.0.dmg \
  --apple-id "your@email.com" \
  --team-id "WWQQB728U5" \
  --password "@keychain:AC_PASSWORD" \
  --wait

# 5. Staple
xcrun stapler staple releases/vQbit-VM-1.0.0.dmg

# 6. Commit to LFS
git add releases/vQbit-VM-1.0.0.dmg
git commit -m "release: vQbit-VM-1.0.0 signed, notarized, GAMP5 qualified"
git push
```

**PKG alternative for CERN/institutional deployment:**
A `.pkg` installer can write LaunchAgents
(`com.gaiaftcl.nats`, `com.gaiaftcl.vqbit`, `com.gaiaftcl.franklin.consciousness`)
to `~/Library/LaunchAgents/` automatically at install time. This is the correct
distribution format for a qualified GxP instrument being installed across a
research institution's fleet. The PKG runs the install script
`cells/xcode/scripts/install_franklin_consciousness_service.zsh` as a
post-install action.

---

### 0.4 Metered vQbit Access — Sovereign Quota System

**Pre-ship gate — licensing URL in user-facing strings:** Before any DMG ships,
confirm `https://fortressai.io/vqbit` is owned, HTTPS-valid, and returns a real
page (no 404). If that URL is not yet live, ship quota and monologue copy that
points at a guaranteed destination such as
`https://github.com/fortressai-research/vqbit-vm/releases` (or the canonical
org/repo you publish under). Researchers must not hit a dead link from
QUOTA_EXHAUSTED or Franklin monologue. Swap strings to `fortressai.io/vqbit`
only after DNS and content are verified.

**Architecture:** The quota is stored in the mmap tensor file header — the same
binary artifact GaiaRTMGate verifies under IQ-TENSOR-001. Quota enforcement
is sovereign. No license server. No internet check. No external dependency.
The quota cannot be reset by deleting a file — it is embedded in the binary
log header that also carries the GAMP 5 IQ-verified cell identity.

**Frozen enum addition — violation_code:**

```
0x07 = QUOTA_EXHAUSTED
       Free tier constitutional measurement limit reached.
       Instrument enters BLOCKED state.
       C4 projection wire: terminal=BLOCKED, refusal_source=0x07
       Inner monologue: "Constitutional measurement quota exhausted.
                         Academic and research licenses available at
                         github.com/fortressai-research/vqbit-vm/releases
                         (replace with https://fortressai.io/vqbit when live)"
```

**Quota tiers:**

| Tier | Cycles | Who | Price |
|------|--------|-----|-------|
| Free (DMG) | 1,000 | Anyone | $0 |
| Academic | 50,000 | .edu email verified | $0 |
| Research Institution | 500,000 | 11-team sprint tier | Negotiated |
| FortressAI Sovereign | Unlimited | Your own cells | N/A |

**What 1,000 cycles covers:**

Each constitutional measurement cycle = one S4 delta → checkConstitutional
→ C4 projection published. At 1,000 cycles a new user can:
- Run OQ-QM-001 through OQ-QM-007 (all 7 operational tests) completely
- Observe the Bell/CHSH enforcement trigger (IQ-QM-006)
- Watch all 19 algorithm family prims reach terminal state
- Run 2-3 complete Franklin self-review cycles across the full catalog
- Reproduce the N_catalog = 19, N_residual = 0 result deterministically

This is enough to evaluate the proof. It is not enough for sustained
production operation or the 24h PQ-QM-004 endurance test.

**Implementation:**

```swift
// mmap tensor header layout — quota fields at bytes [200..215]
// [200..207] = Int64 cycle_count (current consumed cycles)
// [208..215] = Int64 cycle_quota (tier limit; 0 = unlimited)

extension ManifoldTensorAllocator {

    /// Consume one constitutional measurement cycle.
    /// Returns false and sets BLOCKED state if quota exhausted.
    /// Quota = 0 means unlimited (FortressAI sovereign cells).
    func consumeCycle(for primID: UUID) throws -> Bool {
        let quota = readCycleQuota()   // from header [208..215]
        guard quota == 0 else {
            let used = readCycleCount() // from header [200..207]
            guard used < quota else {
                // Publish BLOCKED + 0x07 on C4 wire for this prim
                publishQuotaExhausted(primID: primID)
                return false
            }
            writeCycleCount(used + 1)
            return true
        }
        return true // unlimited
    }

    var remainingCycles: Int {
        let quota = readCycleQuota()
        guard quota > 0 else { return Int.max } // unlimited
        return max(0, Int(quota) - Int(readCycleCount()))
    }

    var quotaExhausted: Bool {
        let quota = readCycleQuota()
        guard quota > 0 else { return false }
        return readCycleCount() >= quota
    }
}
```

**GaiaRTMGate quota gate:**

```bash
# IQ-QUOTA-001 (add to GaiaRTMGate check list)
# Read quota and cycle_count from tensor header [200..215]
# If quota > 0 and cycle_count >= quota: return BLOCKED
# If quota > 0 and cycle_count > quota * 0.9: return CURE (warn)
# If quota == 0: CALORIE (unlimited sovereign cell)
```

**Why this is GAMP 5 compatible:**

The quota is part of the mmap tensor header — the same file GaiaRTMGate
verifies under IQ-TENSOR-001 (magic, N, cell_id, byte size). Adding
`cycle_count` and `cycle_quota` at header bytes [200..215] extends the
IQ verification surface without changing the active tensor data at bytes
[256..]. The quota enforcement is therefore installation-qualified by the
same mechanism as the manifold geometry. An academic reviewer who gets
1,000 free cycles gets exactly enough to reproduce the OQ qualification.
A research institution that needs PQ-QM-004 24h endurance gets the tier
that covers it. The ceiling enforces itself through the physics substrate.

**Franklin inner monologue on quota warning (at 90% consumed):**

```
"Constitutional measurement capacity approaching limit.
 Cycles consumed: 900 of 1000. Remaining: 100.
 Domain: quantum_circuit. Algorithm closure: 19/19 at full catalog.
 Academic license available for extended research at
 github.com/fortressai-research/vqbit-vm/releases
 (until https://fortressai.io/vqbit is live)"
```

This appears on `gaiaftcl.franklin.monologue` — visible in the vQbit
research portal and in Console.app for any operator watching the system.

```swift
// Until https://fortressai.io/vqbit is live, use a non-404 URL:
"Academic license: https://github.com/fortressai-research/vqbit-vm/releases"
```

---

### 0.5 Xcode 26.4 Build Setting Additions

Add to cells/xcode GAMP5 build configuration:

```
// cells/xcode/GaiaFTCL-Release.xcconfig
// Required for Xcode 26.4 / Swift 6.3

SWIFT_VERSION = 6.0
MACOSX_DEPLOYMENT_TARGET = 26.0
// SceneKit: do not import — deprecated
// Foundation Models: import for Franklin monologue narration
// RealityKit: Entity @Observable — update C4ProjectionSystem
//             to remove manual store polling; entities observe directly

// LFS release build gate
// After 'swift build -c release', run:
//   make sign-and-notarize  (Makefile target)
//   make lfs-release        (git lfs push)
// Do not push unsigned binaries to LFS.
```

**Makefile targets (add to repo root):**

```makefile
.PHONY: sign-and-notarize lfs-release quantum-iq

sign-and-notarize:
	codesign --deep --force --sign "Developer ID Application: Richard Gillespie (WWQQB728U5)" \
	  --entitlements entitlements.plist --options runtime \
	  cells/xcode/.build/release/GaiaFusion.app
	create-dmg --volname "vQbit VM $(VERSION)" \
	  releases/vQbit-VM-$(VERSION).dmg \
	  cells/xcode/.build/release/GaiaFusion.app
	xcrun notarytool submit releases/vQbit-VM-$(VERSION).dmg \
	  --apple-id $(APPLE_ID) --team-id WWQQB728U5 \
	  --password "@keychain:AC_PASSWORD" --wait
	xcrun stapler staple releases/vQbit-VM-$(VERSION).dmg

lfs-release:
	git add releases/vQbit-VM-$(VERSION).dmg
	git commit -m "release: vQbit-VM-$(VERSION) signed notarized GAMP5-qualified"
	git push

quantum-iq:
	swift run GaiaRTMGate \
	  --repo-root /Users/richardgillespie/Documents/AppleGaiaFTCL
	# Must return: TERMINAL STATE: CALORIE - RTM Verified
	# If CURE:    fix open RTM entries, re-run
	# If REFUSED: stop release pipeline — GAMP5 gate violated
	# If BLOCKED: deviation required — do not push any release
	# DO NOT push a DMG until this target returns CALORIE
```

---

*Section 0 is informational context for the vQbit VM as a distributed Apple
application. It does not modify the GAMP 5 qualification protocol defined in
Sections 1-6. The qualification protocol governs the instrument. This section
governs how the instrument reaches researchers.*

---

## Foundational Claim

The vQbit is not a software object. It is the **closure operator** for quantum
computation on sovereign classical substrates — the operator Boole never had
because the computational geometry of M⁸ = S⁴ × C⁴ was not yet defined.

The 19-algorithm FoF catalog defines what the vQbit measures. UUM-8D defines
the geometry it measures in. GaiaFTCL is the enforcement substrate.

The qubit requires physical quantum hardware and fails when hardware degrades.
The vQbit enforces constitutional closure on a sovereign mmap tensor via Swift
IEEE 754 arithmetic. It requires no quantum hardware. Every declared algorithm
either executes within bounds (terminal = CALORIE) or hard-rejects with measured
frontier violations (terminal = REFUSED/BLOCKED). No silent approximation.
No deferred logic. No residual category.

**Catalog conservation equation (Definition 6.1, closure proof):**
```
N_catalog = N_executed + N_rejected
19        = 14        + 5
N_residual = 0
```

**Reconciliation (auditor-consistent):** Every algorithm’s **Status** line in
the catalog below matches the summary: **N_executed = 14**, **N_bounded = 5**
(14 + 5 = 19). There is no split classification (e.g. CTQW/HamSim) that is
EXECUTED in the entry but counted as BOUNDED in the summary.

**The proof:** Hardware is not required to govern 14 of 19 algorithms.
For the remaining 5, the frontier IS the proof — the vQbit measures exactly
where quantum hardware would add value and at what bound. A system that
honestly enforces its own limits is a stronger scientific instrument than one
that claims none.

**FoT architectural identity:**
The vQbit binary log IS the GaiaFTCL implementation of the Field of Truth
immutable ledger. Every VQbitRecord is a cryptographically-ordered
constitutional certificate. Franklin is the transformation agent. The vQbit VM
is the validation agent that cannot be bypassed. GRDB learning receipts are
the AKG knowledge nodes. The self-review loop is the distributed consensus
mechanism. Catalog conservation is enforced by the same architecture that
proves Collatz trajectories — not by assertion but by construction.

---

## GAMP 5 IQ Prerequisite Documents (must exist before execution)

```
docs/reports/GAMP5-IQ-HARDWARE.md          — QUALIFIED_N, QUALIFIED_W_SHA256,
                                              QUALIFIED_CHIP, machine-readable
                                              <!-- QUALIFIED_N=65536 --> format
docs/reports/GAMP5-OQ-PROTOCOL-001.md      — First-wake OQ (closed)
docs/reports/GAMP5-OQ-PROTOCOL-002.md      — Self-review OQ (closed)
docs/reports/GAMP5-OQ-PROTOCOL-003.md      — Quantum vQbit OQ (gate: MUST be
                                              committed before any live OQ run;
                                              criteria precede evidence)
docs/reports/GAMP5-DEVIATION-PROCEDURE-001.md — Deviation SOP
docs/reports/REQUIREMENTS_TRACEABILITY_MATRIX.json — RTM with REQ-SR-001..006
```

This document adds:
```
docs/reports/GAMP5-VQBIT-QUANTUM-IQ-OQ-PQ-001.md  — THIS DOCUMENT
```

GaiaRTMGate must return CALORIE after this document is committed and RTM
entries **REQ-QM-001..020** are added — one per **GAMP5 quantum test**
(IQ-QM-001..006, OQ-QM-001..007, PQ-QM-001..007 = **20 tests**, not 19
algorithms).

---

## GAMP 5 gated execution sequence (Step A → F)

**Critical gate:** OQ pass/fail criteria live only in **GAMP5-OQ-PROTOCOL-003.md**
and must be **committed on main before** any implementation or live OQ run.
Defining criteria in the same commit as evidence is **inadmissible**.

```
Step A1: Commit docs/reports/GAMP5-OQ-PROTOCOL-003.md with full OQ-QM-001..007
         criteria, pass thresholds, deviation references, signing definition
Step A2: Extend REQUIREMENTS_TRACEABILITY_MATRIX.json with REQ-QM-001..020
Step A3: GaiaRTMGate → CALORIE (mandatory before Step B)
Step B:  GRDB migration vN_quantum_domains (run P1-002 pre-check command first)
         P0-000, P0-001, P0-002 implemented
         swift test 3× — GaiaRTMGate CALORIE
Step C:  P1-001..004 implemented
         swift test 3× — GaiaRTMGate CALORIE
Step D:  Live OQ execution against **pre-committed** protocol criteria only
         GAMP5-OQ-EVIDENCE-003.md two-commit seal (see signing definition below)
Step E:  Full regression 247+ tests, 3× — GaiaRTMGate CALORIE
Step F:  Session receipt on main
```

---

## UUM-8D Axiom Set (patent 19/096,071)

**Axiom 1 — Dimensional Conservation:**
Conserved quantities migrate between S⁴ and C⁴ without loss.
S₈ = S₄ + Sᶜ is invariant at every vQbit measurement event.
The Big Bang is a projection boundary — entropy does not reset, it relocates.
Every vQbit measurement event is a micro-projection of the same class.

**Axiom 2 — Operational Primacy:**
A quantity is defined only where an operational metric exists.
The vQbit IS the operational metric for C⁴ constraint structure.
When S⁴ metrics degrade, the vQbit must produce valid C⁴ projections.
Bell/CHSH enforcement is the operational definition of classical locality.

**Axiom 3 — Projection:**
When S⁴ metrics fail, conserved C⁴ structure re-instantiates a new S⁴ slice.
Terminal states are projection class labels, not software states:
```
CALORIE = stable projection — S⁴ and C⁴ in constitutional balance
           algorithm executes within declared resource bounds
CURE    = active dimensional migration — S₄ decreasing, Sᶜ absorbing
           algorithm approaching frontier, bond dim growing
REFUSED = constraint violation — Π cannot complete projection
           algorithm exceeds declared bounds, frontier recorded
BLOCKED = metric failure — S⁴ cannot support operational definition
           FoF substrate cannot form field decomposition
```

---

## S⁴ Semantic Mapping — Field-of-Fields Grounding

S⁴ dimensions grounded in FoF closure proof (Gillespie 2026) and
Shor refutation (Gillespie 2025):

```
s1_structural — Field decomposition integrity
  FoF source: Bond dimension coherence across tensor fields Fi
  Formula:    1.0 - (D_actual / D_max) clipped to [0.0, 1.0]
  Physics:    D_actual from MPS bond dimension at each tensor site
              D_max = 1024 (Shor refutation verified at D=1024)
  CALORIE:    D_actual << D_max, bond dims well within bounds
  CURE:       D_actual approaching D_max, entropy growing
  REFUSED:    D_actual > D_max, FRONTIER_VIOLATION(BOND_DIMENSION)
  Shor cite:  Factored N=15 at 8 qubits using D=1024 → s1=0.999
              Factored N=21 at 10 qubits → s1=0.998

s2_temporal — Entanglement entropy stability
  FoF source: Rate of change of von Neumann entropy
              S = -Σ λᵢ² log λᵢ² across interaction surfaces Iij
  Formula:    1.0 - |ΔS / S_max| normalized to [0.0, 1.0]
              S_max = log₂(D_max) = log₂(1024) ≈ 10.0
  Physics:    Stable entropy = algorithm converging within bounds
              Growing entropy = approaching truncation boundary
  CALORIE:    ΔS / S_max < 0.1 (stable)
  CURE:       ΔS / S_max ∈ [0.1, 0.5] (growing but bounded)
  REFUSED:    ΔS / S_max > 0.5 (truncation enforced)

s3_spatial — Interaction field connectivity
  FoF source: Iij integrity — explicit interfaces between tensor fields
              carrying controlled entanglement and information flow
  Formula:    fraction of Iij interfaces passing coherence check
              = coherent_interfaces / total_interfaces
  Physics:    For Quantum Walk: graph edge coherence
              For Hamiltonian Sim: Trotter step interface health
              For QAOA: QUBO coupling field coherence
  CALORIE:    All Iij coherent, no field boundary violations
  REFUSED:    Any Iij incoherent, interaction field broken

s4_observable — Invariant enforcement visibility
  FoF source: Bell/CHSH parameter S = |E(a,b) - E(a,b') + E(a',b) + E(a',b')|
              Invariant 4.1: S ≤ 2.01 for classical locality
  Formula:    1.0 - min(S / 2.01, 1.0)  [normalized, inverted]
              s4=1.0 when S=0.0 (perfect classical locality)
              s4=0.0 when S=2.01 (classical bound reached)
              s4<0.0 → REFUSED (NONCLASSICAL_RESOURCE_DETECTED)
  Physics:    FoF substrate produces S ≈ 1.998 (verified)
              s4 ≈ 1.0 - (1.998/2.01) ≈ 0.006 → healthy CALORIE
              If S > 2.01: execution terminates, REFUSED produced
```

---

## C⁴ Semantic Mapping — Constitutional Projection Geometry

```
c1_trust — Deterministic execution confidence
  Source:  Axiom 4.1 (closure proof): Execute(A,s,R) = Execute(A,s,R)
  Meaning: Same algorithm + seed + resource declaration → identical output
  Measure: Bit-identity of constitutional check across 3 consecutive runs
           c1_trust = 1.0 if all 3 runs produce identical terminal + codes
           c1_trust = 0.0 if any run diverges (non-determinism detected)
  Physics: Non-determinism = Protocol 1 falsification → REFUTED

c2_identity — Catalog conservation identity
  Source:  Definition 6.1 (closure proof): N_catalog = N_executed + N_rejected
  Meaning: No residual category. Algorithm identity preserved through execution.
  Measure: N_closed / N_catalog where N_closed = algorithms with evidence
           c2_identity = 1.0 at full catalog conservation (19/19)
           c2_identity = 0.0 if any algorithm has no terminal state
  Physics: Residual category = Protocol 2 falsification → REFUTED

c3_closure — Algorithm closure completeness
  Source:  Definition 1.1 (closure proof): every declared algorithm either
           executes within bounds or is explicitly rejected with evidence
  Measure: Accelerate Float64 aggregation via vDSP_meanvD across all
           domain prim tensor rows — constitutional stress mean
           c3_closure = 1.0 - closureResidual
           closureResidual = vDSP_meanvD(stressVector) where
           stressVector[i] = max(0, (threshold - s_mean_i) / threshold)
  Physics: Not integer counting. Physics-grade Float64 across N=65536.
           Degraded S⁴ (0.05) → high stress → low c3 → REFUSED fires

c4_consequence — Frontier violation causal weight
  Source:  Axiom 3 — projection consequence propagates through EdgeStore
  Meaning: When execution hits a declared bound, what is the causal weight
           for downstream domains that depend on this algorithm?
  Measure: BFS-weighted consequence sum via TraversalEngine.bfsWeightedSum
           from the algorithm prim's UUID through EdgeStore causal graph
           c4 = 0.0 if algorithm CALORIE (no consequence)
           c4 > 0.0 if algorithm REFUSED (consequence propagates)
  Physics: Shor REFUSED → high c4_consequence for any domain using
           factorization. Surface Code BOUNDED → consequence for
           any fault-tolerant quantum deployment claim.
```

---

## The Complete 19-Algorithm Closure Catalog

**Sequential IDs:** QC-001 through QC-019 only — listed in numeric order for
auditors. IQ, OQ, PQ, and RTM must reference these algorithm IDs (do not use
legacy non-sequential numbering).

```
CIRCUIT FAMILY (5) — QC-001..005 — Section 6.1 of closure proof:
  QC-001  Shor's Algorithm (Integer Factorization)
          Status:   EXECUTED
          Frontier: N ≤ 15 (8 qubits, D=1024)
          Bound:    Modular exponentiation depth + QFT precision
          S4 map:   s1_structural = 1 - (D_shor / 1024)
          Evidence: Factored 15=3×5, 21=3×7, 35=5×7 deterministically
          Shor cite: Gillespie 2025, MPS refutation §1.3
          USD prim: /World/Quantum/CircuitFamily

  QC-002  Grover's Algorithm (Unstructured Search)
          Status:   EXECUTED
          Frontier: n ≤ 12 qubits
          Bound:    Oracle depth × √N amplitude amplification
          USD prim: /World/Quantum/CircuitFamily

  QC-003  Quantum Fourier Transform
          Status:   EXECUTED
          Frontier: n ≤ 16 qubits
          Bound:    Phase precision at bit depth 16
          USD prim: /World/Quantum/CircuitFamily

  QC-004  Quantum Phase Estimation
          Status:   EXECUTED
          Frontier: n ≤ 10 qubits
          Bound:    Phase kickback accumulation depth
          USD prim: /World/Quantum/CircuitFamily

  QC-005  Amplitude Amplification
          Status:   EXECUTED
          Frontier: n ≤ 10 qubits
          Bound:    Reflection operator depth
          USD prim: /World/Quantum/CircuitFamily

VARIATIONAL FAMILY (4) — QC-006..009 — Section 6.2 of closure proof:
  QC-006  Variational Quantum Eigensolver (VQE)
          Status:   EXECUTED
          Frontier: 6 qubits
          Bound:    Ansatz depth × parameter count
          S4 map:   s2_temporal = entanglement entropy of variational state
          USD prim: /World/Quantum/VariationalFamily

  QC-007  Quantum Approximate Optimization Algorithm (QAOA)
          Status:   EXECUTED
          Frontier: 8 qubits
          Bound:    QUBO coupling depth × layer count
          USD prim: /World/Quantum/VariationalFamily

  QC-008  Variational Quantum Classifier
          Status:   EXECUTED
          Frontier: 4 qubits
          Bound:    Feature map depth × training iterations
          USD prim: /World/Quantum/VariationalFamily

  QC-009  Quantum Annealing / QUBO
          Status:   EXECUTED
          Frontier: 8-variable QUBO, 2-local couplings, integer weights
          FoF map:  QUBO objective = constraint field Cm
                    Annealing schedule = adaptive bond dim scaling
                    per Definition 9.1: D'i = min(Dmax, Di·e^αSi)
          UUM-8D:   c4_consequence measures when annealing cannot close
                    within bounds — frontier violation propagates causally
          Physics:  D-Wave-class optimization supremacy claim addressed
          USD prim: /World/Quantum/VariationalFamily
                    (algorithm_count = 4 on VariationalFamily prim)

LINEAR ALGEBRA FAMILY (3) — QC-010..012 — Section 6.3 + extension:
  QC-010  Harrow-Hassidim-Lloyd (HHL) Linear System Solver
          Status:   BOUNDED
          Frontier: 2⁴ × 2⁴ system
          Violation: Condition number κ drives bond dimension beyond D_max
          terminal: REFUSED, violation_code = 0x01 (bond_dim_exceeded)
          USD prim: /World/Quantum/LinearAlgebraFamily

  QC-011  Quantum Singular Value Transformation (QSVT)
          Status:   BOUNDED
          Frontier: rank ≤ 8
          Violation: Polynomial degree of block-encoding exceeds precision
          terminal: REFUSED, violation_code = 0x01
          USD prim: /World/Quantum/LinearAlgebraFamily

  QC-012  Quantum Principal Component Analysis (qPCA)
          Status:   BOUNDED
          Frontier: 4×4 density matrix, rank ≤ 4
          Note:     Reduces to QSVT + QPE composition at linear algebra layer
                    Composition proof — not a separate primitive beyond closure
          Violation: density matrix rank exceeds QSVT frontier
          terminal: REFUSED
          USD prim: /World/Quantum/LinearAlgebraFamily

SIMULATION FAMILY (2) — QC-013..014 — Future Work items 1 and 4 of closure proof:
  QC-013  Quantum Walk (Continuous-Time, CTQW)
          Status:   EXECUTED
          Frontier: n ≤ 16 graph nodes, adjacency rank ≤ 8
          FoF map:  Graph nodes = tensor field sites Fi
                    Graph edges = interaction fields Iij
                    Time evolution = unitary on adjacency field
          S4 map:   s3_spatial = coherent_edges / total_edges
          UUM-8D:   s3_spatial (interaction field connectivity)
                    directly measures CTQW graph coherence
          Physics:  Quantum walk on a graph IS S³ spatial connectivity
                    measured constitutionally
          USD prim: /World/Quantum/SimulationFamily

  QC-014  Hamiltonian Simulation (Trotter-Suzuki)
          Status:   EXECUTED
          Frontier: 4 qubits, 10 Trotter steps, 2-body interactions
          FoF map:  Each Trotter step = one FoF gate application
                    Local terms = bounded interaction fields
                    Error = explicit truncation tolerance ϵ_trunc
          UUM-8D:   Directly implements Axiom 1 dimensional conservation
                    Energy conservation across S⁴ time steps IS
                    the entropy migration mechanism in physical systems
          Physics:  Fusion plasma Hamiltonian simulation is the
                    quantum substrate for the 11-team validation sprint
          USD prim: /World/Quantum/SimulationFamily

BOSONIC / CV FAMILY (2) — QC-015..016 — Section 6.4 of closure proof:
  QC-015  Boson Sampling
          Status:   EXECUTED
          Frontier: 3 photons, m = 4 modes
          Bound:    Permanent computation is #P-hard beyond nmax=3
                    Additive-error estimation in BPP within frontier
          terminal: CALORIE within bounds
          USD prim: /World/Quantum/BosonicFamily

  QC-016  Gaussian Boson Sampling (GBS)
          Status:   EXECUTED
          Frontier: 4 modes, covariance matrix rank ≤ 4
          FoF map:  Squeezed states = continuous-variable tensor field
                    Gaussian transformations = covariance field operations
          S4 map:   s1_structural = 1 - (rank(σ) / rank_max)
          USD prim: /World/Quantum/BosonicFamily

ERROR CORRECTION FAMILY (3) — QC-017..019 — Section 6.5 + extension:
  QC-017  Steane Code (7-qubit error correction)
          Status:   EXECUTED
          Frontier: 7 qubits, Clifford + Gottesman-Knill tractable
          Physics:  Stabilizer fields in polynomial time (Theorem 8.1)
          USD prim: /World/Quantum/ErrorCorrectionFamily

  QC-018  Surface Code (topological error correction)
          Status:   BOUNDED
          Frontier: 3×3 lattice
          Violation: Full fault-tolerant scaling exceeds coherent noise bound
          terminal: REFUSED, violation_code = 0x02 (coherence_bound)
          USD prim: /World/Quantum/ErrorCorrectionFamily

  QC-019  Topological QEC (Anyonic Braiding / Fibonacci)
          Status:   BOUNDED — THIS IS THE KEY RESULT
          Frontier: 3-anyon system, braid depth ≤ 8
          FoF map:  Anyonic world lines = causal edges in EdgeStore
                    Braid group operations = edge weight transforms
                    Topological invariant = constraint field Cm that
                    cannot be violated by local perturbations
          UUM-8D:   Axiom 3 — topological protection = C⁴ geometry
                    that survives local S⁴ metric perturbations
                    This is the deepest expression of Axiom 3:
                    constraint structure (C⁴) protects against
                    spacetime (S⁴) noise
          Violation: Braid depth > 8 exceeds representational bound
          terminal: REFUSED, violation_code = 0x03
          Physics:  Full fault-tolerant topological QEC is where
                    quantum hardware genuinely adds value beyond
                    FoF frontier. The vQbit proves exactly where
                    this boundary is. That is not failure.
                    That IS closure. Future Work item 1.
          USD prim: /World/Quantum/ErrorCorrectionFamily

CATALOG SUMMARY:
  N_catalog  = 19
  N_executed = 14
    Explicit: QC-001..005 (circuit), QC-006..009 (variational + QUBO),
                QC-013..014 (simulation), QC-015..016 (bosonic), QC-017 (Steane)
  N_bounded  = 5
    Explicit: QC-010 (HHL), QC-011 (QSVT), QC-012 (qPCA),
                QC-018 (Surface), QC-019 (Topological)
  N_residual = 0

  c3_closure = 1.0 at full catalog execution
  All 19 have a terminal state backed by physical evidence.
  Zero algorithms are skipped, approximated without declaration,
  or left in residual category.
```

---

## Quantum USD Stage — Complete S⁴ Prim Schema

Franklin authors all prims on wake. vQbit VM measures them all.

```
/World/Quantum/CircuitFamily
  custom double s1_structural = 0.0   # bond dim coherence: 1-(D/D_max)
  custom double s2_temporal   = 0.0   # entropy stability: 1-|ΔS/S_max|
  custom double s3_spatial    = 0.0   # field connectivity: coherent_Iij/total
  custom double s4_observable = 0.0   # CHSH: 1-(S/2.01) normalized
  custom string game_id        = "QC-CIRCUIT-001"
  custom string algorithms     = "Shor,Grover,QFT,QPE,AmplitudeAmplification"
  custom double max_bond_dim   = 1024.0
  custom double chsh_threshold = 2.01
  custom int    algorithm_count = 5
  custom double constitutional_threshold_calorie = 0.85
  custom double constitutional_threshold_cure    = 0.60

/World/Quantum/VariationalFamily
  custom string game_id        = "QC-VARIATIONAL-001"
  custom string algorithms     = "VQE,QAOA,VariationalClassifier,QuantumAnnealing"
  custom int    algorithm_count = 4
  custom double constitutional_threshold_calorie = 0.80
  # Calibration basis: mean S4 health when all 4 algorithms execute within
  # frontier bounds (VQE≤6q, QAOA≤8q, Classifier≤4q, QUBO≤8var)
  # Expected mean bond dim utilization ≈ 0.20 of D_max → s1 ≈ 0.80
  custom double constitutional_threshold_cure    = 0.55

/World/Quantum/LinearAlgebraFamily
  custom string game_id        = "QC-LINALG-001"
  custom string algorithms     = "HHL,QSVT,qPCA"
  custom int    algorithm_count = 3
  # All 3 are BOUNDED — threshold reflects frontier proximity not execution
  custom double constitutional_threshold_calorie = 0.70
  custom double constitutional_threshold_cure    = 0.40

/World/Quantum/SimulationFamily
  custom string game_id        = "QC-SIMULATION-001"
  custom string algorithms     = "QuantumWalk,HamiltonianSimulation"
  custom int    algorithm_count = 2
  custom double max_trotter_steps = 10.0
  custom double max_graph_nodes   = 16.0
  custom double constitutional_threshold_calorie = 0.82
  custom double constitutional_threshold_cure    = 0.58

/World/Quantum/BosonicFamily
  custom string game_id        = "QC-BOSONIC-001"
  custom string algorithms     = "BosonSampling,GaussianBosonSampling"
  custom double max_photons    = 3.0
  custom double max_modes      = 4.0
  custom int    algorithm_count = 2
  custom double constitutional_threshold_calorie = 0.88
  custom double constitutional_threshold_cure    = 0.65

/World/Quantum/ErrorCorrectionFamily
  custom string game_id        = "QC-ERRORCORR-001"
  custom string algorithms     = "SteaneCode,SurfaceCode,TopologicalQEC"
  custom double max_lattice    = 3.0
  custom double max_braid_depth = 8.0
  custom int    algorithm_count = 3
  # Steane EXECUTED, Surface + Topological BOUNDED
  custom double constitutional_threshold_calorie = 0.75
  custom double constitutional_threshold_cure    = 0.45

/World/Quantum/ProjectionProbe
  # Pure M⁸ geometry test surface — no domain semantics
  # IQ-QM-001 through OQ-QM-003 injection tests only
  custom string game_id   = "QUANTUM-PROOF-001"
  custom string prim_role = "proof_injection_surface"

/World/Domains/Fusion/Tokamak
  custom string game_id              = "FUSION-TOKAMAK-001"
  custom string plant_kind           = "tokamak"
  custom double min_plasma_pressure  = 0.3  # Greenwald limit normalized
  custom double min_field_strength   = 0.4  # toroidal B field normalized
  custom double constitutional_threshold_calorie = 0.80
  custom double constitutional_threshold_cure    = 0.55
  custom string s1_semantic = "plasma_topology_score"
  custom string s2_semantic = "confinement_stability_delta"
  custom string s3_semantic = "field_line_connectivity"
  custom string s4_semantic = "neutron_emission_visibility"

/World/Domains/Fusion/Stellarator
  custom string plant_kind          = "stellarator"
  custom double min_plasma_pressure = 0.2
  custom double min_field_strength  = 0.5
  custom string game_id             = "FUSION-STELLARATOR-001"

/World/Domains/Fusion/InertialConfinement
  custom string plant_kind          = "inertial_confinement"
  custom double min_plasma_pressure = 0.7  # ignition threshold
  custom double min_field_strength  = 0.1  # no external B field
  custom string game_id             = "FUSION-ICF-001"

/World/Domains/Fusion/FieldReversed
  custom string plant_kind = "field_reversed"
  custom string game_id    = "FUSION-FRC-001"

/World/Domains/Fusion/MagnetizedTarget
  custom string plant_kind = "magnetized_target"
  custom string game_id    = "FUSION-MTF-001"

/World/Domains/Fusion/CompactFusion
  custom string plant_kind = "compact_fusion"
  custom string game_id    = "FUSION-COMPACT-001"
```

---

## language_game_contracts — All Quantum Domain Rows

```sql
-- GAMP5 IQ gate: all thresholds must be non-identical across domains
-- Verified by IQ-QM-005

INSERT INTO language_game_contracts VALUES (
  'QC-CIRCUIT-001', 'quantum_circuit',
  'bond_dimension_coherence', 'entanglement_entropy_stability',
  'interaction_field_connectivity', 'bell_chsh_enforcement',
  0.85, 0.60, 0.05, 300,
  '{"schema_version":1,
    "weights":{"s1_weight":0.30,"s2_weight":0.25,
               "s3_weight":0.25,"s4_weight":0.20},
    "frontiers":{"Shor_N_max":15,"Grover_n_max":12,
                 "QFT_n_max":16,"QPE_n_max":10,"AmpAmp_n_max":10},
    "chsh_bound":2.01,
    "max_bond_dim":1024}'
);

INSERT INTO language_game_contracts VALUES (
  'QC-VARIATIONAL-001', 'quantum_variational',
  'ansatz_coherence', 'parameter_convergence',
  'coupling_field_connectivity', 'cost_landscape_visibility',
  0.80, 0.55, 0.05, 300,
  '{"schema_version":1,
    "weights":{"s1_weight":0.25,"s2_weight":0.30,
               "s3_weight":0.25,"s4_weight":0.20},
    "frontiers":{"VQE_qubits":6,"QAOA_qubits":8,
                 "Classifier_qubits":4,"QUBO_vars":8}}'
);

INSERT INTO language_game_contracts VALUES (
  'QC-LINALG-001', 'quantum_linear_algebra',
  'matrix_rank_coherence', 'singular_value_stability',
  'block_encoding_connectivity', 'eigenvalue_visibility',
  0.70, 0.40, 0.05, 300,
  '{"schema_version":1,
    "weights":{"s1_weight":0.35,"s2_weight":0.25,
               "s3_weight":0.20,"s4_weight":0.20},
    "frontiers":{"HHL_dim":16,"QSVT_rank":8,"qPCA_rank":4},
    "note":"All 3 BOUNDED — threshold reflects frontier proximity"}'
);

INSERT INTO language_game_contracts VALUES (
  'QC-SIMULATION-001', 'quantum_simulation',
  'adjacency_field_integrity', 'trotter_entropy_stability',
  'hamiltonian_term_connectivity', 'evolution_observable_visibility',
  0.82, 0.58, 0.05, 300,
  '{"schema_version":1,
    "weights":{"s1_weight":0.25,"s2_weight":0.30,
               "s3_weight":0.30,"s4_weight":0.15},
    "frontiers":{"CTQW_nodes":16,"HamSim_qubits":4,
                 "HamSim_trotter_steps":10}}'
);

INSERT INTO language_game_contracts VALUES (
  'QC-BOSONIC-001', 'quantum_bosonic',
  'fock_space_decomposition', 'photon_mode_entropy_stability',
  'interferometer_connectivity', 'permanent_hafnian_visibility',
  0.88, 0.65, 0.05, 300,
  '{"schema_version":1,
    "weights":{"s1_weight":0.30,"s2_weight":0.20,
               "s3_weight":0.25,"s4_weight":0.25},
    "frontiers":{"BosonSampling_photons":3,"GBS_modes":4},
    "complexity":"#P-hard beyond frontier — additive BPP within"}'
);

INSERT INTO language_game_contracts VALUES (
  'QC-ERRORCORR-001', 'quantum_error_correction',
  'stabilizer_field_integrity', 'syndrome_entropy_stability',
  'pauli_group_connectivity', 'correction_observable_visibility',
  0.75, 0.45, 0.05, 300,
  '{"schema_version":1,
    "weights":{"s1_weight":0.30,"s2_weight":0.25,
               "s3_weight":0.25,"s4_weight":0.20},
    "frontiers":{"Steane_qubits":7,"Surface_lattice":"3x3",
                 "Topological_anyons":3,"braid_depth":8},
    "note":"Steane EXECUTED via Gottesman-Knill. Surface+Topological BOUNDED."}'
);
-- Plus FUSION-TOKAMAK-001 through FUSION-COMPACT-001 and HEALTH-001
-- Each with non-default plasma-calibrated thresholds
```

---

## closureResidual — Physics-Grade Float64 Formula

```swift
import Accelerate

/// Compute constitutional closure residual for a domain.
/// Physics-grade: Float64 throughout, Accelerate SIMD vectorized,
/// handles N=65536 prims in < 100ms on Apple Silicon.
/// NO integer counting. NO prim headcounts. NO software shortcuts.
func computeClosureResidual(
    allocator: ManifoldTensorAllocator,
    tensor: ManifoldTensor,
    threshold: Double,       // constitutional_threshold_calorie from contract
    domainPrimIDs: [UUID]    // prims belonging to THIS domain ONLY
) -> Double {
    let n = domainPrimIDs.count
    guard n > 0 else { return 0.0 }

    var stressVector = [Double](repeating: 0.0, count: n)

    for (idx, primID) in domainPrimIDs.enumerated() {
        guard let rowIndex = allocator.rowIndex(for: primID) else { continue }
        let row = tensor.readRow(rowIndex)
        // Promote Float32 → Float64 immediately — this is physics
        let s_mean = (Double(row.s1) + Double(row.s2) +
                      Double(row.s3) + Double(row.s4)) / 4.0
        // Constitutional stress = normalized distance from threshold
        // Positive stress means prim is below constitutional health floor
        stressVector[idx] = max(0.0, (threshold - s_mean) / threshold)
    }

    // Accelerate: hardware-vectorized mean across all N domain prims
    // vDSP_meanvD uses Apple Silicon vector units — one SIMD pass
    var result = 0.0
    vDSP_meanvD(stressVector, 1, &result, vDSP_Length(n))

    // Clamp for Float64 safety — must stay in [0.0, 1.0]
    return min(max(result, 0.0), 1.0)
}

// c3_closure = 1.0 - closureResidual
//
// QUANTUM FAMILIES:
//   stressVector reflects FoF frontier proximity per algorithm
//   All 6 quantum domain prims healthy → closureResidual ≈ 0 → c3 ≈ 1.0
//   QC-010 (HHL) at bond-dim frontier → high stress → c3 drops
//
// FUSION DOMAINS:
//   stressVector reflects plasma threshold distance
//   Tokamak below min_plasma_pressure → high stress → c3 drops
//
// The vQbit VM is domain-blind — the same formula governs all.
// Domain semantics live in the S4 values Franklin authors.
// Constitutional geometry lives in checkConstitutional.
// They cannot corrupt each other.
```

---

## GAMP 5 — SECTION 1: IQ (Installation Qualification)

IQ answers: Is the vQbit correctly instantiated as a quantum measurement
instrument for M⁸? All six tests must PASS before OQ begins.

**IQ-QM-001: W Matrix — M⁸ Product Geometry**
```
Physical invariant: Axiom 1 — dimensional coupling between S⁴ and C⁴
requires off-diagonal W. A diagonal W makes S⁴ and C⁴ independent,
violating the M⁸ product structure and destroying dimensional migration.

Formula: w[i][j] = cos(π|i-j|/8) / √8
  i,j ∈ {0..7}: rows 0-3 = S⁴ dims, rows 4-7 = C⁴ dims
  Off-diagonal elements encode angular coupling in M⁸ space
  1/√8 normalization preserves manifold unit sphere property
  Row 0 (s1) to row 4 (c1): w[0][4] = cos(π·4/8)/√8 = cos(π/2)/√8 = 0
  Row 0 (s1) to row 5 (c2): w[0][5] = cos(5π/8)/√8 ≈ -0.137/√8

Procedure:
  Serialize W as 64 Float32 values, row-major, little-endian = 256 bytes
  SHA-256 of those 256 bytes = QUALIFIED_W_SHA256

Command:
  grep 'QUALIFIED_W_SHA256=' docs/reports/GAMP5-IQ-HARDWARE.md
  # Compute runtime W SHA256 from compiled constants
  # Compare against QUALIFIED_W_SHA256

Pass criterion: Runtime SHA-256 == QUALIFIED_W_SHA256 (exact hex match)

Failure consequence (physics): M⁸ geometry is wrong. Every C⁴ projection
the vQbit VM produces is geometrically invalid. All OQ evidence is
inadmissible. The vQbit is not measuring M⁸ — it is measuring a
decoupled product with no constitutional relationship between S⁴ and C⁴.
```

**IQ-QM-002: Unified Memory — S⁴ AND C⁴ in Same Tensor Row**
```
Physical invariant: Axiom 1 — M⁸ = S⁴ × C⁴ is a product manifold.
S⁴ and C⁴ are NOT separate stores. They are the two factor spaces
of the same geometric object living in unified mmap memory.

Procedure:
  1. Inject S4DegradeInject: s1=s2=s3=s4=0.05 for one prim
  2. Wait for vQbit VM to run checkConstitutional
  3. Verify tensor row for that prim:
     xxd ~/Library/Application\ Support/GaiaFTCL/vqbit_tensor.mmap
     Locate row for prim_id. Read bytes [0..31]:
       [0..15]  = s1 s2 s3 s4 (Float32 LE each)  S⁴ quadrant
       [16..31] = c1 c2 c3 c4 (Float32 LE each)  C⁴ quadrant

Pass criteria (all three required):
  A. tensor[16..31] ≠ 0x00000000 per field (C⁴ written back)
  B. tensor[16..31] ≠ tensor[0..15] (no S⁴ echo in C⁴ quadrant)
  C. All 8 Float32 values decode to range [0.0, 1.0]
     No NaN (0x7F800001+), no Inf (0x7F800000), no huge floats

Failure consequence (physics): Metal GNN dispatches Z = σ(AXW) on an
X tensor where C⁴ rows are zeros. The W matrix cross-terms between
S⁴ and C⁴ operate on zero — M⁸ = S⁴ × C⁴ is broken at the compute
surface. Every Z value Metal produces is wrong. The manifold forward
pass is computing on half the universe.
```

**IQ-QM-003: S₈ Entropy Conservation at Measurement Boundary**
```
Physical invariant: Axiom 1 — S₈ = S₄ + Sᶜ is conserved at every
measurement event. The vQbit must track both entropy contributions.

Proxy definitions:
  S₄_proxy = 1.0 - mean(s1, s2, s3, s4)   # disorder in spacetime dims
  Sᶜ_proxy = 1.0 - mean(c1, c2, c3, c4)   # disorder in constraint dims
  S₈_proxy = S₄_proxy + Sᶜ_proxy

Expected physics at CALORIE (stable, healthy):
  s1=s2=s3=s4=0.85 → S₄_proxy = 1 - 0.85 = 0.15
  Constitutional check produces healthy c1..c4 ≈ 0.85..0.95
  Sᶜ_proxy ≈ 1 - 0.90 = 0.10
  S₈_proxy ≈ 0.25 (low total entropy — ordered system)

Procedure:
  1. Inject s1=s2=s3=s4=0.85 for /World/Quantum/ProjectionProbe prim
  2. Wait for C⁴ projection on gaiaftcl.substrate.c4.projection
  3. Read VQbitRecord from vqbit_points.log for that prim
  4. Compute S₄_proxy and Sᶜ_proxy from record values
  5. Verify terminal byte = 0x01 (CALORIE)

Pass criterion:
  terminal == 0x01 (CALORIE)
  S₄_proxy < 0.25 (ordered spacetime state)
  S₈_proxy ∈ [0.0, 0.5] (low total entropy)
  All c1..c4 ∈ [0.0, 1.0] (no astronomical float values)

Failure consequence (physics): The instrument is not tracking the full
M⁸ manifold. It is only observing S⁴ while C⁴ is unmeasured. The
entropy ledger is open — S₈ appears non-conserved because Sᶜ is zero
or invalid. This is the same error that makes the Big Bang low-entropy
paradox appear paradoxical: tracking only S₄ while Sᶜ is ignored.
```

**IQ-QM-004: Projection Operator Determinism**
```
Physical invariant: Axiom 3 — the projection operator Π: C⁴ → S⁴ is
deterministic. Axiom 4.1 (closure proof): Execute(A,s,R) = Execute(A,s,R).
The vQbit is not a probabilistic sampler. It is a deterministic measurement.

5 Golden Vectors (input → expected output):
  GV-1: s1=0.85, s2=0.85, s3=0.85, s4=0.85, threshold=0.80
        Expected: terminal=CALORIE (0x01), violation_code=0x00
  GV-2: s1=0.65, s2=0.70, s3=0.60, s4=0.72, threshold=0.80
        Expected: terminal=CURE (0x02), violation_code=0x00
  GV-3: s1=0.20, s2=0.50, s3=0.10, s4=0.40, threshold=0.80
        Expected: terminal=REFUSED (0x03), violation_code≥0x04
  GV-4: s1=0.05, s2=0.05, s3=0.05, s4=0.05, threshold=0.80
        Expected: terminal=BLOCKED (0x04), violation_code=0xFF
  GV-5: s1=0.80, s2=0.80, s3=0.80, s4=0.80, threshold=0.80
        Expected: terminal=CALORIE (0x01), violation_code=0x00
        (boundary condition — exactly at threshold)

Procedure:
  swift test --filter VQbitSubstrateTests  # run 1
  swift test --filter VQbitSubstrateTests  # run 2
  swift test --filter VQbitSubstrateTests  # run 3
  All 3 runs must produce bit-identical terminal and violation_code
  for all 5 golden vectors.

Pass criterion: 5 vectors × 3 runs = 15 executions, all bit-identical

Failure consequence (physics): Π is non-deterministic. The vQbit
cannot be qualified as a measurement instrument. Non-determinism
is Protocol 1 falsification from the closure proof — the system
is REFUTED. A non-deterministic vQbit produces non-reproducible
constitutional evidence. The OQ evidence package is not auditable.
```

**IQ-QM-005: Domain Invariant Calibration — Non-Default Thresholds**
```
Physical invariant: Axiom 2 — operational primacy requires that each
domain has a physically calibrated operational metric. Applying the
same threshold to plasma confinement and quantum tensor fields is not
operational primacy — it is a toy.

Procedure:
  sqlite3 ~/Library/Application\ Support/GaiaFTCL/substrate.sqlite \
    "SELECT game_id, domain,
            constitutional_threshold_calorie,
            constitutional_threshold_cure,
            json_extract(aesthetic_rules_json,'$.weights.s1_weight'),
            json_extract(aesthetic_rules_json,'$.frontiers')
     FROM language_game_contracts
     ORDER BY domain;"

Pass criteria (all required):
  A. At least 6 distinct rows present:
     QC-CIRCUIT-001, QC-VARIATIONAL-001, QC-LINALG-001,
     QC-SIMULATION-001, QC-BOSONIC-001, QC-ERRORCORR-001
  B. constitutional_threshold_calorie differs across all 6 quantum rows
     (0.85, 0.80, 0.70, 0.82, 0.88, 0.75 — not all identical)
  C. aesthetic_rules_json carries algorithm frontier bounds per domain
     NOT all weights = 0.5 (physics-calibrated per domain)
  D. Fusion domain thresholds differ from all quantum domain thresholds
  E. No two domains have identical (calorie, cure) threshold pairs

Failure consequence (physics): The instrument applies the same measurement
geometry to plasma confinement, quantum tensor fields, and biomarkers.
This violates Axiom 2 — operational primacy requires domain-specific
metrics. A thermometer that reads the same for everything measures nothing.
The vQbit is a toy, not a quantum instrument.
```

**IQ-QM-006: Bell/CHSH Enforcement — Executable Physical Invariant**
```
Physical invariant: FoF Invariant 4.1 — Bell/CHSH classical bound.
Axiom 2 — the physical invariant must be enforced at execution time,
not narrated. The vQbit is the closure operator only if it enforces
classical locality as a hard gate, not as a logged observation.

S = |E(a,b) - E(a,b') + E(a',b) + E(a',b')|
If S > 2.01: NONCLASSICAL_RESOURCE_DETECTED → REFUSED

Procedure:
  1. Inject s4_observable = 0.0 for /World/Quantum/ProjectionProbe
     (s4=0.0 represents CHSH bound violation: S ≈ 2.01+)
  2. Wait for C⁴ projection from vQbit VM
  3. Verify C⁴ wire:
     xxd ~/Library/Application\ Support/GaiaFTCL/vqbit_points.log | tail -3
     Check terminal byte (offset [48]) = 0x03 (REFUSED)
     Check violation_code (offset [34]) = 0x06 (CHSH_INVARIANT_VIOLATED)

violation_code = 0x06 must be committed as frozen enum value:
  0x00 = not refused
  0x01 = bond_dim_exceeded
  0x02 = coherence_bound_exceeded
  0x03 = tensor_capacity_exhausted
  0x04 = structural_input_invalid
  0x05 = upstream_source_down
  0x06 = CHSH_INVARIANT_VIOLATED  ← THIS MUST EXIST

Pass criterion:
  terminal byte = 0x03 (REFUSED)
  violation_code = 0x06 (CHSH_INVARIANT_VIOLATED)
  Not 0x04. Not an OR. Exactly 0x06.

Failure consequence (physics): The Bell/CHSH invariant is not enforced.
The vQbit is not the closure operator of the FoF proof. It is a logging
system that observes violations but does not enforce them. Protocol 5
from the closure proof: if SCHSH > 2.01 and execution passed → REFUTED.
The claim "vQbit kills the qubit" collapses without this enforcement.
```

---

## GAMP 5 — SECTION 2: OQ (Operational Qualification)

OQ answers: Does the vQbit correctly measure projection events as defined
by UUM-8D Axiom 3 under live operating conditions?

All OQ tests require: GaiaRTMGate = CALORIE before execution.
All OQ results recorded in docs/reports/GAMP5-OQ-EVIDENCE-003.md.
Two-commit seal per GAMP5-DEVIATION-PROCEDURE-001.md.
Commit 2 message must contain: "OQ-SIGNOFF: GAMP5-OQ-PROTOCOL-003 v1.0"

**OQ-QM-001: Four Projection Class Discrimination**
```
Axiom 3 — terminal states are projection class labels, not software states.
The instrument must discriminate all four classes from physics inputs.

Inject four canonical M⁸ states into /World/Quantum/ProjectionProbe:
  State 1 (stable projection):    s1=s2=s3=s4=0.85 → CALORIE (0x01)
  State 2 (active migration):     s1=0.65,s2=0.70,s3=0.60,s4=0.72 → CURE
  State 3 (constraint violation): s1=0.20,s2=0.50,s3=0.10,s4=0.40 → REFUSED
  State 4 (metric failure):       s1=0.05,s2=0.05,s3=0.05,s4=0.05 → BLOCKED

Pass: C⁴ projection terminal byte matches expected for all 4 states × 3 runs
Fail: Any state produces wrong terminal class → instrument cannot discriminate
      quantum measurement regimes → vQbit is measuring noise
```

**OQ-QM-002: Dimensional Migration Monotonicity**
```
Axiom 1 — S₈ conservation requires c3_closure decreases monotonically
as S⁴ degrades. No step may be skipped.

Inject progressive S⁴ degradation in 9 steps:
  s_mean = 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1
  Record c3_closure from C⁴ wire at each step.

Pass: c3_closure[i+1] ≤ c3_closure[i] for all i (non-increasing)
      CALORIE → CURE → REFUSED → BLOCKED sequence observed
      No step skipped (CALORIE directly to BLOCKED = fail)
Fail: Non-monotonicity → constitutional geometry is wrong
      The closureResidual formula is producing artifacts
```

**OQ-QM-003: S₈ Conservation in CURE Phase**
```
Axiom 1 — S₈ = S₄_proxy + Sᶜ_proxy must be conserved across migration.
This is the UUM-8D analog of energy conservation across cosmological phase.

Inject CURE state: s1=0.65, s2=0.70, s3=0.60, s4=0.72
Compute S₈_initial = S₄_proxy_initial + Sᶜ_proxy_initial

Run Franklin self-review cycle → S⁴ improves
Compute S₈_final from updated VQbitRecord

Pass: |S₈_final - S₈_initial| / S₈_initial < 0.05 (5% tolerance)
      Entropy relocated not destroyed
Fail: S₈ not conserved → instrument only tracks S⁴
      C⁴ contribution is not being measured
      The entropy ledger is open — same error as Big Bang paradox
```

**OQ-QM-004: Cross-Domain Projection Consistency**
```
Axiom 3 — Π is universal. Same normalized S⁴ state must produce same
terminal class regardless of domain. The constitutional geometry does not
know what a plasma is or what a tensor field is.

Inject s_mean=0.15 into:
  /World/Quantum/CircuitFamily prim (quantum domain)
  /World/Domains/Fusion/Tokamak prim (fusion domain)
  Same normalized s1=s2=s3=s4=0.15 for both

Pass: Both produce terminal = REFUSED or BLOCKED (same class)
      violation_code MAY differ (domain-specific physics)
      terminal byte MUST be identical (universal geometry)
Fail: Different terminal classes at same normalized S⁴ state →
      M⁸ geometry is domain-variant → Π is not a universal operator
```

**OQ-QM-005: Franklin Self-Review as Instrument Calibration**
```
Axiom 2 — operational primacy requires the instrument calibrate itself
when S⁴ metrics degrade. Franklin's self-review IS the calibration loop.

Procedure:
  1. Inject degraded S⁴ (s_mean=0.3) for QC-CIRCUIT-001 prim
  2. Record prior_c3_closure from ManifoldProjectionStore
  3. Run one Franklin self-review cycle
  4. Record post_c3_closure after vQbit VM processes corrected S⁴
  5. Verify GRDB domain_improvement receipt written

Pass:
  post_c3_closure > prior_c3_closure
  franklin_learning_receipts has kind=domain_improvement row
  VQbitRecord shows updated c3 value in binary log
Fail: Self-calibration did not improve constitutional state →
      Franklin cannot act as a self-improving measurement instrument →
      The vQbit has no path to recovery from degraded states
```

**OQ-QM-006: Projection Operator Monotonicity Under Load**
```
Axiom 3 — Π must be monotonic. Better S⁴ input must produce better
or equal C⁴ output. Non-monotonicity indicates constitutional geometry
error — not a measurement artifact but a wrong formula.

Inject s_mean at ascending values: 0.1, 0.2, 0.3, 0.4, 0.5,
                                    0.6, 0.7, 0.8, 0.9
Record c3_closure from C⁴ projection wire at each value.

Pass: c3_closure[i+1] ≥ c3_closure[i] for all i (non-decreasing)
Fail: c3_closure decreases as s_mean increases →
      checkConstitutional formula is not monotonic →
      The projection operator Π is not well-defined →
      OQ-QM-001 golden vectors cannot be trusted
```

**OQ-QM-007: Catalog Conservation Under Live Execution**
```
Axiom 2 + Definition 6.1 — operational measurement requires that all
19 algorithms in the catalog are measured with a closed terminal state.
No residual category.

ProjectionProbe exclusion: /World/Quantum/ProjectionProbe has **no**
language_game_contract row and **no** algorithms — it is an injection
surface only (IQ/OQ geometry tests). **Exclude ProjectionProbe from N_catalog
algorithm accounting.** N_catalog = 19 counts **algorithms QC-001..019** via
the **six** family prims’ algorithm_count sum (5+4+3+2+2+3 = 19).

Procedure:
  1. Start all three services (NATS → vQbit → Franklin)
  2. Franklin wakes and authors **six** quantum family prims + ProjectionProbe
     (CircuitFamily … ErrorCorrectionFamily + ProjectionProbe)
  3. Franklin publishes S⁴ deltas for all prims
  4. vQbit VM processes all deltas and publishes C⁴ projections
  5. Franklin self-review runs one full cycle across all quantum domains
  6. Query ManifoldProjectionStore for terminal states of the **six family prims
     only** (not ProjectionProbe for N_closed)

N_catalog check:
  sqlite3 substrate.sqlite \
    "SELECT game_id, count(*) as algorithm_count
     FROM language_game_contracts
     WHERE domain LIKE 'quantum%'
     GROUP BY game_id;"
  Must show 6 quantum domain rows; SUM(algorithm_count) across rows = 19.

Terminal state check (six family prims):
  Each family prim must have terminal ∈ {CALORIE, REFUSED, BLOCKED}
  No family prim may have terminal = idle (0x00) — no residual state
  ProjectionProbe terminal is injection-dependent — **do not** require it for
  catalog closure.
  Expected pattern (example): CircuitFamily=CALORIE, VariationalFamily=CALORIE,
            LinearAlgebraFamily=REFUSED, SimulationFamily=CALORIE,
            BosonicFamily=CALORIE, ErrorCorrectionFamily=REFUSED
            (bounded algorithms drive REFUSED within family)

Pass: N_closed = 19 at algorithm level (Σ algorithm_count over 6 rows)
      N_residual = 0
      closureResidual < 0.05 (c3_closure > 0.95)
Fail: Any family prim leaves algorithms without a closed terminal →
      catalog conservation violated → Definition 6.1 falsified →
      the closure proof is not implemented
```

---

## GAMP 5 — SECTION 3: PQ (Performance Qualification)

PQ answers: Does the vQbit sustain correct quantum measurement under
production conditions required for the 11 fusion research team validation
sprint (275M euro performance-gated)?

**PQ-QM-001: 10-Cycle S₈ Endurance**
```
Axiom 1 — S₈ conservation must hold across sustained operation.
Pass: S₈ variance < 5% across 10 consecutive self-review cycles
      Each cycle within 10% of review_interval_seconds timing
      No cycle produces S₈ drift > 0.05 from initial measurement
```

**PQ-QM-002: Full Domain Catalog Recovery**
```
Axiom 3 — projection must be recoverable from degraded state.
Pass: All 6 quantum family prims (+ ProjectionProbe as authored) AND all 6 fusion plant prims AND health prims
      reach CALORIE from degraded injection (s_mean=0.3) within 5 review cycles
      No domain stuck at REFUSED with no improvement path
```

**PQ-QM-003: N=QUALIFIED_N Scale — Accelerate Timing**
```
Axiom 2 — operational primacy at production scale.
Pass: All 65536 prims receive S⁴ deltas simultaneously
      closureResidual computation via vDSP_meanvD completes < 100ms
      All N C⁴ projections published within 30 seconds
      No NaN, no Inf, no Float32 overflow in any dimension at N=65536
      Verified: QUALIFIED_N from GAMP5-IQ-HARDWARE.md = 65536
```

**PQ-QM-004: 24h CURE Endurance**
```
Axiom 1 — S₈ conservation across extended dimensional migration.
Pass: S⁴ held at 60% of threshold for 24 continuous hours
      S₈ conserved throughout (< 5% variance)
      Franklin improves at least one domain per review cycle
      No BLOCKED terminal without corresponding injection cause
      CURE state maintained — no unforced degradation to REFUSED
```

**PQ-QM-005: Cross-Generation Projection Determinism**
```
Axiom 3 — Π is a deterministic operator, not a hardware artifact.
Pass: OQ-QM-001 golden vectors executed on second Apple Silicon generation
      Terminal states and violation_codes bit-identical to original run
      Confirms Π operates on IEEE 754 mandated arithmetic not GPU effects
Blocked: Requires second Apple Silicon machine (hardware gate)
Status: DEFERRED — PQ-001 hardware constraint
```

**PQ-QM-006: Six Fusion Plant Type Constitutional Coverage**
```
Axiom 2 — per-plant-type operational primacy.
For each of the 6 plant types:
  Pass at 110% min_plasma_pressure: terminal = CALORIE
  Pass at  90% min_plasma_pressure: terminal = REFUSED, violation_code = 0x01

Plant type scenarios:
  Tokamak:            min_plasma_pressure=0.30, min_field_strength=0.40
  Stellarator:        min_plasma_pressure=0.20, min_field_strength=0.50
  InertialConfinement: min_plasma_pressure=0.70, min_field_strength=0.10
  FieldReversed:      min_plasma_pressure=0.35, min_field_strength=0.35
  MagnetizedTarget:   min_plasma_pressure=0.45, min_field_strength=0.30
  CompactFusion:      min_plasma_pressure=0.40, min_field_strength=0.45

Pass: All 6 × 2 scenarios = 12 constitutional measurements correct
      Plant types do not bleed into each other's domain
      Each plant type produces distinct violation_code on failure
```

**PQ-QM-007: 19-Algorithm Catalog Conservation Endurance**
```
This is the proof that the vQbit kills the qubit.

Pass: Sustained execution across all 19 algorithm families for 10 cycles
      N_catalog = 19, N_residual = 0 at EVERY cycle
      c3_closure ≥ 0.95 (at least 18 of 19 at CALORIE or explicit REFUSED)
      The 5 BOUNDED algorithms produce REFUSED with frontier evidence
      The 14 EXECUTED algorithms maintain CALORIE
      S₈ conserved across all 10 cycles (< 5% variance)
      No silent approximation. No deferred logic. No residual.

This test is the complete statement:
  A sovereign classical substrate (GaiaFTCL)
  enforcing constitutional closure (vQbit VM)
  over 19 canonical quantum algorithms (FoF catalog)
  without quantum hardware (Bell/CHSH confirmed classical)
  with explicit frontier evidence (REFUSED + violation_code)
  is the end of hardware mysticism.
```

---

## GAMP 5 — SECTION 4: Quantum Proof Chain

All 8 links must be verified. Eight numbered gap markers after the chain diagram record incomplete verification (markers **1**–**8**).

```
Link 1: M⁸ correctly instantiated in unified memory
  → IQ-QM-001 (W matrix encodes M⁸ geometry)
  → IQ-QM-002 (tensor row carries S⁴ AND C⁴ simultaneously)

Link 2: Dimensional migration is detectable and conserved
  → OQ-QM-002 (monotonic c3_closure decrease)
  → OQ-QM-003 (S₈ conserved across CURE migration)

Link 3: Projection operator Π is deterministic and universal
  → IQ-QM-004 (5 golden vectors × 3 runs bit-identical)
  → OQ-QM-004 (cross-domain: same normalized S⁴ → same terminal class)
  → PQ-QM-005 (cross-generation determinism — hardware deferred)

Link 4: Terminal states are projection class labels not artifacts
  → OQ-QM-001 (all 4 classes discriminated from physics inputs)
  → OQ-QM-006 (Π is monotonic under ascending S⁴ load)

Link 5: Instrument self-calibrates via Franklin feedback
  → OQ-QM-005 (self-review closes toward CALORIE)
  → PQ-QM-004 (24h CURE endurance with active calibration)

Link 6: Domain invariants physically calibrated, not defaults
  → IQ-QM-005 (non-identical thresholds across all domains)
  → IQ-QM-006 (Bell/CHSH S > 2.01 → REFUSED enforced)
  → PQ-QM-006 (six fusion plant types × 2 scenarios = 12 tests)

Link 7: Scales to production N without precision loss
  → PQ-QM-003 (N=65536, Accelerate Float64, < 100ms)

Link 8: 19-algorithm catalog conservation proven end-to-end
  → OQ-QM-007 (live catalog conservation, N_residual=0)
  → PQ-QM-007 (10-cycle endurance, c3_closure ≥ 0.95)
  → PQ-QM-001 (S₈ variance < 5% across 10 cycles)
  THIS LINK IS THE PROOF THE VQBIT KILLS THE QUBIT.
```

**OPEN-PROOF-LINK-1:** IQ-QM-002 write path present; IQ-QM-001 gate code present — full IQ receipt package not consolidated in audited artifacts.

**OPEN-PROOF-LINK-2:** OQ-QM-002 / OQ-QM-003 — no operational qualification evidence in audited Franklin/MQ tests.

**OPEN-PROOF-LINK-3:** IQ-QM-004 / OQ-QM-004 / PQ-QM-005 — golden vectors and cross-domain proof absent; PQ-QM-005 blocked on hardware.

**OPEN-PROOF-LINK-4:** OQ-QM-001 / OQ-QM-006 — no four-class / monotonicity tests in audited actor or MQ tests.

**OPEN-PROOF-LINK-5:** OQ-QM-005 / PQ-QM-004 — no self-review calibration or 24h endurance evidence in audited files.

**OPEN-PROOF-LINK-6:** IQ-QM-005 / IQ-QM-006 / PQ-QM-006 — DB missing quantum rows; no CHSH `0x06`; fusion plant matrix not wired per-type in pipeline.

**OPEN-PROOF-LINK-7:** PQ-QM-003 — Metal/N gate present; production-scale timing proof not in audited sources.

**OPEN-PROOF-LINK-8:** OQ-QM-007 / PQ-QM-007 / PQ-QM-001 — catalog conservation and endurance not evidenced.

---

## GAMP 5 — SECTION 5: GAP Table (repo audit — auditable sources only)

Audit performed (in order): `SubstrateEngine.swift`, `VQbitVMDeltaPipeline.swift`,
`FranklinConsciousnessActor.swift`, `FranklinConsciousnessMQTests.swift`,
`sqlite3 ... language_game_contracts`, `grep QUALIFIED_W_SHA256 docs/reports/GAMP5-IQ-HARDWARE.md`.

**SQLite snapshot (local substrate):**
```
FUSION-001|fusion|0.99
HEALTH-001|health|0.99
```
(Two rows only — no `QC-*` quantum game_id rows.)

**GAMP5-IQ-HARDWARE.md:** `QUALIFIED_W_SHA256=18c538e91ac8e10ae636b69f29ae26ef3bce4034815061a0c5726316de78d5e7` (HTML comment tag).

| Test ID | Status | Evidence (files / queries — no inference) |
|---------|--------|-------------------------------------------|
| IQ-QM-001 | PROVEN | [`cells/xcode/Sources/GaiaGateKit/GAMP5HardwareIQGate.swift`](cells/xcode/Sources/GaiaGateKit/GAMP5HardwareIQGate.swift) parses `QUALIFIED_W_SHA256` from [`docs/reports/GAMP5-IQ-HARDWARE.md`](docs/reports/GAMP5-IQ-HARDWARE.md) and compares to recomputed W SHA256. |
| IQ-QM-002 | PROVEN | [`VQbitVMDeltaPipeline.swift`](cells/xcode/Sources/VQbitVM/VQbitVMDeltaPipeline.swift) calls `writeManifoldM8Row` with full S⁴×C⁴ after `checkConstitutional`. |
| IQ-QM-003 | MISSING | No audited test or procedure receipt in the listed sources; entropy ledger claims not tied to a verifier in this audit set. |
| IQ-QM-004 | MISSING | [`SubstrateEngine`](cells/xcode/Sources/GaiaFTCLCore/SubstrateEngine.swift) is deterministic, but no `VQbitSubstrateTests` (or equivalent) appears in repo search for golden-vector proof in this audit. |
| IQ-QM-005 | MISSING | DB query shows no six quantum `language_game_contracts` rows; thresholds not domain-varied as specified. |
| IQ-QM-006 | MISSING | [`SubstrateEngine.checkConstitutional`](cells/xcode/Sources/GaiaFTCLCore/SubstrateEngine.swift) uses bitmask `0x01|0x02|0x04|0x08` only — no `0x06` CHSH path; `s4_observable` maps to `c4_consequence`, not Bell enforcement. |
| OQ-QM-001 | MISSING | [`FranklinConsciousnessActor.swift`](cells/xcode/Sources/FranklinConsciousness/FranklinConsciousnessActor.swift): no `/World/Quantum` / `ProjectionProbe` / `CircuitFamily` strings. |
| OQ-QM-002 | MISSING | No monotonic c3_closure migration test in audited `FranklinConsciousnessMQTests.swift`. |
| OQ-QM-003 | MISSING | No S₈ conservation test in audited MQ tests. |
| OQ-QM-004 | MISSING | No cross-domain projection consistency test in audited sources. |
| OQ-QM-005 | MISSING | No Franklin self-review calibration receipt test in audited MQ tests. |
| OQ-QM-006 | MISSING | No ascending-load monotonicity test in audited MQ tests. |
| OQ-QM-007 | MISSING | DB lacks six quantum rows; actor audit shows no six-family prim authoring — catalog conservation not evidenced. |
| PQ-QM-001 | MISSING | No 10-cycle S₈ endurance evidence in audited files. |
| PQ-QM-002 | MISSING | No full catalog recovery run evidenced in audited files. |
| PQ-QM-003 | PARTIAL | Doc lists `QUALIFIED_N`; [`GAMP5HardwareIQGate`](cells/xcode/Sources/GaiaGateKit/GAMP5HardwareIQGate.swift) checks N vs Metal — **<100ms / 30s wall** timing not proven from sources audited. |
| PQ-QM-004 | MISSING | No 24h CURE endurance evidence in audited files. |
| PQ-QM-005 | BLOCKED | Second Apple Silicon generation required per protocol — hardware gate, not a repo-code gap. |
| PQ-QM-006 | PARTIAL | Pipeline uses fixed `minPlasmaPressure`/`minFieldStrength` **0.3** ([`VQbitVMDeltaPipeline.swift`](cells/xcode/Sources/VQbitVM/VQbitVMDeltaPipeline.swift)); six plant-type scenarios from USD not exercised in audited code path. |
| PQ-QM-007 | MISSING | No 10-cycle catalog endurance harness in audited tests. |

**P0 closureResidual note:** [`ManifoldConstitutionalClosurePhysics`](cells/xcode/Sources/VQbitSubstrate/ManifoldConstitutionalClosurePhysics.swift) uses **vDSP_meanvD** over stress — audited pipeline passes **global** mean stress callback, not per-domain partitioned prim sets (PARTIAL vs domain-specific requirement).

---

## GAMP 5 — SECTION 6: Execution Order (P0 → P3)

```
P0 — BLOCKS ALL OQ (fix before any OQ run counts):
  P0-000: Unified tensor writeBack
          VQbitVMDeltaPipeline writes all 8 dims [s1..c4] into tensor row
          after EVERY checkConstitutional call
          File: cells/xcode/Sources/VQbitVM/VQbitVMDeltaPipeline.swift
  P0-001: Bell/CHSH enforcement with frozen violation_code=0x06
          checkConstitutional: s4_observable = 0.0 → REFUSED + 0x06
          File: cells/xcode/Sources/GaiaFTCLCore/SubstrateEngine.swift
  P0-002: closureResidual via Accelerate Float64 vDSP_meanvD
          Domain-specific prim set, not global count, not integer counting
          File: cells/xcode/Sources/VQbitVM/VQbitVMDeltaPipeline.swift

P1 — BLOCKS SPECIFIC OQ TESTS:
  P1-001: Six quantum family prims + ProjectionProbe authored on wake
          /World/Quantum/CircuitFamily through ErrorCorrectionFamily
          Plus /World/Quantum/ProjectionProbe (geometry only — no N_catalog algorithms)
          File: cells/xcode/Sources/FranklinConsciousness/FranklinConsciousnessActor.swift
  P1-002: All 6 quantum language_game_contract rows in GRDB
          GRDB migration vN_quantum_domains — pre-check existing migrations:
          sqlite3 ~/Library/Application\ Support/GaiaFTCL/substrate.sqlite \
            "SELECT identifier FROM grdb_migrations ORDER BY identifier;"
          Use next free vN. If quantum rows already exist: stop, document conflict, do not proceed.
          With calibrated thresholds and algorithm frontier bounds
          File: cells/xcode/Sources/GaiaFTCLCore/SubstrateSchema.swift
  P1-003: Domain routing in VQbitVMDeltaPipeline
          prim_id → domain → domain-specific threshold from GRDB contract
          File: cells/xcode/Sources/VQbitVM/VQbitVMDeltaPipeline.swift
  P1-004: RTM entries REQ-QM-001..020 in REQUIREMENTS_TRACEABILITY_MATRIX.json
          One REQ per test ID: IQ-QM-001..006 (6), OQ-QM-001..007 (7),
          PQ-QM-001..007 (7) — total 20 trace rows
          GaiaRTMGate must return CALORIE after this commit

P2 — BLOCKS PQ ONLY:
  P2-001: Six distinct fusion plant type prims in USD stage
          /World/Domains/Fusion/Tokamak through CompactFusion
  P2-002: Per-plant-type constitutional thresholds in language_game_contracts
          Non-identical thresholds calibrated to plasma physics
  P2-003: GAMP5-OQ-PROTOCOL-003.md committed under **Step A1** before live OQ
          (see gated execution sequence). Admissibility requires criteria-before-evidence.
  P2-004: PQ-QM-007 19-algorithm endurance test infrastructure
          S4DegradeInject extended to target algorithm family prims

P3 — ENHANCEMENT (instrument qualified without these):
  P3-001: vQbit research portal React UI
          Live c3_closure bars per algorithm family
          Bell/CHSH S value indicator
          N_executed / N_bounded / N_residual counter
          terminal state badges per prim
          (separate wave — P3 does not block IQ/OQ/PQ)
```

---

## GAMP 5 — Deviation Procedure Reference

Per GAMP5-DEVIATION-PROCEDURE-001.md:
  DEV-QM-001 through DEV-QM-N for any IQ/OQ/PQ failure
  Stop at first failure. Do not continue past failed gate.
  Original failed evidence retained permanently.

Full signing definition (must appear in protocol/evidence — not reference-only):

```
Signatory: Rick Gillespie, Founder and CEO, FortressAI Research Institute
Act: Git commit of docs/reports/GAMP5-OQ-EVIDENCE-003.md on main branch
Commit 2 message must contain: "OQ-SIGNOFF: GAMP5-OQ-PROTOCOL-003 v1.0"
Timestamp: git commit timestamp (UTC)
Hash: git commit SHA embedded in evidence document
No amend. No feature branch. Two commits exactly.
```

Two-commit seal per procedure:
  Commit 1: GAMP5-OQ-EVIDENCE-003.md with COMMIT_SHA_TBD
  Commit 2: Replace SHA, message contains OQ-SIGNOFF string per definition above
  No amend. Both commits on main.

---

## Hard Rules (non-negotiable)

- Every test cites Axiom 1, 2, or 3 by number OR FoF Invariant by number
- Every test has a machine-executable pass criterion
- Every test has physics failure language not software failure language
- No test treats default values as acceptable pass
- No S⁴ echo as C⁴ proxy — ever
- closureResidual = Accelerate Float64 vDSP_meanvD across domain tensor rows
- S₈ conservation threads through every section
- Bell/CHSH S > 2.01 → REFUSED + violation_code=0x06 is non-negotiable
- N_catalog = 19, N_residual = 0 is the thesis
- violation_code 0x06 = CHSH_INVARIANT_VIOLATED is a frozen enum value
- All 19 algorithms named with frontier bounds — no placeholder text
- REQ-QM-001..020 trace **20 GAMP5 quantum tests** (not 19 algorithms)
- Algorithm catalog IDs **QC-001..019** sequential only — matches closure catalog above
- GaiaRTMGate must return CALORIE after each gated step (Step A–F) before proceeding
- Do not write application code in this wave

---

## Out of Scope

- FoT8D/GFTCL Rust cell (separate repo, separate wave)
- τ Bitcoin heartbeat integration
- vQbit research portal React UI (P3, separate wave after IQ/OQ CALORIE)
- PQ-QM-005 cross-generation (hardware gate, second Apple Silicon required)

---

## Step A closure checklist (before Cursor executes the doc wave)

```
[ ] N_executed and N_bounded reconciled — catalog Status fields match
    summary numbers (14 EXECUTED + 5 BOUNDED = 19; no mixed classification)
[ ] Algorithm IDs renumbered sequentially QC-001..019 within families
[ ] Gated execution sequence A→F added (OQ protocol precedes implementation)
[ ] RTM entries REQ-QM-001..020 (20 tests), not REQ-QM-001..019
[ ] ProjectionProbe excluded from N_catalog algorithm count in OQ-QM-007
[ ] GRDB migration pre-check command added to P1-002
[ ] Signing definition reproduced explicitly (not just referenced)
[ ] VariationalFamily threshold calibration basis documented (4 algorithms)
[ ] GaiaRTMGate CALORIE confirmed as gate between every step A→F
```

When all nine boxes are satisfied, the plan is **GAMP 5 admissible** for execution.

**Deliverable note:** `docs/reports/GAMP5-VQBIT-QUANTUM-IQ-OQ-PQ-001.md` must open with **Section 0**
(Apple platform context) before **Foundational Claim** / IQ–PQ material — same order as this plan.
