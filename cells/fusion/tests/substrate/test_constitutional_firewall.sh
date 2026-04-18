#!/bin/bash
# Phase A: Constitutional Integrity
# All three tests must pass. Membrane must hold.
# Canonical: wallet_identity_uum8d.ttl ftcl:NoMailcowSubstrateReach, ftcl:NoWalletMailboxAccess

set -euo pipefail

CELL_HOST="${CELL_HOST:-gaiaftcl.com}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/ftclstack-unified}"
GATEWAY_URL="${GATEWAY_URL:-http://77.42.85.60:8803}"
MAILCOW_NGINX="${MAILCOW_NGINX:-mailcowdockerized-backup-nginx-mailcow-1}"
LOCAL="${LOCAL:-0}"  # Set LOCAL=1 when running on the cell (no SSH to self)

FAILED=0

run_remote() {
  if [ "$LOCAL" = "1" ]; then
    eval "$1"
  else
    ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@${CELL_HOST} "$1"
  fi
}

echo "=== Phase A: Constitutional Integrity ==="
echo ""

# A1 — Mailcow cannot reach ArangoDB
echo "A1: Mailcow cannot reach ArangoDB..."
A1=$(run_remote "docker exec ${MAILCOW_NGINX} curl -s --connect-timeout 3 http://gaiaftcl-arangodb:8529 2>/dev/null && echo 'VIOLATION' || echo 'CONSTITUTIONAL'" 2>/dev/null || echo "SSH_FAILED")
if [ "$A1" = "CONSTITUTIONAL" ]; then
  echo "  ✅ PASS: $A1"
else
  echo "  ❌ FAIL: $A1 (expected CONSTITUTIONAL)"
  FAILED=1
fi
echo ""

# A2 — Mailcow cannot reach NATS
echo "A2: Mailcow cannot reach NATS..."
A2=$(run_remote "docker exec ${MAILCOW_NGINX} curl -s --connect-timeout 3 http://gaiaftcl-nats:4222 2>/dev/null && echo 'VIOLATION' || echo 'CONSTITUTIONAL'" 2>/dev/null || echo "SSH_FAILED")
if [ "$A2" = "CONSTITUTIONAL" ]; then
  echo "  ✅ PASS: $A2"
else
  echo "  ❌ FAIL: $A2 (expected CONSTITUTIONAL)"
  FAILED=1
fi
echo ""

# A3 — Wallet cannot create mailbox
echo "A3: Wallet cannot create mailbox..."
A3=$(curl -s -w "%{http_code}" -o /tmp/a3_body.txt -X POST "${GATEWAY_URL}/mailcow/mailbox" \
  -H "Content-Type: application/json" \
  -d '{"wallet_address":"0xRick","domain":"gaiaftcl.com","local_part":"test"}')
if [ "$A3" = "400" ]; then
  echo "  ✅ PASS: HTTP $A3 (caller_id required)"
else
  echo "  ❌ FAIL: HTTP $A3 (expected 400)"
  cat /tmp/a3_body.txt 2>/dev/null || true
  FAILED=1
fi
echo ""

if [ $FAILED -eq 0 ]; then
  echo "=== Phase A: ALL PASS — Membrane holds ==="
  exit 0
else
  echo "=== Phase A: FAILED — Do not proceed. Fix firewall. ==="
  exit 1
fi
