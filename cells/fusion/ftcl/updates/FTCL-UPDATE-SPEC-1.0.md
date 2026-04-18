# FTCL-UPDATE-SPEC-1.0 — Closed Fleet Update Protocol

**Status:** CANONICAL  
**Supersedes:** Watchtower-based auto-update (VOIDED)  
**Effective:** Immediately upon ratification  

---

## 1. VOID WATCHTOWER PATH

### 1.1 Declaration

The following are declared **NON-CANONICAL** for production GaiaFTCL deployments:

- `containrrr/watchtower` and all derivatives
- Any `:latest` tag polling mechanism
- Any image reference by mutable tag (e.g., `image: ghcr.io/gaiaftcl/service:latest`)
- Any "auto-pull on registry change" mechanism

### 1.2 Supersession Note

**Any cell running Watchtower or equivalent polling auto-updater is OUT-OF-CONSTITUTION.**

Such cells MUST:
1. Emit `FAILURE` status on all health endpoints
2. Refuse to participate in games
3. Be excluded from mesh routing until remediated

### 1.3 Violation Classification

```
UNAUTHORIZED_MUTATION: Any container restart that changes code without 
a preceding COMMITMENT+TRANSACTION referencing a signed digest set.

Consequence: Immediate FAILURE state, quarantine from mesh.
```

---

## 2. CLOSED UPDATE GAME: G_FTCL_UPDATE_FLEET_V1

### 2.1 Game Definition

```yaml
game_id: G_FTCL_UPDATE_FLEET_V1
version: 1.0.0
type: FLEET_UPDATE
closure: STRICT

description: |
  Canonical game for updating GaiaFTCL fleet to a new digest set.
  All updates MUST go through this game. No exceptions.

move_order:
  - REQUEST      # Propose update with target digest set
  - COMMITMENT   # Accept quote, lock fee
  - TRANSACTION  # Pay fee, authorize execution
  - REPORT       # Per-cell execution reports + finalization

skip_allowed: false
fee_timing: UPFRONT  # Fee MUST clear before any build/pull/restart
```

### 2.2 Move Specifications

#### REQUEST Move

```yaml
move: REQUEST
from: <proposer_entity>@gaiaftcl.com
to: governance@gaiaftcl.com

envelope:
  X-FTCL-Type: REQUEST
  X-FTCL-Game: G_FTCL_UPDATE_FLEET_V1
  X-FTCL-Domain: INFRASTRUCTURE
  X-FTCL-Value-ID: <sha256 of payload>

payload:
  action: PROPOSE_UPDATE
  target_digest_set: <FTCL_DIGESTSET_<version>.json hash>
  target_digest_set_url: <signed URL to digest set>
  source_commit: <git commit hash>
  constitution_hash: <hash of current constitution>
  reason: <human-readable justification>
  rollout_strategy: canary|ring1|ring2|immediate
  
response:
  quote:
    request_evaluation_fee: <QFOT amount>
    fleet_update_fee: <QFOT amount>
    per_cell_restart_fee: <QFOT amount per cell>
    total_cells: <count>
    total_fee: <sum>
    valid_until: <timestamp>
  digest_set_verification:
    verified: true|false
    attestations_valid: true|false
    sbom_hashes: [...]
    provenance_hashes: [...]
```

#### COMMITMENT Move

```yaml
move: COMMITMENT
from: <proposer_entity>@gaiaftcl.com
to: governance@gaiaftcl.com

envelope:
  X-FTCL-Type: COMMITMENT
  X-FTCL-Game: G_FTCL_UPDATE_FLEET_V1
  X-FTCL-Cost: <total_fee from quote>
  X-FTCL-Value-ID: <sha256 of payload>

payload:
  action: ACCEPT_QUOTE
  quote_hash: <hash of received quote>
  target_digest_set: <same as REQUEST>
  payment_authorization: <signed authorization>
  
preconditions:
  - Quote must not be expired
  - Digest set must still be available
  - All attestations must still verify
```

#### TRANSACTION Move

```yaml
move: TRANSACTION
from: ledger@gaiaftcl.com
to: governance@gaiaftcl.com

envelope:
  X-FTCL-Type: TRANSACTION
  X-FTCL-Game: G_FTCL_UPDATE_FLEET_V1
  X-FTCL-Value-ID: <sha256 of payload>

payload:
  action: FEE_CLEARED
  commitment_hash: <hash of COMMITMENT>
  amount: <QFOT transferred>
  from_account: <payer>
  to_account: governance@gaiaftcl.com
  transaction_proof: <on-chain or AKG proof>
  
postconditions:
  - Fee is locked, non-refundable except via rollback game
  - Update execution is now AUTHORIZED
```

