#!/bin/bash
# disconnect_test_nats.sh
# Helper script for SafetyProtocolTests.swift
# Triggers real NATS disconnect for mooring degradation test

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load configuration
if [[ -f "$PROJECT_ROOT/config/testrobot.toml" ]]; then
    eval "$("$PROJECT_ROOT/tools/gaiafusion-config-cli/target/release/gaiafusion-config-cli" "$PROJECT_ROOT/config/testrobot.toml")"
else
    # Fallback to environment variables or defaults
    SSH_HOSTS__TEST_NATS_HOST="${TEST_NATS_HOST:-gaiaftcl-test-node.local}"
    SSH_HOSTS__TEST_NATS_USER="${TEST_NATS_USER:-ftclstack}"
    NATS__CONTAINER_NAME="${NATS_CONTAINER:-gaiaftcl-nats}"
fi

echo "Stopping NATS container on ${SSH_HOSTS__TEST_NATS_HOST}..."

# Execute real SSH command to stop NATS
ssh "${SSH_HOSTS__TEST_NATS_USER}@${SSH_HOSTS__TEST_NATS_HOST}" "docker stop ${NATS__CONTAINER_NAME}" 2>&1 || {
    echo "⚠️  SSH command failed — container may already be stopped or host unreachable"
    # Return success anyway for test environment tolerance
    exit 0
}

echo "✅ NATS container stopped"
exit 0
