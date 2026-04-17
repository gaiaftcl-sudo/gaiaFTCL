#!/usr/bin/env bash
set -euo pipefail

echo "🧪 GaiaFTCL Full Test Suite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

PASSED=0
FAILED=0
TOTAL=0

test_result() {
    TOTAL=$((TOTAL + 1))
    if [ $1 -eq 0 ]; then
        PASSED=$((PASSED + 1))
        echo "✅ PASS: $2"
    else
        FAILED=$((FAILED + 1))
        echo "❌ FAIL: $2"
    fi
}

# Test Suite 1: Build System
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite 1: Build System"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test 1.1: Build script exists and is executable
if [ -x scripts/build_test_dmg.sh ]; then
    test_result 0 "Build script exists and is executable"
else
    test_result 1 "Build script exists and is executable"
fi

# Test 1.2: Build directory can be created
mkdir -p build/test_suite && test_result 0 "Build directory creation" || test_result 1 "Build directory creation"

# Test 1.3: Dist directory exists
if [ -d dist ]; then
    test_result 0 "Dist directory exists"
else
    test_result 1 "Dist directory exists"
fi

# Test 1.4: DMG file exists
if [ -f dist/GaiaFTCL-1.0.0-test.dmg ]; then
    test_result 0 "DMG file exists"
else
    test_result 1 "DMG file exists"
fi

# Test 1.5: Checksum file exists
if [ -f dist/GaiaFTCL-1.0.0-test.dmg.sha256 ]; then
    test_result 0 "Checksum file exists"
else
    test_result 1 "Checksum file exists"
fi

# Test 1.6: Version manifest exists
if [ -f dist/version.json ]; then
    test_result 0 "Version manifest exists"
else
    test_result 1 "Version manifest exists"
fi

echo ""

# Test Suite 2: File Integrity
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite 2: File Integrity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test 2.1: DMG size is reasonable
SIZE=$(stat -f%z dist/GaiaFTCL-1.0.0-test.dmg 2>/dev/null || echo 0)
if [ $SIZE -gt 1000 ] && [ $SIZE -lt 100000000 ]; then
    test_result 0 "DMG size is reasonable ($SIZE bytes)"
else
    test_result 1 "DMG size is reasonable ($SIZE bytes)"
fi

# Test 2.2: Checksum verification
EXPECTED=$(cat dist/GaiaFTCL-1.0.0-test.dmg.sha256 | awk '{print $1}')
ACTUAL=$(shasum -a 256 dist/GaiaFTCL-1.0.0-test.dmg | awk '{print $1}')
if [ "$EXPECTED" = "$ACTUAL" ]; then
    test_result 0 "Checksum verification matches"
else
    test_result 1 "Checksum verification matches"
fi

# Test 2.3: Version manifest is valid JSON
if jq empty dist/version.json 2>/dev/null; then
    test_result 0 "Version manifest is valid JSON"
else
    test_result 1 "Version manifest is valid JSON"
fi

# Test 2.4: Version manifest has required fields
REQUIRED_FIELDS=("version" "build_date" "dmg_name" "checksum" "size")
ALL_PRESENT=true
for field in "${REQUIRED_FIELDS[@]}"; do
    if ! jq -e ".$field" dist/version.json >/dev/null 2>&1; then
        ALL_PRESENT=false
        break
    fi
done
if [ "$ALL_PRESENT" = true ]; then
    test_result 0 "Version manifest has all required fields"
else
    test_result 1 "Version manifest has all required fields"
fi

echo ""

# Test Suite 3: Installation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite 3: Installation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test 3.1: App exists in Applications
if [ -d /Applications/GaiaFTCL.app ]; then
    test_result 0 "App exists in /Applications"
else
    test_result 1 "App exists in /Applications"
fi

# Test 3.2: App bundle has Contents directory
if [ -d /Applications/GaiaFTCL.app/Contents ]; then
    test_result 0 "App bundle has Contents directory"
else
    test_result 1 "App bundle has Contents directory"
fi

