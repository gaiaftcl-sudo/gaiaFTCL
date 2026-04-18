# CI — What It Means (and what it does NOT mean)

**Status:** the CI honesty payloads described here are **landed in the
repo tree** (workflows under `.github/workflows/` and the GAIAOS
mirror). This document remains the map of what a green run means versus
what it does not mean — it is not operator OQ/PQ.

**Scope:** this document tells a reviewer, operator, or auditor exactly
what a green GitHub Actions run in this repo should prove — and, more
importantly, what it does **not** prove. It is the counter-document to
marketing-style workflow names.

---

## 0. The one rule

**GitHub Actions runs on a headless VM with no human operator, no Aqua
session, no Metal window, and no SSH-signed receipts.** Therefore no
workflow in this repo is qualified to emit an operator OQ / PQ receipt
or a GAMP 5 qualification artifact. Any workflow that appears to is a
labeling bug — fix the label, do not re-scope the workflow.

See `.cursorrules` → KERNEL DEADLOCK PROTOCOL for the substrate-level
reason: AppKit/Metal/VFS collides with agent-shell headless execution.
`swift test` / `xcodebuild test` can run in CI (they do not require a
window), but they do not constitute operator qualification.

---

## 1. Landed state (repo as shipped)

| File | Landed behavior | Honest tier |
| --- | --- | --- |
| `.github/workflows/mac-cell-ci.yml` | `VALIDATION_TIER: CI_headless_smoke`; MetalRenderer **clippy** + build from `MetalRenderer/rust`; GaiaFusion xctest step labeled CI smoke (not operator OQ); MacHealth `swift test` | CI headless smoke |
| `.github/workflows/gaiaos-ci.yml` | No `continue-on-error` / `\|\| true`; scoped pytest; `VALIDATION_TIER: CI_headless_smoke` | CI headless smoke (Linux subset) |
| `.github/workflows/gaiafusion-gamp5-validation.yml` (root) | Workflow `name:` is honest build-smoke wording; `VALIDATION_TIER.txt` in evidence; artifact `gaiafusion-build-smoke-evidence` | CI headless smoke |
| `GAIAOS/.github/workflows/gaiafusion-gamp5-validation.yml` (mirror) | Same semantics as root; paths use `macos/GaiaFusion` for GAIAOS-only checkouts | CI headless smoke |
| `.github/workflows/full-cycle.yml` | **Removed** — previously overclaimed vs minimal root `Cargo.toml` workspace | — |
| `.github/workflows/sparkle-release-lint.yml` | Ubuntu + `zsh` + `lint_sparkle_release.sh` on `project.yml` | CI gate |
| `.github/workflows/receipt-hygiene.yml` | Fails on `provenance_tag: "M"` without non-empty `receipt_sig` under evidence roots (fixtures excluded) | CI gate |

---

## 2. Design intent per workflow (reference)

### `.github/workflows/mac-cell-ci.yml` — **CI headless smoke**
Should prove:
- The Rust MetalRenderer FFI compiles clippy-clean for `aarch64-apple-darwin`
  (**add** `cargo clippy --release --target aarch64-apple-darwin --all-targets -- -D warnings`).
- The GaiaFusion Swift package builds against Xcode 15.4.
- The GaiaFusion XCTest targets run to completion without crashing.
- The MacHealth Swift package `swift test` passes.

Labeling changes:
- Rename step `Run Swift Tests (TestRobit / OQ)` →
  `GaiaFusion xcodebuild test (CI headless smoke — not operator OQ)`.
- Add `env: { VALIDATION_TIER: CI_headless_smoke }` at the top.

Does **not** prove: Metal-window launch, operator witness, OQ/PQ.

### `.github/workflows/gaiaos-ci.yml` — **Linux subset, hard-fail**
Target:
- Remove `continue-on-error: true` from Clippy and `cargo test` steps.
- Remove `|| true` and `continue-on-error: true` from pytest step.
- Scope pytest: `--ignore=services/node_modules --ignore=services/integration --ignore=services/e2e -m "not integration"`.
- Add `env: { VALIDATION_TIER: CI_headless_smoke }`.

If this requires loosening, add the exclusion to the pytest
`--ignore`/`-m` filter, **do not** re-introduce masked failures.

