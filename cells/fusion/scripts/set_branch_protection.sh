#!/usr/bin/env bash
# Apply GitHub branch protection on main + tag ruleset for v* — no browser required.
# Branch protection is server-side policy, not a file in the repo (so pushes cannot turn it off).
#
# Prerequisites: gh CLI, `gh auth login` with admin/settings permission on the repo.
#
#   cd "$(git rev-parse --show-toplevel)"
#   bash cells/fusion/scripts/set_branch_protection.sh
#
# Required status check names must match what GitHub shows on a green PR (often "Workflow name / job name").
# Override with comma-separated list:
#   GITHUB_REQUIRED_CONTEXTS='Foo / Bar,Baz / Qux' bash cells/fusion/scripts/set_branch_protection.sh
#
# Dry run (print JSON, no API calls):
#   DRY_RUN=1 bash cells/fusion/scripts/set_branch_protection.sh

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI not found. Install: https://cli.github.com" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh not authenticated. Run: gh auth login" >&2
  exit 1
fi

if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
  OWNER_REPO="$GITHUB_REPOSITORY"
else
  OWNER_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
fi

BRANCH="${PROTECT_BRANCH:-main}"

echo "Repository: ${OWNER_REPO}"
echo "Branch:     ${BRANCH}"
echo ""

DEFAULT_CTX=$(cat <<'EOF'
Receipt Hygiene / Refuse unsigned M-provenance evidence
Sparkle Release Lint / Refuse placeholder SUPublicEDKey / SUFeedURL
GAIAOS CI / Test Rust (GAIAOS tree — Linux subset)
GAIAOS CI / Test Python (GAIAOS tree — unit scope)
Mac Cell CI / GaiaFusion build+xcodebuild test (CI headless smoke)
Mac Cell CI / MacHealth — SIL V2 swift test (CI headless smoke)
GaiaFusion Build Smoke (was GAMP 5 Validation — renamed for honesty) / GaiaFusion build smoke (CI headless — not operator OQ)
EOF
)

if [[ -n "${GITHUB_REQUIRED_CONTEXTS:-}" ]]; then
  export _CTX_LINES="${GITHUB_REQUIRED_CONTEXTS}"
else
  export _CTX_LINES="${DEFAULT_CTX}"
fi

BRANCH_BODY="$(python3 <<'PY'
import json, os
raw = os.environ["_CTX_LINES"]
if "," in raw and "\n" not in raw.strip():
    contexts = [x.strip() for x in raw.split(",") if x.strip()]
else:
    contexts = [x.strip() for x in raw.splitlines() if x.strip()]
body = {
    "required_status_checks": {"strict": True, "contexts": contexts},
    "enforce_admins": True,
    "required_pull_request_reviews": {
        "dismiss_stale_reviews": True,
        "require_code_owner_reviews": False,
        "required_approving_review_count": 1,
    },
    "restrictions": None,
    "required_linear_history": False,
    "allow_force_pushes": False,
    "allow_deletions": False,
    "required_conversation_resolution": True,
    "lock_branch": False,
    "allow_fork_syncing": True,
}
print(json.dumps(body))
PY
)"

RULESET_BODY="$(python3 <<'PY'
import json
print(json.dumps({
    "name": "protect-v-tags",
    "target": "tag",
    "enforcement": "active",
    "conditions": {
        "ref_name": {
            "include": ["refs/tags/v*"],
            "exclude": []
        }
    },
    "rules": [
        {"type": "deletion"},
        {"type": "non_fast_forward"},
    ],
}))
PY
)"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "=== Branch protection JSON ==="
  echo "$BRANCH_BODY" | python3 -m json.tool
  echo ""
  echo "=== Tag ruleset JSON ==="
  echo "$RULESET_BODY" | python3 -m json.tool
  exit 0
fi

echo "Applying branch protection via GitHub API..."
echo "$BRANCH_BODY" | gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "repos/${OWNER_REPO}/branches/${BRANCH}/protection" \
  --input -

echo "OK: branch protection updated for ${BRANCH}."
echo ""

echo "Creating tag ruleset for refs/tags/v* ..."
set +e
OUT="$(echo "$RULESET_BODY" | gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "repos/${OWNER_REPO}/rulesets" \
  --input - 2>&1)"
RC=$?
set -e

if [[ "$RC" -ne 0 ]]; then
  echo "WARN: tag ruleset API failed (duplicate name, token scope, or API shape). Fix in UI or delete existing ruleset and re-run." >&2
  echo "$OUT" >&2
  echo "Manual: Settings → Rules → Rulesets → New ruleset → Target: tags → include refs/tags/v*" >&2
else
  echo "OK: tag ruleset created."
  echo "$OUT"
fi

echo ""
echo "Verify: Settings → Branches → ${BRANCH}, and Settings → Rules → Rulesets."
echo "If branch protection failed with 422, run DRY_RUN=1, inspect contexts, and compare to a green PR's check names."
