# Franklin — receipts and terminal map

## Schema

| Field | Meaning |
|-------|--------|
| `schema` | Fixed: `franklin_mac_admin_gamp5_receipt_v1` |
| `ts_utc` | Wall-clock stamp (supplementary) |
| `git_short_sha` | Repo head (context) |
| `smoke_mode` | `true` when default smoke path (self-test + dry-run + optional Console verify) |
| `final_exit` | Process exit code; **0** = script success |
| `phases[]` | `{ name, exit }` per named phase (`admin_cell_self_test`, `gaiaftcl_console`, `gamp5_orchestrator`, …) |
| `note` | Fixed GAMP deviation string (see script) |
| `tau_block_height` | **Optional.** Bitcoin mainnet block height **τ** when `FRANKLIN_INCLUDE_TAU=1` and `bitcoin-cli getblockcount` succeeds |

**Machine validation:** JSON Schema — [`schema/franklin_mac_admin_gamp5_receipt_v1.schema.json`](./schema/franklin_mac_admin_gamp5_receipt_v1.schema.json); checker — `target/release/fo-franklin validate-receipt-v1` ([`fo_cell_substrate`](../shared/rust/fo_cell_substrate/)).

**τ (Bitcoin height):** default receipts are **wall + git** only. For release gates that require **τ** on the same artifact, set **`FRANKLIN_INCLUDE_TAU=1`** with a working **`bitcoin-cli`** (mainnet as configured by your `bitcoin.conf`).

## State machine ↔ mesh language (informative)

Franklin is an **operator automation** layer. It does **not** replace mesh quorum.

| Franklin / operational signal | Mesh language (when talking about the **nine-cell** plane) |
|------------------------------|------------------------------------------------------------|
| `final_exit != 0` or failed phase | Treat as **blocked** / **REFUSED-class** for *that* qualification claim until retried |
| `final_exit == 0` through agreed phases | Evidence of **pass** for **Mac Admin** lane — not a substitute for unrelated mesh receipts |

**Health state machine** (11 states, CURE, etc.) remains in [`../health/wiki/State-Machine.md`](../health/wiki/State-Machine.md) — Franklin does not rename those states.
