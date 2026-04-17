#!/usr/bin/env bash
# Load `SUDO_PASSWORD` from GAIAOS/.env and run: sudo -S "$@"
# Usage: source scripts/lib/sudo_from_env.sh && sudo_from_env killall -9 swift-test
set -euo pipefail

_sudo_from_env_root() {
  local here="${BASH_SOURCE[0]:-$0}"
  cd "$(dirname "$here")/../.." && pwd
}

sudo_from_env() {
  local root
  root="$(_sudo_from_env_root)"
  if [[ ! -f "$root/.env" ]]; then
    echo "REFUSED: missing $root/.env (copy from .env.example; set SUDO_PASSWORD)" >&2
    return 1
  fi
  set -a
  # shellcheck source=/dev/null
  source "$root/.env"
  set +a
  if [[ -z "${SUDO_PASSWORD:-}" ]]; then
    echo "REFUSED: SUDO_PASSWORD not set in $root/.env" >&2
    return 1
  fi
  printf '%s\n' "$SUDO_PASSWORD" | sudo -S "$@"
}
