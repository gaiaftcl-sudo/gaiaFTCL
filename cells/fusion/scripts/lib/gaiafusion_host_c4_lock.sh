#!/usr/bin/env bash
# shellcheck shell=bash
# GaiaFTCL — strip toxic GAIAFUSION_SKIP_* / probe-SIGKILL env leakage on primary Apple Silicon host Mac.
# Source from operator scripts after `set -euo pipefail`.
#
# Rationale: SKIP_* vars exported from CI, IDE sandboxes, or shell profiles must not silently downgrade
# host validation to PARTIAL. CI and Intel Macs are untouched.
#
# Opt-out (deliberate partial on hardware): export GAIAFUSION_ALLOW_SKIP_ON_HOST=1

gaiafusion_host_strip_skip_leak() {
  if [[ "${GAIAFUSION_ALLOW_SKIP_ON_HOST:-}" == "1" ]]; then
    return 0
  fi
  if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
    return 0
  fi
  if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" || -n "${GITLAB_CI:-}" ]]; then
    return 0
  fi

  echo "[C4] Host Mac arm64 (non-CI): clearing GAIAFUSION_SKIP_* / USD probe SIGKILL workarounds — set GAIAFUSION_ALLOW_SKIP_ON_HOST=1 to keep them." >&2
  unset GAIAFUSION_SKIP_WORKING_APP_VERIFY
  unset GAIAFUSION_SKIP_XCTEST
  unset GAIAFUSION_SKIP_MAC_CELL_MCP
  unset GAIAFUSION_SKIP_MESH_MCP
  unset GAIAFUSION_SKIP_USD_PROBE_CLI
  unset GAIAFUSION_USD_PROBE_SIGKILL_OK
  if [[ "${GAIAFUSION_ALLOW_STALE_GATE_BUNDLE:-}" != "1" ]]; then
    unset GAIAFUSION_GATE_SKIP_SWIFT_BUILD
    unset GAIAFUSION_GATE_APP_BUNDLE
    echo "[C4] Cleared GAIAFUSION_GATE_SKIP_SWIFT_BUILD / GAIAFUSION_GATE_APP_BUNDLE — set GAIAFUSION_ALLOW_STALE_GATE_BUNDLE=1 for packaged .app gate." >&2
  fi
}
