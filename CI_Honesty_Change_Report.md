# CI Honesty Change Report — GaiaFTCL Mac Cell

> **Obsolete (2026‑04‑18):** GitHub Actions workflows were **removed** from this repository on purpose. This file is historical. Current truth: [`docs/CI_WHAT_IT_MEANS.md`](docs/CI_WHAT_IT_MEANS.md).

**Date:** 2026‑04‑18
**Scope:** four existing workflows + two proposed workflows + one doc.
**Predecessor:** `GitHubActions_Value_Review.md` (per‑workflow verdict).
**Companion:** `docs/CI_WHAT_IT_MEANS.md` (target‑state map).

---

## 0. Outcome summary

| Artifact | What happened |
| --- | --- |
| `docs/CI_WHAT_IT_MEANS.md` | **Landed** — describes the CI surface as implemented (headless smoke vs operator OQ). |
| `CI_Honesty_Change_Report.md` (this file) | **Landed** — payloads in §2 match what is in-tree unless noted below. |
| `.github/workflows/gaiaos-ci.yml` | **Landed** — hard-fail Linux Rust/Python subset; scoped pytest; `VALIDATION_TIER`. |
| `.github/workflows/mac-cell-ci.yml` | **Landed** — honest labels; MetalRenderer **clippy** + build from `MetalRenderer/rust` (Cargo lives there). |
| `.github/workflows/gaiafusion-gamp5-validation.yml` (root) | **Landed** — honest workflow `name:`, tier stamp, artifact `gaiafusion-build-smoke-evidence`. |
| `cells/fusion/.github/workflows/gaiafusion-gamp5-validation.yml` (mirror) | **Landed** — in sync with root semantics; GAIAOS-relative paths. |
| `.github/workflows/full-cycle.yml` | **Removed** — misleading `FULL_CYCLE_GREEN` / minimal workspace overclaim (preferred alternative to stub). |
| `.github/workflows/sparkle-release-lint.yml` | **Landed** — zsh lint for Sparkle placeholders. |
| `.github/workflows/receipt-hygiene.yml` | **Landed** — unsigned `M` provenance gate on evidence JSON. |

Verified state (`ls .github/workflows/` at repo root):

```
gaiafusion-gamp5-validation.yml
gaiaos-ci.yml
mac-cell-ci.yml
receipt-hygiene.yml
sparkle-release-lint.yml
```

No `full-cycle.yml`. Optional later step: `git mv` both `gaiafusion-gamp5-validation.yml` files to `gaiafusion-build-smoke.yml` if you want filenames to match the honest `name:` field.

---

## 1. Plan‑vs‑ground‑truth verification (carried forward)

Before editing, the following claims in the user's execution plan were
verified against the repo:

| Claim | Verification | Result |
| --- | --- | --- |
| `lint_sparkle_release.sh` shebang is `#!/usr/bin/env zsh` (not bash) | Read `cells/fusion/macos/GaiaFTCLConsole/scripts/lint_sparkle_release.sh` line 1 | **Confirmed zsh** |
| `lint_sparkle_release.sh` resolves `ROOT` via `$(cd "$(dirname "$0")/../../.." && pwd)` and expects `${ROOT}/macos/GaiaFTCLConsole/project.yml` | Read line 5–6 of the script | **Confirmed** — invoke with full path from repo root: `zsh cells/fusion/macos/GaiaFTCLConsole/scripts/lint_sparkle_release.sh` |
| Root `Cargo.toml` is the minimal workspace `["rust_fusion_usd_parser", "gaia-metal-renderer"]` and does **not** span the full GAIAOS tree | Read `Cargo.toml` | **Confirmed.** `full-cycle.yml`'s "FULL_CYCLE_GREEN" receipt was overclaiming. |
| GAIAOS mirror of `gaiafusion-gamp5-validation.yml` uses `working-directory: macos/GaiaFusion` vs the root copy's `cells/fusion/macos/GaiaFusion` | Read both files | **Confirmed** — mirror was out of sync. |
| No committed evidence JSON today carries `provenance_tag: "M"` without a `receipt_sig` | `grep -rlE '"provenance_tag"\s*:\s*"M"'` across all evidence roots | **Confirmed zero matches.** Receipt‑hygiene gate would land green. |
| One `M_SIL` file exists: `cells/fusion/macos/MacHealth/evidence/oq/sil_v2_unit_protocol_contract_fixture.json` | Grep for `"M_SIL"` | **Confirmed.** Excluded by `*_fixture.json` rule and by `M_SIL ≠ M`. |

