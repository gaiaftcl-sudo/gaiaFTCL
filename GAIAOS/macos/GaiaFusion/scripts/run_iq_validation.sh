#!/bin/bash
# IQ Validation - Installation Qualification
# Automated verification of installation and configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVIDENCE_DIR="$PROJECT_ROOT/evidence/iq"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT="$EVIDENCE_DIR/IQ_VALIDATION_${TIMESTAMP}.json"

mkdir -p "$EVIDENCE_DIR"

echo "🔍 IQ Validation - Installation Qualification"
echo "=============================================="
echo ""

# Initialize report
cat > "$REPORT" << EOF
{
  "validation_type": "IQ",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "version": "1.0.0-beta.1",
  "build": "$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')",
  "tests": []
}
EOF

# Test 1: Binary exists and is executable
echo "Test 1: Binary Verification"
if [ -x "$PROJECT_ROOT/.build/arm64-apple-macosx/release/GaiaFusion" ]; then
    SIZE=$(stat -f%z "$PROJECT_ROOT/.build/arm64-apple-macosx/release/GaiaFusion")
    echo "  ✅ Release binary exists: $(numfmt --to=iec-i --suffix=B $SIZE 2>/dev/null || echo ${SIZE}B)"
    TEST1="PASS"
else
    echo "  ❌ Release binary not found or not executable"
    TEST1="FAIL"
fi

# Test 2: App bundle structure
echo "Test 2: App Bundle Structure"
if [ -d "$PROJECT_ROOT/GaiaFusion.app" ]; then
    echo "  ✅ App bundle exists"
    
    # Check required directories
    REQUIRED_DIRS=(
        "Contents"
        "Contents/MacOS"
        "Contents/Resources"
    )
    
    BUNDLE_OK=true
    for dir in "${REQUIRED_DIRS[@]}"; do
        if [ -d "$PROJECT_ROOT/GaiaFusion.app/$dir" ]; then
            echo "     ✅ $dir/"
        else
            echo "     ❌ Missing: $dir/"
            BUNDLE_OK=false
        fi
    done
    
    if $BUNDLE_OK; then
        TEST2="PASS"
    else
        TEST2="FAIL"
    fi
else
    echo "  ❌ App bundle not found"
    TEST2="FAIL"
fi

# Test 3: Info.plist validation
echo "Test 3: Info.plist Validation"
if [ -f "$PROJECT_ROOT/GaiaFusion.app/Contents/Info.plist" ]; then
    if plutil -lint "$PROJECT_ROOT/GaiaFusion.app/Contents/Info.plist" > /dev/null 2>&1; then
        echo "  ✅ Info.plist is valid XML"
        VERSION=$(plutil -extract CFBundleShortVersionString raw "$PROJECT_ROOT/GaiaFusion.app/Contents/Info.plist" 2>/dev/null || echo "unknown")
        BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw "$PROJECT_ROOT/GaiaFusion.app/Contents/Info.plist" 2>/dev/null || echo "unknown")
        echo "     Version: $VERSION"
        echo "     Bundle ID: $BUNDLE_ID"
        TEST3="PASS"
    else
        echo "  ❌ Info.plist invalid"
        TEST3="FAIL"
    fi
else
    echo "  ❌ Info.plist not found"
    TEST3="FAIL"
fi

# Test 4: Required resources
echo "Test 4: Required Resources"
REQUIRED_RESOURCES=(
    "fusion-web"
    "default.metallib"
    "gaiafusion_substrate.wasm"
    "gaiafusion_substrate_bindgen.js"
)

RESOURCES_OK=true
for res in "${REQUIRED_RESOURCES[@]}"; do
    if [ -e "$PROJECT_ROOT/GaiaFusion.app/Contents/Resources/$res" ]; then
        echo "  ✅ $res"
    else
        echo "  ❌ Missing: $res"
        RESOURCES_OK=false
    fi
done

if $RESOURCES_OK; then
    TEST4="PASS"
else
    TEST4="FAIL"
fi

# Test 5: Source code compilation
echo "Test 5: Source Code Compilation"
cd "$PROJECT_ROOT"
if swift build --configuration release --product GaiaFusion > /dev/null 2>&1; then
    echo "  ✅ Source compiles without errors"
    TEST5="PASS"
else
    echo "  ❌ Compilation errors"
    TEST5="FAIL"
fi

# Test 6: Test suite compilation
echo "Test 6: Test Suite Compilation"
if swift test --list-tests > /dev/null 2>&1; then
    TEST_COUNT=$(swift test --list-tests 2>/dev/null | grep -c "GaiaFusionTests" || echo "0")
    echo "  ✅ Test suite compiles ($TEST_COUNT tests)"
    TEST6="PASS"
else
    echo "  ❌ Test compilation failed"
    TEST6="FAIL"
fi

# Calculate overall status
if [ "$TEST1" = "PASS" ] && [ "$TEST2" = "PASS" ] && [ "$TEST3" = "PASS" ] && \
   [ "$TEST4" = "PASS" ] && [ "$TEST5" = "PASS" ] && [ "$TEST6" = "PASS" ]; then
    OVERALL="PASS"
    echo ""
    echo "✅ IQ VALIDATION: PASS"
else
    OVERALL="FAIL"
    echo ""
    echo "❌ IQ VALIDATION: FAIL"
fi

# Write JSON report
jq --arg t1 "$TEST1" --arg t2 "$TEST2" --arg t3 "$TEST3" \
   --arg t4 "$TEST4" --arg t5 "$TEST5" --arg t6 "$TEST6" \
   --arg overall "$OVERALL" \
   '.tests = [
     {"name": "Binary Verification", "result": $t1},
     {"name": "App Bundle Structure", "result": $t2},
     {"name": "Info.plist Validation", "result": $t3},
     {"name": "Required Resources", "result": $t4},
     {"name": "Source Compilation", "result": $t5},
     {"name": "Test Suite Compilation", "result": $t6}
   ] | .overall_result = $overall' "$REPORT" > "${REPORT}.tmp" && mv "${REPORT}.tmp" "$REPORT"

echo ""
echo "📄 Report: $REPORT"
echo ""

if [ "$OVERALL" = "PASS" ]; then
    exit 0
else
    exit 1
fi
