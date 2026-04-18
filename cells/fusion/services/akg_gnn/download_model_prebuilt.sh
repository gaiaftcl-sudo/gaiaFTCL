#!/bin/bash
set -e

MODEL_DIR="models/all-MiniLM-L6-v2"
mkdir -p "$MODEL_DIR"

echo "🔽 Downloading pre-exported ONNX model..."

BASE_URL="https://huggingface.co/optimum/all-MiniLM-L6-v2/resolve/main"

curl -L "${BASE_URL}/model.onnx" -o "${MODEL_DIR}/model.onnx"
echo "✓ Downloaded model.onnx"

curl -L "${BASE_URL}/tokenizer.json" -o "${MODEL_DIR}/tokenizer.json"
echo "✓ Downloaded tokenizer.json"

curl -L "${BASE_URL}/config.json" -o "${MODEL_DIR}/config.json"
echo "✓ Downloaded config.json"

echo "✅ Model download complete"
ls -lh "$MODEL_DIR"

