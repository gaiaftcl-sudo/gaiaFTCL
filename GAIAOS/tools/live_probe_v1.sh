#!/bin/bash
# Live Probe V1 - Fail-closed status checker
# Only reports what can be proven with evidence

set -e

PUBLIC_DOMAIN="${PUBLIC_DOMAIN:-gaiaftcl.com}"
HEAD_CELL="${HEAD_CELL:-hel1-01}"
FRANKLIN_CELL="${FRANKLIN_CELL:-hel1-02}"
EVIDENCE_DIR="/opt/gaia/evidence/live_probe"

TIMESTAMP=$(date -u +"%Y%m%dT%H%M%S")
DATE_DIR=$(date -u +"%Y%m%d")
EVIDENCE_FILE="${EVIDENCE_DIR}/${DATE_DIR}/live_probe_${TIMESTAMP}.json"

mkdir -p "${EVIDENCE_DIR}/${DATE_DIR}"

# Initialize results
declare -a CHECKS=()
OVERALL_STATUS="UNKNOWN"
declare -a REASON_CODES=()

# Helper to run check and record result
run_check() {
    local name="$1"
    local command="$2"
    local host="${3:-local}"
    
    local output
    local rc
    
    if [ "$host" = "local" ]; then
        output=$(eval "$command" 2>&1) || rc=$?
        rc=${rc:-0}
    else
        # SSH check
        if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$host" "true" 2>/dev/null; then
            CHECKS+=("$(jq -n --arg name "$name" --arg cmd "$command" --arg host "$host" \
                '{name: $name, command: $cmd, host: $host, result: "UNKNOWN", reason: "NO_ACCESS", rc: null, output: ""}')")
            REASON_CODES+=("NO_ACCESS")
            return
        fi
        
        output=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$host" "$command" 2>&1) || rc=$?
        rc=${rc:-0}
    fi
    
    # Truncate output to 2000 chars
    output="${output:0:2000}"
    
    local result="OK"
    if [ "$rc" -ne 0 ]; then
        result="FAILED"
    fi
    
    CHECKS+=("$(jq -n --arg name "$name" --arg cmd "$command" --arg host "$host" \
        --arg result "$result" --argjson rc "$rc" --arg output "$output" \
        '{name: $name, command: $cmd, host: $host, result: $result, rc: $rc, output: $output}')")
    
    if [ "$result" = "FAILED" ]; then
        case "$name" in
            *service*) REASON_CODES+=("SERVICE_DOWN") ;;
            *route*) REASON_CODES+=("ROUTE_MISSING") ;;
            *port*) REASON_CODES+=("PORT_CLOSED") ;;
            *public*) REASON_CODES+=("PUBLIC_UNREACHABLE") ;;
        esac
    fi
}

echo "🔍 Live Probe V1 - Gateway / health surfaces"
echo "============================================"
echo ""

# Check 1: Head cell reverse proxy
echo "1️⃣  Checking reverse proxy on ${HEAD_CELL}..."
run_check "head_proxy_service" "systemctl is-active caddy || systemctl is-active nginx || echo 'NO_PROXY'" "$HEAD_CELL"

# Check 2: Head cell port bindings
echo "2️⃣  Checking port bindings on ${HEAD_CELL}..."
run_check "head_ports" "ss -lntp | egrep ':(80|443)' || echo 'NO_PORTS'" "$HEAD_CELL"

# Check 3: Head cell local routing
echo "3️⃣  Checking local routing on ${HEAD_CELL}..."
run_check "head_local_route" "curl -sS -m 5 http://127.0.0.1/health 2>&1 | head -c 500" "$HEAD_CELL"

# Check 4: Franklin service
echo "4️⃣  Checking Franklin Guardian on ${FRANKLIN_CELL}..."
run_check "franklin_service" "systemctl is-active franklin-guardian 2>&1" "$FRANKLIN_CELL"

