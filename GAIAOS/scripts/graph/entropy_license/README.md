# Entropy license — Arango collections (operator)

Create once in database `gaiaos` (or your substrate DB):

**Collection `entropy_licenses` (document)**  
Suggested fields: `wallet_address`, `discovery_id`, `discovery_collection`, `entropy_license_fee_paid`, `transaction_hash`, `licensed_at`, `license_receipt_hash`, `license_status` (`ACTIVE` | `EXPIRED` | `REVOKED`).

**Edge collection `license_graph`**  
From wallet / discovery vertices per your knowledge graph model.

**Founder exemption**  
Extend `authorized_wallets` documents with `license_exemption: true` for the founder address (see `services/wallet_gate/seed_authorized_wallets.aql`).

**Wallet gate**  
Set `ENABLE_ENTROPY_LICENSE=1` and comma-separated `ENTROPY_LICENSE_PATH_PREFIXES` (e.g. `discovery/,substrate/discovery`) on `gaiaftcl-wallet-gate`.

**Migration**  
Use `knowledge_graph_migrate.py` patterns to batch-update `discovered_*` with `entropy_license_value` / `entropy_license_fee_usd` — do not run destructive AQL from Cursor against production without a witness plan.
