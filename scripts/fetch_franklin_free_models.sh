#!/usr/bin/env zsh
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "${ROOT}"

fail() {
  print "REFUSED:$1:$2" >&2
  exit 1
}

mkdir -p "cells/franklin/avatar/bundle_assets/meshes"
mkdir -p "cells/franklin/avatar/bundle_assets/provenance"

OUT_OBJ="cells/franklin/avatar/bundle_assets/meshes/franklin_reference_bust.obj"
OUT_META="cells/franklin/avatar/bundle_assets/provenance/free_model_sources.json"

# Sketchfab direct model download requires authenticated API token.
# We keep this explicit so acquisition is deterministic and auditable.
if [[ -z "${SKETCHFAB_TOKEN:-}" ]]; then
  fail "GW_REFUSE_FRANKLIN_MODEL_AUTH_REQUIRED" \
    "Set SKETCHFAB_TOKEN to download free Franklin model archives from Sketchfab API"
fi

MODEL_UID="${FRANKLIN_SKETCHFAB_MODEL_UID:-f42692f137e94607865063cd4883df53}"
API_URL="https://api.sketchfab.com/v3/models/${MODEL_UID}/download"

json="$(curl -fsSL -H "Authorization: Token ${SKETCHFAB_TOKEN}" "${API_URL}")" || \
  fail "GW_REFUSE_FRANKLIN_MODEL_DOWNLOAD_FAILED" "Unable to query Sketchfab download API"

src_url="$(python3 - <<'PY' "${json}"
import json,sys
data=json.loads(sys.argv[1])
for key in ("source","gltf","glb","usdz"):
    v=data.get(key) or {}
    u=v.get("url")
    if u:
        print(u); break
PY
)"

[[ -n "${src_url}" ]] || fail "GW_REFUSE_FRANKLIN_MODEL_URL_MISSING" "No downloadable archive URL returned by API"

tmp_zip="$(mktemp "/tmp/franklin-model-XXXXXX.zip")"
curl -fL "${src_url}" -o "${tmp_zip}" || fail "GW_REFUSE_FRANKLIN_MODEL_FETCH_FAILED" "Failed to fetch model archive"

tmp_dir="$(mktemp -d "/tmp/franklin-model-XXXXXX")"
unzip -q "${tmp_zip}" -d "${tmp_dir}" || fail "GW_REFUSE_FRANKLIN_MODEL_UNZIP_FAILED" "Failed to unzip model archive"

obj_candidate="$(python3 - <<'PY' "${tmp_dir}"
import os,sys
root=sys.argv[1]
for base,_,files in os.walk(root):
    for f in files:
        if f.lower().endswith(".obj"):
            print(os.path.join(base,f)); raise SystemExit
PY
)"

[[ -n "${obj_candidate}" ]] || fail "GW_REFUSE_FRANKLIN_MODEL_OBJ_MISSING" "No OBJ found in downloaded archive"
cp "${obj_candidate}" "${OUT_OBJ}"

python3 - <<'PY' "${OUT_META}" "${MODEL_UID}" "${src_url}" "${OUT_OBJ}"
import json,sys,datetime,os
path,uid,url,obj=sys.argv[1:]
data={
  "timestamp_utc": datetime.datetime.utcnow().isoformat()+"Z",
  "source": "Sketchfab",
  "model_uid": uid,
  "archive_url": url,
  "local_obj": obj,
  "license_note": "Check upstream model license and attribution requirements before redistribution."
}
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path,"w",encoding="utf-8") as f:
    json.dump(data,f,indent=2)
PY

print "CALORIE:FRANKLIN-FREE-MODEL:downloaded ${OUT_OBJ}"
