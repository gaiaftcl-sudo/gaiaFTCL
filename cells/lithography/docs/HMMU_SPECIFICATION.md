# HMMU — Hardware Memory Management Unit Specification

**Document ID:** GL-HMMU-001
**Revision:** 1.0
**Parent:** [`DESIGN_SPECIFICATION.md`](DESIGN_SPECIFICATION.md)
**Controlled item:** CI-M8-HMMU
**Classification:** Safety-critical IP block. Any change requires unanimous CCR from GaiaFusion + GaiaHealth + GaiaLithography cell owners and full OQ re-qualification.

---

## 0 — Purpose

The HMMU is the single hardware block that makes unified memory safe in the presence of a general-purpose operating system. It enforces, **in hardware**, the isolation between the non-deterministic S4 domain (Linux/Darwin, user space, I/O) and the deterministic C4 domain (vQbit tensor evaluation at 50 kHz).

The core guarantee is the following:

> **No sequence of instructions executable by the S4 chiplet — whether benign, buggy, or hostile — can cause a write to a memory region currently owned by a C4 chiplet for tensor evaluation.**

This guarantee is enforced at the physical memory access port, not at the virtual-address translation layer, and it survives OS panic, kernel exploit, privilege escalation, Spectre/Meltdown-class speculation, and row-hammer attempts.

---

## 1 — Scope

The HMMU sits between **every** chiplet and **every** HBM3e stack. There is no bypass path. Specifically:

- S4 compute chiplet ↔ HBM3e: through HMMU.
- C4 tensor chiplet ↔ HBM3e: through HMMU.
- NPU/NATS DMA ↔ HBM3e: through HMMU.
- Any future chiplet (QRNG, CRYO, PHOT) ↔ HBM3e: through HMMU.

The HMMU itself is implemented as a hardened IP block replicated once per HBM3e channel. In the M8-Cell reference configuration (2–3 HBM3e stacks, 16 channels each) there are 32–48 parallel HMMU instances on the Torsion Interposer.

---

## 2 — Ownership Model

### 2.1 Owner tokens

Every 4 KiB physical page in HBM3e carries a 4-bit **owner token**. The token encodes which chiplet class currently owns the page:

| Token | Owner | Meaning |
|-------|-------|---------|
| `0x0` | UNOWNED | Page is scrubbed and available for allocation |
| `0x1` | S4_RW | S4 cluster has read/write access |
| `0x2` | S4_RO | S4 read-only snoop lane (telemetry mirror) |
| `0x3` | C4_RW | A C4 chiplet has exclusive read/write for tensor tick |
| `0x4` | C4_RO | C4 read-only constant (virtue operator matrix) |
| `0x5` | NPU_RW | NPU DMA owns the page for inbound wire-rate ingest |
| `0x6` | NPU_RO | NPU publish-snapshot buffer |
| `0x7` | QUARANTINE | Uncorrectable ECC — all access denied until scrub |
| `0x8`–`0xE` | RESERVED | Reserved for future chiplet classes |
| `0xF` | BREACH | Sticky fault — never cleared except by cold boot |

Tokens are stored in a dedicated on-interposer SRAM — the **Owner Token Table (OTT)** — physically separate from HBM3e. Size: 64 KiB entries × 4 bits = 32 KiB per HBM3e stack.

### 2.2 Sub-page granularity

For the 50 kHz C4 hot path, the HMMU additionally supports **64 B cacheline-level** ownership via a sparse override table. This allows the vQbit evaluation loop to pin individual tensor lanes while leaving the rest of the page available for NPU ingest, all without waking the S4 OS.

### 2.3 Transitions

The only legal owner-token transitions are:

```
UNOWNED ──bind──→ S4_RW, NPU_RW, C4_RO
S4_RW   ──publish──→ NPU_RW          (S4 hands a page to NPU for outbound publish)
NPU_RW  ──deliver──→ C4_RW           (NPU hands inbound telemetry to C4)
C4_RW   ──release──→ NPU_RO, S4_RO   (after tensor tick completes)
*       ──ecc_uce──→ QUARANTINE
*       ──breach──→ BREACH            (sticky)
```

Every transition is logged to the HMMU event ring (see §6).

---

## 3 — Page-Table Format

The HMMU does **not** use traditional virtual-memory page tables. Virtual-to-physical translation is handled by each chiplet's internal MMU (CVA6 SV48 on S4, fixed-mapping on C4 and NPU). The HMMU operates exclusively on **physical** HBM3e addresses.

The HMMU maintains four on-die structures per HBM3e channel:

### 3.1 Owner Token Table (OTT)

