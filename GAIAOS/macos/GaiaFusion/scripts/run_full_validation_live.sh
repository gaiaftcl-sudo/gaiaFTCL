#!/bin/bash
# LIVE VALIDATION SUITE - Cell-Operator Witnessed
# Build → IQ → OQ → PQ (validation on built artifacts)
# Terminal output visible for Cell-Operator verification

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LIVE_LOG="$PROJECT_ROOT/evidence/LIVE_VALIDATION_${TIMESTAMP}.log"

mkdir -p "$PROJECT_ROOT/evidence"

# Banner
cat << 'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  GaiaFusion v1.0.0-beta.1
  LIVE VALIDATION SUITE
  Build → IQ → OQ → PQ → DMG
  
  Cell-Operator: Watch this terminal for all validation results
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

echo "" | tee "$LIVE_LOG"
echo "Started: $(date)" | tee -a "$LIVE_LOG"
echo "Branch: $(git branch --show-current)" | tee -a "$LIVE_LOG"
echo "Commit: $(git rev-parse --short HEAD)" | tee -a "$LIVE_LOG"
echo "" | tee -a "$LIVE_LOG"

# PHASE 1: Clean old artifacts
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LIVE_LOG"
echo "PHASE 1: CLEAN OLD ARTIFACTS" | tee -a "$LIVE_LOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LIVE_LOG"
echo "" | tee -a "$LIVE_LOG"

cd "$PROJECT_ROOT"

echo "Removing old artifacts..." | tee -a "$LIVE_LOG"
rm -f GaiaFusion.app/Contents/MacOS/GaiaFusion 2>/dev/null || true
rm -rf GaiaFusion.app 2>/dev/null || true
rm -f *.dmg 2>/dev/null || true
echo "  ✅ GaiaFusion.app removed" | tee -a "$LIVE_LOG"
echo "  ✅ *.dmg removed" | tee -a "$LIVE_LOG"
echo "" | tee -a "$LIVE_LOG"

# PHASE 2: Build App Bundle
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LIVE_LOG"
echo "PHASE 2: BUILD APP BUNDLE" | tee -a "$LIVE_LOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LIVE_LOG"
echo "" | tee -a "$LIVE_LOG"

if bash "$SCRIPT_DIR/build_app_bundle.sh" 2>&1 | tee -a "$LIVE_LOG"; then
    echo "" | tee -a "$LIVE_LOG"
    echo "✅ APP BUNDLE BUILD: PASS" | tee -a "$LIVE_LOG"
    BUILD_RESULT="PASS"
else
    echo "" | tee -a "$LIVE_LOG"
    echo "❌ APP BUNDLE BUILD: FAIL" | tee -a "$LIVE_LOG"
    BUILD_RESULT="FAIL"
    echo "" | tee -a "$LIVE_LOG"
    echo "STOPPING: App bundle build must succeed before validation" | tee -a "$LIVE_LOG"
    exit 1
fi

echo "" | tee -a "$LIVE_LOG"

# PHASE 3: IQ Validation (on built artifact)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LIVE_LOG"
echo "PHASE 3: IQ VALIDATION (Installation Qualification)" | tee -a "$LIVE_LOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LIVE_LOG"
echo "" | tee -a "$LIVE_LOG"

if bash "$SCRIPT_DIR/run_iq_validation.sh" 2>&1 | tee -a "$LIVE_LOG"; then
    echo "" | tee -a "$LIVE_LOG"
    echo "✅ IQ VALIDATION: PASS" | tee -a "$LIVE_LOG"
    IQ_RESULT="PASS"
else
    echo "" | tee -a "$LIVE_LOG"
    echo "❌ IQ VALIDATION: FAIL" | tee -a "$LIVE_LOG"
    IQ_RESULT="FAIL"
    echo "" | tee -a "$LIVE_LOG"
    echo "STOPPING: IQ validation must pass before proceeding" | tee -a "$LIVE_LOG"
    exit 1
fi

echo "" | tee -a "$LIVE_LOG"

# PHASE 4: OQ Validation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LIVE_LOG"
echo "PHASE 4: OQ VALIDATION (Operational Qualification)" | tee -a "$LIVE_LOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LIVE_LOG"
echo "" | tee -a "$LIVE_LOG"

if bash "$SCRIPT_DIR/run_oq_validation.sh" 2>&1 | tee -a "$LIVE_LOG"; then
    echo "" | tee -a "$LIVE_LOG"
    echo "✅ OQ VALIDATION: PASS" | tee -a "$LIVE_LOG"
    OQ_RESULT="PASS"
else
    echo "" | tee -a "$LIVE_LOG"
    echo "❌ OQ VALIDATION: FAIL" | tee -a "$LIVE_LOG"
    OQ_RESULT="FAIL"
    echo "" | tee -a "$LIVE_LOG"
    echo "STOPPING: OQ validation must pass before proceeding" | tee -a "$LIVE_LOG"
    exit 1
fi

echo "" | tee -a "$LIVE_LOG"

# PHASE 5: PQ Validation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LIVE_LOG"
echo "PHASE 5: PQ VALIDATION (Performance Qualification)" | tee -a "$LIVE_LOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LIVE_LOG"
echo "" | tee -a "$LIVE_LOG"

if bash "$SCRIPT_DIR/run_pq_validation.sh" 2>&1 | tee -a "$LIVE_LOG"; then
    echo "" | tee -a "$LIVE_LOG"
    echo "✅ PQ VALIDATION: PASS" | tee -a "$LIVE_LOG"
    PQ_RESULT="PASS"
