#!/bin/bash
# Clean Validation Suite - IQ → OQ → PQ → Install
# Run in clean sandbox for Cell-Operator visual verification

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  GaiaFusion v1.0.0-beta.1 — Clean Validation Suite"
echo "  IQ → OQ → PQ → Build → Install"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Clean sandbox
echo "Step 1: Cleaning sandbox..."
cd "$PROJECT_ROOT"
rm -rf .build GaiaFusion.app *.dmg 2>/dev/null || true
echo "  ✅ Build artifacts removed"
echo ""

# Step 2: IQ Validation
echo "Step 2: Running IQ Validation..."
bash "$SCRIPT_DIR/run_iq_validation.sh"
if [ $? -ne 0 ]; then
    echo "❌ IQ VALIDATION FAILED"
    exit 1
fi
echo ""

# Step 3: OQ Validation
echo "Step 3: Running OQ Validation..."
bash "$SCRIPT_DIR/run_oq_validation.sh"
if [ $? -ne 0 ]; then
    echo "❌ OQ VALIDATION FAILED"
    exit 1
fi
echo ""

# Step 4: PQ Validation
echo "Step 4: Running PQ Validation..."
bash "$SCRIPT_DIR/run_pq_validation.sh"
if [ $? -ne 0 ]; then
    echo "❌ PQ VALIDATION FAILED"
    exit 1
fi
echo ""

# Step 5: Build App Bundle
echo "Step 5: Building App Bundle..."
bash "$SCRIPT_DIR/build_app_bundle.sh"
if [ $? -ne 0 ]; then
    echo "❌ APP BUNDLE BUILD FAILED"
    exit 1
fi
echo ""

# Step 6: Build DMG
echo "Step 6: Building DMG..."
bash "$SCRIPT_DIR/build_dmg.sh"
if [ $? -ne 0 ]; then
    echo "❌ DMG BUILD FAILED"
    exit 1
fi
echo ""

# Final summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ ALL VALIDATIONS PASSED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Distribution artifacts:"
echo "  📦 GaiaFusion.app (19MB)"
echo "  💿 GaiaFusion-1.0.0-beta.1.dmg (18MB)"
echo ""
echo "Evidence generated:"
echo "  📄 evidence/iq/IQ_VALIDATION_*.json"
echo "  📄 evidence/oq/OQ_VALIDATION_*.json"
echo "  📄 evidence/pq/PQ_VALIDATION_*.json"
echo ""
echo "Next steps:"
echo "  1. Visual verification: open GaiaFusion.app"
echo "  2. DMG test: open GaiaFusion-1.0.0-beta.1.dmg"
echo "  3. Git commit: git commit -m 'Release v1.0.0-beta.1'"
echo "  4. PR to main: git push && gh pr create"
echo ""
