#!/usr/bin/env zsh
# Sparkle Release lint — refuse placeholder signing keys / bogus feed URLs.
# Invoked from repo root (FoT8D): zsh GAIAOS/macos/GaiaFTCLConsole/scripts/lint_sparkle_release.sh
# ROOT resolves to GAIAOS/ (three levels up from this file).

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PROJ="$ROOT/macos/GaiaFTCLConsole/project.yml"

if [[ ! -f "$PROJ" ]]; then
  echo "REFUSED: missing project.yml at $PROJ" >&2
  exit 2
fi

extract_yaml_string() {
  local key="$1"
  grep -E "^[[:space:]]*${key}:" "$PROJ" | head -1 | sed -n 's/^[^:]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

KEY="$(extract_yaml_string SUPublicEDKey)"
FEED="$(extract_yaml_string SUFeedURL)"

if [[ -z "$KEY" ]]; then
  echo "REFUSED: SUPublicEDKey missing or empty in project.yml" >&2
  exit 1
fi

# Placeholder / non-shipping values (case-insensitive substring checks on key material)
typeset -l klower="$KEY"
if [[ "$klower" == *placeholder* || "$klower" == *changeme* || "$klower" == *todo* ]]; then
  echo "REFUSED: SUPublicEDKey must be a real Sparkle Ed25519 public key (got: ${KEY})." >&2
  exit 1
fi

# Ed25519 Sparkle public keys are 44-char base64url-ish; allow = padding
if (( ${#KEY} < 40 )); then
  echo "REFUSED: SUPublicEDKey looks too short to be a Sparkle Ed25519 public key." >&2
  exit 1
fi

if [[ -z "$FEED" ]]; then
  echo "REFUSED: SUFeedURL missing or empty in project.yml" >&2
  exit 1
fi

typeset -l flower="$FEED"
if [[ "$flower" == *example.com* || "$flower" == *localhost* || "$flower" == *placeholder* ]]; then
  echo "REFUSED: SUFeedURL must not use example.com, localhost, or placeholder hosts (got: ${FEED})." >&2
  exit 1
fi

echo "OK: SUPublicEDKey, SUFeedURL look sane (${PROJ})."
exit 0
