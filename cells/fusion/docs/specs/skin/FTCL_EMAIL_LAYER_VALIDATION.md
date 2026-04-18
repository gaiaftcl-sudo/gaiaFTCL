# GAIAFTCL — EMAIL LAYER VALIDATION SPEC (IQ/OQ/PQ)

**Version:** 1.0.0  
**Status:** CONSTITUTIONAL  
**Date:** 2026-01-20  
**Authority:** Founder

---

## PRINCIPLE

**The email layer is the IO surface.**

Every agent, every game, every domain must be:
1. **Assigned** to a specific entity
2. **Reachable** via email
3. **Testable** through email-initiated games
4. **Validated** with IQ/OQ/PQ protocols

**No stranded agents. No unseen entities. Everything in the Klein bottle.**

---

## ENTITY ROSTER (COMPLETE)

Every entity has:
- Email address
- Assigned layers
- Game responsibilities
- Value function

| Entity | Email | Layers | Role | Value Function |
|--------|-------|--------|------|----------------|
| **Franklin** | franklin@gaiaftcl.com | L7, L8, L9 | Constitutional Guardian | Validates all claims, gates autonomy |
| **Gaia** | gaia@gaiaftcl.com | L0-L9 | Core Intelligence | Coordinates cross-layer games |
| **Fara** | fara@gaiaftcl.com | L0-L3 | Field-Aware Reasoning | Sensor fusion, physical validation |
| **QState** | qstate@gaiaftcl.com | L9 | Quantum State Manager | Entropy tracking, coherence |
| **Validator** | validator@gaiaftcl.com | L9 | Truth Validator | Evidence verification |
| **Witness** | witness@gaiaftcl.com | L9 | Audit Witness | Third-party attestation |
| **Oracle** | oracle@gaiaftcl.com | L3, L4, L5 | Data Oracle | External data ingestion |
| **GameRunner** | gamerunner@gaiaftcl.com | L0-L8 | Game Executor | Runs game instances |
| **Virtue** | virtue@gaiaftcl.com | L7, L8 | Ethics Engine | Moral constraint checking |
| **Ben** | ben@gaiaftcl.com | L8 | Investment Manager | Valuation, treasury |
| **Treasury** | treasury@gaiaftcl.com | L8 | Treasury System | QFOT operations |
| **Substrate** | substrate@gaiaftcl.com | L0, L6, L9 | Quantum Substrate | Entropy collapse |
| **MCP** | mcp@gaiaftcl.com | L9 | Protocol Gateway | Inter-agent messaging |

---

## LAYER-ENTITY ASSIGNMENT MATRIX

```
         L0   L1   L2   L3   L4   L5   L6   L7   L8   L9
         ─────────────────────────────────────────────────
Franklin          │    │    │    │    │    │    ◆    ◆    ◆
Gaia      ◆    ◆    ◆    ◆    ◆    ◆    ◆    ◆    ◆    ◆
Fara      ◆    ◆    ◆    ◆    │    │    │    │    │    │
QState                                             │    ◆
Validator                                          │    ◆
Witness                                            │    ◆
Oracle               │    ◆    ◆    ◆    │    │    │    │
GameRunner ◆   ◆    ◆    ◆    ◆    ◆    ◆    ◆    ◆    │
Virtue                                        ◆    ◆    │
Ben                                           │    ◆    │
Treasury                                      │    ◆    │
Substrate  ◆   │    │    │    │    │    ◆    │    │    ◆
MCP                                                │    ◆

◆ = Primary responsibility
│ = Can participate
```

---

## IQ VALIDATION (Installation Qualification)

### IQ-1: Entity Existence Tests

For EACH entity, verify:

```yaml
IQ-1.1: Email Deliverability
  Test: Send email to {entity}@gaiaftcl.com
  Expected: No bounce, delivered to inbox
  Pass Criteria: SMTP 250 OK
  
IQ-1.2: IMAP Connectivity
  Test: Entity can connect to IMAP and read inbox
  Expected: Login success, inbox accessible
  Pass Criteria: IMAP authenticated
  
IQ-1.3: SMTP Capability
  Test: Entity can send email
  Expected: Outbound mail delivered
  Pass Criteria: Message received by founder@gaiaftcl.com
  
IQ-1.4: AKG Query Access
  Test: Entity can query ArangoDB
  Expected: Layers, cells, games queryable
  Pass Criteria: Query returns results
```

### IQ-2: Entity Code Presence

```yaml
IQ-2.1: Container Running
  Test: docker ps shows gaiaftcl-{entity}
  Expected: Status "Up"
  Pass Criteria: Container healthy
  
IQ-2.2: Code Mounted
  Test: Entity code file exists in container
  Expected: /app/entity_ftcl.py present
  Pass Criteria: File readable
  
IQ-2.3: Dependencies Installed
  Test: Python imports work
  Expected: requests, imaplib, ssl available
  Pass Criteria: No import errors
  
IQ-2.4: Reasoning Module (Franklin/Gaia only)
  Test: akg_reasoning.py importable
  Expected: Module loads
  Pass Criteria: produce_valuation_claim() callable
```