Evidence roots discovered under the repo:

```
FoT8D/evidence/
FoT8D/cells/fusion/macos/GaiaFusion/evidence/
FoT8D/cells/fusion/macos/MacHealth/evidence/
FoT8D/cells/fusion/evidence/
FoT8D/cells/fusion/archive/rust_prototype_2026_04_13/evidence/
FoT8D/cells/fusion/apps/gaiaos_browser_cell/public/docs/evidence/
FoT8D/cells/fusion/services/gaiaos_ui_tester_mcp/evidence/
FoT8D/cells/fusion/services/discord_frontier/evidence/
FoT8D/cells/fusion/services/gaiaos_ui_web/app/api/evidence/
FoT8D/cells/fusion/services/gaiaos_ui_web/evidence/
```

YAML syntax check performed on the attempted payloads before reversion
(`python3 -c "import yaml; yaml.safe_load(open(f))"`): all seven parsed
cleanly after quoting the rename title to avoid a YAML scanner error on
the colon in "was GAMP 5 Validation".

---

## 2. Proposed payloads (drop‑in YAML)

The operator can paste any of these into the corresponding file and
commit. They are the exact payloads that were attempted.

### 2.1  `.github/workflows/gaiaos-ci.yml` — hard‑fail the Linux subset

```yaml
# Hoisted from cells/fusion/.github/workflows/ci.yml — runs when repo root is FoT8D/gaiaFTCL.
#
# VALIDATION_TIER: CI_headless_smoke (Linux Rust/Python subset only).
# This is NOT operator OQ. AppKit/Metal/Swift tests live in mac-cell-ci.yml
# and still require operator-in-the-loop qualification under Aqua (see
# .cursorrules KERNEL DEADLOCK PROTOCOL).
#
# Policy: no continue-on-error, no `|| true`. A green run means the Linux-side
# Rust workspace and scoped Python unit tests actually pass. If this needs to
# be loosened, add the exclusion to the pytest `-k`/`--ignore` scope instead
# of masking the failure.

name: GAIAOS CI

on:
  push:
    branches: [main, develop]
    paths:
      - "cells/fusion/**"
      - ".github/workflows/gaiaos-ci.yml"
  pull_request:
    branches: [main]
    paths:
      - "cells/fusion/**"

env:
  CARGO_TERM_COLOR: always
  RUST_BACKTRACE: 1
  VALIDATION_TIER: CI_headless_smoke

defaults:
  run:
    working-directory: GAIAOS

jobs:
  test-rust:
    name: Test Rust (GAIAOS tree — Linux subset)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: rustfmt, clippy
      - uses: Swatinem/rust-cache@v2
        with:
          workspaces: GAIAOS
          cache-on-failure: true
      - name: Check formatting
        run: cargo fmt --all -- --check
      - name: Clippy (hard gate)
        run: cargo clippy --workspace --all-targets -- -D warnings
      - name: Build
        run: cargo build --workspace --release
      - name: Test
        run: cargo test --workspace --release

  test-python:
    name: Test Python (GAIAOS tree — unit scope)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
          cache: "pip"
      - name: Install dependencies
        run: |
          pip install pytest pytest-asyncio httpx fastapi uvicorn pydantic
      # Scope note: ignore node_modules, integration/, e2e/, and anything
      # marked @pytest.mark.integration — those require live services and
      # don't belong in a headless smoke tier. Add explicit ignores here
      # rather than re-introducing `|| true` / continue-on-error.
      - name: Run Python tests (unit only)
        run: |
          python -m pytest services/ -v \
            --ignore=services/node_modules \
            --ignore=services/integration \
            --ignore=services/e2e \
            -m "not integration"
```

**Delta vs current:** removes two `continue-on-error: true` and one
`|| true`; narrows pytest scope; adds `VALIDATION_TIER` env; renames
job titles to "Linux subset / unit scope".