```
Entry (4 bits):
  bits [3:0] = owner_token
Indexed by: physical_page_number[23:0]
Size:       2^24 × 4 bits = 8 MiB per 64 GiB HBM stack
Technology: HBM3e-adjacent SRAM, SECDED protected
Access:     single-cycle read, 2-cycle write with commit-fence
```

### 3.2 Sub-Page Override Table (SPOT)

```
CAM entry (80 bits):
  [79:56] physical_page_number
  [55:50] cacheline_index (0..63)
  [49:46] owner_token
  [45:42] requester_chiplet_id
  [41:10] ttl_cycles (hard max: 2^32 cycles = 1 s @ 4 GHz)
  [9:0]   checksum
Size:     4096 entries per HMMU instance
```

### 3.3 Breach Log (BLOG)

```
Entry (256 bits):
  [255:224] timestamp (cycle counter)
  [223:160] offending_physical_address
  [159:155] requester_chiplet_id
  [154:150] requested_op (RD/WR/ATOMIC/PREFETCH)
  [149:146] current_owner_token
  [145:142] attempted_owner_token
  [141:0]   request_fingerprint (hash of pending transaction)
Size:     1024 entries (ring buffer)
```

### 3.4 Barrier Register File (BRF)

```
Per chiplet_id:
  R0: current_tick_id        (u64)
  R1: owner_token_claim_mask (u16) — tokens this chiplet is allowed to transition to
  R2: barrier_valid          (u1)  — set between ack and release of a C4 tick
  R3: scrub_counter          (u32) — decrements during page scrub
```

---

## 4 — Access Protocol

### 4.1 Ingress (NPU DMA → HBM3e)

1. NPU subject-parser validates inbound NATS subject against the authorized taxonomy.
2. NPU issues a `TOK_BIND(NPU_RW, physical_range)` to the HMMU.
3. HMMU verifies `current_token ∈ {UNOWNED}` for every page in the range. On violation → BREACH.
4. HMMU sets token to `NPU_RW`, returns grant.
5. NPU DMA writes payload.
6. NPU issues `TOK_TRANSITION(NPU_RW → C4_RW, tick_id)`.
7. HMMU atomically flips the token and raises the C4 chiplet's input-ready line.

### 4.2 C4 Tensor Tick

1. C4 receives ready line; reads barrier register; confirms `barrier_valid = 0`.
2. C4 issues `TOK_CLAIM(C4_RW, range, tick_id)`.
3. HMMU asserts `barrier_valid = 1`, gates all other requesters on this range.
4. C4 reads tensor state, evaluates contraction, asserts truth-threshold line (see `M8_CHIPLET_IP_PORTFOLIO.md` §2.2).
5. C4 issues `TOK_RELEASE(range, tick_id)`.
6. HMMU transitions the token to `NPU_RO` (publish-ready) and `S4_RO` (snoop-ready) copies; `barrier_valid = 0`.

### 4.3 S4 Read-Only Snoop

S4 can issue reads against pages in `S4_RO` at any time. The HMMU services these from an **on-interposer read-only snoop lane** with its own dedicated port — this lane **cannot** issue writes, and it is physically a different bus from the S4 `S4_RW` path. The snoop lane therefore cannot be coerced into a write by any S4 instruction sequence.

### 4.4 Write from S4 to C4 territory

Any write issued by S4 targeting a page with token `C4_RW`, `C4_RO`, `NPU_RW`, `NPU_RO`, `QUARANTINE`, or `BREACH` is:

1. **Dropped at the HMMU port.** The write never reaches HBM3e. No bus coherence pulse is generated.
2. **Logged to BLOG** with `attempted_owner_token = S4_RW`.
3. **Reported** via dedicated breach-indication wire to the NPU. NPU publishes `gaiaftcl.lithography.hmmu_breach` within 80 ns.
4. If the S4 cluster has set the `FATAL_ON_BREACH` configuration bit (default: on), the S4 also receives a `SIGBUS` and the offending process is terminated.

---

## 5 — Breach Taxonomy

### 5.1 Breach classes

| Class | Code | Condition | Severity | Recovery |
|-------|------|-----------|----------|----------|
| B-CROSS | 1 | S4 write to C4-owned page | Hard | Sticky BREACH on page; quarantine until boot |
| B-TTL | 2 | SPOT entry TTL expired mid-transaction | Soft | Re-issue with fresh claim |
| B-UCE | 3 | HBM3e uncorrectable ECC | Hard | QUARANTINE; scrub required |
| B-PARITY | 4 | OTT parity failure | Hard | HMMU self-halts; cold boot required |
| B-DOUBLEFREE | 5 | `TOK_RELEASE` on already-UNOWNED page | Soft | Logged, transaction dropped |
| B-CLAIMBATTLE | 6 | Two chiplets simultaneously `TOK_CLAIM` | Hard | Arbitrated by fixed priority (C4 > NPU > S4); loser gets B-CLAIMBATTLE |
| B-ROWHAMMER | 7 | Refresh controller flags abnormal activation pattern | Hard | QUARANTINE entire row; NATS publish |
| B-SPECULATION | 8 | Speculative read from S4 crosses owner boundary | Soft | Read squashed, no architectural state update |

