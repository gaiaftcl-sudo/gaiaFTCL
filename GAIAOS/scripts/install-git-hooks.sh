#!/bin/bash
# Install Franklin + M8 Git hooks (repo root = git toplevel, works from FoT8D monorepo)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"
HOOKS_SOURCE="${REPO_ROOT}/GAIAOS/scripts/git-hooks"
HOOKS_TARGET="${REPO_ROOT}/.git/hooks"

echo "=========================================="
echo "GAIAFTCL — Installing Git Hooks (M8 + Franklin)"
echo "=========================================="
echo ""

if [ ! -d "${HOOKS_TARGET}" ]; then
    echo "❌ Error: .git/hooks not found at ${HOOKS_TARGET}"
    echo "   Run from a clone whose git root is FoT8D (not a subfolder-only checkout)."
    exit 1
fi

echo "Repo root: ${REPO_ROOT}"
echo "Installing pre-push hook..."
cp "${HOOKS_SOURCE}/pre-push" "${HOOKS_TARGET}/pre-push"
chmod +x "${HOOKS_TARGET}/pre-push"
echo "✅ Installed: ${HOOKS_TARGET}/pre-push"
echo ""

echo "=========================================="
echo "✅ Git hooks installed successfully"
echo "=========================================="
echo ""
echo "PHASE 1 — M8 remote guard (protected refs: main, develop)"
echo "  • Blocks non-fast-forward (force-push) and delete of protected refs"
echo "  • Bypass (emergency): GIT_M8_REMOTE_GUARD_BYPASS=1 git push ..."
echo ""
echo "PHASE 2 — FRANKLIN LOCKDOWN (when treasury/MCP paths change)"
echo "  • Validates canaries when protected paths change"
echo ""
echo "PROTECTED PATHS (Franklin):"
echo "  • services/gaiaos_ui_tester_mcp/… (see pre-push source)"
echo ""
echo "To bypass ALL hooks (NOT RECOMMENDED):"
echo "  git push --no-verify"
echo ""