### 2.2  `.github/workflows/mac-cell-ci.yml` — honest labels + MetalRenderer clippy

```yaml
# VALIDATION_TIER: CI_headless_smoke
#
# This workflow runs on GitHub-hosted macOS runners. It is a headless CI
# smoke only — it verifies that the Swift package builds, the Rust FFI
# compiles clippy-clean, and the XCTest targets execute without crashing.
#
# It is NOT operator OQ. Operator OQ requires:
#   • a human witness in Terminal.app under the Aqua session,
#   • Metal window launch (AppKit/NSApp main-thread invariant),
#   • SSH-signed receipts emitted from the operator shell.
# See .cursorrules KERNEL DEADLOCK PROTOCOL.
#
# Any step label in this file that sounds like a qualification term of art
# (IQ/OQ/PQ, GAMP 5, "validated") is a bug — fix the label, do not re-scope
# the workflow.

name: Mac Cell CI

on:
  push:
    branches: [main]
    paths:
      - 'cells/fusion/macos/GaiaFusion/**'
      - 'cells/fusion/macos/MacHealth/**'
      - 'Scenarios_Physics_Frequencies_Assertions.md'
      - '.github/workflows/mac-cell-ci.yml'
  pull_request:
    branches: [main]
    paths:
      - 'cells/fusion/macos/GaiaFusion/**'
      - 'cells/fusion/macos/MacHealth/**'
      - 'Scenarios_Physics_Frequencies_Assertions.md'
  workflow_dispatch:

env:
  VALIDATION_TIER: CI_headless_smoke

jobs:
  build-and-test-mac:
    name: GaiaFusion build+xcodebuild test (CI headless smoke)
    runs-on: macos-14

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Select Xcode 15.4
        run: sudo xcode-select -s /Applications/Xcode_15.4.app/Contents/Developer

      - name: Install Rust toolchain (aarch64-apple-darwin)
        uses: dtolnay/rust-toolchain@stable
        with:
          toolchain: 1.85.0
          targets: aarch64-apple-darwin
          components: rustfmt, clippy

      - name: Cache Rust dependencies
        uses: Swatinem/rust-cache@v2
        with:
          workspaces: "cells/fusion/macos/GaiaFusion/MetalRenderer"

      - name: Cache Xcode DerivedData
        uses: actions/cache@v4
        with:
          path: ~/Library/Developer/Xcode/DerivedData
          key: ${{ runner.os }}-xcode-deriveddata-${{ hashFiles('cells/fusion/macos/GaiaFusion/Package.resolved') }}
          restore-keys: |
            ${{ runner.os }}-xcode-deriveddata-

      - name: Clippy MetalRenderer (hard gate — no warnings)
        working-directory: cells/fusion/macos/GaiaFusion/MetalRenderer
        run: cargo clippy --release --target aarch64-apple-darwin --all-targets -- -D warnings

      - name: Build Rust Metal Renderer (FFI)
        working-directory: cells/fusion/macos/GaiaFusion/MetalRenderer
        run: |
          cargo build --release --target aarch64-apple-darwin
          mkdir -p lib
          cp target/aarch64-apple-darwin/release/libgaia_metal_renderer.a lib/

      - name: Build Swift Package (GaiaFusion)
        working-directory: cells/fusion/macos/GaiaFusion
        run: |
          xcodebuild build \
            -scheme GaiaFusion \
            -destination 'platform=macOS,arch=arm64' \
            -derivedDataPath ~/Library/Developer/Xcode/DerivedData

      # Intentionally labeled a "CI headless smoke", not OQ.
      # Operator OQ happens in Terminal.app Aqua with a signed receipt.
      - name: GaiaFusion xcodebuild test (CI headless smoke — not operator OQ)
        working-directory: cells/fusion/macos/GaiaFusion
        run: |
          xcodebuild test \
            -scheme GaiaFusion \
            -destination 'platform=macOS,arch=arm64' \
            -derivedDataPath ~/Library/Developer/Xcode/DerivedData

  machealth-sil-v2:
    name: MacHealth — SIL V2 swift test (CI headless smoke)
    runs-on: macos-14
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Select Xcode 15.4
        run: sudo xcode-select -s /Applications/Xcode_15.4.app/Contents/Developer

      - name: Swift test (MacHealth + SIL V2 contracts, CI smoke)
        working-directory: cells/fusion/macos/MacHealth
        run: swift test -v
```

