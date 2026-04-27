#!/usr/bin/env bash
# Build signed avatar bundle + pubkey for sprout Gate E.
# Inputs: bundle_assets/ (committed). Output: build/avatar_bundle/, build/bundle_pubkey.bin (gitignored).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY="${FRANKLIN_KEY:?FRANKLIN_KEY must point to a 32-byte Ed25519 private key}"
IN="${ROOT}/bundle_assets"
OUT="${ROOT}/build/avatar_bundle"
PUB="${ROOT}/build/bundle_pubkey.bin"
BUNDLE_ID="${FRANKLIN_BUNDLE_ID:-franklin.passy.v1}"

[[ -d "${IN}" ]] || {
  echo >&2 "[build_bundle] missing ${IN}"
  exit 2
}

pick_sign_bundle() {
  local -a candidates=()
  case "$(uname -s)/$(uname -m)" in
    Darwin/arm64)
      candidates=(
        "${ROOT}/host-tools/darwin-arm64/sign_bundle"
        "${ROOT}/target/release/sign_bundle"
      )
      ;;
    Darwin/x86_64)
      candidates=(
        "${ROOT}/host-tools/darwin-amd64/sign_bundle"
        "${ROOT}/target/release/sign_bundle"
      )
      ;;
    *)
      candidates=(
        "${ROOT}/target/release/sign_bundle"
      )
      ;;
  esac
  local p
  for p in "${candidates[@]}"; do
    if [[ -x "$p" ]]; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

SB="$(pick_sign_bundle)" || {
  echo >&2 "[build_bundle] no sign_bundle binary found."
  echo >&2 "  Expected host-tools/darwin-arm64/sign_bundle (Apple Silicon) or target/release/sign_bundle after cargo build."
  exit 127
}

mkdir -p "$(dirname "${OUT}")" "$(dirname "${PUB}")"
rm -rf "${OUT}"

"${SB}" \
  --input "${IN}" \
  --output "${OUT}" \
  --key "${KEY}" \
  --bundle-id "${BUNDLE_ID}" \
  --pubkey-out "${PUB}"

[[ -d "${OUT}" && -f "${PUB}" ]] || {
  echo >&2 "[build_bundle] missing output dir or pubkey"
  exit 8
}

echo "[build_bundle] ok bundle=${OUT} pubkey=${PUB}"
