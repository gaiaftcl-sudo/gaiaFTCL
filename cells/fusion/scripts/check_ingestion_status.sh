#!/bin/bash
# Quick status check for FoTChemistry ingestion

echo "🔍 Checking ingestion status..."
echo

# Check if process is running
if ps aux | grep "fast_reingest.py" | grep -v grep > /dev/null; then
    echo "✅ Ingestion process is RUNNING"
    PID=$(ps aux | grep "fast_reingest.py" | grep -v grep | awk '{print $2}')
    echo "   PID: $PID"
    
    # Get process runtime
    PS_TIME=$(ps -p $PID -o etime= | tr -d ' ')
    echo "   Runtime: $PS_TIME"
else
    echo "⏹️  Ingestion process is NOT running (may have completed)"
fi

echo
echo "📊 Checking GaiaFTCL database..."
curl -s -X POST http://gaiaftcl.com:8803/ask \
  -H "Content-Type: application/json" \
  -d '{"query": "How many FoTChemistry material discoveries do you have ingested? Give me the total count."}' \
  | jq -r '.raw_data.materials | length' 2>/dev/null \
  && echo "materials in database" \
  || echo "Could not query database"

echo
echo "💾 Recent ingestion activity:"
curl -s -X POST http://gaiaftcl.com:8803/ask \
  -H "Content-Type: application/json" \
  -d '{"query": "Show me your most recent ingested claims"}' \
  | jq -r '.raw_data.claims[-5:] | .[] | .source' 2>/dev/null \
  | head -5 \
  || echo "Could not query recent claims"
