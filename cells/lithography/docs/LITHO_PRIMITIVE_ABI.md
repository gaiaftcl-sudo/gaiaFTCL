# LithoPrimitive ABI Specification

**Document ID:** GL-ABI-001
**Revision:** 1.0
**Parent:** [`DESIGN_SPECIFICATION.md`](DESIGN_SPECIFICATION.md)
**Controlled item:** CI-M8-ABI-LITHO
**Classification:** Binary contract. Any layout change is a mask-change CCR and requires parallel publish of a new NATS subject version.

---

## 0 — Purpose

The **LithoPrimitive** is the 128-byte C-representation struct that serializes every silicon-substrate event (HMMU breach, fab lot step, tape-out record, mask reject, etc.) into a single fixed-size payload. It is the silicon-cell analog of `vQbitPrimitive` (76 B, GaiaFusion/GaiaHealth) and `BioligitPrimitive` (96 B, GaiaHealth).

Every NATS message published on the `gaiaftcl.lithography.*` subject tree carries exactly one LithoPrimitive in its payload. No dynamic allocation, no length prefix, no variable fields — the size is fixed at 128 bytes so that the NPU hardware subject parser can DMA it directly to an HMMU-allocated page.

---

## 1 — Struct Layout

```c
// lithoprimitive.h — Rev 1.0
// (c) 2026 Richard Gillespie — USPTO 19/460,960 and 19/096,071

#pragma pack(push, 1)

typedef struct LithoPrimitive {
    // --- Header (16 B) ---
    uint8_t   magic[4];       // @0   "LTHO" (0x4C 0x54 0x48 0x4F)
    uint8_t   abi_major;      // @4   1
    uint8_t   abi_minor;      // @5   0
    uint8_t   event_class;    // @6   see §2
    uint8_t   event_code;     // @7   class-specific sub-code
    uint32_t  prim_id;        // @8   monotonic per-chiplet event id
    uint32_t  tick_id;        // @12  C4 tick counter when emitted

    // --- Provenance (16 B) ---
    uint16_t  cell_id;        // @16  0=Lithography, 1=Fusion, 2=Health, 3=Guardian
    uint16_t  chiplet_id;     // @18  low 4 bits = chiplet class, high 12 bits = instance
    uint32_t  hart_id;        // @20  issuing RISC-V hart (0xFFFFFFFF if hardware-origin)
    uint64_t  timestamp_ns;   // @24  nanoseconds since cell boot

    // --- Event payload (72 B) ---
    union {
        // HMMU breach (event_class = 0x01)
        struct {
            uint64_t phys_addr;     // @32
            uint8_t  current_tok;   // @40
            uint8_t  attempted_tok; // @41
            uint8_t  breach_class;  // @42 (B-CROSS, B-TTL, ...)
            uint8_t  reserved;      // @43
            uint32_t requester_id;  // @44
            uint8_t  fingerprint[56]; // @48..103
        } hmmu;

        // Fab-process step (event_class = 0x02)
        struct {
            uint8_t  pdk_hash[32];  // @32..63
            uint32_t lot_id;        // @64
            uint32_t wafer_id;      // @68
            uint16_t step_id;       // @72
            uint16_t yield_bp;      // @74  basis points
            uint32_t drc_errors;    // @76
            uint32_t lvs_errors;    // @80
            uint64_t reserved;      // @84..91 (deliberately spans header-adjacent pad)
            uint8_t  reserved2[12]; // @92..103
        } fab;

        // Tape-out lock (event_class = 0x03)
        struct {
            uint8_t  gdsii_sha256[32]; // @32..63
            uint64_t ccr_signers;      // @64  bitmask of approving cell owners
            uint64_t lock_timestamp;   // @72
            uint8_t  signature[24];    // @80..103  secp256k1 compressed
        } tapeout;

        // Tensor state snapshot (event_class = 0x04)
        struct {
            uint16_t chi;           // @32
            uint16_t virtue_mask;   // @34  which virtue operators active
            uint32_t reserved;      // @36
            float    truth;         // @40  bfloat32
            float    entropy;       // @44
            uint8_t  state_digest[56]; // @48..103  truncated SHA of χ-bank
        } tensor;

        // Thermal / telemetry (event_class = 0x05)
        struct {
            int16_t  temp_c_x10[8]; // @32..47  per-chiplet junction, fixed-point ×10
            uint32_t power_mw[8];   // @48..79  per-chiplet power in milliwatts
            uint8_t  reserved[24];  // @80..103
        } thermal;

        // Generic / reserved
        uint8_t raw[72];            // @32..103
    } payload;

    // --- Integrity footer (24 B) ---
    uint8_t  publisher_pubkey_fp[16]; // @104..119  Owl Protocol key fingerprint
    uint32_t crc32c;                  // @120      CRC-32C over bytes 0..119
    uint32_t schema_hash;             // @124      FNV-1a of the struct layout (compile-time)
} LithoPrimitive;

#pragma pack(pop)

_Static_assert(sizeof(LithoPrimitive) == 128, "LithoPrimitive must be exactly 128 bytes");
```