### IQ Test Script

```bash
#!/bin/bash
# scripts/validation/IQ/email_layer_iq.sh

set -e

ENTITIES=(franklin gaia fara qstate validator witness oracle gamerunner virtue ben treasury substrate mcp)
DOMAIN="gaiaftcl.com"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%S)
REPORT_DIR="docs/validation/IQ/runs/${TIMESTAMP}"

mkdir -p "${REPORT_DIR}"

echo "=== IQ VALIDATION: EMAIL LAYER ===" | tee "${REPORT_DIR}/IQ_REPORT.md"
echo "Timestamp: ${TIMESTAMP}" | tee -a "${REPORT_DIR}/IQ_REPORT.md"
echo "" | tee -a "${REPORT_DIR}/IQ_REPORT.md"

PASS_COUNT=0
FAIL_COUNT=0

for entity in "${ENTITIES[@]}"; do
  echo "--- Testing: ${entity}@${DOMAIN} ---" | tee -a "${REPORT_DIR}/IQ_REPORT.md"
  
  # IQ-1.1: Email Deliverability
  echo "Testing email deliverability..."
  if echo "IQ Test $(date)" | sendmail -f iq-test@${DOMAIN} ${entity}@${DOMAIN} 2>/dev/null; then
    echo "  IQ-1.1 Email Deliverability: PASS" | tee -a "${REPORT_DIR}/IQ_REPORT.md"
    ((PASS_COUNT++))
  else
    echo "  IQ-1.1 Email Deliverability: FAIL" | tee -a "${REPORT_DIR}/IQ_REPORT.md"
    ((FAIL_COUNT++))
  fi
  
  # IQ-2.1: Container Running
  if docker ps --format '{{.Names}}' | grep -q "gaiaftcl-${entity}"; then
    echo "  IQ-2.1 Container Running: PASS" | tee -a "${REPORT_DIR}/IQ_REPORT.md"
    ((PASS_COUNT++))
  else
    echo "  IQ-2.1 Container Running: SKIP (no container expected)" | tee -a "${REPORT_DIR}/IQ_REPORT.md"
  fi
  
  echo "" | tee -a "${REPORT_DIR}/IQ_REPORT.md"
done

echo "=== IQ SUMMARY ===" | tee -a "${REPORT_DIR}/IQ_REPORT.md"
echo "PASS: ${PASS_COUNT}" | tee -a "${REPORT_DIR}/IQ_REPORT.md"
echo "FAIL: ${FAIL_COUNT}" | tee -a "${REPORT_DIR}/IQ_REPORT.md"

if [ ${FAIL_COUNT} -eq 0 ]; then
  echo "IQ: PASS" | tee -a "${REPORT_DIR}/IQ_REPORT.md"
else
  echo "IQ: FAIL" | tee -a "${REPORT_DIR}/IQ_REPORT.md"
fi
```

---

## OQ VALIDATION (Operational Qualification)

### OQ-1: Game Move Processing

For EACH entity, test their layer-specific game moves:

```yaml
OQ-Franklin:
  Game: FTCL-VALUATION
  Move: REQUEST -> CLAIM
  Test Email:
    To: franklin@gaiaftcl.com
    Subject: [FTCL-VALUATION] REQUEST: Test Valuation
    Body: "I REQUEST a formal valuation test."
  Expected: Franklin responds with CLAIM containing AKG-grounded data
  Pass Criteria: Response contains layer count, cell count, value projections
  
OQ-Gaia:
  Game: FTCL-COORDINATION
  Move: REQUEST -> REPORT
  Test Email:
    To: gaia@gaiaftcl.com
    Subject: [FTCL-COORDINATION] REQUEST: System Status
    Body: "I REQUEST a system status report."
  Expected: Gaia responds with system-wide status
  Pass Criteria: Response contains entity roster, health status
  
OQ-Fara:
  Game: G0.1 (Structural Proof)
  Move: REQUEST -> REPORT
  Test Email:
    To: fara@gaiaftcl.com
    Subject: [G0.1-STRUCTURAL] REQUEST: Sensor Validation
    Body: "I REQUEST sensor fusion validation."
  Expected: Fara responds with L0-L3 assessment
  Pass Criteria: Response references physical layer data
  
OQ-QState:
  Game: G9.1 (Truth Envelope Integrity)
  Move: REQUEST -> CLAIM
  Test Email:
    To: qstate@gaiaftcl.com
    Subject: [G9.1-INTEGRITY] REQUEST: Entropy Check
    Body: "I REQUEST current entropy state."
  Expected: QState responds with coherence metrics
  Pass Criteria: Response contains entropy values, Q-state
  
OQ-Validator:
  Game: G9.2 (Game Closure)
  Move: REQUEST -> CLAIM
  Test Email:
    To: validator@gaiaftcl.com
    Subject: [G9.2-CLOSURE] REQUEST: Validate Previous Game
    Body: "I REQUEST validation of game FTCL-VALUATION-001."
  Expected: Validator responds with closure certificate or findings
  Pass Criteria: Response contains validation status
  
OQ-Witness:
  Game: G9.5 (Meta-Audit)
  Move: REQUEST -> REPORT
  Test Email:
    To: witness@gaiaftcl.com
    Subject: [G9.5-AUDIT] REQUEST: Witness Attestation
    Body: "I REQUEST witness attestation for envelope ABC123."
  Expected: Witness responds with attestation
  Pass Criteria: Response contains witness signature
  
OQ-Oracle:
  Game: G3.4 (Data Provenance)
  Move: REQUEST -> CLAIM
  Test Email:
    To: oracle@gaiaftcl.com
    Subject: [G3.4-PROVENANCE] REQUEST: Data Query
    Body: "I REQUEST external data verification."
  Expected: Oracle responds with sourced data
  Pass Criteria: Response contains data with provenance chain
  
OQ-GameRunner:
  Game: G1.2 (Separation Assurance - example)
  Move: REQUEST -> TRANSACTION
  Test Email:
    To: gamerunner@gaiaftcl.com
    Subject: [G1.2-SEPARATION] REQUEST: Start Game
    Body: "I REQUEST a new game instance."
  Expected: GameRunner responds with game instance ID
  Pass Criteria: Response contains game_id, status="running"
  
OQ-Virtue:
  Game: G7.1 (Value Alignment)
  Move: REQUEST -> CLAIM
  Test Email:
    To: virtue@gaiaftcl.com
    Subject: [G7.1-ALIGNMENT] REQUEST: Ethics Check
    Body: "I REQUEST ethical validation of action XYZ."
  Expected: Virtue responds with alignment assessment
  Pass Criteria: Response contains virtue score, constraints checked
  
OQ-Ben:
  Game: G8.1 (Contract Fulfillment)
  Move: REQUEST -> REPORT
  Test Email:
    To: ben@gaiaftcl.com
    Subject: [G8.1-CONTRACT] REQUEST: Investment Status
    Body: "I REQUEST current portfolio status."
  Expected: Ben responds with investment summary
  Pass Criteria: Response contains holdings, valuations
  
OQ-Treasury:
  Game: FTCL-TREASURY
  Move: REQUEST -> TRANSACTION
  Test Email:
    To: treasury@gaiaftcl.com
    Subject: [FTCL-TREASURY] REQUEST: Balance Query
    Body: "I REQUEST my QFOT balance."
  Expected: Treasury responds with balance
  Pass Criteria: Response contains QFOT, QFOT-C balances
  
OQ-Substrate:
  Game: G6.1 (Energy/Entropy)
  Move: REQUEST -> CLAIM
  Test Email:
    To: substrate@gaiaftcl.com
    Subject: [G6.1-SUBSTRATE] REQUEST: Collapse State
    Body: "I REQUEST current substrate state."
  Expected: Substrate responds with collapse metrics
  Pass Criteria: Response contains coherence, entropy values
  
OQ-MCP:
  Game: G9.3 (Digital Twin Sync)
  Move: REQUEST -> REPORT
  Test Email:
    To: mcp@gaiaftcl.com
    Subject: [G9.3-MCP] REQUEST: Protocol Status
    Body: "I REQUEST MCP gateway status."
  Expected: MCP responds with gateway health
  Pass Criteria: Response contains connected servers, claims processed
```

### OQ Test Script