#### REPORT Move (Per-Cell + Final)

```yaml
move: REPORT
from: <cell_id>@gaiaftcl.com | governance@gaiaftcl.com
to: founder@gaiaftcl.com

envelope:
  X-FTCL-Type: REPORT
  X-FTCL-Game: G_FTCL_UPDATE_FLEET_V1
  X-FTCL-Value-ID: <sha256 of payload>

# Per-cell report
payload_cell:
  action: CELL_UPDATE_COMPLETE
  cell_id: <cell>
  stage: canary|ring1|ring2
  prior_digest_set: <hash>
  new_digest_set: <hash>
  services_restarted: [list with digests]
  health_gates:
    email_outbound: PASS|FAIL
    mcp_call: PASS|FAIL
    ledger_write_read: PASS|FAIL
    replay_determinism: PASS|FAIL
  attestation_verification: PASS|FAIL
  
# Final report (from governance)
payload_final:
  action: FLEET_UPDATE_FINALIZED
  transaction_hash: <from TRANSACTION>
  cells_updated: [list]
  cells_failed: [list]
  rollback_triggered: true|false
  final_digest_set: <hash>
  total_cost: <QFOT>
```

---

## 3. DIGEST-PINNING LAW

### 3.1 Immutable Reference Requirement

**All production images MUST be referenced by immutable digest, NEVER by tag.**

```yaml
# FORBIDDEN
image: ghcr.io/gaiaftcl/quantum-substrate:latest
image: ghcr.io/gaiaftcl/virtue-engine:v1.0.0

# REQUIRED
image: ghcr.io/gaiaftcl/quantum-substrate@sha256:a1b2c3d4e5f6...
image: ghcr.io/gaiaftcl/virtue-engine@sha256:f6e5d4c3b2a1...
```

### 3.2 Digest Set Schema

```json
{
  "$schema": "https://gaiaftcl.com/schemas/digestset-1.0.json",
  "version": "1.0.0",
  "digest_set_id": "FTCL_DIGESTSET_20260119_001",
  "created_at": "2026-01-19T14:30:00Z",
  "source_commit": "abc123def456...",
  "constitution_hash": "sha256:...",
  
  "images": {
    "quantum-substrate": {
      "digest": "sha256:a1b2c3d4e5f6...",
      "sbom_hash": "sha256:...",
      "provenance_hash": "sha256:...",
      "build_time": "2026-01-19T14:00:00Z"
    },
    "virtue-engine": {
      "digest": "sha256:f6e5d4c3b2a1...",
      "sbom_hash": "sha256:...",
      "provenance_hash": "sha256:...",
      "build_time": "2026-01-19T14:00:00Z"
    },
    "mcp-gateway": {
      "digest": "sha256:...",
      "sbom_hash": "sha256:...",
      "provenance_hash": "sha256:...",
      "build_time": "2026-01-19T14:00:00Z"
    },
    "franklin-guardian": {
      "digest": "sha256:...",
      "sbom_hash": "sha256:...",
      "provenance_hash": "sha256:...",
      "build_time": "2026-01-19T14:00:00Z"
    },
    "fara-agent": {
      "digest": "sha256:...",
      "sbom_hash": "sha256:...",
      "provenance_hash": "sha256:...",
      "build_time": "2026-01-19T14:00:00Z"
    },
    "game-runner": {
      "digest": "sha256:...",
      "sbom_hash": "sha256:...",
      "provenance_hash": "sha256:...",
      "build_time": "2026-01-19T14:00:00Z"
    }
  },
  
  "attestations": {
    "build_provenance": "sha256:...",
    "sbom_aggregate": "sha256:...",
    "constitution_binding": "sha256:..."
  },
  
  "signatures": {
    "governance": "<signature>",
    "franklin": "<signature>"
  },
  
  "root_hash": "sha256:..."
}
```

### 3.3 Cell Update Validation

Every cell update MUST:

1. Receive the digest set hash (root_hash) in the COMMITMENT
2. Fetch and verify the digest set against root_hash
3. Verify all attestations match declared hashes
4. Verify constitution_hash matches current constitution
5. **REFUSE UPDATE if any verification fails**

---

## 4. ATTESTATION AND SBOM REQUIREMENT

### 4.1 Required Attestations Per Image

For every image in a digest set, the following MUST be produced and stored:

