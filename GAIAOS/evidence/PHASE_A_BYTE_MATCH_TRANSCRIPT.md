# PHASE A BYTE-MATCH VERIFICATION TRANSCRIPT

**Date:** 2026-01-31  
**Server:** gaiaos_ui_tester_mcp (localhost:8850)  
**Purpose:** Verify witness hash matches exact evidence bytes returned by GET /evidence/{call_id}

---

## SERVER START

```bash
cd /Users/richardgillespie/Documents/FoT8D/GAIAOS/services/gaiaos_ui_tester_mcp
./target/debug/gaiaos_ui_tester_mcp > /tmp/gaiaos_ui_tester_mcp.log 2>&1 &
```

**Health check:**
```bash
curl -s http://localhost:8850/health | jq .
```

**Response:**
```json
{
  "service": "gaiaos-ui-tester-mcp",
  "status": "healthy",
  "version": "0.1.0"
}
```

---

## ACCEPT CALL EXECUTION

**Command:**
```bash
curl -s -X POST http://localhost:8850/mcp/execute \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: 4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6" \
  -d '{"name": "check_substrate_connection", "params": {"ui_name": "ATC_UI"}}'
```

**Response:**
```json
{
  "ok": true,
  "result": {
    "status": {
      "akg_gnn_connected": true,
      "arango_connected": false,
      "details": [
        "✅ AKG GNN (8700) reachable",
        "✅ NATS (4222) connected",
        "❌ ArangoDB (8529) not reachable",
        "✅ vChip (8001) reachable"
      ],
      "mocked": true,
      "nats_connected": true,
      "ui_name": "ATC_UI",
      "vchip_connected": true,
      "virtue_engine_connected": false
    },
    "success": true
  },
  "witness": {
    "algorithm": "sha256",
    "call_id": "23189a91-001b-43ba-9865-46bc32e6a6f4",
    "hash": "sha256:13bcc3ae2440dd933359b0002ac01f33798fb56cf5ddf6cf50baa0c1b01f8f7e",
    "timestamp": "2026-01-31T12:41:27.666568+00:00"
  },
  "evidence_file": "../../evidence/mcp_calls/2026-01-31T12-41-27-666Z/23189a91-001b-43ba-9865-46bc32e6a6f4.json"
}
```

**Extracted metadata:**
- **Call ID:** `23189a91-001b-43ba-9865-46bc32e6a6f4`
- **Evidence file:** `../../evidence/mcp_calls/2026-01-31T12-41-27-666Z/23189a91-001b-43ba-9865-46bc32e6a6f4.json`
- **Expected hash:** `13bcc3ae2440dd933359b0002ac01f33798fb56cf5ddf6cf50baa0c1b01f8f7e`

---

## EVIDENCE RETRIEVAL

**Command:**
```bash
curl -sS http://localhost:8850/evidence/23189a91-001b-43ba-9865-46bc32e6a6f4 -o /tmp/phase_a_evidence.json
```

**Evidence file location (absolute path):**
```
/Users/richardgillespie/Documents/FoT8D/GAIAOS/evidence/mcp_calls/2026-01-31T12-41-27-666Z/23189a91-001b-43ba-9865-46bc32e6a6f4.json
```

**File size:** 777 bytes

---

## HASH VERIFICATION

**Command:**
```bash
shasum -a 256 /tmp/phase_a_evidence.json
```

**Computed hash:**
```
13bcc3ae2440dd933359b0002ac01f33798fb56cf5ddf6cf50baa0c1b01f8f7e
```

**Comparison:**
```
Expected:  13bcc3ae2440dd933359b0002ac01f33798fb56cf5ddf6cf50baa0c1b01f8f7e
Computed:  13bcc3ae2440dd933359b0002ac01f33798fb56cf5ddf6cf50baa0c1b01f8f7e
```

**Result:** ✅ **HASH MATCH**

---

## EVIDENCE DIRECTORY LAYOUT

**Pattern:** `evidence/mcp_calls/{timestamp}/{call_id}.json`

**Timestamp format:** `YYYY-MM-DDTHH-MM-SS-3fZ` (ISO 8601 with milliseconds)

**Deterministic:** ✅ Yes - timestamp is derived from server time at witness generation

---

## VERIFICATION SUMMARY

| Attribute | Status |
|-----------|--------|
| Server health endpoint | ✅ Reachable |
| MCP execute endpoint | ✅ Reachable |
| Environment ID enforcement | ✅ Active (middleware) |
| Witness generation | ✅ Functional |
| Evidence storage | ✅ Functional |
| Evidence retrieval | ✅ Functional |
| Hash byte-match | ✅ **VERIFIED** |

**Critical implementation detail:** The `witness` field in `MCPCallEvidence` struct is marked with `#[serde(skip_serializing)]`, ensuring the witness hash is NOT included in the saved evidence file. This guarantees the client can recompute the exact same hash from the fetched evidence bytes.

---

## PHASE A BASELINE COMPLETE

**Date:** 2026-01-31T12:41:27Z  
**Verification:** PASS  
**Next phase:** Enforcement boundary testing (Step 4)

---

## REPRODUCIBILITY VERIFICATION (Clean Build)

**Date:** 2026-01-31T12:54:42Z  
**Branch:** phase-a-baseline  
**Commit:** 36a6c16

**Build from scratch:**
```bash
cd /Users/richardgillespie/Documents/FoT8D/GAIAOS/services/gaiaos_ui_tester_mcp
cargo clean -p gaiaos_ui_tester_mcp
cargo build -p gaiaos_ui_tester_mcp
./target/debug/gaiaos_ui_tester_mcp
```

**ACCEPT call:**
```bash
curl -s -X POST http://localhost:8850/mcp/execute \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: 4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6" \
  -d '{"name": "check_substrate_connection", "params": {"ui_name": "ATC_UI"}}'
```

**Response:**
```json
{
  "ok": true,
  "witness": {
    "algorithm": "sha256",
    "call_id": "67193f6f-84f5-4629-b2da-2f2476faa8f9",
    "hash": "sha256:20994e82750c9b7f471a780e3f95d7d898d64f0e7b4f6c8e895028ffef786876",
    "timestamp": "2026-01-31T12:54:42.842314+00:00"
  },
  "evidence_file": "../../evidence/mcp_calls/2026-01-31T12-54-42-842Z/67193f6f-84f5-4629-b2da-2f2476faa8f9.json"
}
```

**Hash verification:**
```
Expected:  20994e82750c9b7f471a780e3f95d7d898d64f0e7b4f6c8e895028ffef786876
Computed:  20994e82750c9b7f471a780e3f95d7d898d64f0e7b4f6c8e895028ffef786876
```

**Result:** ✅ **HASH MATCH - BASELINE REPRODUCIBLE**