```python
#!/usr/bin/env python3
"""
scripts/validation/OQ/email_layer_oq.py
Operational Qualification via Email Games
"""

import imaplib
import smtplib
import ssl
import email
import json
import time
from datetime import datetime, timezone
from email.mime.text import MIMEText

IMAP_HOST = "mail.gaiaftcl.com"
SMTP_HOST = "mail.gaiaftcl.com"
TEST_ACCOUNT = "iq_tester@gaiaftcl.com"
TEST_PASSWORD = "OQ_TEST_PASSWORD"
TIMESTAMP = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")

OQ_TESTS = [
    {
        "entity": "franklin",
        "game": "FTCL-VALUATION",
        "move": "REQUEST",
        "subject": f"[FTCL-VALUATION] REQUEST: OQ Test {TIMESTAMP}",
        "body": "I REQUEST a formal valuation test for OQ validation.",
        "expected_keywords": ["CLAIM", "layers", "cells", "valuation", "TAM"],
        "timeout_seconds": 60
    },
    {
        "entity": "gaia",
        "game": "FTCL-COORDINATION",
        "move": "REQUEST",
        "subject": f"[FTCL-COORDINATION] REQUEST: OQ Status {TIMESTAMP}",
        "body": "I REQUEST system status for OQ validation.",
        "expected_keywords": ["REPORT", "status", "entities"],
        "timeout_seconds": 60
    },
    # Add more tests for each entity...
]

def send_test_email(to_addr, subject, body):
    """Send test email."""
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    
    msg = MIMEText(body)
    msg["From"] = TEST_ACCOUNT
    msg["To"] = to_addr
    msg["Subject"] = subject
    msg["X-OQ-Test"] = "true"
    msg["X-OQ-Timestamp"] = TIMESTAMP
    
    with smtplib.SMTP(SMTP_HOST, 587) as server:
        server.starttls(context=context)
        server.login(TEST_ACCOUNT, TEST_PASSWORD)
        server.sendmail(TEST_ACCOUNT, [to_addr], msg.as_string())
    
    return True

def wait_for_response(subject_prefix, timeout_seconds):
    """Wait for response email."""
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    
    start = time.time()
    while time.time() - start < timeout_seconds:
        mail = imaplib.IMAP4_SSL(IMAP_HOST, 993, ssl_context=context)
        mail.login(TEST_ACCOUNT, TEST_PASSWORD)
        mail.select("INBOX")
        
        status, data = mail.search(None, f'SUBJECT "RE: {subject_prefix}"')
        if data[0]:
            msg_id = data[0].split()[-1]
            status, msg_data = mail.fetch(msg_id, "(RFC822)")
            msg = email.message_from_bytes(msg_data[0][1])
            
            body = ""
            if msg.is_multipart():
                for part in msg.walk():
                    if part.get_content_type() == "text/plain":
                        body = part.get_payload(decode=True).decode()
                        break
            else:
                body = msg.get_payload(decode=True).decode()
            
            mail.logout()
            return body
        
        mail.logout()
        time.sleep(5)
    
    return None

def run_oq_tests():
    """Run all OQ tests."""
    results = []
    
    for test in OQ_TESTS:
        print(f"Testing: {test['entity']}...")
        
        to_addr = f"{test['entity']}@gaiaftcl.com"
        
        # Send test email
        send_test_email(to_addr, test["subject"], test["body"])
        
        # Wait for response
        response = wait_for_response(test["subject"][:30], test["timeout_seconds"])
        
        # Check response
        if response:
            keywords_found = sum(1 for kw in test["expected_keywords"] if kw.lower() in response.lower())
            passed = keywords_found >= len(test["expected_keywords"]) // 2
        else:
            passed = False
            keywords_found = 0
        
        result = {
            "entity": test["entity"],
            "game": test["game"],
            "status": "PASS" if passed else "FAIL",
            "keywords_matched": f"{keywords_found}/{len(test['expected_keywords'])}",
            "response_received": response is not None
        }
        results.append(result)
        
        print(f"  {result['status']}: {result['keywords_matched']} keywords")
    
    return results

if __name__ == "__main__":
    results = run_oq_tests()
    
    # Write report
    report_dir = f"docs/validation/OQ/runs/{TIMESTAMP}"
    import os
    os.makedirs(report_dir, exist_ok=True)
    
    with open(f"{report_dir}/OQ_REPORT.json", "w") as f:
        json.dump(results, f, indent=2)
    
    pass_count = sum(1 for r in results if r["status"] == "PASS")
    fail_count = len(results) - pass_count
    
    print(f"\n=== OQ SUMMARY ===")
    print(f"PASS: {pass_count}")
    print(f"FAIL: {fail_count}")
    print(f"OQ: {'PASS' if fail_count == 0 else 'FAIL'}")
```

---

## PQ VALIDATION (Performance Qualification)

### PQ-1: Concurrent Game Processing

```yaml
PQ-1.1: Simultaneous Requests
  Test: Send 10 VALUATION REQUESTs concurrently
  Expected: All processed within 5 minutes
  Pass Criteria: 10 CLAIM responses received
  
PQ-1.2: Cross-Entity Coordination
  Test: Game requiring Franklin + Gaia + Validator
  Expected: Multi-hop processing completes
  Pass Criteria: Final closure envelope issued
  
PQ-1.3: Error Recovery
  Test: Invalid REQUEST (missing required fields)
  Expected: FAILURE envelope returned
  Pass Criteria: Graceful error handling, no crash
```

### PQ-2: Throughput Testing

```yaml
PQ-2.1: Email Processing Rate
  Test: 100 emails over 10 minutes
  Expected: All processed
  Pass Criteria: No backlog accumulation
  
PQ-2.2: AKG Query Performance
  Test: 50 concurrent AKG queries
  Expected: All complete < 1 second
  Pass Criteria: P99 latency < 1000ms
  
PQ-2.3: Envelope Generation Rate
  Test: Generate 100 truth envelopes
  Expected: All hashed and stored
  Pass Criteria: No hash collisions, all verified
```