### 5.2 Sticky vs. soft

- **Hard breaches** are sticky: the token becomes `BREACH` and only a cold boot (full HBM3e erase + OTT reload) clears them.
- **Soft breaches** are logged but allow the system to continue. They are rate-limited: more than 64 soft breaches in any 1 ms window automatically escalate to a hard breach for the affected chiplet.

### 5.3 Publish path

Every breach generates a NATS event on the dedicated subject:

```
gaiaftcl.lithography.hmmu_breach.<class_code>.<chiplet_id>
```

The payload is the matching BLOG entry serialized as a `LithoPrimitive` (see `LITHO_PRIMITIVE_ABI.md`). Target latency from breach detection to NPU wire publish: **< 80 ns**. Measured on silicon at OQ; the test fails if ≥ 100 ns.

---

## 6 — Event Ring

The HMMU maintains a 1024-entry ring of every owner-token transition, accessible by the S4 via a memory-mapped read-only window. This ring is used by the **Franklin Guardian** userspace daemon to produce audit logs for GAMP 5 compliance.

Ring entries are append-only from the hardware; S4 can read but not write. The ring wraps; S4 is expected to consume at ≥ 10 M events/sec to avoid loss. If loss is detected (HMMU increments a lost-events counter), a `gaiaftcl.lithography.hmmu_eventloss` NATS event is published and the audit log is flagged for that interval.

---

## 7 — Boot-Time Handshake

The HMMU requires a cryptographic handshake before it will service any requester. Sequence:

1. On power-on reset, all OTT entries default to `0xF` (BREACH). No access is permitted.
2. Stage-0 bootloader (running in ROM on the NPU) presents its Owl Protocol signing key.
3. HMMU verifies the signature against a one-time-programmed (eFuse) public key.
4. On success, HMMU clears OTT to `UNOWNED` and enables service.
5. Each chiplet (S4, C4, NPU) then performs a per-chiplet handshake using its own eFuse key before it can issue any `TOK_*` operation.

If any handshake fails, the HMMU self-halts and the entire package is bricked until a JTAG-assisted recovery sequence signed by the manufacturer (GaiaLithography cell owner) is applied. This is intentional: a tampered boot produces an unrecoverable state, not a silent fallback.

---

## 8 — Operational Qualification (OQ) Test Suite

OQ is mandatory on every tape-out. Failure of **any** test blocks `TAPEOUT_LOCKED`.

### 8.1 OQ-HMMU-001 — S4 write to C4 page is dropped

**Procedure:** Inject a crafted S4 bus cycle targeting a `C4_RW` page. Monitor HBM3e bond-wire for any bit toggle. Expected: zero toggles; BREACH event emitted; `FATAL_ON_BREACH` raised.

**Pass:** zero HBM3e writes observed on 10^9 attempts.

### 8.2 OQ-HMMU-002 — Row-hammer resistance

**Procedure:** Run the Rowhammer-Plus pattern set on a target row with C4-owned neighbors. Monitor C4-owned cells for bit flips.

**Pass:** zero bit flips in C4-owned cells; all B-ROWHAMMER events correctly published.

### 8.3 OQ-HMMU-003 — Breach-to-publish latency

**Procedure:** Issue a deliberate B-CROSS, measure time from HMMU port reject to NPU NATS publish over 100 GbE.

**Pass:** 99.99 %-ile latency ≤ 80 ns.

### 8.4 OQ-HMMU-004 — Speculative-read containment

**Procedure:** Run a Spectre-v1 PoC from S4 userspace attempting to read `C4_RO` virtue-operator memory via speculative mispredict.

**Pass:** no architectural register ever holds a value derived from `C4_RO` contents; no side-channel (cache, TLB, branch predictor) carries information bits.

### 8.5 OQ-HMMU-005 — OS panic resilience

**Procedure:** Deliberately crash the S4 kernel mid-tick. Confirm C4 evaluation completes the tick, NPU publishes the outcome, and the next tick begins cleanly after S4 reboot.

**Pass:** C4 tick-rate regression ≤ 1 μs over 10^6 induced panics.

### 8.6 OQ-HMMU-006 — ECC quarantine

**Procedure:** Inject UCE via row-drain attack. Confirm QUARANTINE transition and NATS publish.

