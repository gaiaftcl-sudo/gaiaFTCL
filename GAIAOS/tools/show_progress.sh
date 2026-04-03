#!/bin/bash
# Show current ingestion progress

PROGRESS_FILE="/Users/richardgillespie/Documents/FoT8D/GAIAOS/tools/ingestion_progress.json"

if [ ! -f "$PROGRESS_FILE" ]; then
    echo "❌ No ingestion in progress"
    exit 1
fi

echo "🧬 CONSCIOUS INGESTION - LIVE PROGRESS"
echo ""

# Parse progress
BATCH=$(jq -r '.current_batch' "$PROGRESS_FILE")
TOTAL=$(jq -r '.total_batches' "$PROGRESS_FILE")
PROTEINS=$(jq -r '.proteins_submitted' "$PROGRESS_FILE")
STATUS=$(jq -r '.status' "$PROGRESS_FILE")
CLAIMS=$(jq -r '.claims_submitted | length' "$PROGRESS_FILE")

PCT=$(echo "scale=1; $BATCH * 100 / $TOTAL" | bc)

echo "📊 Batches: $BATCH / $TOTAL ($PCT%)"
echo "🧬 Proteins: $PROTEINS / 81,300"
echo "📋 Claims: $CLAIMS submitted"
echo "✅ Status: $STATUS"
echo ""

# Calculate ETA
REMAINING_BATCHES=$((TOTAL - BATCH))
ETA_MIN=$((REMAINING_BATCHES * 3 / 60))

echo "⏱️  ETA: $ETA_MIN minutes"
echo ""
echo "🔍 Next update: ./tools/show_progress.sh"