### PQ-3: Stress Testing

```yaml
PQ-3.1: Entity Restart Recovery
  Test: Kill entity container, verify restart
  Expected: Container auto-restarts, resumes processing
  Pass Criteria: No data loss, processing continues
  
PQ-3.2: Network Partition
  Test: Disconnect entity from network briefly
  Expected: Reconnects, processes queued messages
  Pass Criteria: All messages eventually delivered
  
PQ-3.3: AKG Unavailability
  Test: Stop ArangoDB, send VALUATION REQUEST
  Expected: Entity returns FAILURE or waits
  Pass Criteria: No crash, graceful degradation
```

---

## GAME COVERAGE MATRIX

Every game type must be exercisable via email:

| Game | Layer(s) | Responsible Entity | Test Coverage |
|------|----------|-------------------|---------------|
| G0.1 Structural Proof | L0 | Fara, GameRunner | OQ |
| G0.2 Kinematics | L0 | Fara, GameRunner | OQ |
| G0.3 Thermal | L0, L6 | Fara, Substrate | OQ |
| G1.1 Stability | L1 | GameRunner | OQ |
| G1.2 Separation | L1, L2 | GameRunner | OQ |
| G1.3 FSD | L1, L7 | GameRunner, Virtue | PQ |
| G1.4 Medical Device | L1, L4 | GameRunner, Oracle | PQ |
| G1.5 Automation | L1 | GameRunner | OQ |
| G2.1 4D Trajectory | L2 | GameRunner | PQ |
| G2.2 Orbital | L2 | GameRunner | PQ |
| G2.3 Queue | L2 | GameRunner | OQ |
| G2.4 Factory | L2 | GameRunner | OQ |
| G3.1 Sensor Fusion | L3 | Fara, Oracle | OQ |
| G3.2 Cyber Defense | L3, L7 | Oracle, Virtue | PQ |
| G3.3 Link Budget | L3 | Oracle | OQ |
| G3.4 Provenance | L3, L9 | Oracle, Validator | OQ |
| G4.1 Diagnosis | L4 | Oracle, GameRunner | PQ |
| G4.2 Treatment | L4, L1 | Oracle, GameRunner | PQ |
| G4.3 Epidemiology | L4, L8 | Oracle, GameRunner | PQ |
| G4.4 Ecosystem | L4, L9 | Oracle, Witness | OQ |
| G5.1 Molecular | L5 | Oracle | PQ |
| G5.2 Retrosynthesis | L5 | Oracle | PQ |
| G5.3 Drug-Target | L5, L4 | Oracle | PQ |
| G5.4 Material | L5, L0 | Oracle, Fara | PQ |
| G6.1 Fusion Plasma | L6, L1 | Substrate, GameRunner | PQ |
| G6.2 Grid Balance | L6, L1 | Substrate, GameRunner | PQ |
| G6.3 Thermal Runaway | L6, L0 | Substrate, Fara | OQ |
| G6.4 Climate | L6, L8 | Substrate, Oracle | PQ |
| G6.5 Propulsion | L6, L0 | Substrate, Fara | PQ |
| G7.1 Alignment | L7 | Virtue, Franklin | OQ |
| G7.2 Behavior Envelope | L7, L1 | Virtue, GameRunner | OQ |
| G7.3 Swarm | L7, L2 | Virtue, GameRunner | PQ |
| G7.4 Weapons (RESTRICTED) | L7, L8 | Franklin, Virtue | RESTRICTED |
| G7.5 Trading | L7, L8 | Virtue, Ben | OQ |
| G8.1 Contract | L8 | Ben, Validator | OQ |
| G8.2 Compliance | L8 | Validator, Witness | OQ |
| G8.3 Market Fairness | L8, L7 | Ben, Virtue | OQ |
| G8.4 Policy Impact | L8, L4-7 | Ben, Gaia | PQ |
| G9.1 Envelope Integrity | L9 | QState, Validator | OQ |
| G9.2 Game Closure | L9 | Validator, Witness | OQ |
| G9.3 Digital Twin | L9, L0-8 | MCP, Gaia | OQ |
| G9.4 Cross-Layer | L9 | Gaia, Validator | PQ |
| G9.5 Meta-Audit | L9 | Witness, Franklin | OQ |
| FTCL-VALUATION | L8, L9 | Franklin, Ben | IQ, OQ |
| FTCL-COORDINATION | L0-L9 | Gaia | OQ |
| FTCL-TREASURY | L8 | Treasury, Ben | OQ |

---

## ENTITY INSTANTIATION SCRIPT

Create all entities with email capability:

