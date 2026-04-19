# M8 Instruction Set Architecture (ISA) Specification

**Document ID:** GL-ISA-001
**Revision:** 1.0
**Parent:** [`DESIGN_SPECIFICATION.md`](DESIGN_SPECIFICATION.md)
**Controlled item:** CI-M8-ISA
**Classification:** Architectural invariant. ISA opcode changes require a mask-change CCR.

---

## 0 — Purpose

The M8 ISA is a superset of **RISC-V RV64GCV** (base integer, multiplication/division, atomics, compressed, single- and double-precision float, and Vector 1.0) extended with the proprietary **vQbit extension (Xvqbit)**. Xvqbit exposes the C4 tensor evaluation engine as a first-class instruction class, accessible from user space (with HMMU gating) and from the OS kernel.

This document specifies only the Xvqbit delta. For the base ISA see the RISC-V Privileged and Unprivileged specifications.

---

## 1 — Design Principles

1. **Xvqbit does not introduce new general-purpose state.** All Xvqbit instructions operate on state that physically lives inside the C4 chiplet or on HBM3e pages owned by the C4 chiplet.
2. **No speculative Xvqbit issue.** The S4 pipeline may **request** an Xvqbit operation, but the operation does not begin until the HMMU confirms page ownership. A speculative branch that would issue Xvqbit is squashed at the reservation station.
3. **Truth is hardware.** The 0.85 threshold is never a configurable operand. It is a mask-locked constant inside the C4 comparator. The ISA therefore cannot express an Xvqbit operation that uses a different threshold.
4. **Every Xvqbit op is a NATS event.** Each Xvqbit completion generates a NATS payload via the NPU's direct wire. This is an architectural guarantee, not a performance hint.
5. **Backwards compatibility with RV64GCV is absolute.** A stock Linux kernel compiled for RV64GCV boots and runs on the S4 chiplet without knowing Xvqbit exists. Xvqbit is discovered via `misa` + `mvqbit` CSR probing.

---

## 2 — Opcode Map

Xvqbit uses the RISC-V **custom-2** opcode space (`0x5B`). The primary function field is bits [14:12] (`funct3`) and the extended function is bits [31:25] (`funct7`).

| funct7 | funct3 | Mnemonic | Name | Semantics |
|--------|--------|----------|------|-----------|
| `0x00` | `0b000` | `vq.init` | Initialize vQbit state | Allocate χ-bank region; bind NATS subject |
| `0x00` | `0b001` | `vq.bind` | Bind MCP tool | Attach a `vchip_*` tool handle to a vQbit context |
| `0x01` | `0b000` | `vq.run` | Run program | Execute a canned tensor program from the virtue bank |
| `0x01` | `0b001` | `vq.step` | Single tensor tick | One 50 kHz tick; return collapse event if truth ≥ 0.85 |
| `0x02` | `0b000` | `vq.collapse` | Force collapse | Read out current max-amplitude basis state |
| `0x02` | `0b001` | `vq.collapseif` | Conditional collapse | Collapse only if truth ≥ 0.85 |
| `0x03` | `0b000` | `vq.bell` | Bell pair | Prepare Bell-state test pattern (debug / BIST) |
| `0x03` | `0b001` | `vq.grover` | Grover oracle | Run a Grover amplitude-amplification pass |
| `0x04` | `0b000` | `vq.coherence` | Read coherence | Return current vQbit entropy and truth scalars |
| `0x04` | `0b001` | `vq.status` | Read status | Full state dump into a LithoPrimitive in HBM3e |
| `0x05` | `0b000` | `vq.virtload` | Load virtue operator | Page in a Justice/Honesty/Temperance/Prudence matrix from C4_RO pool |
| `0x05` | `0b001` | `vq.virtstore` | Store virtue operator | Emit a virtue operator update via NPU (authenticated) |
| `0x06` | `0b000` | `vq.bondset` | Set bond dimension | Configure χ (≤ 1024) for this context |
| `0x06` | `0b001` | `vq.bondget` | Read bond dimension | Return current χ |
| `0x07` | `0b000` | `vq.barrier` | Tensor barrier | Fence all in-flight Xvqbit ops for the calling hart |
| `0x7F` | `0b111` | `vq.fault` | Explicit trap | Generate an HMMU breach for test |

(See §5 for reserved opcodes planned for rev 2.)

---

## 3 — Register Mapping

Xvqbit uses two register classes:

### 3.1 General integer registers (`x0`–`x31`)

