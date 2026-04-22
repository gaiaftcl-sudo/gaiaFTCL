# Franklin — Mac Father substrate (implementation index)

**Franklin** is the **Mac admin mesh cell**: GAMP5, zero-human drivers, and `admin-cell` on every host, on the **same vQbit plane** as domain cells on that Mac (see [`docs/concepts/franklin-role.md`](../../docs/concepts/franklin-role.md)).

**v1.0 regulated spec (URS/FS/DS + qualification plan, draft pre–Mother per doc frontmatter):** [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md). **Implemented today** (scripts, `admin-cell`, evidence paths) is tracked separately in [IMPLEMENTATION.md](./IMPLEMENTATION.md) and the table below. **GAMP doc↔app traceability + exit rules** (stated/verified/evidenced) live in [PLAN_DocApp_GAMP_Traceability.md](./PLAN_DocApp_GAMP_Traceability.md) as companion to the v1.0 spec, not a second product narrative.

## Authoritative code + evidence

| Piece | Path |
|------|------|
| Zero-human GAMP5 + receipt writer | [`../health/scripts/franklin_mac_admin_gamp5_zero_human.sh`](../health/scripts/franklin_mac_admin_gamp5_zero_human.sh) |
| `admin-cell` (Swift) | [`../health/swift/AdminCellRunner/`](../health/swift/AdminCellRunner/) |
| **MacFranklin** (`.app` shell — same driver as above) | [`../health/swift/MacFranklin/README.md`](../health/swift/MacFranklin/README.md) |
| GAIAOS wrapper + LaunchAgent example | [`../../GAIAOS/mac_cell/FranklinGAMP5Admin/`](../../GAIAOS/mac_cell/FranklinGAMP5Admin/) |
| Optional Console verify | [`../../GAIAOS/macos/GaiaFTCLConsole/scripts/verify_build_and_test.sh`](../../GAIAOS/macos/GaiaFTCLConsole/scripts/verify_build_and_test.sh) (if present) |
| Evidence JSON | `cells/health/evidence/franklin_mac_admin_gamp5_*.json` |

## Doc map

- [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md) — **v1.0** complete implementation and qualification plan (GAMP framing, layers, F0–F8, receipt v2, RTM structure).
- [TRACEABILITY.md](./TRACEABILITY.md) — **RTM**: C-001…C-010, FR-REQ-###, tests, evidence globs (implemented vs **[target]**).
- [SUPPLIERS.md](./SUPPLIERS.md) — supplier matrix (per §7); formal assessment text filed here as phases close.
- [IMPLEMENTATION.md](./IMPLEMENTATION.md) — **current** script / `admin-cell` flow (as shipped).
- [RECEIPTS_AND_STATE_MAP.md](./RECEIPTS_AND_STATE_MAP.md) — schema + terminal mapping.
- [MOTHER_DRAFT.md](./MOTHER_DRAFT.md) — **draft** Mother narrative; **C-004** P2P-only constraint.
- [MIGRATION_FROM_TESTROBOT.md](./MIGRATION_FROM_TESTROBOT.md) — three-way **TestRobot** scope + archive pointer.

**Concept spine:** [`../../docs/concepts/`](../../docs/concepts/)

## Testing (receipt conformity)

| Check | Command |
|--------|--------|
| **One-command (Swift + pin verify + receipt conformance + evidence audit; recommended for CI / pre-push)** | `zsh cells/franklin/scripts/franklin_gamp5_validate.sh` |
| **Full pack (zero-drift: CLI + app + fo-franklin)** | `zsh cells/franklin/scripts/franklin_mac_full_package_validate.sh` — same driver/pins as one-command validate; [MacFranklin zero-drift table](../health/swift/MacFranklin/README.md#zero-drift-lock) |
| **Franklin leads entire repo (Mac + Health GAMP5 + optional Fusion game registry)** | `zsh cells/franklin/scripts/franklin_orchestrated_repo_validate.sh` — then push; `FRANKLIN_ONLY=1` for Mac cell only | 
| **After editing** `health_full_local_iqoqpq_gamp.sh` **or** `franklin_mac_admin_gamp5_zero_human.sh` | `zsh cells/franklin/scripts/refresh_franklin_pins.sh` (updates `pins.json` + `cells/health/.admincell-expected/orchestrator.sha256`) |
| **Shared substrate (Rust)** | `cells/shared/rust/fo_cell_substrate/` — `cargo build -p fo_cell_substrate --release` → `fo-franklin` (Franklin F0/F1), `fo-health` (`gamp5-catalog`, `preflight-json`, `json-field`), `fo-fusion` (`plant-adapters`, `json-at` for stdin JSON Pointer) |
| **Pin-only check** | `target/release/fo-franklin verify-pins` · `zsh cells/franklin/tests/test_franklin_pins_verify.sh` |
| **Evidence audit (v1 + v0.1 bootstrap)** | `zsh cells/franklin/scripts/audit_trail_verify.sh` |
| **τ probe (JSON)** | `cd cells/health/swift/AdminCellRunner && swift run admin-cell tau` |
| **Father bootstrap (F1 dev: OpenSSL secp256k1 + Keychain or `state/.father_secp256k1.pem`)** | `cd cells/health/swift/AdminCellRunner && swift run admin-cell bootstrap` (or `zsh cells/franklin/scripts/bootstrap_father.sh` from repo root) |
| **Validate bootstrap JSON** | `target/release/fo-franklin validate-bootstrap path/to/receipt.json` |
| **Fixture + negative test** | `zsh cells/franklin/tests/test_franklin_receipt_conformance.sh` (requires `fo-franklin` built) |
| **Single file (receipt v1)** | `target/release/fo-franklin validate-receipt-v1 path/to/receipt.json` |
| **End-to-end smoke** (builds `admin-cell` if needed, runs self-test + orchestrator `--dry-run`, **skips** long Console verify) | `RUN_FRANKLIN_E2E=1 zsh cells/franklin/tests/test_franklin_receipt_conformance.sh` |

`admin-cell` unit tests (orchestrator args, self-test zsh) also run **inside** `franklin_gamp5_validate.sh` (`cd cells/health/swift/AdminCellRunner && swift test`).

**Traceability / RTM:** [TRACEABILITY.md](./TRACEABILITY.md) · **Suppliers:** [SUPPLIERS.md](./SUPPLIERS.md) · **Version pin (Franklin pack):** [VERSION](./VERSION)
