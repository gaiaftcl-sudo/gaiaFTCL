# Remote git — agent rules (committed copy)

**GitHub branch protection on `main`** is authoritative (no force-push, no delete, required checks). See [BRANCH_PROTECTION_CHECKLIST.md](BRANCH_PROTECTION_CHECKLIST.md).  
Local: `pre-push` runs **Franklin** then **M8 refuse** (`pre-push-franklin`, `pre-push-m8-refuse`).

## Agent must not

1. `git push --force`, `--force-with-lease`, or `git push origin :main` / delete `main` or `develop` unless the operator explicitly ordered that exact operation in the current task.
2. Suggest rewriting `main` history or “fixing” the remote with force — respond **BLOCKED** and give safe next steps (`git fetch`, `git log`).
3. `git reset --hard`, `git clean -fd`, or discard work unless the operator asked to discard named paths.
4. After any push, report **remote**, **branch**, **commit SHA**.

## Emergency bypass (local hook only)

`GIT_M8_REMOTE_GUARD_BYPASS=1 git push ...` — use only in emergencies; GitHub rules still apply.

## Cursor

Copy this file into `.cursor/rules/` as `remote-git-catastrophe-prevention.mdc` with frontmatter `alwaysApply: true` if your workspace does not load docs automatically.