| Attestation | Description | Storage |
|-------------|-------------|---------|
| `sbom_hash` | SPDX/CycloneDX SBOM of image contents | AKG + GHCR attestation |
| `provenance_hash` | SLSA provenance attestation | AKG + GHCR attestation |
| `source_commit` | Git commit that produced the build | AKG |
| `constitution_hash` | Hash of FTCL-UNI-CLOSURE + FTCL-ECON + FTCL-SEED | AKG |

### 4.2 Verification Gate

**Update CANNOT finalize unless:**

```python
def verify_attestations(digest_set, constitution):
    for service, info in digest_set["images"].items():
        # Fetch attestation from GHCR
        attestation = ghcr.get_attestation(info["digest"])
        
        # Verify SBOM hash matches
        assert hash(attestation.sbom) == info["sbom_hash"]
        
        # Verify provenance hash matches
        assert hash(attestation.provenance) == info["provenance_hash"]
        
        # Verify source commit matches
        assert attestation.provenance.source_commit == digest_set["source_commit"]
        
        # Verify constitution hash matches current
        assert digest_set["constitution_hash"] == hash(constitution)
    
    return True  # All verified
```

---

## 5. STAGED ROLLOUT WITH HEALTH GATES

### 5.1 Rollout Stages

| Stage | Cells | Percentage | Wait Before Next |
|-------|-------|------------|------------------|
| `canary` | 1 cell (hel1-05) | ~20% | All gates pass |
| `ring1` | +1 cell (hel1-04) | ~40% | All gates pass |
| `ring2` | Remaining cells | 100% | N/A |

### 5.2 Health Gates Per Stage

Each stage MUST pass ALL gates before proceeding:

```yaml
health_gates:
  email_outbound:
    test: "Send signed REPORT via SMTP to test@gaiaftcl.com"
    verification: "Receive delivery confirmation"
    timeout: 60s
    
  mcp_call:
    test: "Invoke gaiaos_health via MCP gateway"
    verification: "Receive valid response with matching cell_id"
    timeout: 30s
    
  ledger_write_read:
    test: "Write test document to AKG, read back"
    verification: "Content matches, timestamps valid"
    timeout: 30s
    
  replay_determinism:
    test: "Query current digest set from cell"
    verification: "Matches the digest set from COMMITMENT"
    timeout: 10s
```

### 5.3 Failure Policy

**If ANY gate fails at ANY stage:**

1. HALT rollout immediately
2. Trigger automatic rollback on affected cells
3. Emit FAILURE REPORT with gate details
4. Rollback to prior verified digest set
5. Fee is NOT refunded (work was performed)
6. New update attempt requires new game instance

---

## 6. ROLLBACK GAME: G_FTCL_ROLLBACK_V1

### 6.1 Game Definition

```yaml
game_id: G_FTCL_ROLLBACK_V1
version: 1.0.0
type: FLEET_ROLLBACK
closure: STRICT

description: |
  Canonical game for rolling back GaiaFTCL fleet to a prior digest set.
  Same closure requirements as update game.

move_order:
  - REQUEST      # Specify target (prior) digest set
  - COMMITMENT   # Accept quote, lock fee
  - TRANSACTION  # Pay fee, authorize execution
  - REPORT       # Per-cell rollback reports + finalization

skip_allowed: false
fee_timing: UPFRONT
```

### 6.2 Rollback Validation

Before rollback can proceed:

1. Target digest set MUST be a previously-finalized set (in AKG history)
2. All images in target digest set MUST still be available (registry or cache)
3. Attestations for target digest set MUST still verify
4. If any image is unavailable → ROLLBACK FAILS → manual intervention required

---

## 7. CREDENTIALS AND AUTH

### 7.1 Prohibition

**The following are FORBIDDEN:**

```bash
# FORBIDDEN - cleartext credentials
echo -n "USERNAME:PAT" | base64
AUTH=$(echo -n "${GITHUB_USER}:${GITHUB_PAT}" | base64)

# FORBIDDEN - embedded in compose
environment:
  - REPO_USER=your-username
  - REPO_PASS=your-github-pat
```

### 7.2 Required Credential Management

| Requirement | Implementation |
|-------------|----------------|
| Per-cell tokens | Each cell has unique registry token |
| Least-privilege | Tokens have `read:packages` only, no write |
| Encrypted at rest | Tokens stored in cell keystore (encrypted) |
| Rotation game | G_SECRET_ROTATE_V1 for token rotation |
| Audit trail | All token usage logged to AKG |

### 7.3 Token Rotation Game

```yaml
game_id: G_SECRET_ROTATE_V1
version: 1.0.0
type: SECRET_ROTATION

move_order:
  - REQUEST      # Specify which secret to rotate
  - COMMITMENT   # Authorize rotation
  - TRANSACTION  # Fee payment
  - REPORT       # Rotation proof (old hash → new hash)
```