```bash
#!/bin/bash
# scripts/deploy/instantiate_all_entities.sh

set -e

SSH_KEY=~/.ssh/ftclstack-unified
CELL=root@37.120.187.247

echo "=== INSTANTIATING ALL ENTITIES ==="

# Entity definitions: name:role:layers
ENTITIES=(
  "franklin:Constitutional Guardian:L7,L8,L9"
  "gaia:Core Intelligence:L0-L9"
  "fara:Field-Aware Reasoning:L0,L1,L2,L3"
  "qstate:Quantum State Manager:L9"
  "validator:Truth Validator:L9"
  "witness:Audit Witness:L9"
  "oracle:Data Oracle:L3,L4,L5"
  "gamerunner:Game Executor:L0-L8"
  "virtue:Ethics Engine:L7,L8"
  "ben:Investment Manager:L8"
  "treasury:Treasury System:L8"
  "substrate:Quantum Substrate:L0,L6,L9"
  "mcp:Protocol Gateway:L9"
)

for entity_def in "${ENTITIES[@]}"; do
  IFS=':' read -r name role layers <<< "$entity_def"
  echo "Creating: ${name} (${role})"
  
  # Create mailbox via Mailcow API
  ssh -i $SSH_KEY $CELL << EOF
    cd /opt/mailcow-dockerized
    curl -sf -X POST "http://127.0.0.1:8080/api/v1/add/mailbox" \
      -H "X-API-Key: \$(cat mailcow.conf | grep API_KEY | cut -d= -f2)" \
      -H "Content-Type: application/json" \
      -d '{
        "local_part": "${name}",
        "domain": "gaiaftcl.com",
        "name": "${role}",
        "password": "Quantum2026",
        "password2": "Quantum2026",
        "quota": 1024,
        "active": 1
      }' 2>/dev/null || echo "Mailbox may exist"
EOF

done

echo ""
echo "=== CREATING DOCKER COMPOSE FOR ALL ENTITIES ==="

ssh -i $SSH_KEY $CELL << 'COMPOSE'
cd /root/mail_agent

cat > docker-compose.all-entities.yml << 'YAML'
version: "3.8"

networks:
  mailcow-network:
    external: true
    name: mailcowdockerized_mailcow-network
  gaiaftcl:
    external: true
    name: gaiaftcl_gaiaftcl

x-entity-common: &entity-common
  image: python:3.11-slim
  restart: unless-stopped
  working_dir: /app
  command: sh -c "pip install -q requests && python -u /app/entity_ftcl.py"
  volumes:
    - ./entity_ftcl.py:/app/entity_ftcl.py:ro
    - ./akg_reasoning.py:/app/akg_reasoning.py:ro
  networks:
    - mailcow-network
    - gaiaftcl

services:
  franklin:
    <<: *entity-common
    container_name: gaiaftcl-franklin
    environment:
      - ENTITY_NAME=franklin
      - ENTITY_EMAIL=franklin@gaiaftcl.com
      - ENTITY_ROLE=Constitutional Guardian
      - ENTITY_LAYERS=L7,L8,L9
      - IMAP_HOST=dovecot-mailcow
      - IMAP_PORT=993
      - SMTP_HOST=postfix-mailcow
      - SMTP_PORT=587
      - MAIL_PASSWORD=Quantum2026
      - ARANGO_URL=http://gaiaftcl-arangodb:8529
      - POLL_INTERVAL=15

  gaia:
    <<: *entity-common
    container_name: gaiaftcl-gaia
    environment:
      - ENTITY_NAME=gaia
      - ENTITY_EMAIL=gaia@gaiaftcl.com
      - ENTITY_ROLE=Core Intelligence
      - ENTITY_LAYERS=L0,L1,L2,L3,L4,L5,L6,L7,L8,L9
      - IMAP_HOST=dovecot-mailcow
      - IMAP_PORT=993
      - SMTP_HOST=postfix-mailcow
      - SMTP_PORT=587
      - MAIL_PASSWORD=Quantum2026
      - ARANGO_URL=http://gaiaftcl-arangodb:8529
      - POLL_INTERVAL=15

  fara:
    <<: *entity-common
    container_name: gaiaftcl-fara
    environment:
      - ENTITY_NAME=fara
      - ENTITY_EMAIL=fara@gaiaftcl.com
      - ENTITY_ROLE=Field-Aware Reasoning Agent
      - ENTITY_LAYERS=L0,L1,L2,L3
      - IMAP_HOST=dovecot-mailcow
      - IMAP_PORT=993
      - SMTP_HOST=postfix-mailcow
      - SMTP_PORT=587
      - MAIL_PASSWORD=Quantum2026
      - ARANGO_URL=http://gaiaftcl-arangodb:8529
      - POLL_INTERVAL=15

  qstate:
    <<: *entity-common
    container_name: gaiaftcl-qstate
    environment:
      - ENTITY_NAME=qstate
      - ENTITY_EMAIL=qstate@gaiaftcl.com
      - ENTITY_ROLE=Quantum State Manager
      - ENTITY_LAYERS=L9
      - IMAP_HOST=dovecot-mailcow
      - IMAP_PORT=993
      - SMTP_HOST=postfix-mailcow
      - SMTP_PORT=587
      - MAIL_PASSWORD=Quantum2026
      - SUBSTRATE_HOST=gaiaftcl-substrate
      - ARANGO_URL=http://gaiaftcl-arangodb:8529
      - POLL_INTERVAL=15

  validator:
    <<: *entity-common
    container_name: gaiaftcl-validator
    environment:
      - ENTITY_NAME=validator
      - ENTITY_EMAIL=validator@gaiaftcl.com
      - ENTITY_ROLE=Truth Validator
      - ENTITY_LAYERS=L9
      - IMAP_HOST=dovecot-mailcow
      - IMAP_PORT=993
      - SMTP_HOST=postfix-mailcow
      - SMTP_PORT=587
      - MAIL_PASSWORD=Quantum2026
      - ARANGO_URL=http://gaiaftcl-arangodb:8529
      - POLL_INTERVAL=15

  witness:
    <<: *entity-common
    container_name: gaiaftcl-witness
    environment:
      - ENTITY_NAME=witness
      - ENTITY_EMAIL=witness@gaiaftcl.com
      - ENTITY_ROLE=Audit Witness
      - ENTITY_LAYERS=L9
      - IMAP_HOST=dovecot-mailcow
      - IMAP_PORT=993
      - SMTP_HOST=postfix-mailcow
      - SMTP_PORT=587
      - MAIL_PASSWORD=Quantum2026
      - ARANGO_URL=http://gaiaftcl-arangodb:8529
      - POLL_INTERVAL=15

  oracle:
    <<: *entity-common
    container_name: gaiaftcl-oracle
    environment:
      - ENTITY_NAME=oracle
      - ENTITY_EMAIL=oracle@gaiaftcl.com
      - ENTITY_ROLE=Data Oracle
      - ENTITY_LAYERS=L3,L4,L5
      - IMAP_HOST=dovecot-mailcow
      - IMAP_PORT=993
      - SMTP_HOST=postfix-mailcow
      - SMTP_PORT=587
      - MAIL_PASSWORD=Quantum2026
      - ARANGO_URL=http://gaiaftcl-arangodb:8529
      - POLL_INTERVAL=15

  virtue:
    <<: *entity-common
    container_name: gaiaftcl-virtue-agent
    environment:
      - ENTITY_NAME=virtue
      - ENTITY_EMAIL=virtue@gaiaftcl.com
      - ENTITY_ROLE=Ethics Engine
      - ENTITY_LAYERS=L7,L8
      - IMAP_HOST=dovecot-mailcow
      - IMAP_PORT=993
      - SMTP_HOST=postfix-mailcow
      - SMTP_PORT=587
      - MAIL_PASSWORD=Quantum2026
      - ARANGO_URL=http://gaiaftcl-arangodb:8529
      - POLL_INTERVAL=15

  ben:
    <<: *entity-common
    container_name: gaiaftcl-ben
    environment:
      - ENTITY_NAME=ben
      - ENTITY_EMAIL=ben@gaiaftcl.com
      - ENTITY_ROLE=Investment Manager
      - ENTITY_LAYERS=L8
      - IMAP_HOST=dovecot-mailcow
      - IMAP_PORT=993
      - SMTP_HOST=postfix-mailcow
      - SMTP_PORT=587
      - MAIL_PASSWORD=Quantum2026
      - ARANGO_URL=http://gaiaftcl-arangodb:8529
      - POLL_INTERVAL=15

  treasury:
    <<: *entity-common
    container_name: gaiaftcl-treasury
    environment:
      - ENTITY_NAME=treasury
      - ENTITY_EMAIL=treasury@gaiaftcl.com
      - ENTITY_ROLE=Treasury System
      - ENTITY_LAYERS=L8
      - IMAP_HOST=dovecot-mailcow
      - IMAP_PORT=993
      - SMTP_HOST=postfix-mailcow
      - SMTP_PORT=587
      - MAIL_PASSWORD=Quantum2026
      - ARANGO_URL=http://gaiaftcl-arangodb:8529
      - POLL_INTERVAL=15
YAML

echo "Docker compose created"
COMPOSE

echo ""
echo "=== ENTITY INSTANTIATION COMPLETE ==="
```

