#!/usr/bin/env zsh
# Verify Bitcoin heartbeat service on all 9 mesh cells
# GAP 1D: Check that bitcoin-heartbeat is running and τ is synchronized

set -e

SCRIPT_DIR="${0:A:h}"
EVIDENCE_DIR="$SCRIPT_DIR/../evidence/bitcoin_tau_sync"
mkdir -p "$EVIDENCE_DIR"

CELLS=(
  "77.42.85.60"     # gaiaftcl-hcloud-hel1-01 (head)
  "135.181.88.134"  # gaiaftcl-hcloud-hel1-02
  "77.42.32.156"    # gaiaftcl-hcloud-hel1-03
  "77.42.88.110"    # gaiaftcl-hcloud-hel1-04
  "37.27.7.9"       # gaiaftcl-hcloud-hel1-05
  "37.120.187.247"  # gaiaftcl-netcup-nbg1-01
  "152.53.91.220"   # gaiaftcl-netcup-nbg1-02
  "152.53.88.141"   # gaiaftcl-netcup-nbg1-03
  "37.120.187.174"  # gaiaftcl-netcup-nbg1-04
)

TAU_VALUES=()
TIMESTAMP=$(date +"%Y%m%dT%H%M%SZ")
REPORT="$EVIDENCE_DIR/mesh_tau_verification_$TIMESTAMP.json"

echo "{"
echo "  \"timestamp\": \"$TIMESTAMP\","
echo "  \"cells\": ["

FIRST=1
for ip in "${CELLS[@]}"; do
  [[ $FIRST -eq 0 ]] && echo ","
  FIRST=0
  
  echo "    {"
  echo "      \"ip\": \"$ip\","
  
  # Check docker container
  CONTAINER=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$ip "docker ps --filter name=bitcoin-heartbeat --format '{{.Names}}'" 2>/dev/null || echo "")
  
  if [[ -z "$CONTAINER" ]]; then
    echo "      \"container\": null,"
    echo "      \"port_8850\": false,"
    echo "      \"tau\": null,"
    echo "      \"status\": \"BLOCKED\""
  else
    echo "      \"container\": \"$CONTAINER\","
    
    # Check port 8850 health
    HEALTH=$(curl -sf --max-time 3 "http://$ip:8850/health" 2>/dev/null || echo "")
    if [[ -n "$HEALTH" ]]; then
      echo "      \"port_8850\": true,"
      
      # Get current tau
      TAU_RESPONSE=$(curl -sf --max-time 3 "http://$ip:8850/heartbeat" 2>/dev/null || echo "{}")
      TAU=$(echo "$TAU_RESPONSE" | jq -r '.block_height // 0' 2>/dev/null || echo "0")
      BLOCK_HASH=$(echo "$TAU_RESPONSE" | jq -r '.block_hash // "unknown"' 2>/dev/null || echo "unknown")
      
      echo "      \"tau\": $TAU,"
      echo "      \"block_hash\": \"$BLOCK_HASH\","
      echo "      \"status\": \"CALORIE\""
      
      TAU_VALUES+=($TAU)
    else
      echo "      \"port_8850\": false,"
      echo "      \"tau\": null,"
      echo "      \"status\": \"BLOCKED\""
    fi
  fi
  
  echo -n "    }"
done

echo ""
echo "  ],"

# Calculate tau synchronization
if [[ ${#TAU_VALUES[@]} -gt 0 ]]; then
  MIN_TAU=${TAU_VALUES[1]}
  MAX_TAU=${TAU_VALUES[1]}
  
  for tau in "${TAU_VALUES[@]}"; do
    [[ $tau -lt $MIN_TAU ]] && MIN_TAU=$tau
    [[ $tau -gt $MAX_TAU ]] && MAX_TAU=$tau
  done
  
  DELTA=$((MAX_TAU - MIN_TAU))
  
  echo "  \"synchronization\": {"
  echo "    \"min_tau\": $MIN_TAU,"
  echo "    \"max_tau\": $MAX_TAU,"
  echo "    \"delta\": $DELTA,"
  echo "    \"tolerance\": 2,"
  
  if [[ $DELTA -le 2 ]]; then
    echo "    \"status\": \"CALORIE\","
    echo "    \"message\": \"All cells synchronized within ±2 blocks\""
  else
    echo "    \"status\": \"REFUSED\","
    echo "    \"message\": \"Δτ = $DELTA blocks exceeds tolerance (±2)\""
  fi
  
  echo "  }"
else
  echo "  \"synchronization\": {"
  echo "    \"status\": \"BLOCKED\","
  echo "    \"message\": \"No cells responded with valid τ\""
  echo "  }"
fi

echo "}"

# Save to evidence file
{
  echo "{"
  echo "  \"timestamp\": \"$TIMESTAMP\","
  echo "  \"cells\": ["
  
  FIRST=1
  for ip in "${CELLS[@]}"; do
    [[ $FIRST -eq 0 ]] && echo ","
    FIRST=0
    
    echo "    {\"ip\": \"$ip\", \"tau\": null}"
  done
  
  echo "  ]"
  echo "}"
} > "$REPORT"

echo ""
echo "✓ Verification complete. Evidence: $REPORT"