**Delta vs current:** renames misleading step label; adds MetalRenderer
clippy hard gate; adds `VALIDATION_TIER` env; adds a prominent header
comment anchored to KERNEL DEADLOCK PROTOCOL.

### 2.3  `.github/workflows/gaiafusion-gamp5-validation.yml` (root) — honest rename

```yaml
# Hoisted for monorepo root — mirror: cells/fusion/.github/workflows/gaiafusion-gamp5-validation.yml
#
# VALIDATION_TIER: CI_headless_smoke
#
# NOTE ON NAMING: This file is still called gaiafusion-gamp5-validation.yml
# for path-match compatibility. The *workflow* it runs is NOT GAMP 5
# validation — that term of art requires a qualified operator, Aqua
# session, Metal window launch, and SSH-signed receipts. See .cursorrules
# KERNEL DEADLOCK PROTOCOL.
#
# What this workflow actually does:
#   • builds the gaiafusion-config-cli on a GitHub-hosted macos-14 runner,
#   • executes the run_iq_validation.sh and run_oq_validation.sh scripts
#     as headless smoke tests,
#   • uploads the produced evidence/ tree AND a VALIDATION_TIER.txt so
#     downstream consumers cannot mistake the artifact for operator OQ.
#
# TO-DO (operator, requires git mv / git rm):
#   Either
#     git mv .github/workflows/gaiafusion-gamp5-validation.yml \
#            .github/workflows/gaiafusion-build-smoke.yml
#     git mv cells/fusion/.github/workflows/gaiafusion-gamp5-validation.yml \
#            cells/fusion/.github/workflows/gaiafusion-build-smoke.yml
#   or delete both and rely on mac-cell-ci.yml for the headless smoke tier.

name: "GaiaFusion Build Smoke (was GAMP 5 Validation — renamed for honesty)"

on:
  push:
    branches: [main, develop]
    paths:
      - "cells/fusion/macos/GaiaFusion/**"
      - ".github/workflows/gaiafusion-gamp5-validation.yml"
  pull_request:
    branches: [main]
    paths:
      - "cells/fusion/macos/GaiaFusion/**"

env:
  VALIDATION_TIER: CI_headless_smoke

jobs:
  build-smoke:
    name: GaiaFusion build smoke (CI headless — not operator OQ)
    runs-on: macos-14

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: "15.4"

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Build config CLI
        working-directory: cells/fusion/macos/GaiaFusion
        run: |
          cd tools/gaiafusion-config-cli
          cargo build --release

      # These scripts are historically named IQ/OQ; they run as headless
      # smoke here. The VALIDATION_TIER.txt below tells any downstream
      # auditor what this artifact actually represents.
      - name: Run IQ script (headless smoke)
        working-directory: cells/fusion/macos/GaiaFusion
        run: zsh scripts/run_iq_validation.sh

      - name: Run OQ script (headless smoke)
        working-directory: cells/fusion/macos/GaiaFusion
        run: zsh scripts/run_oq_validation.sh

      - name: Stamp VALIDATION_TIER.txt into evidence/
        working-directory: cells/fusion/macos/GaiaFusion
        run: |
          mkdir -p evidence
          cat > evidence/VALIDATION_TIER.txt <<EOF
          VALIDATION_TIER=CI_headless_smoke
          workflow=.github/workflows/gaiafusion-gamp5-validation.yml
          runner=macos-14 (GitHub-hosted)
          witnessed_by=github-actions (NO human operator, NO Aqua session)
          metal_window_launched=false
          receipt_signed=false
          note=This artifact is NOT operator OQ and NOT GAMP 5 qualification.
               Operator OQ requires Terminal.app Aqua + Metal launch + SSH-signed receipt.
               See .cursorrules KERNEL DEADLOCK PROTOCOL.
          commit=${GITHUB_SHA}
          run_url=https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}
          EOF
          cat evidence/VALIDATION_TIER.txt

      - name: Upload evidence (CI smoke tier)
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: gaiafusion-build-smoke-evidence
          path: cells/fusion/macos/GaiaFusion/evidence/
          retention-days: 90
```

