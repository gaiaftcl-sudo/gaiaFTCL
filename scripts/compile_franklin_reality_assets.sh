#!/usr/bin/env zsh
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "${ROOT}"

fail() {
  print "REFUSED:$1:$2" >&2
  exit 1
}

TAU="${FOT_SPROUT_TAU:-$(date -u +%Y%m%dT%H%M%SZ)}"
MESH_DIR="cells/franklin/avatar/bundle_assets/meshes"
BUILD_DIR="cells/franklin/avatar/build/reality"
RECEIPT_DIR="cells/franklin/avatar/evidence/iq"
RECEIPT_PATH="${RECEIPT_DIR}/${TAU}_realitytool_receipt.json"

USDZ="${MESH_DIR}/Franklin_Passy_V2.usdz"
ZTL="${MESH_DIR}/Franklin_Passy_V2.ztl"
RKASSETS="cells/franklin/avatar/bundle_assets/Franklin.rkassets"
REALITY_OUT="${BUILD_DIR}/FranklinAssets.reality"
PLATFORM="${FRANKLIN_REALITY_PLATFORM:-macosx}"
DEPLOYMENT_TARGET="${FRANKLIN_REALITY_DEPLOYMENT_TARGET:-26.0}"

[[ -f "${USDZ}" ]] || fail "GW_REFUSE_FRANKLIN_USDZ_MISSING" "missing ${USDZ}"
[[ -f "${ZTL}" ]] || fail "GW_REFUSE_FRANKLIN_ZTL_MISSING" "missing ${ZTL}"

mkdir -p "${BUILD_DIR}" "${RECEIPT_DIR}"

REALITYTOOL="$(xcrun --find realitytool 2>/dev/null || true)"
[[ -n "${REALITYTOOL}" ]] || fail "GW_REFUSE_REALITYTOOL_MISSING" "xcrun realitytool not found"

USDCHECKER="$(command -v usdchecker || true)"
if [[ -n "${USDCHECKER}" ]]; then
  "${USDCHECKER}" "${USDZ}" >/dev/null 2>&1 || \
    fail "GW_REFUSE_USD_CHECKER_FAILED" "usdchecker failed for ${USDZ}"
fi

[[ -d "${RKASSETS}" ]] || fail "GW_REFUSE_FRANKLIN_RKASSETS_MISSING" "missing ${RKASSETS}"

"${REALITYTOOL}" compile \
  --output-reality "${REALITY_OUT}" \
  --platform "${PLATFORM}" \
  --deployment-target "${DEPLOYMENT_TARGET}" \
  "${RKASSETS}" >/dev/null 2>&1 || \
  fail "GW_REFUSE_REALITYTOOL_COMPILE_FAILED" "realitytool compile failed for ${RKASSETS}"

[[ -f "${REALITY_OUT}" ]] || fail "GW_REFUSE_REALITY_ASSET_MISSING" "missing compiled reality asset ${REALITY_OUT}"

python3 - <<'PY' "${RECEIPT_PATH}" "${USDZ}" "${ZTL}" "${REALITY_OUT}" "${TAU}"
import json, os, sys, datetime
receipt_path, usdz, ztl, reality_out, tau = sys.argv[1:]
payload = {
    "tau": tau,
    "issued_at_utc": datetime.datetime.utcnow().isoformat() + "Z",
    "terminal": "CALORIE",
    "contract": "LG-FRANKLIN-IQ-REALITYTOOL-ASSET-PIPELINE-001",
    "inputs": {
        "usdz": usdz,
        "ztl": ztl,
    },
    "outputs": {
        "reality": reality_out,
        "reality_bytes": os.path.getsize(reality_out),
    },
}
os.makedirs(os.path.dirname(receipt_path), exist_ok=True)
with open(receipt_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2)
PY

print "CALORIE:FRANKLIN-REALITY-PIPELINE:${REALITY_OUT}"
