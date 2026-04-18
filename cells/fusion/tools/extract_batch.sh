#!/bin/bash
# Extract a specific batch from the protein backup file
# Usage: ./extract_batch.sh <batch_number>

PROTEIN_FILE="/Users/richardgillespie/Documents/FoTProtein/UNIQUE_PROTEINS_BACKUP_81301_2026_01_27.json"
BATCH_SIZE=100
BATCH_NUM=$1

if [ -z "$BATCH_NUM" ]; then
    echo "Usage: $0 <batch_number>"
    exit 1
fi

START=$(( ($BATCH_NUM - 1) * $BATCH_SIZE ))
END=$(( $START + $BATCH_SIZE ))

jq -c ".proteins[$START:$END] | length" "$PROTEIN_FILE"
