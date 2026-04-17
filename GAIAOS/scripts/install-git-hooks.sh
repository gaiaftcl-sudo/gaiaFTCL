#!/bin/bash
# Install Franklin lockdown Git hooks

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_SOURCE="${REPO_ROOT}/scripts/git-hooks"
HOOKS_TARGET="${REPO_ROOT}/.git/hooks"

echo "=========================================="
echo "FRANKLIN LOCKDOWN — Installing Git Hooks"
echo "=========================================="
echo ""

if [ ! -d "${HOOKS_TARGET}" ]; then
    echo "❌ Error: .git/hooks directory not found"
    echo "   Are you in a Git repository?"
    exit 1
fi

# Install pre-push hook
echo "Installing pre-push hook..."
cp "${HOOKS_SOURCE}/pre-push" "${HOOKS_TARGET}/pre-push"
chmod +x "${HOOKS_TARGET}/pre-push"
echo "✅ Installed: ${HOOKS_TARGET}/pre-push"
echo ""

echo "=========================================="
echo "✅ Git hooks installed successfully"
echo "=========================================="
echo ""
echo "ACTIVE HOOKS:"
echo "  • pre-push: Validates canaries when protected paths change"
echo ""
echo "PROTECTED PATHS:"
echo "  • services/gaiaos_ui_tester_mcp/src/main.rs"
echo "  • services/gaiaos_ui_tester_mcp/src/treasury/"
echo "  • services/gaiaos_ui_tester_mcp/src/enforcement.rs"
echo "  • services/gaiaos_ui_tester_mcp/src/uum8d_*"
echo "  • evidence/closure_game/CANONICALS.SHA256"
echo "  • services/gaiaos_ui_tester_mcp/tests/no_outflow_guard.sh"
echo "  • services/gaiaos_ui_tester_mcp/tests/run_all_canaries.sh"
echo ""
echo "To bypass (NOT RECOMMENDED):"
echo "  git push --no-verify"
echo ""
