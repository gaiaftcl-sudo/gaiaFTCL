#!/usr/bin/env bash
# Print a falsifiable receipt for what the remote branch tip is (after fetch).
# Usage: bash cells/fusion/scripts/verify_remote_push_receipt.sh [REMOTE] [BRANCH]
# Default REMOTE=origin BRANCH=main
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${ROOT}" ]]; then
  echo "ERROR: not inside a git repository" >&2
  exit 1
fi
cd "${ROOT}"

REMOTE="${1:-origin}"
BRANCH="${2:-main}"

echo "=== Git remote push receipt (C4 witness) ==="
echo "Repository root: ${ROOT}"
echo "Remote name:     ${REMOTE}"
echo "Branch name:     ${BRANCH}"
echo ""

if ! git remote get-url "${REMOTE}" &>/dev/null; then
  echo "ERROR: remote '${REMOTE}' is not configured." >&2
  echo "Configured remotes: $(git remote 2>/dev/null | tr '\n' ' ')" >&2
  exit 1
fi

echo "Remote URL:"
git remote get-url "${REMOTE}"
echo ""

echo "Fetching ${REMOTE} ${BRANCH} ..."
git fetch "${REMOTE}" "${BRANCH}" 2>&1

TRACK="refs/remotes/${REMOTE}/${BRANCH}"
if ! git rev-parse --verify "${TRACK}" &>/dev/null; then
  echo "ERROR: no local tracking ref ${TRACK} after fetch." >&2
  exit 1
fi

SHA="$(git rev-parse "${TRACK}")"
SHORT="$(git rev-parse --short=12 "${TRACK}")"

echo "Tip SHA (40-char): ${SHA}"
echo "Tip SHA (short):   ${SHORT}"
echo ""
echo "Verify (operator copy-paste — must match after any claimed push):"
echo "  git fetch ${REMOTE} && git rev-parse ${REMOTE}/${BRANCH}"
echo "  git ls-remote ${REMOTE} refs/heads/${BRANCH}"
echo ""
echo "GitHub compare (when branch is main):"
echo "  https://github.com/gaiaftcl-sudo/gaiaFTCL/commit/${SHA}"
echo "=== end receipt ==="
