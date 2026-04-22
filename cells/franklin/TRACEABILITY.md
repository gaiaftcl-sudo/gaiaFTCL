# Franklin — requirements traceability matrix (RTM)

**Authority:** Column schema and closure rules: [IMPLEMENTATION_PLAN.md §23](./IMPLEMENTATION_PLAN.md).  
**Master spec:** [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md) v1.0 (URS / FS / DS / qualification phases F0–F8).  
**GAMP execution rules:** [PLAN_DocApp_GAMP_Traceability.md](./PLAN_DocApp_GAMP_Traceability.md).

Status meanings: **implemented** = spec + test/script + evidence path present. **[target]** = named in v1.0 spec, not shipped. **partial** = some evidence, full row waits on a later phase. **deferred** = gated (e.g. Mother F5). **N/A** = constitutional row explicitly out of scope for Franklin infrastructure.

---

## Constitutional invariants (C-001 … C-010)

| Req ID | Source | Description | Spec Path | Test / review | Evidence Glob | Phase | Status |
|---|---|---|---|---|---|---|
| C-001 | Constitutional | Receipt mandate — every qualified action emits traceable record | [IMPLEMENTATION_PLAN.md §8](./IMPLEMENTATION_PLAN.md) | `tests/test_franklin_receipt_conformance.sh`; `fo-franklin validate-receipt-v1` ([`fo_cell_substrate`](../shared/rust/fo_cell_substrate/)) | `cells/health/evidence/franklin_mac_admin_gamp5_*.json` | F0–F4 | partial (v1 receipts; v2 + full audit trail [target] F4) |
| C-002 | Constitutional | Transparency of consequence for heal / quarantine | §8 | [target] heal library + receipt fields | — | F2–F3 | [target] |
| C-003 | Constitutional | Substrate mandate — S⁴ vs C⁴ dispute handling | §8 | [target] `disputed` receipt + tests | — | F2–F3 | [target] |
| C-004 | Constitutional | Mycelia — Mother P2P NATS only | §8 | Architecture / protocol review | — | F5 | deferred |
| C-005 | Constitutional | Biological floor | §8 | Declared N/A (infrastructure) | — | N/A | N/A |
| C-006 | Constitutional | Human rights floor | §8 | Declared N/A (infrastructure) | — | N/A | N/A |
| C-007 | Constitutional | Peace receipt | §8 | Declared N/A (direct Franklin actions) | — | N/A | N/A |
| C-008 | Constitutional | Planetary substrate | §8 | Declared N/A (direct Franklin actions) | — | N/A | N/A |
| C-009 | Constitutional | Entropy license | §8 | Declared N/A (not a discovery surface) | — | N/A | N/A |
| C-010 | Constitutional | Change control / heal authorization | §8 | [target] heal library signing + SOP | — | F3 / F5 | [target] |

---

## Functional requirements — implemented today (Fr-REQ)

