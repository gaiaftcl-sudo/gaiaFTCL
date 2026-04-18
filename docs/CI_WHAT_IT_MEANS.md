# CI — what it means now

**Ground truth:** There are **no** GitHub Actions workflow files in this repository. Nothing in `.github/workflows/` runs on GitHub’s servers for this tree.

**What that implies:** A “green check” from GitHub Actions is **not** something this repo defines anymore. Validation is **local** (or whatever you run yourself): `cargo`, `pytest`, Xcode, Swift tests, etc.

**What it does *not* imply:** This document no longer maps per-workfile CI behavior — that layer was **removed** on purpose to drop automation litter, not project code.

**Remote:** `origin` → `gaiaftcl-sudo/gaiaFTCL` remains the storage for commits. That is separate from Actions.

See [REMOTE_GIT_AGENT_RULES.md](REMOTE_GIT_AGENT_RULES.md) for push receipts (honesty in chat, not CI).
