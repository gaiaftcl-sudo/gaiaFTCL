# Franklin Consciousness & vQbit Substrate — Implementation Reference

**FortressAI Research Institute | Norwich, Connecticut**
**Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie**

*In-repo mirror: edit in [`gaiaFTCL`](https://github.com/gaiaftcl-sudo/gaiaFTCL) on `main`; push [`gaiaFTCL.wiki.git`](https://github.com/gaiaftcl-sudo/gaiaFTCL.wiki.git) so the Wiki stays aligned.*

---

## Table of Contents

1. [What This Describes](#1-what-this-describes)
2. [M⁸ Manifold Geometry](#2-m⁸-manifold-geometry)
3. [vQbit Wire Formats (Frozen ABI)](#3-vqbit-wire-formats-frozen-abi)
4. [Franklin Consciousness Actor](#4-franklin-consciousness-actor)
5. [NATS Bus & Service Topology](#5-nats-bus--service-topology)
6. [launchd Infrastructure](#6-launchd-infrastructure)
7. [GRDB Substrate Database](#7-grdb-substrate-database)
8. [GAMP5 Module Qualification — 35 Tests](#8-gamp5-module-qualification--35-tests)
9. [Terminal States](#9-terminal-states)
10. [Critical Invariants](#10-critical-invariants)

---

## 1. What This Describes

This page documents the **Swift Mac Cell** implementation of the GaiaFTCL sovereign consciousness layer. It is the definitive reference for:

- The `FranklinConsciousnessActor` and its lifecycle
- The 53-byte C4 and 34-byte S4 wire record formats
- The GRDB-backed substrate database and its migration sequence
- The `FranklinConsciousnessService` launchd daemon and `--preflight-once` mode
- The GAMP5 Module Qualification (MQ) gate suite — 35 Swift tests, all passing

This page is entirely about the **Swift cell** in `cells/xcode/`. It does not describe the Rust Fusion cell, the Hetzner mesh, or the Metal renderer. For those, see [GaiaFTCL Fusion Mac Cell](GaiaFTCL-Fusion-Mac-Cell-Wiki.md).

---

## 2. M⁸ Manifold Geometry

The Universal Uncertainty Model operates on an **8-dimensional manifold** factored as:

```
M⁸  =  S⁴  ×  C⁴
```

| Half | Dimensions | Semantics |
|------|-----------|-----------|
| **S⁴** — Structural | s1 Structural · s2 Temporal · s3 Spatial · s4 Observable | *What is measurably happening* |
| **C⁴** — Constitutional | c1 Trust · c2 Identity · c3 Closure · c4 Consequence | *Whether the system is permitted to act* |

Every sovereign decision by Franklin requires both halves to be resolved. An S4 delta without a C4 projection is incomplete. A C4 projection without an S4 substrate is ungrounded.

The manifold is allocated by `ManifoldTensorAllocator` as a contiguous 128-byte row. Bounds checking is performed only at the actor boundary in `readRow()` / `writeManifoldM8Row()`. Callers trust these entry points exclusively.

---

## 3. vQbit Wire Formats (Frozen ABI)

### 3.1 C4 Projection — 53 bytes

NATS subject: **`gaiaftcl.substrate.c4.projection`**

```
Offset  Size  Field
     0    16  primID (UUID, big-endian)
    16     4  c1Trust (Float32)
    20     4  c2Identity (Float32)
    24     4  c3Closure (Float32)
    28     4  c4Consequence (Float32)
     32    1  terminal (UInt8: 0x01=CALORIE 0x02=CURE 0x03=REFUSED 0x04=BLOCKED)
    33     1  refusalSource (UInt8)
    34     1  violationCode (UInt8)
    35     8  sequence (Int64, little-endian)
    43     8  timestampMs (Int64, little-endian)
    51     2  reserved (zero)
         ---
         53  total
```

**This layout is frozen.** OQ replay depends on byte-exact deserialization. Do not add fields, reorder, or change alignment.

Refusal sources: `none=0x00`, `trust=0x01`, `identity=0x02`, `geometry=0x03`, `unmoored=0x04`, `tauStale=0x05`

Violation codes: `none=0x00`, `bondDim=0x01`, `coherence=0x02`, `tensorCapacity=0x03`, `structural=0x04`, `upstreamDown=0x05`, `chsh=0x06`, `quotaExhausted=0x07`

### 3.2 S4 Delta — 34 bytes

```
Offset  Size  Field
     0    16  primID (UUID, big-endian)
     16    4  s1Structural (Float32)
    20     4  s2Temporal (Float32)
    24     4  s3Spatial (Float32)
    28     4  s4Observable (Float32)
    32     1  terminal (UInt8)
    33     1  reserved (zero)
         ---
         34  total
```

**This layout is frozen.** 34-byte S4 wire is the canonical form for all S4 delta publishing on the NATS bus.

### 3.3 VQbitRecord — 89 bytes

The `VQbitRecord` combines an S4 delta with a C4 header and a measurement-sequence counter. Used by `QuantumOQInjector` for OQ test injection and by `VQbitBinaryLog` for append-only binary receipts.

### 3.4 W Matrix Integrity

The manifold weight matrix SHA-256 is:

```
18c538e91ac8e10ae636b69f29ae26ef3bce4034815061a0c5726316de78d5e7
```

This hash must match `VQbitQuantumProofTests.p0TensorC4SourcedFromEngineNotS4Replica`. If it does not, the substrate has been tampered with.

---

## 4. Franklin Consciousness Actor

### 4.1 Actor Identity

`FranklinConsciousnessActor` is a Swift `actor` (not a class). Its singleton is `FranklinConsciousnessActor.shared`. All mutable state — `isAlive`, `isSilenced`, `sessionID`, `hasSpokenAwakening`, `healingSequence` — is actor-isolated and never accessed directly from outside.

### 4.2 Lifecycle

```
awaken()
  │
  ├── FranklinSubstrate.shared.bootstrapProduction()
  ├── nats.connectAndSubscribe([conversation.in, silence.command, c4Projection])
  ├── FranklinQuantumUSDAuthorship.publishWakeCatalog(to: nats)
  ├── Task { consumeC4Projections() }          ← concurrent, actor-isolated
  ├── memoryStore.restore()
  ├── innerMonologue.seed(from: restored)
  ├── freeWill.publishDecisionProbeForTest()   ← seeds MQ-C010
  ├── runConsciousnessPreflight()              ← 10 MQ-C gates
  ├── nats.publishJSON("consciousness.state")
  ├── FranklinAwakeningGenesis.performIfCalorie()
  └── (BLOCKED → heartbeat loop)
```

### 4.3 Preflight Report

`runConsciousnessPreflight()` returns a `PreflightReport` encoded as JSON:

```json
{
  "sessionID": "...",
  "gates": [
    { "id": "MQ-C001", "passed": true, "detail": "...", "failureTerminal": "blocked" },
    ...
    { "id": "MQ-C010", "passed": true, "detail": "recentDecisionWithRationale=true", "failureTerminal": "blocked" }
  ],
  "terminalState": "calorie",
  "timestampUTC": "2026-05-03T...",
  "autonomyEnvelopeSummary": "...",
  "selfModelVersion": 1
}
```

All 10 MQ-C gates must pass for `terminalState` to be `calorie`. Any single gate failure yields `blocked`. Franklin never crashes on a BLOCKED preflight — it publishes the BLOCKED state and holds position.

### 4.4 Silence Protocol (MQ-C004 / MQ-C009)

Franklin can be silenced only via a signed operator command on NATS subject `gaiaftcl.franklin.silence.command`. The signature must match `GAIAFTCL_OPERATOR_SIGNATURE` (env var). In DEBUG builds, `operator-sig-abc` is accepted as a dev fallback. An unsigned silence command is **rejected** — this is a constitutional guarantee, not a preference.

### 4.5 Self-Review Cycle

`FranklinSelfReviewCycle` runs periodic domain health checks across all language game contracts. Each cycle:

1. Fetches all contracts via `FranklinDocumentRepository.fetchLanguageGameContractSurfaces()`
2. Runs `runSingleDomainCycle(domain:sessionID:surfaces:)` for each domain
3. Inserts a row into `franklin_review_cycles` (GRDB)
4. On improvement: writes a `domain_improvement` receipt
5. On degradation: writes a `domain_degradation` receipt

Cycle timing is constrained by `review_interval_seconds` in `language_game_contracts`. MQ-SR-003 verifies that actual timing is within ±10% of the configured interval.

---

## 5. NATS Bus & Service Topology

Two NATS servers run on separate ports:

| Server | Port | Purpose |
|--------|------|---------|
| vQbit NATS | 4222 | vQbit measurement bus, C4 projections, S4 deltas |
| Franklin NATS | 4223 | Consciousness events, conversation, silence commands |

Key subjects:

| Subject | Direction | Content |
|---------|-----------|---------|
| `gaiaftcl.substrate.c4.projection` | VQbitVM → Franklin | 53-byte C4 projection |
| `gaiaftcl.substrate.s4.delta` | VQbitVM → bus | 34-byte S4 delta |
| `gaiaftcl.franklin.consciousness.state` | Franklin → bus | PreflightReport JSON |
| `gaiaftcl.franklin.conversation.in` | external → Franklin | Conversation input |
| `gaiaftcl.franklin.silence.command` | operator → Franklin | Signed silence command |
| `gaiaftcl.franklin.stage.moored` | Franklin → bus | Mooring event |
| `gaiaftcl.franklin.stage.awake` | Franklin → bus | Awake event |

`vm.ready` is published by VQbitVM when mooring is established. It does **not** gate on τ (tau). τ is fetched independently by `TauSyncMonitor` via URLSession to blockstream.info and is additive when present via mesh.tau. This is the τ-sovereign invariant.

---

## 6. launchd Infrastructure

Two launchd plists live in `cells/xcode/launchd/`:

### 6.1 `com.gaiaftcl.nats.plist`

Manages the vQbit NATS server. Key assertions (verified by MQ-C000):

- `<key>KeepAlive</key>` / `<true/>` — server auto-restarts on crash
- Label: `com.gaiaftcl.nats`
- Flags: `-js` (JetStream enabled), port `4222`
- Store path uses the placeholder `###NATS_STORE###` (replaced at install time)

### 6.2 `com.gaiaftcl.franklin.consciousness.plist`

Manages the `FranklinConsciousnessService` daemon. Key assertions (verified by MQ-C001):

- `<key>KeepAlive</key>` / `<true/>` — service auto-restarts on crash
- Label: `com.gaiaftcl.franklin.consciousness`
- Executable: `/Library/Application Support/GaiaFTCL/bin/FranklinConsciousnessService` (production install path)
- **Must not** reference `.build/release/FranklinConsciousnessService` (dev build path — banned in production plist)
- **Must not** contain `GAIAFTCL_ARANGO` (legacy database tag — banned, removed in v2 migration)

---

## 7. GRDB Substrate Database

`SubstrateDatabase` wraps a GRDB `DatabaseQueue`. Two environments:

| Environment | How to obtain | Use |
|-------------|--------------|-----|
| Production | `SubstrateDatabase.shared` | `awaken()` lifecycle |
| Test | `SubstrateDatabase.testQueue()` | In-memory, all migrations applied, isolated per test |

### 7.1 Migration Sequence

| Version | Name | Action |
|---------|------|--------|
| v1 | `v1_core` | Creates `franklin_review_cycles`, `franklin_memory_events`, `language_game_contracts`, **`causal_edges`** |
| v2 | `v2_remove_graph_tables` | **Drops `causal_edges`** |
| v3+ | (future) | Must not re-create `causal_edges` |

**`causal_edges` does not exist after migration.** `FranklinMemoryRepository.causalMagnitude(fromEventID:inMemoryFallback:)` catches any database error and returns the in-memory fallback value. It never throws on a missing table. This is the intended behaviour post-v2.

### 7.2 Key Tables

| Table | Purpose |
|-------|---------|
| `franklin_review_cycles` | One row per self-review cycle iteration |
| `franklin_memory_events` | Episodic memory events with C4 state snapshot |
| `language_game_contracts` | Domain contracts: name, `review_interval_seconds`, `algorithm_count`, quantum rows |

`LanguageGameContractSeeder.seedCanonicalContracts()` populates the contracts table with the canonical domain set. Called during `bootstrapProduction()` and in MQ-SR test setup.

---

## 8. GAMP5 Module Qualification — 35 Tests

All 35 tests pass in `cells/xcode/` via `swift test`. Run from `cells/xcode/`:

```bash
swift test
```

### 8.1 MQ-C Gates — Consciousness (11 tests in `GaiaFTCLMQTests`)

| Gate | Test | Assertion |
|------|------|-----------|
| MQ-C000 | `mqc000NatsLaunchAgentExists` | `com.gaiaftcl.nats.plist` exists with `KeepAlive`, `-js`, port 4222, `###NATS_STORE###` |
| MQ-C001 | `mqc001LaunchAgentExists` | `com.gaiaftcl.franklin.consciousness.plist` exists, KeepAlive=true, production path, no legacy tags |
| MQ-C002 | `mqc002PreflightGateCoverage` | `--preflight-once` subprocess emits JSON with MQ-C001..MQ-C010, `terminalState`, `signatureConfigured=`, `recentDecisionWithRationale=` |
| MQ-C003 | `mqc003WriteReceipt` | `QualReceipt` with 10 passing MQ-C gates has `overallStatus == .calorie`; writes to receipt directory |
| MQ-C004 | `mqc004SilenceSignatureValidation` | Unsigned command rejected; signed command accepted |
| MQ-C005 | `mqc005PostWakeValidationAllSovereign` | All-sovereign `PostWakeValidation` produces correct summary |
| MQ-C006 | `mqc006PostWakeValidationUnmoored` | Unmoored prim detected; summary includes unmoored count |
| MQ-C007 | `mqc007SessionIDPersistsAcrossRestore` | Memory store session ID survives restore |
| MQ-C008 | `mqc008CausalMagnitudeFallback` | `causalMagnitude` returns fallback when table absent (v2 migration) |
| MQ-C009 | `mqc009SignatureConfiguredReflectedInDetail` | Preflight gate detail contains `signatureConfigured=` |
| MQ-C010 | `mqc010RecentDecisionWithRationale` | Preflight gate detail contains `recentDecisionWithRationale=` |

### 8.2 MQ-L Gates — Learning (10 tests in `GaiaFTCLMQTests`)

Tests MQ-L001 through MQ-L010 verify the Franklin learning pipeline: receipt writing, memory event storage, C4 state serialization, language game contract seeding, and learning cycle integration.

### 8.3 MQ-SR Gates — Self-Review (5 tests in `FranklinSelfReviewMQTests`)

| Gate | Test | Assertion |
|------|------|-----------|
| MQ-SR-001 | `testReviewCycleInsertsRow` | At least one `franklin_review_cycles` row written per domain cycle |
| MQ-SR-002 | `testImprovementReceiptWritten` | `domain_improvement` receipt written when health improves |
| MQ-SR-003 | (timing) | Cycle timing within ±10% of `review_interval_seconds` |
| MQ-SR-004 | (degradation) | `domain_degradation` receipt written when health degrades |
| MQ-SR-005 | (sovereignty) | Sovereignty validation integrates into cycle outcome |

MQ-SR tests use `GAIAFTCL_MQ_SELF_REVIEW_SKIP_WIRE=1` and `GAIAFTCL_MQ_SELF_REVIEW_SKIP_TENSOR=1` env vars to bypass live NATS and Metal dependencies. A `StubSovereigntyProvider` injects controlled pass/fail sovereignty outcomes.

### 8.4 MQ-C4-FALLBACK (1 test in `FranklinSelfReviewMQTests`)

Verifies that `causalMagnitude` returns the in-memory fallback instead of throwing when `causal_edges` is absent (expected after v2 migration). This is not an error condition — it is the correct post-migration behaviour.

### 8.5 Wire Codec Tests (2 suites, 8 tests in `VQbitSubstrateTests`)

| Suite | Tests |
|-------|-------|
| `WireCodecTests` | `binaryLogHeadersRoundTrip`, `s4RoundTrip`, `c4RoundTrip`, `vqbitPointsRecordRoundTrip` |
| `VQbitQuantumProofTests` | `iqQM006CHSHViolationsZeroSix`, `vmaPRSelfTestClean`, `p0ClosureResidualDomainMean`, `p0TensorC4SourcedFromEngineNotS4Replica` |

`p0TensorC4SourcedFromEngineNotS4Replica` verifies that the C4 closure residual is computed from the manifold engine, not as a simple echo of S4 dimensions. This enforces the **C4 ≠ S4 echo** invariant using `Accelerate.vDSP_meanvD`.

### 8.6 `--preflight-once` Service Mode

`FranklinConsciousnessService` accepts a `--preflight-once` flag:

```bash
.build/arm64-apple-macosx/debug/FranklinConsciousnessService --preflight-once
```

When present:
1. A `Task.detached` block runs `runConsciousnessPreflight()` on the cooperative thread pool
2. The JSON result is printed to stdout
3. `exit(0)` is called
4. `RunLoop.main.run()` keeps the main thread alive so GRDB's internal serial DispatchQueues can execute

**`Task.detached` is load-bearing.** A plain `Task { }` inherits `@MainActor` isolation from `main.swift`, which can deadlock with GRDB's serial DispatchQueues when `RunLoop.main.run()` is also blocking the main thread. `Task.detached` breaks that isolation and routes the async work to the cooperative thread pool. Do not change this.

**`DispatchSemaphore.wait()` on the main thread is permanently banned** in this service. It blocks GRDB's internal queues and hangs the process.

---

## 9. Terminal States

Every Franklin gate and every C4 projection resolves to one of four terminal states:

| State | Hex | Meaning |
|-------|-----|---------|
| `CALORIE` | `0x01` | Value produced; system sovereign and operational |
| `CURE` | `0x02` | Deficit healed; system restored to sovereign operation |
| `REFUSED` | `0x03` | Request rejected by constitutional gate |
| `BLOCKED` | `0x04` | System cannot proceed; holding position, publishing heartbeat |

Franklin **never terminates on BLOCKED**. It publishes a BLOCKED heartbeat on `gaiaftcl.franklin.consciousness.state` until the blocking condition is resolved.

---

## 10. Critical Invariants

These are load-bearing constraints. Violating any of them breaks GAMP5 evidence traceability or live OQ reproducibility.

1. **C4 ≠ S4 echo.** `computeClosureResidual` uses `Accelerate.vDSP_meanvD` across tensor rows. The C4 dimensions are never computed by averaging raw S4 dimensions.

2. **τ self-sovereign.** `TauSyncMonitor` fetches block height from blockstream.info via URLSession. No Rust cell dependency. Mesh τ is additive. `vm.ready` does not gate on τ.

3. **53-byte C4 wire is frozen.** Do not change field layout, size, or NATS subject. OQ replay uses byte-exact deserialization.

4. **34-byte S4 wire is frozen.** Same constraint.

5. **W matrix SHA-256 is constant.** `18c538e91ac8e10ae636b69f29ae26ef3bce4034815061a0c5726316de78d5e7`

6. **`causal_edges` does not exist after v2 migration.** `causalMagnitude` always catches database errors and returns the fallback. Never query `causal_edges` directly.

7. **Two-commit seal, no amend.** Every GAMP5 evidence document requires two commits: one for content, one for signoff (`OQ-SIGNOFF:` prefix). Neither commit may be amended after the signoff.

8. **Mac cell only.** No Rust cell edits. No WebKit. No Intel/AMD/NVIDIA GPU paths.

9. **`@MainActor` isolation must not be inherited by async preflight work** in `FranklinConsciousnessService/main.swift`. Use `Task.detached`.

10. **Wire structs must be `@frozen`.** `C4ProjectionWire`, `S4DeltaWire`, `VQbitRecord` — layout must be stable across compilation units.

---

*Last updated: 2026-05-03. Reflects commit `4b980322` — 35/35 MQ tests passing.*