---

## 2 — Event Classes

| `event_class` | Name | Subject prefix |
|---------------|------|----------------|
| `0x00` | RESERVED_NULL | — (invalid) |
| `0x01` | HMMU_BREACH | `gaiaftcl.lithography.hmmu_breach.*` |
| `0x02` | FAB_STEP | `gaiaftcl.lithography.fab.*` |
| `0x03` | TAPEOUT | `gaiaftcl.lithography.tapeout.*` |
| `0x04` | TENSOR_SNAPSHOT | `gaiaftcl.lithography.tensor.*` |
| `0x05` | THERMAL | `gaiaftcl.lithography.thermal.*` |
| `0x06` | POWER_EVENT | `gaiaftcl.lithography.power.*` |
| `0x07` | BOOT_HANDSHAKE | `gaiaftcl.lithography.boot.*` |
| `0x08` | MASK_REJECTED | `gaiaftcl.lithography.mask_rejected.*` |
| `0x09` | OQ_RESULT | `gaiaftcl.lithography.oq.*` |
| `0x0A` | PQ_RESULT | `gaiaftcl.lithography.pq.*` |
| `0x0B` | SHIP | `gaiaftcl.lithography.ship.*` |
| `0x0C`–`0xEF` | RESERVED_FUTURE | — |
| `0xF0`–`0xFE` | VENDOR_EXTENSION | `gaiaftcl.lithography.vendor.*` |
| `0xFF` | TEST_FIXTURE | `gaiaftcl.lithography.test.*` |

Each class defines its own `event_code` enumeration. For HMMU, the codes are `B-CROSS=1`, `B-TTL=2`, `B-UCE=3`, etc., matching `HMMU_SPECIFICATION.md` §5.

---

## 3 — Regression Guards

The following static assertions (RG-* = regression guard) are compiled into the CI pipeline and must pass on every commit. A failure here fails the build.

| Guard | Check |
|-------|-------|
| RG-L-001 | `sizeof(LithoPrimitive) == 128` |
| RG-L-002 | `offsetof(LithoPrimitive, magic) == 0` |
| RG-L-003 | `offsetof(LithoPrimitive, prim_id) == 8` |
| RG-L-004 | `offsetof(LithoPrimitive, tick_id) == 12` |
| RG-L-005 | `offsetof(LithoPrimitive, timestamp_ns) == 24` |
| RG-L-006 | `offsetof(LithoPrimitive, payload) == 32` |
| RG-L-007 | `offsetof(LithoPrimitive, publisher_pubkey_fp) == 104` |
| RG-L-008 | `offsetof(LithoPrimitive, crc32c) == 120` |
| RG-L-009 | `offsetof(LithoPrimitive, schema_hash) == 124` |
| RG-L-010 | Magic bytes `{'L','T','H','O'}` always present |
| RG-L-011 | `abi_major == 1 && abi_minor == 0` for Rev 1 |
| IQ-L-001 | Rust `repr(C)` struct matches C layout byte-for-byte (cbindgen diff) |
| IQ-L-002 | SystemVerilog DPI packed struct matches C layout (DPI binding test) |
| IQ-L-003 | Serialized payload on the wire equals in-memory layout (network captured) |
| IQ-L-004 | CRC-32C validated end-to-end (NPU hardware and software consumer agree) |

---

## 4 — Rust Binding

The corresponding Rust mirror lives at `cells/lithography/rust/lithoprimitive/src/lib.rs`:

