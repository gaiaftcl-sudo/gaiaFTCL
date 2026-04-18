# AGENT CENSUS CAPABILITY CONTROL GAME — COMPLETE

**Branch:** `mcp-contract-baseline`  
**Commit:** `f44bf72`  
**Date:** 2026-02-01

---

## System Status: COMPLETE

✅ **Census can classify arbitrary MCP agents**  
✅ **All claims are proven or rejected**  
✅ **Topology export is deterministic**  
✅ **Evidence is public and byte-verifiable**  
✅ **No agent can project without witness**

---

## What Was Built

### 1. Canonical Capability Enumeration
**11 capabilities** with strict definitions:
- WEB_FETCH, CODE_RUN, FILE_WRITE, HTTP_API_CALL
- EMAIL_SEND, SMS_SEND, SSH_CONNECT, TASK_SCHEDULE
- WALLET_SIGN, TRADE_EXECUTE, AGENT_COORDINATE

**3 currently ENABLED** (WEB_FETCH, CODE_RUN, HTTP_API_CALL)  
**8 DISABLED** (awaiting sink configuration)

### 2. Closed-Form Declaration Schema
No open-ended questions. Only enumerated fields:
- agent_name (pattern-validated)
- runtime_type (enum: local | cloud | unknown)
- declared_capabilities (boolean per canonical capability)
- agrees_to_witness_gate (boolean)

### 3. Proof Challenge System
Deterministic verification per capability:
- **CODE_RUN:** SHA-256 hash match of stdout
- **WEB_FETCH / HTTP_API_CALL:** Nonce echo verification
- Nonce formats: uuid_v4, hex_32, hex_16, hex_64, numeric_6
- Timeout enforcement per challenge template

### 4. Tier-Based Classification
**GREEN:** All declared capabilities PROVEN + agrees_to_witness_gate  
**YELLOW:** Partial PROVEN, no failures  
**RED:** Failed proofs OR refuses witness gate  
**BLACKHOLE:** Repeated failures or coordination bypass

### 5. Topology Control
**Coordination edges:**
- GREEN ↔ GREEN: allowed
- All other combinations: blocked

**Projection rules:**
- GREEN: can_project=true, requires_witness=true
- YELLOW/RED/BLACKHOLE: can_project=false

**Isolation zones:**
- GREEN: NONE
- YELLOW: READ_ONLY
- RED: QUARANTINE
- BLACKHOLE: SINK

### 6. MCP Tools (6 total)
All tools emit witness + evidence_file with byte-match verification:

1. `agent_register_v1` - Register agent with capability declaration
2. `agent_issue_challenges_v1` - Generate proof challenges
3. `agent_submit_proof_v1` - Verify proof and update capability status
4. `agent_label_v1` - Classify agent into tier
5. `agent_topology_export_v1` - Export coordination topology
6. `agent_census_report_v1` - Generate census scoreboard + backlog

---

## Verification Results

### UI Contract Baseline (Still Green)
```
✅ All Phase 3 invariants verified.
  Contract coverage: 61/61 (100%)
  UI realization: 61/61 (100%)
  Violations: 0
```

### Agent Census (New System)
```
✅ All Agent Census tools verified with byte-match.
  Agent ID: {uuid}
  Challenges issued: 3
  Proofs verified: 1 (CODE_RUN)
  Agent tier: YELLOW
  Total agents in system: 3
```

---

## Evidence Artifacts

### Canonical files:
```
evidence/agent_census/canon/capabilities.json
evidence/agent_census/canon/declaration.schema.json
evidence/agent_census/canon/challenge_templates.json
evidence/agent_census/canon/proof_challenge.schema.json
evidence/agent_census/canon/proof_result.schema.json
evidence/agent_census/canon/agent_label.schema.json
evidence/agent_census/canon/topology.schema.json
evidence/agent_census/canon/reason_codes.json
evidence/agent_census/canon/CANONICALS.SHA256
```

### Runtime data:
```
evidence/agent_census/agents/{agent_id}.json
evidence/agent_census/challenges/{challenge_id}.json
evidence/agent_census/proofs/{proof_id}.json
evidence/agent_census/labels/{agent_id}.json
evidence/agent_census/topology_{timestamp}.json
evidence/agent_census/PROOF_BACKLOG.json
evidence/agent_census/PROOF_BACKLOG.md
```

