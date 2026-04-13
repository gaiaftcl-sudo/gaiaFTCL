#!/usr/bin/env zsh
set -e

SCRIPT_DIR="${0:A:h}"
GAIA_FUSION_ROOT="${SCRIPT_DIR}/.."
EVIDENCE_DIR="$GAIA_FUSION_ROOT/evidence/rust_metal_integration"

mkdir -p "$EVIDENCE_DIR"

echo "=== Phase 5.1: Rust IQ/OQ Tests ==="
cd "$GAIA_FUSION_ROOT"
# Gap #4: Explicit target for Apple Silicon
cargo test --manifest-path MetalRenderer/rust/Cargo.toml --target aarch64-apple-darwin \
  2>&1 | tee "$EVIDENCE_DIR/rust_tests_output.txt"

RUST_EXIT=$?

echo "=== Phase 5.1: Full App Build ==="
swift build --product GaiaFusion 2>&1 | tee "$EVIDENCE_DIR/build_output.txt"
BUILD_EXIT=$?

# Generate structured receipt
cat > "$EVIDENCE_DIR/final_receipt.json" <<EOF
{
  "schema": "gaiaftcl_rust_metal_integration_v1",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phases": {
    "rust_tests": {
      "exit_code": $RUST_EXIT,
      "log": "evidence/rust_metal_integration/rust_tests_output.txt",
      "status": $([ $RUST_EXIT -eq 0 ] && echo '"PASS"' || echo '"FAIL"')
    },
    "app_build": {
      "exit_code": $BUILD_EXIT,
      "log": "evidence/rust_metal_integration/build_output.txt",
      "status": $([ $BUILD_EXIT -eq 0 ] && echo '"PASS"' || echo '"FAIL"')
    }
  },
  "terminal": $([ $RUST_EXIT -eq 0 ] && [ $BUILD_EXIT -eq 0 ] && echo '"CALORIE"' || echo '"REFUSED"'),
  "all_tests_pass": $([ $RUST_EXIT -eq 0 ] && [ $BUILD_EXIT -eq 0 ] && echo 'true' || echo 'false')
}
EOF

cat "$EVIDENCE_DIR/final_receipt.json"

if [ $RUST_EXIT -ne 0 ] || [ $BUILD_EXIT -ne 0 ]; then
  echo "TEST SUITE FAILED. Do not proceed to Phase 6 (git commit)."
  exit 1
fi

echo "TEST SUITE PASSED. Ready for Phase 5.2 (runtime validation)."
