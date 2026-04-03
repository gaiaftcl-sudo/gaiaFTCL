# MCP Contract Baseline Handoff

## Baseline Identity

**Branch:** `mcp-contract-baseline`  
**Tag:** `mcp-contract-baseline-v1`  
**Commit:** `5693e07cdc19d0c382c0a972393917ac3aafbdb4`  
**Date:** 2026-02-01

---

## Quick Verification

### Run the regression test:
```bash
cd GAIAOS
bash evidence/ui_contract/verify_phase3.sh
```

**Expected output:**
```
✅ All Phase 3 invariants verified.
  Contract coverage: 61/61 (100%)
  UI realization: 61/61 (100%)
  Violations: 0
```

---

## Server Requirements

### Start the MCP server:
```bash
cd GAIAOS/services/gaiaos_ui_tester_mcp
cargo run
```

Server listens on: `http://localhost:8850`

### Required environment:
- Rust toolchain (cargo)
- Port 8850 available
- Canonical files in `evidence/ui_expected/` (validated on startup)

---

## Environment Header Behavior

The MCP server enforces environment ID validation:

### ✅ Health endpoint (ungated):
```bash
curl http://localhost:8850/health
# Returns: 200 OK
```

### ❌ Missing X-Environment-ID header:
```bash
curl -X POST http://localhost:8850/mcp/execute \
  -H "Content-Type: application/json" \
  -d '{"name":"ui_contract_generate","params":{}}'
# Returns: 400 Bad Request
```

### ❌ Invalid X-Environment-ID:
```bash
curl -X POST http://localhost:8850/mcp/execute \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: invalid-id" \
  -d '{"name":"ui_contract_generate","params":{}}'
# Returns: 403 Forbidden
```

### ❌ Unadmitted tool:
```bash
curl -X POST http://localhost:8850/mcp/execute \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: 4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6" \
  -d '{"name":"not_a_tool","params":{}}'
# Returns: 422 Unprocessable Entity
# Message: "tool not in admissibility contract"
```

### ✅ Valid call:
```bash
curl -X POST http://localhost:8850/mcp/execute \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: 4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6" \
  -d '{"name":"ui_contract_generate","params":{}}'
# Returns: 200 OK with witness + evidence_file
```

---

## Evidence Files & Byte-Match Verification

### Evidence location:
Evidence files are written to:
```
evidence/mcp_calls/YYYY-MM-DDTHH-MM-SS-MMMZ/{call_id}.json
```

### Byte-match verification:
Every MCP tool response includes:
```json
{
  "witness": {
    "call_id": "uuid-here",
    "hash": "sha256:hex-hash-here",
    "algorithm": "sha256",
    "timestamp": "ISO-8601-timestamp"
  },
  "evidence_file": "../../evidence/mcp_calls/.../uuid.json"
}
```

**To verify:**
```bash
# Extract call_id and hash from response
CALL_ID="uuid-from-response"
EXPECTED_HASH="hex-from-response"

# Fetch evidence
curl -sS "http://localhost:8850/evidence/${CALL_ID}" -o /tmp/evidence.json

# Compute hash
GOT_HASH=$(shasum -a 256 /tmp/evidence.json | awk '{print $1}')

# Compare
if [ "$GOT_HASH" = "$EXPECTED_HASH" ]; then
  echo "✅ BYTE-MATCH OK"
else
  echo "❌ BYTE-MATCH FAIL"
fi
```

---

## MCP Tools

### `ui_contract_generate`
Validates canonical integrity and contract completeness.

**Returns:**
- `counts_raw`: Canonical file lengths (38 total)
- `counts_expanded`: Actual UI items after expansion (61 total)
- `contract_coverage`: total_items, mapped_items, unmapped_items
- `ui_coverage`: ui_present_items, ui_absent_items, violations
- `canonicals_hash`: SHA-256 of CANONICALS.SHA256 lockfile
- `surface_map_hash`: SHA-256 of ui_surface_map.json
- `manifest_hash`: SHA-256 of ui_contract_manifest.json

### `ui_contract_report`
Same as `ui_contract_generate`, plus:
- Generates `UI_ABSENT_BACKLOG.json` (machine-readable)
- Generates `UI_ABSENT_BACKLOG.md` (human-readable)
- Returns `backlog_files` paths

---

## Canonical Validation Lifecycle

**Startup validation:**
- Canonical files are validated **once per server process start** using `OnceLock`
- Validation checks: file existence, SHA-256 hashes, valid JSON, no duplicate IDs
- Server will not start if canonicals are invalid

**Runtime verification:**
- `canonicals_hash` in every tool response enables external verification
- To detect runtime tampering: compare `canonicals_hash` to recomputed hash of `CANONICALS.SHA256`
- If mismatch: canonical files were modified after server start (requires restart to detect)

---

## Truth Rules (Fail-Closed)

1. **Contract must be 100%:** `mapped_items == total_items`
2. **UI_PRESENT requires proof:** Non-empty route + selector + assertion
3. **Route validation:** UI_PRESENT items must use allowed routes only (`/index.html`)
4. **Proof violations:** Empty strings are rejected (not just null)
5. **UI count consistency:** `ui_present + ui_absent == ui_total`

All violations trigger explicit REJECT with error codes.

---

## File Locations

**Canonical sources (read-only):**
```
evidence/ui_expected/domains.json
evidence/ui_expected/games.json
evidence/ui_expected/envelopes.json
evidence/ui_expected/uum8d_dimensions.json
evidence/ui_expected/game_envelopes.json
evidence/ui_expected/game_dimensions.json
evidence/ui_expected/CANONICALS.SHA256
```

**Contract files:**
```
evidence/ui_contract/ui_contract_manifest.json
evidence/ui_contract/ui_surface_map.json
evidence/ui_contract/UI_ABSENT_BACKLOG.json
evidence/ui_contract/UI_ABSENT_BACKLOG.md
evidence/ui_contract/README.md
evidence/ui_contract/verify_phase3.sh
```

**Server code:**
```
services/gaiaos_ui_tester_mcp/src/main.rs
services/gaiaos_ui_tester_mcp/src/enforcement.rs
services/gaiaos_ui_tester_mcp/src/witness_wrapper.rs
services/gaiaos_ui_tester_mcp/Cargo.toml
```

---

## Next Steps (Not Implemented)

This baseline is **server-only**. The following are documented but not implemented:

- Phase 5+ (if any): Asset-aware 3D UI work
- Production deployment configuration
- Multi-environment MCP setup (cell03, cell04, production)
- Automated CI/CD integration

For questions or issues, refer to:
- `evidence/ui_contract/README.md` (detailed semantics)
- `evidence/ui_contract/verify_phase3.sh` (regression test)
- Git history on `mcp-contract-baseline` branch
