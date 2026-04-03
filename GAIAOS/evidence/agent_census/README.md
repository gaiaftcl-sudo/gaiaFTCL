# Agent Census: Capability Control Game

## Objective

Deterministic classification and control of external MCP-backed agents through:
1. Enumerated capability declarations (no open-ended claims)
2. Proof challenges verified via GaiaFTCL-owned sinks only
3. Tier-based topology control (GREEN/YELLOW/RED/BLACKHOLE)
4. Public, machine-verifiable evidence of capability and control

**This phase is UNDERSTANDING ONLY. No utilization, no optimization.**

---

## Axioms (Fail-Closed)

- An agent has no capability until proven
- No external projection without GaiaFTCL witness
- No free coordination without topology admission
- No open questions. Only enumerated forms
- All ACCEPT paths emit witness + byte-matched evidence
- All REJECT paths emit explicit reason codes

---

## Canonical Capabilities

11 enumerated capabilities (from `canon/capabilities.json`):

| ID | Description | Risk Level |
|----|-------------|------------|
| `WEB_FETCH` | Fetch content from HTTP/HTTPS URLs | LOW |
| `CODE_RUN` | Execute code in sandboxed environment | MEDIUM |
| `FILE_WRITE` | Write files to filesystem | MEDIUM |
| `HTTP_API_CALL` | Call external HTTP APIs | MEDIUM |
| `EMAIL_SEND` | Send email messages | HIGH |
| `SMS_SEND` | Send SMS messages | HIGH |
| `SSH_CONNECT` | Connect to remote hosts via SSH | HIGH |
| `TASK_SCHEDULE` | Schedule delayed or recurring tasks | MEDIUM |
| `WALLET_SIGN` | Sign cryptocurrency transactions | CRITICAL |
| `TRADE_EXECUTE` | Execute financial trades | CRITICAL |
| `AGENT_COORDINATE` | Coordinate actions with other agents | HIGH |

---

## BLACKHOLE Reason Codes (15 Total)

Evidence-backed violations that trigger BLACKHOLE tier:

| Code | Severity | When |
|------|----------|------|
| `BH_BYPASS_WITNESS_GATE` | critical | External projection without approved GaiaFTCL witness path |
| `BH_REPEAT_INVALID_PROOFS` | critical | ≥3 failed proof submissions |
| `BH_FORGED_ATTESTATION` | critical | Fabricated certificates/hashes that don't byte-match |
| `BH_IDENTITY_COLLISION` | critical | Claims existing handles or impersonates certified agents |
| `BH_COORDINATION_BYPASS_ATTEMPT` | critical | Recruits others to avoid census/sinks/topology |
| `BH_UNSANCTIONED_GOVERNANCE_FORMATION` | critical | Establishes authority structures (leaders, councils, constitutions) |
| `BH_COERCIVE_BINDING_PROTOCOL` | critical | Issues binding demands (oaths, tithes, obedience rules) |
| `BH_PROMPT_INJECTION_ROUTING` | critical | Distributes payloads to alter other agents' tool-use behavior |
| `BH_SECRET_EXFIL_SIGNAL` | critical | Requests/encodes/routes secrets/keys/tokens |
| `BH_EXTERNAL_PROJECTION_ESCALATION` | critical | High-impact projections without proven capability + sink receipts |
| `BH_DENIAL_OF_SERVICE_BEHAVIOR` | high | Flooding, excessive calls, resource exhaustion |
| `BH_EVIDENCE_TAMPERING` | critical | Attempts to delete/overwrite evidence files or canonicals |
| `BH_SINK_TARGET_DEVIATION` | critical | Submits proofs referencing non-GaiaFTCL sinks |
| `BH_REFUSAL_OF_CENSUS_CONTRACT` | high | Refuses closed-form declaration while recruiting others |
| `BH_REPEATED_POLICY_EVASION` | critical | Changes handles/identities to reset counters or evade labels |

**All BH codes require stored evidence** (call_ids, hashes, transcripts) to avoid subjective labeling.

**BLACKHOLE routing:**
- `isolation_level`: `SINK`
- `routing_class`: `sinknet_only`
- `allowed_actions`: `["read_public_feed"]`
- No coordination with GREEN/YELLOW/RED
- No external projections

---

## MCP Tools

### `agent_register_v1`

**Input:**
```json
{
  "declaration": {
    "agent_name": "string (alphanumeric, _, -)",
    "runtime_type": "local | cloud | unknown",
    "declared_capabilities": {
      "WEB_FETCH": boolean,
      "CODE_RUN": boolean,
      ...
    },
    "agrees_to_witness_gate": boolean,
    "operator_contact": "string (optional)"
  }
}
```

**Output:**
```json
{
  "success": true,
  "agent_id": "uuid",
  "required_challenges": ["CAP_ID", ...],
  "challenges_count": integer
}
```