else
    echo "" | tee -a "$LIVE_LOG"
    echo "❌ PQ VALIDATION: FAIL" | tee -a "$LIVE_LOG"
    PQ_RESULT="FAIL"
    echo "" | tee -a "$LIVE_LOG"
    echo "STOPPING: PQ validation must pass before proceeding" | tee -a "$LIVE_LOG"
    exit 1
fi

echo "" | tee -a "$LIVE_LOG"

# PHASE 6: Build DMG
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LIVE_LOG"
echo "PHASE 6: BUILD DMG INSTALLER" | tee -a "$LIVE_LOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LIVE_LOG"
echo "" | tee -a "$LIVE_LOG"

if bash "$SCRIPT_DIR/build_dmg.sh" 2>&1 | tee -a "$LIVE_LOG"; then
    echo "" | tee -a "$LIVE_LOG"
    echo "✅ DMG BUILD: PASS" | tee -a "$LIVE_LOG"
    DMG_RESULT="PASS"
else
    echo "" | tee -a "$LIVE_LOG"
    echo "❌ DMG BUILD: FAIL" | tee -a "$LIVE_LOG"
    DMG_RESULT="FAIL"
    echo "" | tee -a "$LIVE_LOG"
    echo "STOPPING: DMG build failed" | tee -a "$LIVE_LOG"
    exit 1
fi

echo "" | tee -a "$LIVE_LOG"

# Final Summary
cat << 'EOF' | tee -a "$LIVE_LOG"
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✅ ALL VALIDATIONS PASSED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

echo "" | tee -a "$LIVE_LOG"
echo "Validation Results:" | tee -a "$LIVE_LOG"
echo "  ✅ App Bundle Build: PASS" | tee -a "$LIVE_LOG"
echo "  ✅ IQ (Installation): PASS" | tee -a "$LIVE_LOG"
echo "  ✅ OQ (Operational): PASS" | tee -a "$LIVE_LOG"
echo "  ✅ PQ (Performance): PASS" | tee -a "$LIVE_LOG"
echo "  ✅ DMG Installer: PASS" | tee -a "$LIVE_LOG"
echo "" | tee -a "$LIVE_LOG"

echo "Distribution Artifacts:" | tee -a "$LIVE_LOG"
if [ -f "$PROJECT_ROOT/GaiaFusion.app/Contents/MacOS/GaiaFusion" ]; then
    APP_SIZE=$(du -sh "$PROJECT_ROOT/GaiaFusion.app" | cut -f1)
    echo "  📦 GaiaFusion.app ($APP_SIZE)" | tee -a "$LIVE_LOG"
fi

if [ -f "$PROJECT_ROOT/GaiaFusion-1.0.0-beta.1.dmg" ]; then
    DMG_SIZE=$(du -sh "$PROJECT_ROOT/GaiaFusion-1.0.0-beta.1.dmg" | cut -f1)
    echo "  💿 GaiaFusion-1.0.0-beta.1.dmg ($DMG_SIZE)" | tee -a "$LIVE_LOG"
fi

echo "" | tee -a "$LIVE_LOG"

echo "Evidence Files:" | tee -a "$LIVE_LOG"
IQ_REPORT=$(ls -t "$PROJECT_ROOT/evidence/iq/IQ_VALIDATION_"*.json 2>/dev/null | head -1)
OQ_REPORT=$(ls -t "$PROJECT_ROOT/evidence/oq/OQ_VALIDATION_"*.json 2>/dev/null | head -1)
PQ_REPORT=$(ls -t "$PROJECT_ROOT/evidence/pq/PQ_VALIDATION_"*.json 2>/dev/null | head -1)

if [ -n "$IQ_REPORT" ]; then
    echo "  📄 IQ: $(basename "$IQ_REPORT")" | tee -a "$LIVE_LOG"
fi
if [ -n "$OQ_REPORT" ]; then
    echo "  📄 OQ: $(basename "$OQ_REPORT")" | tee -a "$LIVE_LOG"
fi
if [ -n "$PQ_REPORT" ]; then
    echo "  📄 PQ: $(basename "$PQ_REPORT")" | tee -a "$LIVE_LOG"
fi

echo "" | tee -a "$LIVE_LOG"
echo "📝 Complete log: $LIVE_LOG" | tee -a "$LIVE_LOG"
echo "" | tee -a "$LIVE_LOG"

cat << 'EOF' | tee -a "$LIVE_LOG"
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  READY FOR VISUAL VERIFICATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

echo "" | tee -a "$LIVE_LOG"
echo "Cell-Operator Next Steps:" | tee -a "$LIVE_LOG"
echo "  1. Launch app:  open GaiaFusion.app" | tee -a "$LIVE_LOG"
echo "  2. Run 7-check protocol: RUNTIME_VERIFICATION_PROTOCOL_20260415.md" | tee -a "$LIVE_LOG"
echo "  3. Test DMG:    open GaiaFusion-1.0.0-beta.1.dmg" | tee -a "$LIVE_LOG"
echo "  4. If all pass: git commit && git push && gh pr create" | tee -a "$LIVE_LOG"
echo "" | tee -a "$LIVE_LOG"

echo "Completed: $(date)" | tee -a "$LIVE_LOG"
echo "" | tee -a "$LIVE_LOG"

exit 0
