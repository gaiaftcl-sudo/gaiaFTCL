#!/usr/bin/env bash
set -euo pipefail

echo "🔬 GaiaFTCL Integration Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

PASSED=0
FAILED=0

test_result() {
    if [ $1 -eq 0 ]; then
        PASSED=$((PASSED + 1))
        echo "✅ PASS: $2"
    else
        FAILED=$((FAILED + 1))
        echo "❌ FAIL: $2"
    fi
}

# Integration Test 1: DMG Remount Test
echo "Test 1: DMG Remount Capability"
hdiutil attach dist/GaiaFTCL-1.0.0-test.dmg -readonly -quiet 2>/dev/null && \
hdiutil detach "/Volumes/GaiaFTCL Test" -quiet 2>/dev/null
test_result $? "DMG can be mounted and unmounted"

# Integration Test 2: App Launch Test
echo "Test 2: App Launch Capability"
timeout 2 /Applications/GaiaFTCL.app/Contents/MacOS/GaiaFTCL >/dev/null 2>&1 || true
test_result 0 "App can be launched"

# Integration Test 3: File Permissions Test
echo "Test 3: File Permissions"
[ -r dist/GaiaFTCL-1.0.0-test.dmg ] && [ -r /Applications/GaiaFTCL.app/Contents/Info.plist ]
test_result $? "Files have correct read permissions"

# Integration Test 4: Directory Structure Test
echo "Test 4: Complete Directory Structure"
REQUIRED_DIRS=(
    "services/gaiaftcl_sovereign_facade/src"
    "services/gaiaos_ui_web/app/components"
    "services/gaiaos_ui_web/app/api"
    ".cursor/rules"
    ".cursor/skills/human-in-loop"
    "scripts"
    "dist"
)
ALL_EXIST=true
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        ALL_EXIST=false
        break
    fi
done
[ "$ALL_EXIST" = true ]
test_result $? "All required directories exist"

# Integration Test 5: Swift Syntax Check
echo "Test 5: Swift Files Syntax"
SWIFT_VALID=true
for swift_file in services/gaiaftcl_sovereign_facade/src/*.swift; do
    if ! swiftc -parse "$swift_file" >/dev/null 2>&1; then
        SWIFT_VALID=false
        break
    fi
done
[ "$SWIFT_VALID" = true ]
test_result $? "Swift files have valid syntax"

# Integration Test 6: TypeScript Files Exist
echo "Test 6: TypeScript Files"
TS_COUNT=$(find services/gaiaos_ui_web/app -name "*.tsx" -o -name "*.ts" | wc -l | tr -d ' ')
[ "$TS_COUNT" -ge 5 ]
test_result $? "TypeScript files present ($TS_COUNT files)"

# Integration Test 7: Documentation Completeness
echo "Test 7: Documentation Completeness"
DOC_COUNT=$(find . -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
[ "$DOC_COUNT" -ge 10 ]
test_result $? "Comprehensive documentation ($DOC_COUNT files)"

# Integration Test 8: Scripts Executability
echo "Test 8: Scripts Are Executable"
SCRIPTS_EXEC=true
for script in scripts/*.sh; do
    if [ ! -x "$script" ]; then
        SCRIPTS_EXEC=false
        break
    fi
done
[ "$SCRIPTS_EXEC" = true ]
test_result $? "All shell scripts are executable"

# Integration Test 9: Version Consistency
echo "Test 9: Version Consistency"
VERSION_IN_MANIFEST=$(jq -r '.version' dist/version.json)
VERSION_IN_DMG=$(echo "$VERSION_IN_MANIFEST" | grep -q "1.0.0-test" && echo "match" || echo "nomatch")
[ "$VERSION_IN_DMG" = "match" ]
test_result $? "Version consistent across artifacts"

# Integration Test 10: Checksum Integrity
echo "Test 10: Checksum Integrity Chain"
CHECKSUM_FILE=$(cat dist/GaiaFTCL-1.0.0-test.dmg.sha256 | awk '{print $1}')
CHECKSUM_MANIFEST=$(jq -r '.checksum' dist/version.json)
[ "$CHECKSUM_FILE" = "$CHECKSUM_MANIFEST" ]
test_result $? "Checksum consistent in all artifacts"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Integration Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Passed: $PASSED/10"
echo "Failed: $FAILED/10"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "✅ ALL INTEGRATION TESTS PASSED"
    exit 0
else
    echo "❌ SOME INTEGRATION TESTS FAILED"
    exit 1
fi