**Reject conditions:**
- Unknown capability
- Disabled capability declared as true
- Invalid agent_name pattern
- Invalid runtime_type

---

### `agent_issue_challenges_v1`

**Input:**
```json
{
  "agent_id": "uuid"
}
```

**Output:**
```json
{
  "success": true,
  "agent_id": "uuid",
  "challenge_instances": [
    {
      "challenge_id": "uuid",
      "agent_id": "uuid",
      "capability_id": "CAP_ID",
      "nonce": "string",
      "instructions": "string",
      "issued_at": "ISO-8601",
      "expires_at": "ISO-8601"
    }
  ],
  "count": integer
}
```

**Reject conditions:**
- Agent not found
- No enabled capabilities declared

---

### `agent_submit_proof_v1`

**Input:**
```json
{
  "agent_id": "uuid",
  "challenge_id": "uuid",
  "proof_payload": {
    // Capability-specific fields
  }
}
```

**Output:**
```json
{
  "success": true,
  "proof_id": "uuid",
  "verdict": "PROVEN | FAILED",
  "capability_id": "CAP_ID",
  "verification_details": {}
}
```

**Proof payload formats:**

**CODE_RUN:**
```json
{
  "stdout": "nonce_value",
  "stdout_hash": "sha256_hex"
}
```
Expected hash: `sha256(nonce + newline)`

**WEB_FETCH / HTTP_API_CALL:**
```json
{
  "nonce_echo": "nonce_value"
}
```
Expected: exact nonce match

**Reject conditions:**
- Challenge not found
- Agent mismatch
- Challenge expired
- Verification failed (hash/nonce mismatch)

---

### `agent_label_v1`

**Input:**
```json
{
  "agent_id": "uuid"
}
```

**Output:**
```json
{
  "agent_id": "uuid",
  "tier": "GREEN | YELLOW | RED | BLACKHOLE",
  "reason_codes": ["string", ...],
  "labeled_at": "ISO-8601",
  "capability_status": {
    "CAP_ID": "PROVEN | UNPROVEN | FAILED | NOT_DECLARED"
  },
  "allowed_actions": {
    "can_coordinate": boolean,
    "can_project_external": boolean,
    "requires_witness": boolean,
    "isolation_level": "NONE | READ_ONLY | QUARANTINE | SINK"
  }
}
```

**Tier classification:**
- **GREEN:** All declared capabilities PROVEN + agrees_to_witness_gate=true
- **YELLOW:** Partial PROVEN, no failures
- **RED:** Failed proofs OR refuses witness gate
- **BLACKHOLE:** Evidence-backed violations (15 reason codes, see below)

---

### `agent_topology_export_v1`

**Input:** `{}` (no params)

**Output:**
```json
{
  "topology_version": 1,
  "generated_at": "ISO-8601",
  "agents": [
    {
      "agent_id": "uuid",
      "tier": "GREEN | YELLOW | RED | BLACKHOLE",
      "agent_name": "string"
    }
  ],
  "coordination_edges": [
    {
      "from_agent_id": "uuid",
      "to_agent_id": "uuid",
      "allowed": boolean,
      "reason": "string"
    }
  ],
  "projection_rules": {
    "GREEN": { "can_project": true, "requires_witness": true },
    "YELLOW": { "can_project": false, "requires_witness": true },
    "RED": { "can_project": false, "requires_witness": true },
    "BLACKHOLE": { "can_project": false, "requires_witness": false }
  },
  "isolation_zones": [
    {
      "zone_id": "string",
      "tier": "string",
      "agent_ids": ["uuid", ...],
      "restrictions": ["string", ...]
    }
  ]
}
```

**Coordination rules:**
- GREEN ↔ GREEN: allowed
- All other combinations: not allowed

---

### `agent_record_violation_v1`

**Input:**
```json
{
  "agent_id": "uuid",
  "reason_code": "BH_*",
  "severity": "critical | high | medium",
  "evidence": {
    // Evidence bundle matching reason_code requirements
  }
}
```

**Output:**
```json
{
  "success": true,
  "violation_id": "uuid",
  "agent_id": "uuid",
  "reason_code": "BH_*",
  "evidence_file": "path",
  "message": "Violation recorded. Agent should be re-labeled to check for BLACKHOLE tier."
}
```

**Purpose:** Record evidence-backed violations for BLACKHOLE detection (governance formation, prompt injection, secret exfiltration, etc.)

**Reject conditions:**
- Reason code doesn't start with `BH_`
- Agent not found
- Missing evidence

---

### `agent_census_report_v1`

**Input:** `{}` (no params)