```rust
#![no_std]
#![allow(non_camel_case_types)]

// Generated by cbindgen from the C header.
// Any manual edit here will fail the RG-L-* CI guards.

#[repr(C, packed)]
pub struct LithoPrimitive {
    pub magic: [u8; 4],
    pub abi_major: u8,
    pub abi_minor: u8,
    pub event_class: u8,
    pub event_code: u8,
    pub prim_id: u32,
    pub tick_id: u32,
    pub cell_id: u16,
    pub chiplet_id: u16,
    pub hart_id: u32,
    pub timestamp_ns: u64,
    pub payload: [u8; 72],      // access via helper methods
    pub publisher_pubkey_fp: [u8; 16],
    pub crc32c: u32,
    pub schema_hash: u32,
}

impl LithoPrimitive {
    pub const SIZE: usize = 128;
    pub const MAGIC: [u8; 4] = *b"LTHO";
    pub const ABI_MAJOR: u8 = 1;
    pub const ABI_MINOR: u8 = 0;
}

const _: () = assert!(core::mem::size_of::<LithoPrimitive>() == 128);
```

A procedural macro (`lithoprimitive::event!{}`) is provided so userspace code can emit events without touching the unsafe payload union.

---

## 5 — NATS Subject Taxonomy

Every subject has the form:

```
gaiaftcl.lithography.<event-class-name>.<cell>.<chiplet-class>.<instance>.<event-code>
```

Example:

```
gaiaftcl.lithography.hmmu_breach.litho.c4.2.B-CROSS
```

Wildcard subscriptions used in the FoT8D substrate:

| Subscriber | Subscription |
|------------|--------------|
| Franklin Guardian (audit) | `gaiaftcl.lithography.>` |
| GaiaFusion (consumes tensor events) | `gaiaftcl.lithography.tensor.*.c4.*.*` |
| GaiaHealth (consumes tensor events) | `gaiaftcl.lithography.tensor.*.c4.*.*` |
| Fab operator console | `gaiaftcl.lithography.fab.>` |
| Security operations | `gaiaftcl.lithography.hmmu_breach.>` + `gaiaftcl.lithography.mask_rejected.>` |

---

## 6 — Serialization Rules

1. **Endianness:** all multi-byte fields are **little-endian** on the wire and in HBM3e. RISC-V is LE; x86 is LE; ARM GaiaOS kernels run in LE.
2. **No padding beyond what is declared.** `#pragma pack(push, 1)` is required in C; `#[repr(C, packed)]` in Rust.
3. **CRC coverage:** `crc32c` covers bytes `[0..120]` inclusive. It does **not** cover itself or the `schema_hash`.
4. **`schema_hash`:** the FNV-1a 32-bit hash of a canonical textual representation of the struct layout, computed at compile time. Any struct change produces a different hash, which lets a subscriber reject an unexpected ABI version without parsing the body.
5. **Owl signature:** the `publisher_pubkey_fp` is truncated SHA-256 of the publisher's secp256k1 public key. A separate signing path (not part of the primitive) attaches a 64-byte ECDSA signature in the NATS header for high-integrity subjects.

---

## 7 — ABI Versioning Policy

- **Rev 1.0**: frozen on first M8-Cell tape-out.
- **Rev 1.x**: may add new `event_class` values ≤ `0xEF` without breaking existing consumers. New fields must go in the `raw[72]` union member (not the header).
- **Rev 2.0**: breaking changes. Triggers a mask-change CCR and a parallel NATS subject tree `gaiaftcl.lithography.v2.>` during the migration window.

Consumers are required to check `abi_major` before interpreting payloads. A mismatch must be logged and the message dropped (never silently reinterpreted).

---

## 8 — Cross-References

- Sibling ABIs: `cells/fusion/docs/vQbitPrimitive-ABI.md`, `cells/health/wiki/BioligitPrimitive-ABI.md`
- Xvqbit ops that emit LithoPrimitives: [`M8_ISA.md`](M8_ISA.md)
- Wire-path latency requirements: [`HMMU_SPECIFICATION.md`](HMMU_SPECIFICATION.md) §5
- NPU hardware parser: [`M8_CHIPLET_IP_PORTFOLIO.md`](M8_CHIPLET_IP_PORTFOLIO.md) §3

---

*The LithoPrimitive is the on-wire contract between silicon and the rest of the FoT8D substrate. Consumers across Fusion, Health, Guardian, and the audit pipeline all decode this exact layout — any change is a constitutional change to the substrate.*
