#!/usr/bin/env zsh
# Avatar IQ plan phases 0–2 (sprout Gate F): crypto verify, contract alignment, genesis/hash-lock seal.
set -euo pipefail
emulate -L zsh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "${ROOT}/../../.." && pwd)"

PHASE=""
while (( $# )); do
  case "$1" in
    --phase)
      PHASE="${2:?}"
      shift 2
      ;;
    -h|--help)
      print -r -- "usage: $(basename "$0") --phase 0|1|2"
      exit 0
      ;;
    *)
      print -u2 "[plan_phases] unknown argument: $1"
      exit 2
      ;;
  esac
done

[[ -n "${PHASE}" ]] || {
  print -u2 "[plan_phases] missing --phase 0|1|2"
  exit 2
}

pick_verify_bundle() {
  local cand
  local candidates=()
  case "$(uname -s)/$(uname -m)" in
    Darwin/arm64)
      candidates=(
        "${ROOT}/host-tools/darwin-arm64/verify_bundle"
        "${ROOT}/target/release/verify_bundle"
      )
      ;;
    Darwin/x86_64)
      candidates=(
        "${ROOT}/host-tools/darwin-amd64/verify_bundle"
        "${ROOT}/target/release/verify_bundle"
      )
      ;;
    *)
      candidates=(
        "${ROOT}/target/release/verify_bundle"
      )
      ;;
  esac
  for cand in "${candidates[@]}"; do
    if [[ -x "${cand}" ]]; then
      print -r -- "${cand}"
      return 0
    fi
  done
  return 1
}

yaml_scalar() {
  # First line matching ^key: value — strips optional quotes.
  local file="$1" key="$2"
  [[ -f "${file}" ]] || return 1
  awk -v k="${key}:" '$1==k { sub(/^[^ ]+:[[:space:]]*/, ""); gsub(/^"|"$/, ""); print; exit }' "${file}"
}

OUT="${ROOT}/build/iq_phase_${PHASE}"
mkdir -p "${OUT}"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

case "${PHASE}" in
  0)
    VB="$(pick_verify_bundle)" || {
      print -u2 "[plan_phases] no verify_bundle binary (host-tools or target/release)"
      exit 127
    }
    [[ -f "${ROOT}/build/bundle_pubkey.bin" && -d "${ROOT}/build/avatar_bundle" ]] || {
      print -u2 "[plan_phases] missing bundle build (run scripts/build_bundle.zsh / Gate E)"
      exit 14
    }
    "${VB}" --pubkey "${ROOT}/build/bundle_pubkey.bin" "${ROOT}/build/avatar_bundle"
    jq -n \
      --arg ts "${TS}" \
      --arg phase "${PHASE}" \
      '{phase:$phase,passed:true,kind:"verify_bundle",ts:$ts}' > "${OUT}/receipt.json"
    ;;
  1)
    [[ -f "${ROOT}/build/avatar_bundle/manifest.yaml" ]] || {
      print -u2 "[plan_phases] missing manifest.yaml"
      exit 15
    }
    [[ -f "${REPO}/substrate/HASH_LOCKS.yaml" ]] || {
      print -u2 "[plan_phases] missing substrate/HASH_LOCKS.yaml"
      exit 16
    }
    locks_cv="$(yaml_scalar "${REPO}/substrate/HASH_LOCKS.yaml" contract_version)" || locks_cv=""
    manifest_cv="$(yaml_scalar "${ROOT}/build/avatar_bundle/manifest.yaml" contract_version)" || manifest_cv=""
    [[ -n "${locks_cv}" && -n "${manifest_cv}" ]] || {
      print -u2 "[plan_phases] could not read contract_version from HASH_LOCKS or manifest"
      exit 17
    }
    [[ "${locks_cv}" == "${manifest_cv}" ]] || {
      print -u2 "[plan_phases] contract_version mismatch: HASH_LOCKS=${locks_cv} manifest=${manifest_cv}"
      exit 18
    }
    jq -n \
      --arg ts "${TS}" \
      --arg phase "${PHASE}" \
      --arg cv "${manifest_cv}" \
      '{phase:$phase,passed:true,kind:"contract_alignment",contract_version:$cv,ts:$ts}' > "${OUT}/receipt.json"
    ;;
  2)
    gr="${FOT_GENESIS_RECORD_PATH:-}"
    [[ -n "${gr}" && -f "${gr}" ]] || {
      print -u2 "[plan_phases] FOT_GENESIS_RECORD_PATH must point to genesis_record.json (Gate D)"
      exit 19
    }
    [[ -f "${REPO}/substrate/HASH_LOCKS.yaml" ]] || {
      print -u2 "[plan_phases] missing substrate/HASH_LOCKS.yaml"
      exit 16
    }
    stored="$(jq -r '.hash_locks_sha256 // empty' "${gr}")"
    current="$(shasum -a 256 "${REPO}/substrate/HASH_LOCKS.yaml" | awk '{print $1}')"
    [[ -n "${stored}" ]] || {
      print -u2 "[plan_phases] genesis_record missing hash_locks_sha256"
      exit 20
    }
    [[ "${stored}" == "${current}" ]] || {
      print -u2 "[plan_phases] genesis hash_locks_sha256 drift: genesis=${stored} current=${current}"
      exit 21
    }
    jq -n \
      --arg ts "${TS}" \
      --arg phase "${PHASE}" \
      --arg hash "${current}" \
      '{phase:$phase,passed:true,kind:"genesis_hash_lock_seal",hash_locks_sha256:$hash,ts:$ts}' > "${OUT}/receipt.json"
    ;;
  *)
    print -u2 "[plan_phases] phase must be 0, 1, or 2"
    exit 2
    ;;
esac

print -r -- "[plan_phases] phase ${PHASE} PASS → ${OUT}/receipt.json"