Standard RISC-V. Used for operand addresses, context handles, result counts.

### 3.2 vQbit context handles

Xvqbit introduces a single new CSR: **`mvqbit`** (address `0x7A0`), a 64-bit handle. The handle encodes:

- bits [63:48]: cell identity (e.g. `fusion`, `health`, `litho`, `guardian`)
- bits [47:32]: χ (bond dimension)
- bits [31:16]: C4 chiplet ID
- bits [15:0]:  page-table entry offset into the χ-bank

There is no "vQbit register file" visible to the programmer. All state lives on the C4 chiplet and is addressed only via handles.

### 3.3 Context-bank zeroing

On hart entry to user mode, the OS must execute `csrw mvqbit, x0` to zero any stale handle. Failure to do so produces an HMMU breach on the first Xvqbit issue — this is intentional and enforces hygiene.

---

## 4 — Instruction Semantics

### 4.1 `vq.init rd, rs1, rs2`

Allocate a vQbit context.

```
rs1 = virtue-bank selector (0=Justice, 1=Honesty, 2=Temperance, 3=Prudence, -1=all)
rs2 = initial bond dimension χ (must be ≤ 1024)
rd  = returned context handle (or 0 on failure)
```

Effects: NPU issues `TOK_BIND(C4_RO, virtue_range)` and `TOK_BIND(C4_RW, χ_bank_range)` via HMMU. If either bind fails, `rd = 0` and a NATS event is published.

### 4.2 `vq.bind rs1, rs2`

Attach an MCP tool handle to the current `mvqbit` context.

```
rs1 = tool handle (one of: vchip_init, vchip_run_program, vchip_collapse,
                           vchip_bell_state, vchip_grover, vchip_coherence, vchip_status)
rs2 = option word (flags: AUDIT, PUBLISH_ON_COLLAPSE, BLOCK_ON_BARRIER)
```

### 4.3 `vq.run rs1, rs2`

Execute a preloaded program.

```
rs1 = program id (range 0..65535; id 0 is reserved for BIST)
rs2 = tick budget (max cycles before forced barrier)
```

Execution proceeds asynchronously on the C4 chiplet. Completion is signaled via the `vq.barrier` instruction or via a NATS event.

### 4.4 `vq.step rd`

Execute exactly one 50 kHz tick.

```
rd = 0 if no collapse; 1 if collapse-eligible (truth ≥ 0.85); -1 on fault
```

This is the primary primitive used by GaiaFusion's tokamak-control loop and GaiaHealth's per-frame MD gate.

### 4.5 `vq.collapse rd`, `vq.collapseif rd`

```
rd = basis-state index of max-amplitude collapsed state, OR
     -1 if collapseif was used and truth < 0.85
```

### 4.6 `vq.coherence rd`

```
rd[31:0]  = bfloat16 truth × 2^16 (fixed-point)
rd[63:32] = bfloat16 entropy × 2^16
```

### 4.7 `vq.status rs1`

```
rs1 = physical address of a 128-byte-aligned LithoPrimitive buffer
```

C4 emits a full status snapshot to the addressed buffer. See [`LITHO_PRIMITIVE_ABI.md`](LITHO_PRIMITIVE_ABI.md).

### 4.8 `vq.barrier`

Fence all in-flight Xvqbit ops for this hart. Blocking. Completes when the C4 chiplet has drained the per-hart issue queue and all outstanding NATS events have been acknowledged by JetStream.

---

## 5 — Reserved Opcodes

Rev 2 (planned):

| funct7 | funct3 | Mnemonic | Purpose |
|--------|--------|----------|---------|
| `0x08` | — | `vq.entangle` | Produce a 2-vQbit entangled handle |
| `0x09` | — | `vq.measure_partial` | Partial measurement on a subsystem |
| `0x0A` | — | `vq.decoherence_rate` | Read current decoherence slope |
| `0x0B` | — | `vq.photonic_tx` | Photonic chiplet cross-rack emit |

---

## 6 — Exceptions & Traps

| Code | Name | Cause |
|------|------|-------|
| 0x18 | `vq-no-context` | Xvqbit op issued with `mvqbit = 0` |
| 0x19 | `vq-bond-exceeded` | Requested χ > 1024 |
| 0x1A | `vq-no-c4` | C4 chiplet unreachable or faulted |
| 0x1B | `vq-hmmu-denied` | HMMU denied the required token transition |
| 0x1C | `vq-nats-drop` | NPU could not publish the associated event |
| 0x1D | `vq-truth-misalign` | Operand alignment for `vq.status` not 128 B |
| 0x1E | `vq-context-revoked` | HMMU revoked the context mid-op (quarantine) |
| 0x1F | `vq-program-invalid` | Program id not loaded |