### 2.4  `cells/fusion/.github/workflows/gaiafusion-gamp5-validation.yml` (mirror) — kept in sync

```yaml
# GAIAOS-tree mirror — kept in sync with
# /.github/workflows/gaiafusion-gamp5-validation.yml at repo root.
#
# VALIDATION_TIER: CI_headless_smoke
#
# This is NOT GAMP 5 qualification. See the root-mirror header comment.
# Operator OQ requires Aqua + Metal launch + SSH-signed receipts.
#
# TO-DO (operator, requires git mv / git rm) — rename or delete both
# mirrors together. See .cursorrules KERNEL DEADLOCK PROTOCOL.

name: "GaiaFusion Build Smoke (was GAMP 5 Validation — renamed for honesty)"

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

env:
  VALIDATION_TIER: CI_headless_smoke

jobs:
  build-smoke:
    name: GaiaFusion build smoke (CI headless — not operator OQ)
    runs-on: macos-14

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '15.4'

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Build config CLI
        working-directory: macos/GaiaFusion
        run: |
          cd tools/gaiafusion-config-cli
          cargo build --release

      - name: Run IQ script (headless smoke)
        working-directory: macos/GaiaFusion
        run: zsh scripts/run_iq_validation.sh

      - name: Run OQ script (headless smoke)
        working-directory: macos/GaiaFusion
        run: zsh scripts/run_oq_validation.sh

      - name: Stamp VALIDATION_TIER.txt into evidence/
        working-directory: macos/GaiaFusion
        run: |
          mkdir -p evidence
          cat > evidence/VALIDATION_TIER.txt <<EOF
          VALIDATION_TIER=CI_headless_smoke
          workflow=cells/fusion/.github/workflows/gaiafusion-gamp5-validation.yml
          runner=macos-14 (GitHub-hosted)
          witnessed_by=github-actions (NO human operator, NO Aqua session)
          metal_window_launched=false
          receipt_signed=false
          note=This artifact is NOT operator OQ and NOT GAMP 5 qualification.
               Operator OQ requires Terminal.app Aqua + Metal launch + SSH-signed receipt.
               See .cursorrules KERNEL DEADLOCK PROTOCOL.
          commit=${GITHUB_SHA}
          run_url=https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}
          EOF
          cat evidence/VALIDATION_TIER.txt

      - name: Upload evidence (CI smoke tier)
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: gaiafusion-build-smoke-evidence
          path: macos/GaiaFusion/evidence/
          retention-days: 90
```

### 2.5  `.github/workflows/full-cycle.yml` — retirement stub

```yaml
# RETIRED — this workflow previously emitted a "FULL_CYCLE_GREEN" /
# "CERN READY" receipt based on `cargo test --workspace` at the repo root.
# Per the CI honesty review (GitHubActions_Value_Review.md), that receipt
# was misleading because:
#   • root Cargo.toml is a minimal workspace
#     (members = ["rust_fusion_usd_parser", "gaia-metal-renderer"]),
#     NOT the full GAIAOS tree,
#   • the fresh-clone re-test adds no real signal,
#   • "CERN READY" and "status: FULL_CYCLE_GREEN" overclaim what a
#     GitHub-hosted Linux/macOS runner can witness,
#   • PQ / operator OQ requires Aqua + Metal launch + SSH-signed receipt
#     and cannot be done on a GitHub runner. See .cursorrules
#     KERNEL DEADLOCK PROTOCOL.
#
# This workflow is now manual-only (workflow_dispatch). Any scheduled or
# push-triggered invocation is gone — so no more "GREEN" receipts land in
# CI artifacts.
#
# TO-DO (operator, requires git rm):
#   git rm .github/workflows/full-cycle.yml
#   git commit -m "ci: retire full-cycle.yml (superseded by mac-cell-ci + receipt-hygiene)"

name: "[RETIRED] GaiaFTCL Full Cycle"

on:
  workflow_dispatch:

jobs:
  retired-notice:
    name: Retired — see mac-cell-ci + receipt-hygiene
    runs-on: ubuntu-latest
    steps:
      - name: Print retirement notice and exit non-zero
        run: |
          echo "════════════════════════════════════════════════════════════"
          echo "  full-cycle.yml is RETIRED."
          echo ""
          echo "  Use instead:"
          echo "    • mac-cell-ci.yml          (CI headless smoke for GaiaFusion + MacHealth)"
          echo "    • gaiaos-ci.yml            (Linux Rust/Python unit tier)"
          echo "    • receipt-hygiene.yml      (fails PRs that leak provenance_tag: M without a receipt_sig)"
          echo "    • sparkle-release-lint.yml (fails PRs that leak placeholder SUPublicEDKey / SUFeedURL)"
          echo ""
          echo "  Operator OQ (Aqua + Metal launch + SSH-signed receipt) is"
          echo "  NOT done in GitHub Actions — see .cursorrules KERNEL"
          echo "  DEADLOCK PROTOCOL."
          echo "════════════════════════════════════════════════════════════"
          exit 1
```

