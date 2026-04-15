#!/bin/bash
# PQ Validation - Performance Qualification
# Automated performance metrics collection

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVIDENCE_DIR="$PROJECT_ROOT/evidence/pq"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT="$EVIDENCE_DIR/PQ_VALIDATION_${TIMESTAMP}.json"

mkdir -p "$EVIDENCE_DIR"

echo "🔍 PQ Validation - Performance Qualification"
echo "============================================="
echo ""

# Test 1: Binary size (performance indicator)
echo "Test 1: Binary Size"
DEBUG_SIZE=$(stat -f%z "$PROJECT_ROOT/.build/arm64-apple-macosx/debug/GaiaFusion" 2>/dev/null || echo 0)
RELEASE_SIZE=$(stat -f%z "$PROJECT_ROOT/.build/arm64-apple-macosx/release/GaiaFusion" 2>/dev/null || echo 0)

if [ "$RELEASE_SIZE" -gt 0 ] && [ "$DEBUG_SIZE" -gt 0 ]; then
    REDUCTION=$(echo "scale=2; (1 - $RELEASE_SIZE / $DEBUG_SIZE) * 100" | bc)
    echo "  Debug: $(numfmt --to=iec-i --suffix=B $DEBUG_SIZE 2>/dev/null || echo ${DEBUG_SIZE}B)"
    echo "  Release: $(numfmt --to=iec-i --suffix=B $RELEASE_SIZE 2>/dev/null || echo ${RELEASE_SIZE}B)"
    echo "  Optimization: ${REDUCTION}% reduction"
    TEST1="PASS"
else
    echo "  ❌ Binary size check failed"
    TEST1="FAIL"
fi

# Test 2: Build time
echo ""
echo "Test 2: Build Performance"
START_TIME=$(date +%s)
if swift build --configuration release --product GaiaFusion > /dev/null 2>&1; then
    END_TIME=$(date +%s)
    BUILD_TIME=$((END_TIME - START_TIME))
    echo "  ✅ Release build time: ${BUILD_TIME}s"
    
    if [ "$BUILD_TIME" -lt 60 ]; then
        TEST2="PASS"
    else
        TEST2="PARTIAL"
        echo "     (Build time > 60s threshold)"
    fi
else
    echo "  ❌ Build failed"
    TEST2="FAIL"
fi

# Test 3: Test compilation performance
echo ""
echo "Test 3: Test Compilation"
START_TIME=$(date +%s)
if swift test --list-tests > /dev/null 2>&1; then
    END_TIME=$(date +%s)
    TEST_BUILD_TIME=$((END_TIME - START_TIME))
    TEST_COUNT=$(swift test --list-tests 2>/dev/null | wc -l | tr -d ' ')
    echo "  ✅ Test compile time: ${TEST_BUILD_TIME}s"
    echo "  ✅ Test count: $TEST_COUNT"
    TEST3="PASS"
else
    echo "  ❌ Test compilation failed"
    TEST3="FAIL"
fi

# Test 4: App bundle size
echo ""
echo "Test 4: App Bundle Size"
if [ -d "$PROJECT_ROOT/GaiaFusion.app" ]; then
    BUNDLE_SIZE=$(du -sk "$PROJECT_ROOT/GaiaFusion.app" | awk '{print $1}')
    BUNDLE_SIZE_MB=$(echo "scale=2; $BUNDLE_SIZE / 1024" | bc)
    echo "  ✅ Bundle size: ${BUNDLE_SIZE_MB}MB"
    
    if [ "$BUNDLE_SIZE" -lt 102400 ]; then  # 100MB threshold
        TEST4="PASS"
    else
        TEST4="PARTIAL"
        echo "     (Bundle > 100MB)"
    fi
else
    echo "  ❌ App bundle not found"
    TEST4="FAIL"
fi

# Test 5: DMG compression
echo ""
echo "Test 5: DMG Compression"
if [ -f "$PROJECT_ROOT/GaiaFusion-1.0.0-beta.1.dmg" ]; then
    DMG_SIZE=$(stat -f%z "$PROJECT_ROOT/GaiaFusion-1.0.0-beta.1.dmg")
    DMG_SIZE_MB=$(echo "scale=2; $DMG_SIZE / 1024 / 1024" | bc)
    COMPRESSION=$(echo "scale=2; (1 - $DMG_SIZE / ($BUNDLE_SIZE * 1024)) * 100" | bc)
    echo "  ✅ DMG size: ${DMG_SIZE_MB}MB"
    echo "  ✅ Compression: ${COMPRESSION}%"
    TEST5="PASS"
else
    echo "  ❌ DMG not found"
    TEST5="FAIL"
fi

# Calculate overall
if [ "$TEST1" = "PASS" ] && [ "$TEST2" = "PASS" ] && [ "$TEST3" = "PASS" ] && \
   [ "$TEST4" = "PASS" ] && [ "$TEST5" = "PASS" ]; then
    OVERALL="PASS"
    echo ""
    echo "✅ PQ VALIDATION: PASS"
elif [ "$TEST1" = "FAIL" ] || [ "$TEST2" = "FAIL" ] || [ "$TEST3" = "FAIL" ] || \
     [ "$TEST4" = "FAIL" ] || [ "$TEST5" = "FAIL" ]; then
    OVERALL="FAIL"
    echo ""
    echo "❌ PQ VALIDATION: FAIL"
else
    OVERALL="PARTIAL"
    echo ""
    echo "🟡 PQ VALIDATION: PARTIAL"
fi

# Write report
cat > "$REPORT" << EOF
{
  "validation_type": "PQ",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "version": "1.0.0-beta.1",
  "build": "$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')",
  "metrics": {
    "binary_size": {
      "debug_bytes": $DEBUG_SIZE,
      "release_bytes": $RELEASE_SIZE,
      "reduction_percent": $REDUCTION
    },
    "build_time_seconds": $BUILD_TIME,
    "test_compile_time_seconds": $TEST_BUILD_TIME,
    "test_count": $TEST_COUNT,
    "bundle_size_mb": $BUNDLE_SIZE_MB,
    "dmg_size_mb": $DMG_SIZE_MB,
    "dmg_compression_percent": $COMPRESSION
  },
  "tests": [
    {"name": "Binary Size", "result": "$TEST1"},
    {"name": "Build Performance", "result": "$TEST2"},
    {"name": "Test Compilation", "result": "$TEST3"},
    {"name": "App Bundle Size", "result": "$TEST4"},
    {"name": "DMG Compression", "result": "$TEST5"}
  ],
  "overall_result": "$OVERALL"
}
EOF

echo ""
echo "📄 Report: $REPORT"
echo ""

if [ "$OVERALL" = "FAIL" ]; then
    exit 1
else
    exit 0
fi