### `.github/workflows/gaiafusion-gamp5-validation.yml` — **rename or retire**
Two acceptable operator choices (decision is the operator's):
1. **Retire** — `git rm` both root and GAIAOS mirror. Coverage is
   subsumed by `mac-cell-ci.yml`.
2. **Rename** — `git mv` both to `gaiafusion-build-smoke.yml`,
   change workflow `name:` to something like
   `GaiaFusion Build Smoke (was GAMP 5 Validation — renamed for honesty)`,
   add `VALIDATION_TIER: CI_headless_smoke`, and emit a
   `VALIDATION_TIER.txt` stamp into the evidence artifact so it cannot
   be mistaken for qualification output.

Either way, the root and the mirror must be changed together.

### `.github/workflows/sparkle-release-lint.yml` — **NEW, release hard gate**
Should prove, on any PR that touches `GAIAOS/macos/GaiaFTCLConsole/project.yml`:
- `SUPublicEDKey` is not a placeholder (no `placeholder`/`PLACEHOLDER`/`changeme`/`TODO`).
- `SUFeedURL` does not point at `example.com`, `localhost:0`, or any placeholder host.

Implementation: one ubuntu-latest job that `apt-get install -y zsh`
then runs `zsh GAIAOS/macos/GaiaFTCLConsole/scripts/lint_sparkle_release.sh`
from repo root. No `continue-on-error`.

### `.github/workflows/receipt-hygiene.yml` — **NEW, evidence hard gate**
Should prove, across `evidence/**` and `GAIAOS/**/evidence/**`:
- No committed JSON carries `provenance_tag: "M"` without a non-empty
  `receipt_sig`.
- `M_SIL` is fine — it is a different tag.
- Tests/fixtures are excluded by path and filename
  (`/Tests/`, `/tests/`, `/Fixtures/`, `/fixtures/`, `*_fixture.json`).

A Grep sweep at write time confirmed:
- zero files currently carry `"provenance_tag": "M"` in any evidence
  tree, so this gate will land green.
- the one `M_SIL` file
  (`GAIAOS/macos/MacHealth/evidence/oq/sil_v2_unit_protocol_contract_fixture.json`)
  is excluded via the `*_fixture.json` rule AND is `M_SIL` not `M`, so
  it would not be flagged.

### `.github/workflows/full-cycle.yml` — **retire**
Replace with a `workflow_dispatch`-only stub that prints a retirement
notice and exits 1, OR `git rm` entirely. The existing file emits a
`FULL_CYCLE_GREEN` / `CERN READY` receipt from a minimal root Cargo
workspace (`members = ["rust_fusion_usd_parser", "gaia-metal-renderer"]`)
which overstates what a GitHub runner witnesses.

---

## 3. What operator OQ / PQ actually looks like

This repo does **not** try to do operator qualification in CI. Operator
qualification requires, at minimum:

- Terminal.app under the operator's logged-in macOS Aqua session
  (`launchctl managername` reports `Aqua`).
- Metal window actually drawn (AppKit NSApp main-thread invariant held).
- A receipt written under the `fot-*` SSH-signed namespace with
  parent-hash chaining.
- For SIL V2: nonce reconstruction ρ ≥ 0.95 and RMSE/peak ≤ 0.10;
  filter ≤5%/≤10°/>40dB at 60Hz; TX envelope Freq±0.1Hz, Phase±5°,
  Duty±1%, Amp±2%, latency ≤500ms p99.

None of those conditions can be witnessed on a GitHub runner.

---

## 4. Which workflow tells me what?

| I want to know… | Look at |
| --- | --- |
| Does the Linux Rust subset compile and test? | `gaiaos-ci.yml` |
| Does the Python unit subset pass? | `gaiaos-ci.yml` (test-python) |
| Does GaiaFusion build + xcodebuild-test headlessly? | `mac-cell-ci.yml` |
| Does MacHealth `swift test` pass? | `mac-cell-ci.yml` (machealth-sil-v2) |
| Does the GaiaFusion config-CLI build and do IQ/OQ scripts exit 0? | `gaiafusion-gamp5-validation.yml` (or its renamed successor) |
| Are Sparkle signing keys still placeholders? | `sparkle-release-lint.yml` (fails PR) |
| Has an unsigned `M` receipt leaked into evidence? | `receipt-hygiene.yml` (fails PR) |
| Did an operator qualify this build? | **Not a GitHub Actions question.** |

---

## 5. Optional filename cleanup (operator)

The files `gaiafusion-gamp5-validation.yml` (root + GAIAOS mirror) may
still be renamed to `gaiafusion-build-smoke.yml` via `git mv` if desired;
content and workflow `name:` already describe build smoke, not GAMP 5
qualification.

---

## 6. Disclaimers

This document is a map of the CI surface, not a regulatory submission.
Nothing in this repo's GitHub Actions is suitable as evidence for
medical-device qualification, pharma GxP computer-system validation,
CERN detector-grade validation, or any other regulated regime. If the
workflow name sounds like it is — fix the name.
