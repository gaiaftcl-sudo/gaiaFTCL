#!/usr/bin/env bash
# Canonical GaiaFusion "working app" verification: composite → mac gate (WKWebView + WASM + Playwright)
# → bundled /_next/static HTTP probes → **Mac full cell** :8803 → nine-cell WAN MCP mesh phase.
# XCTest is NOT proof of a working embedded surface; this script is the operator default.
#
# Env:
#   GAIA_ROOT                       — repo root (default: parent of scripts/)
#   GAIAFUSION_SKIP_COMPOSITE=1     — pass --skip-composite-assets to gate (pre-built Resources)
#   GAIAFUSION_VERIFY_RETRIES       — gate retries (default 3)
#   GAIAFUSION_SKIP_STATIC_PROBES=1 — skip /_next/static curl phase
#   GAIAFUSION_STATIC_PROBE_MAX     — max asset URLs to check (default 32)
#   GAIAFUSION_SKIP_MAC_CELL_MCP=1  — skip local Mac cell :8803 probes (CI/sandbox); receipt mac_cell_phase: SKIPPED
#   GAIAFUSION_MAC_CELL_HOST        — default 127.0.0.1
#   GAIAFUSION_MAC_CELL_PORT        — default 8803 (fusion-sidecar-gateway host map)
#   GAIAFUSION_SKIP_MESH_MCP=1      — skip WAN mesh phase (sandbox); receipt mesh_phase: SKIPPED
#   GAIAFUSION_SKIP_SELF_PROBE=1    — skip GET /api/fusion/self-probe (WKWebView DOM + WASM in one JSON)
#   GAIAFUSION_SKIP_OPENUSD_PLAYBACK_VERIFY=1 — skip /api/fusion/openusd-playback frames_presented gate (gate also probes; this is shell receipt)
#   GAIAFTCL_MESH_HOSTS             — optional space-separated "name:ip" list (default: nine crystal cells)
#   GAIAFTCL_VERIFY_CELL            — optional single "name:ip" (overrides mesh list when set)
#   GAIAFUSION_INCLUDE_XCTEST=1     — after success, run swift test in macos/GaiaFusion (compile hygiene; uses --disable-sandbox for USD-linked test bundles)
#   GAIAFUSION_GATE_USE_XCODE=1     — opt-in xcodebuild in gate (default is SwiftPM-only; Package.swift is truth)
#   GAIAFUSION_GATE_APP_BUNDLE=…    — path to GaiaFUSION.app (e.g. dist/GaiaFusion.app) to launch packaged Mach-O
#   Pre-build USD linkage: `scripts/verify_gaiafusion_usd_runtime_link.sh` (also run from release_smoke after swift build).
#   Host Mac skip lock: scripts/lib/gaiafusion_host_c4_lock.sh (GAIAFUSION_ALLOW_SKIP_ON_HOST=1 to opt out).
#
set -euo pipefail

