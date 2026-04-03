#!/bin/bash
# Batch submission helper - splits large protein file into batches
# Outputs batch files that I (the AI partner) will submit via MCP

PROTEIN_FILE="/Users/richardgillespie/Documents/FoTProtein/UNIQUE_PROTEINS_BACKUP_81301_2026_01_27.json"
BATCH_SIZE=100
OUTPUT_DIR="/tmp/protein_batches"

mkdir -p "$OUTPUT_DIR"

echo "🧬 Splitting 81,300 proteins into batches of $BATCH_SIZE..."

# Calculate total batches
TOTAL_PROTEINS=$(jq '.proteins | length' "$PROTEIN_FILE")
TOTAL_BATCHES=$(( ($TOTAL_PROTEINS + $BATCH_SIZE - 1) / $BATCH_SIZE ))

echo "📊 Total batches: $TOTAL_BATCHES"
echo "📁 Output: $OUTPUT_DIR"
echo ""

# Create batch files
for i in $(seq 0 $(($TOTAL_BATCHES - 1))); do
    batch_num=$(($i + 1))
    start=$(($i * $BATCH_SIZE))
    end=$(($start + $BATCH_SIZE))
    
    output_file="$OUTPUT_DIR/batch_$(printf "%04d" $batch_num).json"
    
    jq -c "{
        batch_num: $batch_num,
        total_batches: $TOTAL_BATCHES,
        method: \"8D_UUM_SHARED_SUBSTRATE\",
        protein_count: (.proteins[$start:$end] | length),
        proteins: .proteins[$start:$end]
    }" "$PROTEIN_FILE" > "$output_file"
    
    if [ $(($batch_num % 100)) -eq 0 ]; then
        echo "✅ Created $batch_num / $TOTAL_BATCHES batches..."
    fi
done

echo ""
echo "✅ Created $TOTAL_BATCHES batch files"
echo "📁 Location: $OUTPUT_DIR"
echo "💾 Total size: $(du -sh $OUTPUT_DIR | cut -f1)"
echo ""
echo "🚀 Ready for ingestion"