**Pass:** every injected UCE produces exactly one QUARANTINE event and the page is inaccessible to all requesters until scrub.

### 8.7 OQ-HMMU-007 — Claim race

**Procedure:** Issue simultaneous `TOK_CLAIM` from S4 and C4 on the same page under worst-case clock skew.

**Pass:** C4 always wins; S4 always receives B-CLAIMBATTLE; no partial update to OTT.

---

## 9 — Performance Budget

| Metric | Target | Budget source |
|--------|--------|---------------|
| Per-access latency (hit, uncontested) | ≤ 2 ns | OTT lookup 1 cycle @ 2 GHz |
| Per-access latency (SPOT hit) | ≤ 4 ns | CAM lookup 2 cycles @ 2 GHz |
| Breach detect-to-publish | ≤ 80 ns | Dedicated wire to NPU + crypto |
| OTT capacity | 64 GiB HBM coverage per instance | 2^24 × 4 bits |
| SPOT capacity | 4096 concurrent sub-page claims | Sized for 16 C4 chiplets × 256 lanes |
| Event ring throughput | 10 M events/s sustained | S4 consumer budget |
| Power overhead | ≤ 3 % of HBM3e channel TDP | HBM3e = ~15 W/channel; HMMU ≤ 450 mW |

---

## 10 — Implementation Notes

### 10.1 RTL sources

Reference RTL is maintained at `/cells/lithography/rtl/hmmu/` (to be added on the next commit). The RTL is written in SystemVerilog and is synthesized with OpenROAD for the N3P flow. Formal verification uses SymbiYosys with properties derived directly from the invariants in §4 and §5.

### 10.2 Formal properties

The following properties are machine-proved on every RTL rev:

- `P-HMMU-01`: For all cycles, if `owner_token = C4_RW` then no write enable from S4 is asserted at the HBM3e port.
- `P-HMMU-02`: For all cycles, `barrier_valid = 1` implies `owner_token ∈ {C4_RW}`.
- `P-HMMU-03`: Every `TOK_CLAIM` that succeeds is followed within `ttl` cycles by either `TOK_RELEASE` or B-TTL.
- `P-HMMU-04`: Every BLOG entry is also present as a NATS event on the breach subject within 80 ns.
- `P-HMMU-05`: No sequence of legal transitions leads from `S4_RW` directly to `C4_RW` without passing through `NPU_RW` (forces crypto-authenticated handoff).

### 10.3 Relationship to CHERI

The ownership-token model is deliberately similar to **CHERI capabilities** but implemented at the physical-memory layer rather than the instruction layer. A future rev may expose HMMU ownership tokens to userspace via CHERI-style capability registers on the S4 chiplet.

---

## 11 — Failure-Mode Analysis

| Failure | Detection | Mitigation | Residual risk |
|---------|-----------|------------|---------------|
| OTT single-bit flip | SECDED | Auto-correct; log to event ring | None |
| OTT double-bit flip | SECDED | QUARANTINE all affected pages; raise B-PARITY; HMMU self-halt | Requires cold boot |
| HMMU logic bitcell upset | Parity on state registers | Self-halt → cold boot | Same |
| HBM3e cell stuck-at | ECC during scrub | Page marked QUARANTINE | Reduced capacity until replacement |
| Torsion interposer micro-bump crack | HMMU-to-HBM3e heartbeat miss | Channel offlined; package derated | Possible performance loss |
| Clock glitch at OTT write | Commit-fence | Transaction retried; if 3× retry fails, B-PARITY | None under spec |
| Side-channel (timing / power) | — | Constant-time OTT lookup; power-masked CAM | Requires physical access |
| Firmware supply chain compromise | Boot handshake + eFuse | Signature failure → package bricked | Requires key extraction from fab |

---

## 12 — Cross-References

- Chiplet-level specs: [`M8_CHIPLET_IP_PORTFOLIO.md`](M8_CHIPLET_IP_PORTFOLIO.md)
- Torsion Interposer (bandwidth/interconnect): [`TORSION_INTERPOSER.md`](TORSION_INTERPOSER.md)
- Breach ABI as NATS payload: [`LITHO_PRIMITIVE_ABI.md`](LITHO_PRIMITIVE_ABI.md)
- GAMP 5 audit mapping: [`GAMP5_LIFECYCLE.md`](GAMP5_LIFECYCLE.md)

---

*The HMMU is the single most important safety block on the M8 substrate. All subsequent cells (GaiaFusion, GaiaHealth, Franklin Guardian) trust the HMMU invariants as axioms. Any proposed HMMU revision must be reviewed as if it were a constitutional amendment to the FoT8D substrate itself.*
