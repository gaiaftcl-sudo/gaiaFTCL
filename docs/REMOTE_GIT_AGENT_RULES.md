# Remote git — agent rules (committed copy)

**GitHub server-side settings** on `main` (if enabled in the repo’s Settings) are authoritative for force-push / deletion / linear history — not anything in this file.

**Local reality:** `core.hooksPath` is typically **`.githooks`** for **Git LFS**; that directory’s `pre-push` is the LFS hook. The old **`GAIAOS/scripts/git-hooks/*`** Franklin/M8 scripts were **never wired** when `hooksPath` points at `.githooks`, so they did not run; those files and the installer are **removed** from the tree to stop false confidence.

## Agent must not

1. `git push --force`, `--force-with-lease`, or `git push origin :main` / delete `main` or `develop` unless the operator explicitly ordered that exact operation in the current task.
2. Suggest rewriting `main` history or “fixing” the remote with force — respond **BLOCKED** and give safe next steps (`git fetch`, `git log`).
3. `git reset --hard`, `git clean -fd`, or discard work unless the operator asked to discard named paths.
4. After any push, report **remote**, **branch**, **commit SHA**.

## Push receipt (mandatory — no hollow claims)

Saying “pushed to the remote” without something the operator can **re-run and verify** is **REFUSED** (narrative-only / S4).

After any successful `git push`, the report must include **all** of:

| Field | Example |
|--------|---------|
| Remote name | `origin` |
| Branch name | `main` |
| Tip SHA (40 hex) | `a1b2c3d4e5f6…` (full hash) |
| Verify command | `git fetch origin && git rev-parse origin/main` |
| Cross-check | `git ls-remote origin refs/heads/main` |

The operator must be able to run the verify commands and see a SHA that **matches** the claimed tip. If you cannot provide that, the correct statement is **“not verified”** or **BLOCKED**, not “pushed.”

**Helper (prints fetch + SHA + copy-paste verify lines):**

```bash
bash GAIAOS/scripts/verify_remote_push_receipt.sh origin main
```

Optional: paste **one line** of real `git ls-remote` / `git rev-parse` stdout from the machine that performed the push.

## Cursor

Copy this file into `.cursor/rules/` as `remote-git-catastrophe-prevention.mdc` with frontmatter `alwaysApply: true` if your workspace does not load docs automatically.