**Preferred alternative:** `git rm .github/workflows/full-cycle.yml`.

### 2.6  `.github/workflows/sparkle-release-lint.yml` — NEW hard gate

```yaml
# VALIDATION_TIER: CI_gate
#
# Gate against shipping a GaiaFTCLConsole Release build with placeholder
# Sparkle signing keys or feed URL. Runs the same zsh lint script a human
# would run locally from repo root:
#
#   zsh cells/fusion/macos/GaiaFTCLConsole/scripts/lint_sparkle_release.sh
#
# The script checks cells/fusion/macos/GaiaFTCLConsole/project.yml and refuses
# if SUPublicEDKey is a placeholder (placeholder / PLACEHOLDER / changeme
# / TODO) or if SUFeedURL points at example.com / placeholder / localhost:0.
# Hard fail is the correct behavior — do NOT add continue-on-error here.

name: Sparkle Release Lint

on:
  push:
    branches: [main, develop]
    paths:
      - 'cells/fusion/macos/GaiaFTCLConsole/project.yml'
      - 'cells/fusion/macos/GaiaFTCLConsole/scripts/lint_sparkle_release.sh'
      - '.github/workflows/sparkle-release-lint.yml'
  pull_request:
    branches: [main]
    paths:
      - 'cells/fusion/macos/GaiaFTCLConsole/project.yml'
      - 'cells/fusion/macos/GaiaFTCLConsole/scripts/lint_sparkle_release.sh'
      - '.github/workflows/sparkle-release-lint.yml'
  workflow_dispatch:

env:
  VALIDATION_TIER: CI_gate

jobs:
  sparkle-release-lint:
    name: Refuse placeholder SUPublicEDKey / SUFeedURL
    # ubuntu-latest is fine — the script is pure zsh + grep and the file
    # under test is a plain YAML manifest. No Xcode/Sparkle tooling needed.
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install zsh
        run: |
          sudo apt-get update
          sudo apt-get install -y zsh
          zsh --version

      - name: Confirm project.yml is present (sanity)
        run: |
          test -f cells/fusion/macos/GaiaFTCLConsole/project.yml \
            || { echo "missing cells/fusion/macos/GaiaFTCLConsole/project.yml"; exit 2; }

      - name: Run Sparkle release lint (hard gate)
        run: zsh cells/fusion/macos/GaiaFTCLConsole/scripts/lint_sparkle_release.sh

      # Positive-path evidence so reviewers can see what was inspected.
      - name: Print inspected Sparkle fields
        if: always()
        run: |
          echo "── SUPublicEDKey / SUFeedURL in project.yml ──"
          grep -nE 'SUPublicEDKey|SUFeedURL' \
            cells/fusion/macos/GaiaFTCLConsole/project.yml || true
```

### 2.7  `.github/workflows/receipt-hygiene.yml` — NEW hard gate

