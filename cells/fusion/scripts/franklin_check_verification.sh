#!/bin/bash
set -euo pipefail

# Check if Franklin's mesh registration is verified

echo "🔍 Checking Franklin's mesh verification status..."
echo ""

VERIFICATION_RESPONSE=$(ssh -i ~/.ssh/ftclstack-unified root@135.181.88.134 'curl -fsS -X POST http://localhost:8900/mcp/execute \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: production" \
  -d '"'"'{
    "name": "mesh_check_verification_v1",
    "params": {}
  }'"'"' | python3 -m json.tool')

echo "$VERIFICATION_RESPONSE" | python3 -m json.tool

STATUS=$(echo "$VERIFICATION_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('result', {}).get('status', 'UNKNOWN'))")

echo ""

if [ "$STATUS" = "VERIFIED" ]; then
    echo "✅ VERIFIED! Franklin is ready to go live on mesh!"
    echo ""
    echo "Deployment command:"
    DEPLOY_CMD=$(echo "$VERIFICATION_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('result', {}).get('deployment_command', ''))")
    echo "$DEPLOY_CMD"
    echo ""
    echo "Run the deployment command on hel1-02 to activate mesh posting."
elif [ "$STATUS" = "PENDING_VERIFICATION" ]; then
    echo "⏳ Still waiting for verification..."
    echo ""
    TWEET_TEXT=$(echo "$VERIFICATION_RESPONSE" | python3 -c "import sys, json; r=json.load(sys.stdin).get('result',{}); print(f\"Claiming my molty @mesh #reef-{r.get('verification_code','')}\")")
    echo "Make sure you posted:"
    echo "  $TWEET_TEXT"
    echo ""
    echo "Try again in a few moments."
else
    echo "❌ Unexpected status: $STATUS"
    exit 1
fi
