# GaiaFTCL Sovereign Cell Architecture

Canonical definitions for local Mac processes vs external mesh. **Cell** refers only to **S4** and **C4** on the workstation; external VMs are **mesh nodes**, not cells.

## Canonical Definitions

### S4 Cell — Franklin

- **Process:** `FranklinConsciousness` / `FranklinConsciousnessService`
- **NATS:** `NATSConfiguration.franklinNATSURL` (env `GAIAFTCL_FRANKLIN_NATS_URL`, default `nats://127.0.0.1:4223`)
- **Subjects owned:** `gaiaftcl.franklin.*`
- **Role:** Authors USD-stage prims, publishes wake catalog, self-review and calibration. **Does not** run **checkConstitutional** or own the **M⁸** tensor.
- **Peers:** Own NATS broker + **client** to **C4** NATS (`vqbitNATSURL`) for **S⁴** publish / **C⁴** subscribe.

### C4 Cell — vQbit VM

- **Process:** `VQbitVM`
- **NATS:** `NATSConfiguration.vqbitNATSURL` (env `GAIAFTCL_VQBIT_NATS_URL`, else legacy `GAIAFTCL_NATS_URL`, default `nats://127.0.0.1:4222`)
- **Subjects owned:** `gaiaftcl.substrate.*`
- **Role:** Receives **S⁴** deltas, runs **checkConstitutional**, emits **C⁴** projections and **VQbitRecords**, terminal states. **The measurement instrument.** **Only** local process that routes to external mesh NATS cluster peers.
- **Peers:** Own broker for substrate wire + mesh gateways (`GuestNetworkDefaults.natsMeshEndpoints`).

### Mesh Node — External Helsinki / Nuremberg VMs

- **Instances:** Hetzner Helsinki + Netcup Nuremberg (see `GuestNetworkDefaults.natsMeshEndpoints`)
- **Stack:** ArangoDB, NATS JetStream, Rust runners, ARM64 where noted
- **Role:** Distributed workloads and knowledge graph; connect as **peers to C4 NATS / mesh relay**, **not** to Franklin’s S4 NATS.

## Message Flow

```
Franklin  ──(vqbitNATSURL)──►  gaiaftcl.substrate.s4.delta   ──►  vQbit VM
vQbit VM  ──(vqbitNATSURL)──►  gaiaftcl.substrate.c4.projection  ──►  Franklin (subscribe)
vQbit VM  ──(mesh NATS)────►  mesh nodes
Franklin  ──(franklinNATSURL)► gaiaftcl.franklin.*  (monologue, consciousness, …)
```

## What Changed From “Cell” (Generic)

Previously “cell” mixed Mac processes and mesh VMs. Correct usage:

| Term | Meaning |
|------|---------|
| **S4 Cell** | Franklin (local Mac) |
| **C4 Cell** | vQbit VM (local Mac), mesh gateway |
| **Mesh Node** | External Helsinki / Nuremberg VM |
| **Cell** | **Only** S4 or C4 locally — never a mesh node |

## NATS URL Registry

| Constant | Source |
|----------|--------|
| `NATSConfiguration.vqbitNATSURL` | `GAIAFTCL_VQBIT_NATS_URL` → `GAIAFTCL_NATS_URL` → `nats://127.0.0.1:4222` |
| `NATSConfiguration.franklinNATSURL` | `GAIAFTCL_FRANKLIN_NATS_URL` → `nats://127.0.0.1:4223` |

**Single-broker development:** point **both** env vars at the same URL (e.g. `nats://127.0.0.1:4222`) so Franklin and vQbit share one `nats-server`.

**OQ tooling (`QuantumOQInjector`):** connects to **`vqbitNATSURL` only** for **S⁴**/**C⁴** wire. Optional second connection to **`franklinNATSURL`** only when `--wait-franklin-cycle` needs **`gaiaftcl.franklin.monologue`**.

## IQ-ARCH Status (source of truth)

| ID | Statement | Location |
|----|-----------|----------|
| IQ-ARCH-001 | Two named URL APIs: `vqbitNATSURL`, `franklinNATSURL` | `GaiaFTCLCore/NATSConfiguration.swift` |
| IQ-ARCH-002 | Franklin publishes **S⁴** on **substrate** client (`publishWire` → vQbit broker) | `FranklinConsciousness/NATSBridge.swift` |
| IQ-ARCH-003 | **C⁴** published by vQbit on substrate NATS; Franklin subscribes on substrate client | `VQbitVM/VQbitVMDeltaPipeline.swift`, `NATSBridge` |
| IQ-ARCH-004 | `gaiaftcl.franklin.*` uses Franklin broker | `FranklinInnerMonologue.swift`, `NATSBridge` |