```yaml
# VALIDATION_TIER: CI_gate
#
# Fail PRs that commit an M-provenance evidence receipt (provenance_tag = "M")
# without a non-empty receipt_sig. Rationale:
#
#   • M_SIL is an in-software / fixture provenance and is fine to land.
#   • M is a machine-witnessed physical receipt; without a receipt_sig it
#     is an unsigned claim of physical witness. That must not land in the
#     evidence tree.
#
# Scope:
#   • evidence/**          at repo root
#   • cells/fusion/**/evidence/** anywhere under GAIAOS
#
# Excluded by design:
#   • Tests/**, Fixtures/**, sil_v2_unit_protocol_contract_fixture.json,
#     and files matching *_fixture.json — these are test inputs, not
#     landed receipts, and they legitimately carry provenance_tag: M
#     without a receipt_sig.
#
# Hard gate. Do NOT add continue-on-error.

name: Receipt Hygiene

on:
  push:
    branches: [main, develop]
    paths:
      - 'evidence/**'
      - 'cells/fusion/**/evidence/**'
      - '.github/workflows/receipt-hygiene.yml'
  pull_request:
    branches: [main]
    paths:
      - 'evidence/**'
      - 'cells/fusion/**/evidence/**'
      - '.github/workflows/receipt-hygiene.yml'
  workflow_dispatch:

env:
  VALIDATION_TIER: CI_gate

jobs:
  receipt-hygiene:
    name: Refuse unsigned M-provenance evidence
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Check evidence trees (hard gate)
        shell: python
        run: |
          import json
          import os
          import re
          import sys
          from pathlib import Path

          REPO = Path(os.environ.get("GITHUB_WORKSPACE", ".")).resolve()

          # Roots to walk.
          roots = []
          top_evidence = REPO / "evidence"
          if top_evidence.is_dir():
              roots.append(top_evidence)
          gaiaos = REPO / "GAIAOS"
          if gaiaos.is_dir():
              for ev in gaiaos.rglob("evidence"):
                  if ev.is_dir():
                      roots.append(ev)

          if not roots:
              print("receipt-hygiene: no evidence/ trees present — nothing to check.")
              sys.exit(0)

          # Exclude test/fixture inputs — they legitimately carry
          # provenance_tag: M (or M_SIL) without receipt_sig.
          EXCLUDE_PATH_SUBSTR = (
              "/Tests/",
              "/tests/",
              "/Fixtures/",
              "/fixtures/",
          )
          EXCLUDE_NAME_RE = re.compile(r"(?i)(^|/)(.*_fixture\.json|.*\.fixture\.json)$")

          def is_excluded(p: Path) -> bool:
              s = str(p).replace("\\", "/")
              if any(sub in s for sub in EXCLUDE_PATH_SUBSTR):
                  return True
              if EXCLUDE_NAME_RE.search(s):
                  return True
              return False

          def flag(obj, path_hint):
              """Yield (reason, jsonpath) for every M-without-sig violation."""
              def walk(node, jsonpath):
                  if isinstance(node, dict):
                      tag = node.get("provenance_tag")
                      if isinstance(tag, str) and tag.strip() == "M":
                          sig = node.get("receipt_sig")
                          if not isinstance(sig, str) or not sig.strip():
                              yield (
                                  "provenance_tag == 'M' without non-empty receipt_sig",
                                  jsonpath or "$",
                              )
                      for k, v in node.items():
                          yield from walk(v, f"{jsonpath}.{k}" if jsonpath else f"$.{k}")
                  elif isinstance(node, list):
                      for i, v in enumerate(node):
                          yield from walk(v, f"{jsonpath}[{i}]")
              return list(walk(obj, ""))

          violations = []
          scanned = 0
          skipped_excluded = 0
          skipped_unparsable = 0

          for root in roots:
              for p in root.rglob("*.json"):
                  if is_excluded(p):
                      skipped_excluded += 1
                      continue
                  try:
                      with p.open("r", encoding="utf-8") as f:
                          obj = json.load(f)
                  except Exception as e:
                      skipped_unparsable += 1
                      print(f"WARN unparsable: {p.relative_to(REPO)}: {e}", file=sys.stderr)
                      continue
                  scanned += 1
                  for reason, jpath in flag(obj, str(p)):
                      violations.append((p.relative_to(REPO), jpath, reason))

          print(f"receipt-hygiene: scanned={scanned} "
                f"excluded={skipped_excluded} unparsable={skipped_unparsable}")
          if violations:
              print("── VIOLATIONS ──")
              for rel, jpath, reason in violations:
                  print(f"  {rel}  at {jpath}  :: {reason}")
              print(f"receipt-hygiene: REFUSED — {len(violations)} violation(s)")
              sys.exit(1)
          print("receipt-hygiene: OK — no M-provenance evidence missing receipt_sig.")
```

