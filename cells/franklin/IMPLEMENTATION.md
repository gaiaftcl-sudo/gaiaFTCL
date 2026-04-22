# Franklin — implementation (current)

**For the full product roadmap** (substrate/identity/clock/vQbit/heal/Mother/CLI, phases **F0–F8**), see [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md). This file describes what the **shipped** shell + `admin-cell` path does **today**.

## Role

**Franklin** (Mac **admin** cell) drives the **Mac Admin** “self-heal” loop: build/locate `admin-cell`, run self-test, optionally run **GaiaFTCLConsole** `verify_build_and_test.sh`, then either **smoke** (orchestrator `--dry-run`) or **full** unattended orchestrator with explicit deviation flags per GAMP policy. The **narrative** in [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md) — Franklin and domain cells on the **shared vQbit** plane — is the target; **today’s** code path is shell + `admin-cell` + [`fo_cell_substrate`](../shared/rust/fo_cell_substrate) (`fo-franklin` validates receipts, including `franklin_mac_admin_cell_role`). `AdminCellRunner` has no separate vQbit store yet; per-cell vQbit records from the plan remain **[target]** (F2+).

Canonical entry: [`../health/scripts/franklin_mac_admin_gamp5_zero_human.sh`](../health/scripts/franklin_mac_admin_gamp5_zero_human.sh).

**Hash pins (F0):** Any change to the GAMP orchestrator or this Franklin driver must update committed SHA-256 pins: run `zsh cells/franklin/scripts/refresh_franklin_pins.sh` from repo root. That writes [`../franklin/pins.json`](../franklin/pins.json) and `cells/health/.admincell-expected/orchestrator.sha256` (used by `admin-cell` to refuse a tampered orchestrator). `admin-cell` → [`../health/scripts/health_full_local_iqoqpq_gamp.sh`](../health/scripts/health_full_local_iqoqpq_gamp.sh).

**Environment (τ):** set `FRANKLIN_INCLUDE_TAU=1` to record **`tau_block_height`** on the receipt when `bitcoin-cli getblockcount` is available (mainnet per your node config). Default is off (wall + git only).

**Conformity tests:** [README — Testing](./README.md#testing-receipt-conformity) · one-command: `zsh cells/franklin/scripts/franklin_gamp5_validate.sh` · or `cells/franklin/tests/test_franklin_receipt_conformance.sh` (set `RUN_FRANKLIN_E2E=1` for script + real receipt). **RTM / requirements:** [TRACEABILITY.md](./TRACEABILITY.md).

**F1 (in progress in-repo):** `admin-cell tau` (τ from `bitcoin-cli` or `authoritative_offline`); `admin-cell bootstrap` / `bootstrap_father.sh` writes `franklin_bootstrap_receipt_v0.1` (public PEM + commitment; private in Keychain or `cells/franklin/state/.father_secp256k1.pem` — never commit). **Next:** ECDSA sign receipts, bech32, Keychain-only hardening, receipt v2.

## Phase flow (script)

1. Resolve `REPO_ROOT`, ensure `cells/health/evidence/` exists.
2. Locate or **build** `admin-cell` (`swift build -c release` in `AdminCellRunner`).
3. `run_admin` with self-test and/or smoke/orchestrator flags (env: `FRANKLIN_GAMP5_SMOKE`, `FRANKLIN_GAMP5_ORCH_ARGS`, `FRANKLIN_INCLUDE_CONSOLE_VERIFY`, `FRANKLIN_INCLUDE_FOT8D_RING2`).
4. Write JSON receipt **`franklin_mac_admin_gamp5_receipt_v1`** (see [RECEIPTS_AND_STATE_MAP.md](./RECEIPTS_AND_STATE_MAP.md)).

## Links to mesh / health docs

- [`../health/docs/TESTROBOT_VS_HEALTH_IQOQPQ.md`](../health/docs/TESTROBOT_VS_HEALTH_IQOQPQ.md) — **TestRobot vs admin-cell** vs **Franklin**.
- [`../health/docs/LOCAL_IQOQPQ_ORCHESTRATOR_V3.md`](../health/docs/LOCAL_IQOQPQ_ORCHESTRATOR_V3.md) — orchestrator URS and script names.
- **Console live path** (if used): spawns `admin-cell` for full health chain (see TESTROBOT doc).

## LOCKED / boundaries

Console product lock: [`../fusion/macos/GaiaFTCLConsole/LOCKED.md`](../fusion/macos/GaiaFTCLConsole/LOCKED.md) — dependency isolation; Franklin may *call* verify scripts but must not blur **locked** boundaries in code reviews.