---

## 8. ACTION TRIGGER RULE

### 8.1 GitHub Actions Scope

**GitHub Actions MAY:**
- Build images from source
- Push images to GHCR
- Generate attestations and SBOMs
- Create CANDIDATE digest sets
- Emit PROPOSAL suggestions

**GitHub Actions MAY NOT:**
- Directly trigger production deployment
- Modify running cells
- Execute any code on production infrastructure

### 8.2 Deployment Gate

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DEPLOYMENT AUTHORIZATION                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   "Docs changed" or "Code pushed"                                   │
│         │                                                           │
│         ▼                                                           │
│   GitHub Actions builds candidate images                            │
│         │                                                           │
│         ▼                                                           │
│   Candidate digest set published (NOT deployed)                     │
│         │                                                           │
│         ▼                                                           │
│   PROPOSAL emitted to governance@gaiaftcl.com                       │
│         │                                                           │
│         ▼                                                           │
│   ════════════════════════════════════════════════                  │
│   ║  HUMAN OR AUTHORIZED ENTITY DECISION POINT  ║                  │
│   ════════════════════════════════════════════════                  │
│         │                                                           │
│         ▼                                                           │
│   G_FTCL_UPDATE_FLEET_V1 REQUEST initiated                          │
│         │                                                           │
│         ▼                                                           │
│   COMMITMENT + TRANSACTION (fee paid)                               │
│         │                                                           │
│         ▼                                                           │
│   Staged rollout with health gates                                  │
│         │                                                           │
│         ▼                                                           │
│   FINALIZED or ROLLED BACK                                          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 9. ECONOMICS

### 9.1 Update Pricing

| Action | Fee (QFOT) | Recipient |
|--------|------------|-----------|
| Update proposal evaluation (REQUEST) | 10 | governance |
| Fleet update execution (COMMITMENT) | 100 | governance |
| Per-cell restart (REPORT) | 5/cell | cell operator |
| Rollback (COMMITMENT) | 50 | governance |
| Secret rotation (COMMITMENT) | 20 | governance |

### 9.2 Quote Transparency

Every REQUEST response MUST include a signed quote:

```json
{
  "quote_id": "Q-20260119-001",
  "game": "G_FTCL_UPDATE_FLEET_V1",
  "breakdown": {
    "request_evaluation": 10,
    "fleet_update_base": 100,
    "cell_restarts": {
      "count": 5,
      "per_cell": 5,
      "subtotal": 25
    }
  },
  "total": 135,
  "currency": "QFOT",
  "valid_until": "2026-01-19T15:30:00Z",
  "signature": "<governance signature>"
}
```

---

## 10. OUTPUTS REQUIRED

This specification requires the following artifacts to be produced:

### A) This Document
- `ftcl/updates/FTCL-UPDATE-SPEC-1.0.md` ✓

### B) Game Definitions
- `ftcl/games/G_FTCL_UPDATE_FLEET_V1.yaml`
- `ftcl/games/G_FTCL_ROLLBACK_V1.yaml`
- `ftcl/games/G_SECRET_ROTATE_V1.yaml`

### C) Digest Set Schema
- `ftcl/schemas/digestset-1.0.json`
- `ftcl/digestsets/FTCL_DIGESTSET_EXAMPLE.json`

### D) Watchtower Removal Migration
- `scripts/remove-watchtower.sh`
- Migration steps documented

### E) Per-Cell Updater Service
- `services/cell_updater/` - Pull-by-digest + verify attestations + restart
- Design specification

---

## ENFORCEMENT

### Critical Rule

> **Any container restart that changes code without a preceding COMMITMENT+TRANSACTION referencing a digest set is treated as an unauthorized mutation and must emit FAILURE immediately.**

### Compliance Check

Each cell MUST run a compliance checker that:

1. Monitors all container restarts
2. Verifies each restart has a corresponding TRANSACTION in AKG
3. Verifies running digest matches authorized digest set
4. Emits FAILURE and quarantines if violation detected

---

## RATIFICATION

This specification becomes CANONICAL upon:

1. Signature by `governance@gaiaftcl.com`
2. Signature by `franklin@gaiaftcl.com`
3. Publication to AKG with immutable hash
4. Emission of REPORT to all cells

---

**Document Hash:** `<to be computed on finalization>`  
**Constitution Binding:** FTCL-UNI-CLOSURE-2.0 §3, §7  
**Author:** governance@gaiaftcl.com  
**Date:** 2026-01-19  
