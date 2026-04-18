# Branch protection — one-time setup (GitHub server, not a repo file)

**Authoritative rule:** branch protection and tag rulesets live **on GitHub’s servers**, not in git — otherwise anyone who could push could turn protection off. Local `pre-push` hooks are optional; **Settings** are the substrate.

## Option A — CLI (no browser)

Requires `gh` and `gh auth login` with permission to change repo settings.

```bash
cd "$(git rev-parse --show-toplevel)"
bash GAIAOS/scripts/set_branch_protection.sh
```

Preview JSON only:

```bash
DRY_RUN=1 bash GAIAOS/scripts/set_branch_protection.sh
```

If GitHub returns **422** on branch protection, the required check **names** may not match your Actions job names. Open a green PR, copy the exact check strings from the checks list, then:

```bash
GITHUB_REQUIRED_CONTEXTS='Exact One / Job A,Exact Two / Job B' bash GAIAOS/scripts/set_branch_protection.sh
```

## Option B — Web UI

Tick these in **github.com → your repo → Settings**.

## 1. Branch: `main`

- [ ] **Require a pull request before merging** (1 approval; approver must not be the PR author if you use that rule)
- [ ] **Require status checks to pass** before merge — include at minimum:
  - `receipt-hygiene`
  - `mac-cell-ci`
  - `sparkle-release-lint`
  - `gaiaos-ci` (if green on your tree)
  - workflow currently named GaiaFusion build smoke (file may still be `gaiafusion-gamp5-validation.yml`) — add if green
- [ ] **Require branches to be up to date before merging**
- [ ] **Block force pushes**
- [ ] **Block deletions**
- [ ] **Do not allow bypassing the above** — uncheck “Allow administrators to bypass”

## 2. Tags: `v*`

- [ ] **Tag protection rule** for pattern `v*` — block create / delete / update except for your release role (IQ/OQ/PQ keyed to a tag SHA; moving tags invalidate qualification)

## 3. Local (already in repo)

- [ ] Run once: `bash GAIAOS/scripts/install-git-hooks.sh` — installs `pre-push` (Franklin → M8 refuse)

Emergency M8 bypass only: `GIT_M8_REMOTE_GUARD_BYPASS=1 git push ...` — GitHub rules still apply.