---

## 3. Operator handoff — exact zsh invocations

```zsh
# From repo root. Apply the payloads in §2 however you prefer
# (copy/paste from this file, or use your own editor).

# 1. Land the two new gates first (additive, no risk to existing signal):
#    - copy §2.6 into .github/workflows/sparkle-release-lint.yml
#    - copy §2.7 into .github/workflows/receipt-hygiene.yml
git add .github/workflows/sparkle-release-lint.yml \
        .github/workflows/receipt-hygiene.yml

# 2. Harden gaiaos-ci.yml (§2.1) and mac-cell-ci.yml (§2.2):
git add .github/workflows/gaiaos-ci.yml \
        .github/workflows/mac-cell-ci.yml

# 3. Rename (keep filename, fix content) or retire the gamp5 mirrors (§2.3, §2.4):
#    Option A — in-place honest rename:
git add .github/workflows/gaiafusion-gamp5-validation.yml \
        cells/fusion/.github/workflows/gaiafusion-gamp5-validation.yml
#    Option B — filename rename (replaces Option A content edits):
# git mv .github/workflows/gaiafusion-gamp5-validation.yml \
#        .github/workflows/gaiafusion-build-smoke.yml
# git mv cells/fusion/.github/workflows/gaiafusion-gamp5-validation.yml \
#        cells/fusion/.github/workflows/gaiafusion-build-smoke.yml
#    Option C — delete both:
# git rm .github/workflows/gaiafusion-gamp5-validation.yml \
#        cells/fusion/.github/workflows/gaiafusion-gamp5-validation.yml

# 4. Retire full-cycle.yml (§2.5):
#    Option A — replace with retirement stub:
git add .github/workflows/full-cycle.yml
#    Option B — delete:
# git rm .github/workflows/full-cycle.yml

# 5. Stage the docs:
git add docs/CI_WHAT_IT_MEANS.md \
        CI_Honesty_Change_Report.md \
        GitHubActions_Value_Review.md

# 6. Single honest commit:
git commit -m "ci: honesty pass — drop soft-fails, label CI smoke vs operator OQ, add sparkle + receipt-hygiene gates"

# 7. Push:
git push gaiaftcl HEAD:main
```

Operator‑only steps (cannot be done from the agent shell per KERNEL
DEADLOCK PROTOCOL): `git add`, `git rm`, `git mv`, `git commit`,
`git push`, and the local `swift test` / `xcodebuild test` runs that
cross into AppKit/Metal/VFS territory.

---

## 4. Verification evidence (pre‑reversion)

- YAML syntax: all seven attempted payloads parsed cleanly with
  `python3 yaml.safe_load`. One scanner error on the quoted rename
  title was fixed by wrapping the `name:` value in double quotes to
  escape the embedded colon.
- Grep sweep for `"provenance_tag": "M"` across all ten evidence roots:
  zero matches. Receipt‑hygiene would have landed green on current
  main.
- Grep sweep for `"provenance_tag": "M_SIL"`: one match, in a
  `*_fixture.json` file under `Tests/`-adjacent path — excluded twice
  over (filename pattern + `M_SIL ≠ M`).
- Lint script shebang and `ROOT` resolution verified by direct Read;
  invocation from repo root is `zsh cells/fusion/macos/GaiaFTCLConsole/scripts/lint_sparkle_release.sh`.
- Root `Cargo.toml` confirmed minimal workspace (two members).

---

## 5. Disclaimers

This report describes a CI honesty pass. It is not a regulatory
submission, not operator OQ / PQ, and not GAMP 5 qualification
evidence. The physics / frequency assertions referenced elsewhere in
the repo (`Scenarios_Physics_Frequencies_Assertions.md`) are separate
from the CI plumbing described here. Nothing in GitHub Actions is
qualified to witness a Metal window launch or emit an SSH‑signed
operator receipt.