# Test 3.3: Info.plist exists
if [ -f /Applications/GaiaFTCL.app/Contents/Info.plist ]; then
    test_result 0 "Info.plist exists"
else
    test_result 1 "Info.plist exists"
fi

# Test 3.4: MacOS directory exists
if [ -d /Applications/GaiaFTCL.app/Contents/MacOS ]; then
    test_result 0 "MacOS directory exists"
else
    test_result 1 "MacOS directory exists"
fi

# Test 3.5: Executable exists and is executable
if [ -x /Applications/GaiaFTCL.app/Contents/MacOS/GaiaFTCL ]; then
    test_result 0 "Executable exists and is executable"
else
    test_result 1 "Executable exists and is executable"
fi

echo ""

# Test Suite 4: Documentation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite 4: Documentation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DOCS=(
    "HUMAN_IN_LOOP_PROTOCOL.md"
    "TESTING_PROTOCOL.md"
    "FINAL_IMPLEMENTATION_SUMMARY.md"
    "DMG_DISTRIBUTION_STATUS.md"
    "COMPLETE_CLOSURE.md"
    "TEST_EXECUTION_EVIDENCE.md"
)

for doc in "${DOCS[@]}"; do
    if [ -f "$doc" ]; then
        test_result 0 "Documentation exists: $doc"
    else
        test_result 1 "Documentation exists: $doc"
    fi
done

echo ""

# Test Suite 5: Swift Source Files
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite 5: Swift Source Files"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

SWIFT_FILES=(
    "services/gaiaftcl_sovereign_facade/src/main.swift"
    "services/gaiaftcl_sovereign_facade/src/s4_ingestor.swift"
    "services/gaiaftcl_sovereign_facade/src/identity_mooring.swift"
    "services/gaiaftcl_sovereign_facade/src/projection_engine.swift"
    "services/gaiaftcl_sovereign_facade/src/color_state_projection.swift"
    "services/gaiaftcl_sovereign_facade/src/state_dashboard.swift"
)

for swift_file in "${SWIFT_FILES[@]}"; do
    if [ -f "$swift_file" ]; then
        test_result 0 "Swift file exists: $(basename $swift_file)"
    else
        test_result 1 "Swift file exists: $(basename $swift_file)"
    fi
done

echo ""

# Test Suite 6: Web Distribution
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite 6: Web Distribution"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

WEB_FILES=(
    "services/gaiaos_ui_web/app/components/DownloadButton.tsx"
    "services/gaiaos_ui_web/app/dmgInstall/route.ts"
    "services/gaiaos_ui_web/app/api/version/route.ts"
    "services/gaiaos_ui_web/app/api/analytics/download/route.ts"
)

for web_file in "${WEB_FILES[@]}"; do
    if [ -f "$web_file" ]; then
        test_result 0 "Web file exists: $(basename $web_file)"
    else
        test_result 1 "Web file exists: $(basename $web_file)"
    fi
done

echo ""

# Test Suite 7: Invariant Rules
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite 7: Invariant Rules"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test 7.1: Human-in-loop invariant exists
if [ -f .cursor/rules/human-in-loop-invariant.mdc ]; then
    test_result 0 "Human-in-loop invariant rule exists"
else
    test_result 1 "Human-in-loop invariant rule exists"
fi

# Test 7.2: Skill exists
if [ -f .cursor/skills/human-in-loop/SKILL.md ]; then
    test_result 0 "Human-in-loop skill exists"
else
    test_result 1 "Human-in-loop skill exists"
fi

# Test 7.3: .cursorrules exists
if [ -f .cursorrules ]; then
    test_result 0 ".cursorrules file exists"
else
    test_result 1 ".cursorrules file exists"
fi

echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Total Tests: $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "Success Rate: $(awk "BEGIN {printf \"%.1f\", ($PASSED/$TOTAL)*100}")%"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "✅ ALL TESTS PASSED"
    exit 0
else
    echo "❌ SOME TESTS FAILED"
    exit 1
fi