GAIA_ROOT="${GAIA_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$GAIA_ROOT"
EVIDENCE="${GAIA_ROOT}/evidence/fusion_control"
mkdir -p "$EVIDENCE"
RECEIPT_PATH="${EVIDENCE}/gaiafusion_working_app_verify_receipt.json"
GATE_RECEIPT_REL="evidence/fusion_control/fusion_mac_app_gate_receipt.json"
GATE_RECEIPT="${GAIA_ROOT}/${GATE_RECEIPT_REL}"
TS_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VERIFY_RETRIES="${GAIAFUSION_VERIFY_RETRIES:-3}"
STATIC_MAX="${GAIAFUSION_STATIC_PROBE_MAX:-32}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  python3 - "$RECEIPT_PATH" "$TS_UTC" "$GATE_RECEIPT_REL" "$(uname -s)" <<'PY'
import json, sys
path, ts, gate_rel, platform = sys.argv[1:5]
doc = {
    "schema": "gaiaftcl_gaiafusion_working_app_verify_v1",
    "ts_utc": ts,
    "terminal": "REFUSED",
    "gate_receipt_path": gate_rel,
    "reason": "darwin_required",
    "platform": platform,
    "mesh_phase": "BLOCKED",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
  echo "REFUSED: verify_gaiafusion_working_app.sh requires Darwin (macOS) — receipt ${RECEIPT_PATH}" >&2
  exit 3
fi

# shellcheck source=/dev/null
source "${GAIA_ROOT}/scripts/lib/gaiafusion_host_c4_lock.sh"
gaiafusion_host_strip_skip_leak

if ! command -v python3 >/dev/null 2>&1; then
  echo "REFUSED: python3 required" >&2
  exit 1
fi

GATE_ARGS=(--root "$GAIA_ROOT")
if [[ "${GAIAFUSION_SKIP_COMPOSITE:-0}" == "1" ]]; then
  GATE_ARGS+=(--skip-composite-assets)
fi

FAIL_LOG="${EVIDENCE}/verify_gaiafusion_gate_attempt.log"
: >"$FAIL_LOG"
attempt=1
gate_rc=1
while [[ "$attempt" -le "$VERIFY_RETRIES" ]]; do
  echo "━━ GaiaFusion working-app gate attempt ${attempt}/${VERIFY_RETRIES} ━━"
  set +e
  python3 "${GAIA_ROOT}/scripts/run_fusion_mac_app_gate.py" "${GATE_ARGS[@]}" 2>&1 | tee -a "$FAIL_LOG"
  gate_rc=${PIPESTATUS[0]}
  set -e
  if [[ "$gate_rc" -eq 0 ]]; then
    break
  fi
  echo "gate failed rc=${gate_rc} (log: ${FAIL_LOG})" >&2
  if [[ "$attempt" -lt "$VERIFY_RETRIES" ]]; then
    # Single Mac cell: never pkill -f GaiaFusion (matches shells/tests under .../macos/GaiaFusion/).
    bash "${GAIA_ROOT}/scripts/stop_mac_cell_gaiafusion.sh" || true
    sleep 1
  fi
  attempt=$((attempt + 1))
done

if [[ "$gate_rc" -ne 0 ]]; then
  python3 - "$RECEIPT_PATH" "$TS_UTC" "$GATE_RECEIPT_REL" "$attempt" "$gate_rc" "$FAIL_LOG" <<'PY'
import json, sys
path, ts, gate_rel, att_s, rc_s, log_path = sys.argv[1:7]
try:
    tail = open(log_path, encoding="utf-8", errors="replace").read()[-4000:]
except OSError:
    tail = ""
doc = {
    "schema": "gaiaftcl_gaiafusion_working_app_verify_v1",
    "ts_utc": ts,
    "terminal": "REFUSED",
    "gate_receipt_path": gate_rel,
    "gate_attempts": int(att_s),
    "gate_rc": int(rc_s),
    "gate_log_tail": tail,
    "mesh_phase": "REFUSED",
    "next_static_probes_ok": None,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
  echo "REFUSED: fusion mac app gate failed — ${RECEIPT_PATH}" >&2
  exit "$gate_rc"
fi

FUSION_PORT="$(python3 -c "
import json
p = r'''${GATE_RECEIPT}'''
with open(p, encoding='utf-8') as f:
    d = json.load(f)
w = d.get('witness') or {}
print(w.get('fusion_ui_port') or '')
")"
if [[ -z "${FUSION_PORT}" || ! "$FUSION_PORT" =~ ^[0-9]+$ ]]; then
  python3 - "$RECEIPT_PATH" "$TS_UTC" "$GATE_RECEIPT_REL" <<'PY'
import json, sys
path, ts, gate_rel = sys.argv[1:4]
doc = {
    "schema": "gaiaftcl_gaiafusion_working_app_verify_v1",
    "ts_utc": ts,
    "terminal": "REFUSED",
    "gate_receipt_path": gate_rel,
    "reason": "fusion_ui_port_missing_from_gate_receipt",
    "mesh_phase": "BLOCKED",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
  echo "REFUSED: could not read fusion_ui_port from ${GATE_RECEIPT}" >&2
  exit 1
fi

SELF_PROBE_DETAIL="null"
SELF_PROBE_OK="skip"
if [[ "${GAIAFUSION_SKIP_SELF_PROBE:-0}" != "1" ]]; then
  echo "━━ In-app self-probe (HTTP CLI → /api/fusion/self-probe) ━━"
  if ! SELF_JSON="$(curl -sS --max-time 25 "http://127.0.0.1:${FUSION_PORT}/api/fusion/self-probe")"; then
    python3 - "$RECEIPT_PATH" "$TS_UTC" "$GATE_RECEIPT_REL" "$FUSION_PORT" "$attempt" <<'PY'
import json, sys
path, ts, gate_rel, port_s, att_s = sys.argv[1:6]
doc = {
    "schema": "gaiaftcl_gaiafusion_working_app_verify_v1",
    "ts_utc": ts,
    "terminal": "REFUSED",
    "gate_receipt_path": gate_rel,
    "gate_attempts": int(att_s),
    "fusion_ui_port": int(port_s),
    "self_probe_phase": "REFUSED",
    "reason": "curl_self_probe_failed",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
    echo "REFUSED: /api/fusion/self-probe not reachable on port ${FUSION_PORT}" >&2
    exit 1
  fi
  SELF_PROBE_DETAIL="$SELF_JSON"
  export VERIFY_SELF_PROBE_PAYLOAD="$SELF_JSON"
  if ! python3 -c "import json,os; d=json.loads(os.environ['VERIFY_SELF_PROBE_PAYLOAD']); assert d.get('schema')=='gaiaftcl_fusion_self_probe_v1'; assert d.get('terminal')=='CURE'; u=d.get('usd_px') or {}; assert isinstance(u.get('pxr_version_int'), int) and u.get('pxr_version_int',0)>0; assert u.get('in_memory_stage') is True; assert u.get('plant_control_viewport_prim') is True"; then
    python3 - "$RECEIPT_PATH" "$TS_UTC" "$GATE_RECEIPT_REL" "$FUSION_PORT" "$attempt" <<'PY'
import json, os, sys
path, ts, gate_rel, port_s, att_s = sys.argv[1:6]
raw = os.environ.get("VERIFY_SELF_PROBE_PAYLOAD", "")
try:
    detail = json.loads(raw)
except json.JSONDecodeError:
    detail = {"raw": raw[:2000]}
doc = {
    "schema": "gaiaftcl_gaiafusion_working_app_verify_v1",
    "ts_utc": ts,
    "terminal": "REFUSED",
    "gate_receipt_path": gate_rel,
    "gate_attempts": int(att_s),
    "fusion_ui_port": int(port_s),
    "self_probe_phase": "REFUSED",
    "self_probe": detail,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
    echo "REFUSED: self-probe terminal != CURE or schema mismatch — ${RECEIPT_PATH}" >&2
    unset VERIFY_SELF_PROBE_PAYLOAD 2>/dev/null || true
    exit 1
  fi
  unset VERIFY_SELF_PROBE_PAYLOAD 2>/dev/null || true
  SELF_PROBE_OK="ok"
else
  SELF_PROBE_OK="skip"
fi

OPENUSD_PLAYBACK_VERIFY="skip"
if [[ "${GAIAFUSION_SKIP_OPENUSD_PLAYBACK_VERIFY:-0}" != "1" ]]; then
  echo "━━ Metal viewport: GET /api/fusion/openusd-playback (frames_presented ≥ 1) ━━"
  if ! bash "${GAIA_ROOT}/scripts/verify_gaiafusion_usd_playback.sh" "$FUSION_PORT"; then
    python3 - "$RECEIPT_PATH" "$TS_UTC" "$GATE_RECEIPT_REL" "$FUSION_PORT" "$attempt" <<'PY'
import json, sys
path, ts, gate_rel, port_s, att_s = sys.argv[1:6]
doc = {
    "schema": "gaiaftcl_gaiafusion_working_app_verify_v1",
    "ts_utc": ts,
    "terminal": "REFUSED",
    "gate_receipt_path": gate_rel,
    "gate_attempts": int(att_s),
    "fusion_ui_port": int(port_s),
    "openusd_playback_verify": "REFUSED",
    "reason": "openusd_playback_frames_not_advancing",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
    echo "REFUSED: openusd-playback viewport probe — see ${EVIDENCE}/gaiafusion_openusd_playback_probe.json" >&2
    exit 1
  fi
  OPENUSD_PLAYBACK_VERIFY="CURE"
else
  OPENUSD_PLAYBACK_VERIFY="SKIPPED"
fi
export GAIA_OPENUSD_PB_JSON="${EVIDENCE}/gaiafusion_openusd_playback_probe.json"

STATIC_PROBE_DETAIL="null"
NEXT_STATIC_BOOL="skip"
if [[ "${GAIAFUSION_SKIP_STATIC_PROBES:-0}" != "1" ]]; then
  INDEX_HTML="${GAIA_ROOT}/macos/GaiaFusion/GaiaFusion/Resources/fusion-web/index.html"
  STATIC_JSON="$(python3 - "$INDEX_HTML" "$FUSION_PORT" "$STATIC_MAX" <<'PY'
import json, re, sys, urllib.request
index_path, port_s, max_n = sys.argv[1], sys.argv[2], int(sys.argv[3])
try:
    raw = open(index_path, encoding="utf-8", errors="replace").read()
except OSError as e:
    print(json.dumps({"ok": False, "detail": str(e), "probed": [], "count": 0}))
    sys.exit(0)
urls = set(re.findall(r'(?:src|href)="(/_next/static/[^"]+)"', raw))
urls |= set(re.findall(r"(?:src|href)='(/_next/static/[^']+)'", raw))
ordered = sorted(urls)[:max_n]
if len(urls) == 0:
    print(json.dumps({"ok": False, "detail": "no__next_static_refs_in_index_html", "probed": [], "count": 0}))
    sys.exit(0)
base = f"http://127.0.0.1:{port_s}"
probed = []
ok_all = True
first_fail = None
for path in ordered:
    url = base + path
    try:
        with urllib.request.urlopen(url, timeout=8) as resp:
            code = resp.status
    except Exception as e:
        ok_all = False
        if first_fail is None:
            first_fail = {"url": url, "error": str(e)[:240]}
        probed.append({"url": url, "http_code": 0, "ok": False})
        continue
    good = 200 <= code < 300
    if not good and first_fail is None:
        first_fail = {"url": url, "http_code": code}
    if not good:
        ok_all = False
    probed.append({"url": url, "http_code": code, "ok": good})
print(json.dumps({"ok": ok_all, "first_fail": first_fail, "probed": probed, "count": len(ordered)}))
PY
)"
  STATIC_PROBE_DETAIL="$STATIC_JSON"
  NEXT_STATIC_BOOL="$(echo "$STATIC_JSON" | python3 -c "import sys,json; print('ok' if json.load(sys.stdin)['ok'] else 'bad')")"
  if [[ "$NEXT_STATIC_BOOL" != "ok" ]]; then
    python3 - "$RECEIPT_PATH" "$TS_UTC" "$GATE_RECEIPT_REL" "$FUSION_PORT" "$attempt" "$STATIC_JSON" <<'PY'
import json, sys
path, ts, gate_rel, port_s, att_s, static_s = sys.argv[1:7]
detail = json.loads(static_s)
doc = {
    "schema": "gaiaftcl_gaiafusion_working_app_verify_v1",
    "ts_utc": ts,
    "terminal": "REFUSED",
    "gate_receipt_path": gate_rel,
    "gate_attempts": int(att_s),
    "fusion_ui_port": int(port_s),
    "next_static_probes_ok": False,
    "static_probe": detail,
    "mesh_phase": "BLOCKED",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
    echo "REFUSED: /_next/static probe failed (see static_probe in receipt) — ${RECEIPT_PATH}" >&2
    exit 1
  fi
else
  NEXT_STATIC_BOOL="skip"
fi

mac_cell_phase="CURE"
MAC_CELL_DETAIL_JSON='{"rows":[],"fail":null}'
if [[ "${GAIAFUSION_SKIP_MAC_CELL_MCP:-0}" == "1" ]]; then
  mac_cell_phase="SKIPPED"
else
  MAC_CELL_DETAIL_JSON="$(python3 "${GAIA_ROOT}/scripts/mcp_mac_cell_probe.py")"
  MAC_FAIL="$(echo "$MAC_CELL_DETAIL_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('fail') or '')")"
  if [[ -n "$MAC_FAIL" ]]; then
    python3 - "$RECEIPT_PATH" "$TS_UTC" "$GATE_RECEIPT_REL" "$FUSION_PORT" "$attempt" "$NEXT_STATIC_BOOL" "$STATIC_PROBE_DETAIL" "$MAC_CELL_DETAIL_JSON" "$MAC_FAIL" <<'PY'
import json, sys
path, ts, gate_rel, port_s, att_s, ns, static_s, mac_s, mac_fail = sys.argv[1:10]
static_obj = json.loads(static_s) if static_s and static_s != "null" else None
mac_obj = json.loads(mac_s)
ns_ok = True if ns == "ok" else (False if ns == "bad" else None)
doc = {
    "schema": "gaiaftcl_gaiafusion_working_app_verify_v1",
    "ts_utc": ts,
    "terminal": "REFUSED",
    "gate_receipt_path": gate_rel,
    "gate_attempts": int(att_s),
    "fusion_ui_port": int(port_s),
    "next_static_probes_ok": ns_ok,
    "static_probe": static_obj,
    "mac_cell_phase": "REFUSED",
    "mac_cell": mac_obj.get("rows"),
    "mac_cell_fail": mac_fail,
    "mesh_phase": "BLOCKED",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
    echo "REFUSED: Mac full-cell MCP phase failed (${MAC_FAIL}) — start docker compose -f docker-compose.fusion-sidecar.yml or set GAIAFUSION_SKIP_MAC_CELL_MCP=1 — ${RECEIPT_PATH}" >&2
    exit 1
  fi
fi

mesh_phase="CURE"
MESH_DETAIL_JSON='{"rows":[],"fail":null}'
if [[ "${GAIAFUSION_SKIP_MESH_MCP:-0}" == "1" ]]; then
  mesh_phase="SKIPPED"
else
  MESH_DETAIL_JSON="$(python3 <<'PY'
import json, os, subprocess

def curl_code(url: str) -> str:
    try:
        r = subprocess.run(
            ["curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}", "--connect-timeout", "6", "--max-time", "14", url],
            capture_output=True,
            text=True,
            timeout=22,
        )
        return (r.stdout or "000").strip()
    except Exception:
        return "000"

single = os.environ.get("GAIAFTCL_VERIFY_CELL", "").strip()
raw_hosts = os.environ.get("GAIAFTCL_MESH_HOSTS", "").strip()
if single:
    entries = [single]
elif raw_hosts:
    entries = raw_hosts.split()
else:
    entries = [
        "gaiaftcl-hcloud-hel1-01:77.42.85.60",
        "gaiaftcl-hcloud-hel1-02:135.181.88.134",
        "gaiaftcl-hcloud-hel1-03:77.42.32.156",
        "gaiaftcl-hcloud-hel1-04:77.42.88.110",
        "gaiaftcl-hcloud-hel1-05:37.27.7.9",
        "gaiaftcl-netcup-nbg1-01:37.120.187.247",
        "gaiaftcl-netcup-nbg1-02:152.53.91.220",
        "gaiaftcl-netcup-nbg1-03:152.53.88.141",
        "gaiaftcl-netcup-nbg1-04:37.120.187.174",
    ]

rows = []
fail = None
for entry in entries:
    entry = entry.strip()
    if not entry:
        continue
    if ":" not in entry:
        print(json.dumps({"rows": [], "fail": f"bad_entry:{entry}"}))
        raise SystemExit(0)
    name, ip = entry.split(":", 1)
    hc = curl_code(f"http://{ip}:8803/health")
    cc = curl_code(f"http://{ip}:8803/claims?limit=1")
    rows.append({"cell": name, "ip": ip, "port": 8803, "health_http": hc, "claims_http": cc})
    if not hc.isdigit() or not (200 <= int(hc) < 300):
        fail = f"health:{name}:{ip}:8803:{hc}"
        break
    # Gateway alive: claims may be 400/401/402/403 (wallet) or 200; refuse only timeout/5xx/000
    if cc == "000" or (cc.isdigit() and cc.startswith("5")):
        fail = f"claims:{name}:{ip}:8803:{cc}"
        break

print(json.dumps({"rows": rows, "fail": fail}))
PY
)"
  MESH_FAIL="$(echo "$MESH_DETAIL_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('fail') or '')")"
  if [[ -n "$MESH_FAIL" ]]; then
    python3 - "$RECEIPT_PATH" "$TS_UTC" "$GATE_RECEIPT_REL" "$FUSION_PORT" "$attempt" "$NEXT_STATIC_BOOL" "$STATIC_PROBE_DETAIL" "$mac_cell_phase" "$MAC_CELL_DETAIL_JSON" "$MESH_DETAIL_JSON" "$MESH_FAIL" <<'PY'
import json, sys
path, ts, gate_rel, port_s, att_s, ns, static_s, mac_ph, mac_s, mesh_s, mesh_fail = sys.argv[1:11]
static_obj = json.loads(static_s) if static_s and static_s != "null" else None
mac_obj = json.loads(mac_s)
mesh_obj = json.loads(mesh_s)
ns_ok = True if ns == "ok" else (False if ns == "bad" else None)
doc = {
    "schema": "gaiaftcl_gaiafusion_working_app_verify_v1",
    "ts_utc": ts,
    "terminal": "REFUSED",
    "gate_receipt_path": gate_rel,
    "gate_attempts": int(att_s),
    "fusion_ui_port": int(port_s),
    "next_static_probes_ok": ns_ok,
    "static_probe": static_obj,
    "mac_cell_phase": mac_ph,
    "mac_cell": mac_obj.get("rows"),
    "mesh_phase": "REFUSED",
    "mesh_cells": mesh_obj.get("rows"),
    "mesh_fail": mesh_fail,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
    echo "REFUSED: mesh MCP phase failed (${MESH_FAIL}) — ${RECEIPT_PATH}" >&2
    exit 1
  fi
fi

XCTEST_INCLUDED="0"
if [[ "${GAIAFUSION_INCLUDE_XCTEST:-0}" == "1" ]]; then
  XCT_LOG="$(mktemp "${TMPDIR:-/tmp}/gaiafusion_xctest.XXXXXX")"
  if (cd "${GAIA_ROOT}/macos/GaiaFusion" && swift test --disable-sandbox 2>&1 | tee "$XCT_LOG"); then
    XCTEST_INCLUDED="1"
  else
    xrc=$?
    python3 - "$RECEIPT_PATH" "$TS_UTC" "$GATE_RECEIPT_REL" "$FUSION_PORT" "$attempt" "$NEXT_STATIC_BOOL" "$STATIC_PROBE_DETAIL" "$mac_cell_phase" "$MAC_CELL_DETAIL_JSON" "$MESH_DETAIL_JSON" "$mesh_phase" "$xrc" "$XCT_LOG" <<'PY'
import json, sys
path, ts, gate_rel, port_s, att_s, ns, static_s, mac_ph, mac_s, mesh_s, mph, xrc_s, log_path = sys.argv[1:14]
static_obj = json.loads(static_s) if static_s and static_s != "null" else None
mac_obj = json.loads(mac_s)
mesh_obj = json.loads(mesh_s)
ns_ok = True if ns == "ok" else (False if ns == "bad" else None)
try:
    tail = open(log_path, encoding="utf-8", errors="replace").read()[-4000:]
except OSError:
    tail = ""
doc = {
    "schema": "gaiaftcl_gaiafusion_working_app_verify_v1",
    "ts_utc": ts,
    "terminal": "REFUSED",
    "gate_receipt_path": gate_rel,
    "gate_attempts": int(att_s),
    "fusion_ui_port": int(port_s),
    "next_static_probes_ok": ns_ok,
    "static_probe": static_obj,
    "mac_cell_phase": mac_ph,
    "mac_cell": mac_obj.get("rows"),
    "mesh_phase": mph,
    "mesh_cells": mesh_obj.get("rows"),
    "swift_test_rc": int(xrc_s),
    "swift_test_tail": tail,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
    rm -f "$XCT_LOG"
    echo "REFUSED: swift test failed (GAIAFUSION_INCLUDE_XCTEST=1) — ${RECEIPT_PATH}" >&2
    exit "$xrc"
  fi
  rm -f "$XCT_LOG"
fi

SELF_SNIP="${EVIDENCE}/.verify_self_probe_snapshot.json"
printf '%s' "${SELF_PROBE_DETAIL}" >"${SELF_SNIP}"
python3 - "$RECEIPT_PATH" "$TS_UTC" "$GATE_RECEIPT_REL" "$GATE_RECEIPT" "$FUSION_PORT" "$attempt" "$NEXT_STATIC_BOOL" "$STATIC_PROBE_DETAIL" "$mac_cell_phase" "$MAC_CELL_DETAIL_JSON" "$MESH_DETAIL_JSON" "$mesh_phase" "$XCTEST_INCLUDED" "$SELF_SNIP" "$SELF_PROBE_OK" "${OPENUSD_PLAYBACK_VERIFY}" "${GAIA_OPENUSD_PB_JSON:-}" <<'PY'
import json, os, sys
path, ts, gate_rel, gate_abs, port_s, att_s, ns, static_s, mac_ph, mac_s, mesh_s, mph, xtest_inc, self_path, self_ok, openusd_v, openusd_path = sys.argv[1:18]
static_obj = json.loads(static_s) if static_s and static_s != "null" else None
mac_obj = json.loads(mac_s)
mesh_obj = json.loads(mesh_s)
ns_ok = True if ns == "ok" else (False if ns == "bad" else None)
doc = {
    "schema": "gaiaftcl_gaiafusion_working_app_verify_v1",
    "ts_utc": ts,
    "terminal": "CURE",
    "gate_receipt_path": gate_rel,
    "fusion_mac_app_gate_receipt": gate_abs,
    "gate_attempts": int(att_s),
    "fusion_ui_port": int(port_s),
    "next_static_probes_ok": ns_ok,
    "static_probe": static_obj,
    "mac_cell_phase": mac_ph,
    "mac_cell": mac_obj.get("rows"),
    "mesh_phase": mph,
    "mesh_cells": mesh_obj.get("rows"),
    "swift_test_included_ok": (xtest_inc == "1"),
    "openusd_playback_verify": openusd_v,
}
if self_ok == "ok":
    try:
        with open(self_path, encoding="utf-8") as sf:
            doc["self_probe"] = json.load(sf)
    except OSError:
        doc["self_probe"] = None
    doc["self_probe_phase"] = "CURE"
elif self_ok == "skip":
    doc["self_probe_phase"] = "SKIPPED"
else:
    doc["self_probe_phase"] = "UNKNOWN"
if openusd_v == "CURE" and openusd_path and os.path.isfile(openusd_path):
    try:
        with open(openusd_path, encoding="utf-8") as ouf:
            doc["openusd_playback_probe"] = json.load(ouf)
    except OSError:
        doc["openusd_playback_probe"] = None
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY

echo "CURE: GaiaFusion working-app verify — ${RECEIPT_PATH}"
exit 0
