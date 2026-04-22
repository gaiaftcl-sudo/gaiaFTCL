#!/usr/bin/env zsh
# Resolve `fo-franklin` (workspace: repo root /target/release/fo-franklin).
# Usage: REPO=...; source cells/franklin/scripts/_franklin_bin.zsh; franklin_require_bin
set -euo pipefail

franklin_require_bin() {
  if [[ -z "${REPO:-}" ]]; then
    echo "REFUSED: REPO not set" >&2
    return 1
  fi
  export FRANKLIN_BIN="${REPO}/target/release/fo-franklin"
  if [[ -x "$FRANKLIN_BIN" ]]; then
    return 0
  fi
  echo "REFUSED: missing $FRANKLIN_BIN" >&2
  echo "Build: (cd \"\$REPO\" && cargo build -p fo_cell_substrate --release)" >&2
  return 1
}