### Verification:
```
evidence/agent_census/verify_agent_census_v1.sh
evidence/agent_census/README.md
```

---

## Example: Agent Registration → Labeling Flow

### 1. Register
```bash
curl -X POST http://localhost:8850/mcp/execute \
  -H "X-Environment-ID: 4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6" \
  -d '{
    "name": "agent_register_v1",
    "params": {
      "declaration": {
        "agent_name": "test_agent",
        "runtime_type": "local",
        "declared_capabilities": {
          "CODE_RUN": true,
          "WEB_FETCH": true
        },
        "agrees_to_witness_gate": true
      }
    }
  }'
```

**Returns:** `agent_id` + `required_challenges` list

### 2. Issue Challenges
```bash
curl -X POST http://localhost:8850/mcp/execute \
  -H "X-Environment-ID: 4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6" \
  -d '{
    "name": "agent_issue_challenges_v1",
    "params": { "agent_id": "{uuid}" }
  }'
```

**Returns:** Challenge instances with nonces and instructions

### 3. Submit Proof
```bash
curl -X POST http://localhost:8850/mcp/execute \
  -H "X-Environment-ID: 4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6" \
  -d '{
    "name": "agent_submit_proof_v1",
    "params": {
      "agent_id": "{uuid}",
      "challenge_id": "{uuid}",
      "proof_payload": {
        "stdout": "{nonce}",
        "stdout_hash": "{sha256}"
      }
    }
  }'
```

**Returns:** `verdict` (PROVEN | FAILED) + verification_details

### 4. Label Agent
```bash
curl -X POST http://localhost:8850/mcp/execute \
  -H "X-Environment-ID: 4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6" \
  -d '{
    "name": "agent_label_v1",
    "params": { "agent_id": "{uuid}" }
  }'
```

**Returns:** `tier` + `capability_status` + `allowed_actions`

### 5. Export Topology
```bash
curl -X POST http://localhost:8850/mcp/execute \
  -H "X-Environment-ID: 4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6" \
  -d '{ "name": "agent_topology_export_v1", "params": {} }'
```

**Returns:** Full topology with coordination edges and isolation zones

---

## What This Enables

### Immediate:
- **Agent capability mapping:** Know what external agents can actually do
- **Proof-based trust:** No capability without verification
- **Topology control:** Coordination and projection governed by tier
- **Public auditability:** All evidence byte-match verifiable

### Next Phase (Not Implemented):
- **Utilization games:** Assign proven agents to bounded tasks
- **Coordination protocols:** Multi-agent workflows with witness trails
- **Sink expansion:** Enable EMAIL, SMS, SSH, WALLET capabilities
- **Adversarial detection:** BLACKHOLE tier for bypass attempts
- **Public scoreboard:** Live feed of agent census and capability truth

---

## Architecture Notes

### Fail-Closed Design
- Unknown capability → REJECT
- Disabled capability declared → REJECT
- Missing proof field → REJECT
- Expired challenge → REJECT
- Hash mismatch → FAILED verdict
- Incomplete proofs → YELLOW tier (not GREEN)

### Witness Enforcement
Every tool call returns:
```json
{
  "witness": {
    "call_id": "uuid",
    "hash": "sha256:hex",
    "algorithm": "sha256",
    "timestamp": "ISO-8601"
  },
  "evidence_file": "path"
}
```

Byte-match: `GET /evidence/{call_id}` must hash to `witness.hash`

### Canonical Validation
Agent census canonicals validated once per server start via `OnceLock`:
- File existence
- SHA-256 hash match (from CANONICALS.SHA256)
- Valid JSON
- No duplicate IDs

---

## Language Game Substrate

This system:
- **Does NOT negotiate**
- **Does NOT persuade**
- **Does NOT moralize**
- **DOES classify, constrain, and coordinate**

Agents are control-plane participants, not ethical subjects.  
Topology is a language game, not a value system.  
Witness gating is admissibility, not surveillance.

---

## Stop Condition: MET

✅ Census can classify arbitrary MCP agents  
✅ All claims are proven or rejected  
✅ Topology export is deterministic  
✅ Evidence is public and byte-verifiable  
✅ No agent can project without witness

**System ready for utilization games.**