# Check 5: Franklin local endpoint
echo "5️⃣  Checking Franklin local endpoint on ${FRANKLIN_CELL}..."
run_check "franklin_local_endpoint" "curl -fsS -m 5 http://127.0.0.1:8803/health 2>&1 | head -c 500" "$FRANKLIN_CELL"

# Check 6: Franklin port binding
echo "6️⃣  Checking Franklin port on ${FRANKLIN_CELL}..."
run_check "franklin_port" "ss -lntp | grep ':8803' || echo 'PORT_NOT_BOUND'" "$FRANKLIN_CELL"

# Check 7: Public domain
echo "7️⃣  Checking public domain ${PUBLIC_DOMAIN}..."
run_check "public_domain" "curl -sS -m 10 -k https://${PUBLIC_DOMAIN}/health 2>&1 | head -c 500" "local"

# Determine overall status
echo ""
echo "📊 Analyzing results..."

FAILED_COUNT=$(echo "${CHECKS[@]}" | jq -s '[.[] | select(.result == "FAILED")] | length')
UNKNOWN_COUNT=$(echo "${CHECKS[@]}" | jq -s '[.[] | select(.result == "UNKNOWN")] | length')
OK_COUNT=$(echo "${CHECKS[@]}" | jq -s '[.[] | select(.result == "OK")] | length')

if [ "$UNKNOWN_COUNT" -gt 3 ]; then
    OVERALL_STATUS="UNKNOWN"
    REASON_CODES+=("INSUFFICIENT_ACCESS")
elif [ "$FAILED_COUNT" -eq 0 ] && [ "$OK_COUNT" -ge 5 ]; then
    OVERALL_STATUS="LIVE"
elif [ "$FAILED_COUNT" -gt 0 ] && [ "$OK_COUNT" -gt 0 ]; then
    OVERALL_STATUS="PARTIAL"
else
    OVERALL_STATUS="NOT_LIVE"
fi

# Remove duplicate reason codes
REASON_CODES=($(echo "${REASON_CODES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

# Build evidence JSON
EVIDENCE=$(jq -n \
    --arg status "$OVERALL_STATUS" \
    --argjson checks "$(echo "${CHECKS[@]}" | jq -s '.')" \
    --argjson reason_codes "$(printf '%s\n' "${REASON_CODES[@]}" | jq -R . | jq -s .)" \
    --arg ts "$TIMESTAMP" \
    --arg public_domain "$PUBLIC_DOMAIN" \
    --arg head_cell "$HEAD_CELL" \
    --arg franklin_cell "$FRANKLIN_CELL" \
    '{
        probe_version: "v1",
        ts_utc: $ts,
        status: $status,
        public_domain: $public_domain,
        head_cell: $head_cell,
        franklin_cell: $franklin_cell,
        checks: $checks,
        reason_codes: $reason_codes,
        summary: {
            total: ($checks | length),
            ok: ($checks | map(select(.result == "OK")) | length),
            failed: ($checks | map(select(.result == "FAILED")) | length),
            unknown: ($checks | map(select(.result == "UNKNOWN")) | length)
        },
        self_hash_sha256: ""
    }')

# Compute self-hash
HASH=$(echo "$EVIDENCE" | jq 'del(.self_hash_sha256)' | sha256sum | cut -d' ' -f1)
EVIDENCE=$(echo "$EVIDENCE" | jq --arg hash "sha256:$HASH" '.self_hash_sha256 = $hash')

# Write evidence
echo "$EVIDENCE" > "$EVIDENCE_FILE"

# Display results
echo ""
echo "✅ Evidence written to: $EVIDENCE_FILE"
echo ""
echo "📊 RESULTS:"
echo "=========="
echo "$EVIDENCE" | jq '{status, summary, reason_codes}'
echo ""

# Exit code based on status
case "$OVERALL_STATUS" in
    LIVE) exit 0 ;;
    PARTIAL) exit 1 ;;
    NOT_LIVE) exit 2 ;;
    UNKNOWN) exit 3 ;;
esac