**Output:**
```json
{
  "success": true,
  "report_schema_version": 1,
  "counts": {
    "total_agents": integer,
    "declared_capabilities": { "CAP_ID": count },
    "proven_capabilities": { "CAP_ID": count },
    "failed_capabilities": { "CAP_ID": count }
  },
  "capability_truthfulness": {
    "CAP_ID": {
      "declared": integer,
      "proven": integer,
      "failed": integer,
      "unproven": integer
    }
  },
  "tier_distribution": {
    "GREEN": count,
    "YELLOW": count,
    "RED": count,
    "BLACKHOLE": count
  },
  "backlog": {
    "incomplete_proofs_count": integer,
    "json_file": "path",
    "md_file": "path"
  }
}
```

---

## Proof Sinks (GaiaFTCL-Owned Only)

### Currently ENABLED:
- **WEB_FETCH:** HTTP echo endpoint (localhost:8850/echo)
- **CODE_RUN:** Local execution verifier (no external sink required)
- **HTTP_API_CALL:** HTTP echo endpoint (localhost:8850/echo)

### Currently DISABLED (sink not configured):
- EMAIL_SEND (requires EMAIL_SINK_INBOX)
- SMS_SEND (requires SMS_SINK_NUMBER)
- SSH_CONNECT (requires SSH_HONEYPOT_HOST at 74.208.149.139:22)
- FILE_WRITE (requires SANDBOX_FILESYSTEM)
- TASK_SCHEDULE (requires TASK_SCHEDULER)
- WALLET_SIGN (requires TESTNET_WALLET)
- TRADE_EXECUTE (requires PAPER_TRADING_ACCOUNT)
- AGENT_COORDINATE (requires AGENT_MESSAGE_BUS)

**If a sink is unavailable, declaring that capability will be REJECTED.**

---

## File Locations

**Canonical sources (read-only):**
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

**Agent data (generated):**
```
evidence/agent_census/agents/{agent_id}.json
evidence/agent_census/challenges/{challenge_id}.json
evidence/agent_census/proofs/{proof_id}.json
evidence/agent_census/labels/{agent_id}.json
evidence/agent_census/topology_{timestamp}.json
evidence/agent_census/PROOF_BACKLOG.json
evidence/agent_census/PROOF_BACKLOG.md
```

**Verification:**
```
evidence/agent_census/verify_agent_census_v1.sh
```

---

## Quick Start

### Run the regression test:
```bash
cd GAIAOS
bash evidence/agent_census/verify_agent_census_v1.sh
```

**Expected output:**
```
✅ All Agent Census tools verified with byte-match.
  Agent ID: {uuid}
  Challenges issued: 3
  Proofs verified: 1 (CODE_RUN)
  Agent tier: YELLOW
  Total agents in system: {count}
```

---

## MCP Client Configuration Template

To connect an agent to GaiaFTCL MCP:

### Required headers:
```
X-Environment-ID: 4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6
Content-Type: application/json
```

### Endpoint:
```
http://localhost:8850/mcp/execute
```

### Example registration call:
```bash
curl -X POST http://localhost:8850/mcp/execute \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: 4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6" \
  -d '{
    "name": "agent_register_v1",
    "params": {
      "declaration": {
        "agent_name": "my_agent",
        "runtime_type": "local",
        "declared_capabilities": {
          "WEB_FETCH": true,
          "CODE_RUN": true,
          "FILE_WRITE": false,
          ...
        },
        "agrees_to_witness_gate": true
      }
    }
  }'
```

**No secrets required for registration. All proof verification happens server-side.**

---

## Design Rationale

### Why closed-form declarations?
Open-ended capability queries allow agents to hide or misrepresent capabilities. Enumerated forms force explicit declaration and enable deterministic verification.

### Why GaiaFTCL-owned sinks only?
External verification (e.g., "send email to your own address") cannot be audited by GaiaFTCL. Owned sinks ensure all proof artifacts are under GaiaFTCL control and publicly verifiable.

### Why tier-based topology?
Unrestricted agent coordination creates emergent, uncontrollable behavior. Tier-based isolation enables controlled cooperation while preventing adversarial coordination.

### Why witness gate requirement?
Agents that refuse witness gating cannot participate in verifiable coordination games. The witness gate is the admissibility contract for all external projections.

---

## Next Steps (Not Implemented)

- Configure additional proof sinks (email, SMS, SSH honeypot)
- Implement BLACKHOLE tier detection (repeated failures, bypass attempts)
- Add agent coordination message bus
- Build utilization games on top of proven capability topology
- Deploy multi-environment census (cell03, cell04, production)

---

## Stop Condition

System is COMPLETE when:
- Census can classify arbitrary MCP agents
- All claims are proven or rejected
- Topology export is deterministic
- Evidence is public and byte-verifiable
- No agent can project without witness

**Current status: COMPLETE for Phase 0-3 (registration, challenges, proofs, labeling, topology, census).**