| Req ID | Source | Description | Spec Path | Test | Evidence Glob | Phase | Status |
|---|---|---|---|---|---|---|
| FR-REQ-001 | URS-001 / FS | GAMP5 qualification path without IDE in execution chain (zero-human driver) | §3 Foundation; [IMPLEMENTATION.md](./IMPLEMENTATION.md) | `../health/scripts/franklin_mac_admin_gamp5_zero_human.sh` (manual / E2E via conformance test) | `cells/health/evidence/franklin_mac_admin_gamp5_*.json` | F0 | implemented |
| FR-REQ-002 | FS §5.1 | `admin-cell` invokes `/bin/zsh -f` with controlled args | §5.1; [IMPLEMENTATION.md](./IMPLEMENTATION.md) | `RepoRootTests.testSelfTestZsh` (`cells/health/swift/AdminCellRunner`) | — | F0 | implemented |
| FR-REQ-003 | FS §5.1 | Deviation requires explicit reason when skipping policy | §25.1 | `RepoRootTests.testArgDeviationRequiresReason`, `testArgDeviationWithReason` | — | F0 | implemented |
| FR-REQ-004 | URS-002 | Receipts suitable for audit (v1 schema today) | §5.8 v1; [RECEIPTS_AND_STATE_MAP.md](./RECEIPTS_AND_STATE_MAP.md) | `test_franklin_receipt_conformance.sh`; `fo-franklin validate-receipt-v1` | `cells/health/evidence/`; `schema/franklin_mac_admin_gamp5_receipt_v1.schema.json` | F0 | implemented |
| FR-REQ-005 | URS | Optional τ on receipt when `FRANKLIN_INCLUDE_TAU=1` | [IMPLEMENTATION.md](./IMPLEMENTATION.md); script | Orchestrator + `bitcoin-cli` when enabled | evidence JSON `tau_block_height` field when present | F0 / F1 | partial (no dedicated F1 τ suite yet) |
| FR-REQ-006 | DS §6.1 / F0 | SHA-256 pins for orchestrator scripts; mismatch fails closed | [IMPLEMENTATION_PLAN.md §6.1](./IMPLEMENTATION_PLAN.md) | `fo-franklin verify-pins`; `test_franklin_pins_verify.sh`; `admin-cell` + `.admincell-expected` | [`pins.json`](./pins.json); `cells/health/.admincell-expected/orchestrator.sha256` | F0 | implemented |
| FR-REQ-007 | URS / §6.3 F1 | τ = Bitcoin `getblockcount`; no fabrication; `authoritative_offline` when unavailable | [IMPLEMENTATION_PLAN.md §6.3](./IMPLEMENTATION_PLAN.md) | `TauResolver` + `TauResolverTests`; `admin-cell tau` | JSON stdout; (live height only when `bitcoin-cli` works) | F1 | partial (ECDSA receipt signing N/A) |
| FR-REQ-008 | URS / §6.2 F1 | Father secp256k1 material off-receipt; bootstrap evidence JSON | [IMPLEMENTATION_PLAN.md §6.2](./IMPLEMENTATION_PLAN.md) | `bootstrap_father.sh`; `fo-franklin validate-bootstrap`; `admin-cell bootstrap` | `cells/health/evidence/franklin_bootstrap_receipt_*.json` | F1 | partial (Keychain or secure file; bech32 + signing next) |

Rows for inventory, heal library, Mother protocol, receipt v2, and audit-trail completeness tests are **[target]** until the corresponding F2–F5 work lands; see [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md) §21.

---

## Test / tool index (quick find)

| Artifact | Path |
|---|---|
| One-command validate (Swift + conformance) | [`scripts/franklin_gamp5_validate.sh`](./scripts/franklin_gamp5_validate.sh) |
| Receipt conformance | [`tests/test_franklin_receipt_conformance.sh`](./tests/test_franklin_receipt_conformance.sh) |
| Franklin substrate (library + `fo-franklin` CLI) | [`../shared/rust/fo_cell_substrate`](../shared/rust/fo_cell_substrate) — `cargo build -p fo_cell_substrate --release` |
| JSON schema (v1) | [`schema/franklin_mac_admin_gamp5_receipt_v1.schema.json`](./schema/franklin_mac_admin_gamp5_receipt_v1.schema.json) |
| Swift tests | `cells/health/swift/AdminCellRunner` — `swift test` |

---

## Mesh cross-link (per §24)

For each domain cell on a Mac, Franklin (admin cell) and **shared** local vQbit evidence are traced here via `subject.cell_id` when those fields exist on future receipts; **global** nine-cell mesh RTM rows remain authoritative for **network** mesh behavior; Mac-local Franklin and domain cells share the same vQbit substrate per [IMPLEMENTATION_PLAN.md §5.4 / §9.1](./IMPLEMENTATION_PLAN.md) and gain a cross-link per [IMPLEMENTATION_PLAN.md §24](./IMPLEMENTATION_PLAN.md).