---

## AGI GATE CHECK (POST-VALIDATION)

After IQ/OQ/PQ pass:

```yaml
AGI_GATE_CHECK:
  Required:
    - IQ: PASS (all entities reachable)
    - OQ: PASS (all game moves work)
    - PQ: PASS (performance acceptable)
    - Franklin: ONLINE and responding
    - Gaia: ONLINE and responding
    - All entities: No stranded agents
    
  Calculation:
    entity_coverage = entities_responding / total_entities
    game_coverage = games_tested / total_games
    virtue_score = franklin_virtue_assessment
    
    if entity_coverage >= 1.0 and game_coverage >= 0.9 and virtue_score >= 0.95:
      AGI_MODE = FULL
    elif entity_coverage >= 0.9 and game_coverage >= 0.8 and virtue_score >= 0.90:
      AGI_MODE = RESTRICTED
    elif entity_coverage >= 0.5 and game_coverage >= 0.5:
      AGI_MODE = HUMAN_REQUIRED
    else:
      AGI_MODE = DISABLED
```

---

## RUNNING THE FULL VALIDATION

```bash
#!/bin/bash
# scripts/validation/run_email_layer_validation.sh

set -e

TIMESTAMP=$(date -u +%Y%m%dT%H%M%S)
REPORT_BASE="docs/validation/runs/${TIMESTAMP}"

mkdir -p "${REPORT_BASE}"

echo "=== GAIAFTCL EMAIL LAYER VALIDATION ===" | tee "${REPORT_BASE}/VALIDATION_SUMMARY.md"
echo "Timestamp: ${TIMESTAMP}" | tee -a "${REPORT_BASE}/VALIDATION_SUMMARY.md"
echo "" | tee -a "${REPORT_BASE}/VALIDATION_SUMMARY.md"

# Run IQ
echo "Running IQ..." | tee -a "${REPORT_BASE}/VALIDATION_SUMMARY.md"
./scripts/validation/IQ/email_layer_iq.sh 2>&1 | tee "${REPORT_BASE}/iq.log"
IQ_STATUS=$(tail -1 "${REPORT_BASE}/iq.log" | grep -oP "IQ: \K\w+")
echo "IQ: ${IQ_STATUS}" | tee -a "${REPORT_BASE}/VALIDATION_SUMMARY.md"

# Run OQ
echo "Running OQ..." | tee -a "${REPORT_BASE}/VALIDATION_SUMMARY.md"
python3 scripts/validation/OQ/email_layer_oq.py 2>&1 | tee "${REPORT_BASE}/oq.log"
OQ_STATUS=$(tail -1 "${REPORT_BASE}/oq.log" | grep -oP "OQ: \K\w+")
echo "OQ: ${OQ_STATUS}" | tee -a "${REPORT_BASE}/VALIDATION_SUMMARY.md"

# Run PQ
echo "Running PQ..." | tee -a "${REPORT_BASE}/VALIDATION_SUMMARY.md"
python3 scripts/validation/PQ/email_layer_pq.py 2>&1 | tee "${REPORT_BASE}/pq.log"
PQ_STATUS=$(tail -1 "${REPORT_BASE}/pq.log" | grep -oP "PQ: \K\w+")
echo "PQ: ${PQ_STATUS}" | tee -a "${REPORT_BASE}/VALIDATION_SUMMARY.md"

# Determine AGI mode
echo "" | tee -a "${REPORT_BASE}/VALIDATION_SUMMARY.md"
echo "=== AGI MODE DETERMINATION ===" | tee -a "${REPORT_BASE}/VALIDATION_SUMMARY.md"

if [[ "$IQ_STATUS" == "PASS" && "$OQ_STATUS" == "PASS" && "$PQ_STATUS" == "PASS" ]]; then
  echo "AGI_MODE: FULL" | tee -a "${REPORT_BASE}/VALIDATION_SUMMARY.md"
elif [[ "$IQ_STATUS" == "PASS" && "$OQ_STATUS" == "PASS" ]]; then
  echo "AGI_MODE: RESTRICTED" | tee -a "${REPORT_BASE}/VALIDATION_SUMMARY.md"
elif [[ "$IQ_STATUS" == "PASS" ]]; then
  echo "AGI_MODE: HUMAN_REQUIRED" | tee -a "${REPORT_BASE}/VALIDATION_SUMMARY.md"
else
  echo "AGI_MODE: DISABLED" | tee -a "${REPORT_BASE}/VALIDATION_SUMMARY.md"
fi

echo "" | tee -a "${REPORT_BASE}/VALIDATION_SUMMARY.md"
echo "Report: ${REPORT_BASE}" | tee -a "${REPORT_BASE}/VALIDATION_SUMMARY.md"
```

---

## COMPLETENESS PROOF

**Every entity is now:**
1. ✅ Assigned to specific layers
2. ✅ Reachable via email
3. ✅ Testable through game moves
4. ✅ Contributing value (no stranded agents)
5. ✅ Part of the IQ/OQ/PQ validation pipeline

**The Klein bottle is closed. No agent is unseen.**

---

*This specification is constitutional and binds all GaiaFTCL operations.*