All Xvqbit exceptions are precise (the exception PC is the Xvqbit instruction) and are delivered through the standard RISC-V trap vector. The OS may route them to a signal handler; the default action is to terminate the offending process.

---

## 7 — Encoding

Xvqbit uses the standard R-type encoding with the custom-2 opcode:

```
 31    25 24 20 19 15 14 12 11  7 6      0
[funct7  ][rs2 ][rs1 ][f3 ][rd ][0x5B   ]
```

Example, `vq.step x5`:

```
funct7 = 0x01, funct3 = 0b001, rs2 = x0, rs1 = x0, rd = x5, opcode = 0x5B
Binary:   0000001 00000 00000 001 00101 1011011
Hex:      0x020012DB
```

---

## 8 — ABI and Calling Convention

The standard RISC-V LP64D ABI is extended as follows:

- `mvqbit` is **caller-saved** (the callee may clobber it).
- A function that issues Xvqbit ops must save `mvqbit` before calling any non-Xvqbit-aware routine.
- Xvqbit ops never modify integer argument registers (`a0`–`a7`) except as explicit destination operands.

A compiler intrinsic library `<xvqbit.h>` exposes inline wrappers:

```c
// Allocate a vQbit context. Returns 0 on failure.
uint64_t vq_init(int virtue_selector, int bond_chi);

// Single tick. Returns 0=no collapse, 1=eligible, -1=fault.
int32_t vq_step(void);

// Snapshot. Writes a LithoPrimitive to `buf`.
void vq_status(void *buf);

// Fence.
void vq_barrier(void);
```

The intrinsic library is distributed with the GaiaOS toolchain and is mirrored to the `cells/fusion/` and `cells/health/` lib paths.

---

## 9 — Discovery

Software detects Xvqbit presence by reading the `misa` CSR and checking bit 21 (custom extension bit "V"-plus). A secondary CSR `mvqbit_caps` (address `0x7A1`) enumerates supported opcodes as a bitmask — this allows forward compatibility with rev 2 opcodes.

Linux kernel support is implemented via a `cpu_feature` entry at `arch/riscv/kernel/cpufeature.c`; user-space code reads `/proc/cpuinfo` or `getauxval(AT_HWCAP2)` bit `XVQBIT`.

---

## 10 — Relationship to Existing GAIA-1 Virtual Chip Software

The existing `gaia_chip_server` Rust service (the GAIA-1 Virtual Chip) exposes the MCP tools `vchip_init`, `vchip_run_program`, `vchip_collapse`, `vchip_bell_state`, `vchip_grover`, `vchip_coherence`, and `vchip_status`. Each MCP tool corresponds **1:1** to an Xvqbit opcode as follows:

| MCP tool | Xvqbit opcode |
|----------|---------------|
| `vchip_init` | `vq.init` + `vq.bondset` |
| `vchip_run_program` | `vq.run` |
| `vchip_collapse` | `vq.collapse` |
| `vchip_bell_state` | `vq.bell` |
| `vchip_grover` | `vq.grover` |
| `vchip_coherence` | `vq.coherence` |
| `vchip_status` | `vq.status` |

This correspondence is intentional: the software simulator was designed as the ISA pre-silicon. The silicon implementation preserves the exact semantics (with tightened timing) so that every MCP tool user sees a bit-compatible result on either the simulator or real M8 hardware.

---

## 11 — Cross-References

- Primitive data structure: [`LITHO_PRIMITIVE_ABI.md`](LITHO_PRIMITIVE_ABI.md)
- C4 chiplet implementation: [`M8_CHIPLET_IP_PORTFOLIO.md`](M8_CHIPLET_IP_PORTFOLIO.md) §2
- HMMU enforcement: [`HMMU_SPECIFICATION.md`](HMMU_SPECIFICATION.md) §4
- Virtue operators (mathematical definition): `/wiki/vQbit-Theory.md`
- Existing MCP ABI: `/cells/fusion/docs/vQbitPrimitive-ABI.md`

---

*The Xvqbit extension is the hardware manifestation of the vQbit theory. No ISA change is permitted that would break the ABI-compatibility chain from MCP tool → simulator → silicon.*
