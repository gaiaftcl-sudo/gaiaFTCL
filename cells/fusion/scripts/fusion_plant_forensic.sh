#!/usr/bin/env bash
# GaiaFTCL — Fusion plant / catalog forensic when stack is up or cold.
# Receipt: FUSION_PLANT_FORENSIC_LATEST.json — catalog virtual + production ids, all M8 benchmarks,
# projection slice, optional live GET /api/fusion/s4-projection (production_systems_ui witness).
#
#   bash scripts/fusion_plant_forensic.sh
#
# Env:
#   FUSION_FORENSIC_S4_URL       — base (default http://127.0.0.1:${FUSION_UI_PORT:-8910})
#   FUSION_FORENSIC_SKIP_LIVE=1  — no HTTP (static only)
#   FUSION_FORENSIC_REQUIRE_LIVE=1 — exit 1 unless S4 returns 200
#   FUSION_FORENSIC_SKIP_NPM=1   — skip Vitest fusion units
#   FUSION_FORENSIC_PROJECTION=  — override path to fusion_projection.json
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"
cd "$ROOT"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EVID="$ROOT/evidence/fusion_control"
mkdir -p "$EVID"
OUT="$EVID/FUSION_PLANT_FORENSIC_LATEST.json"
TMPV="$(mktemp)"
trap 'rm -f "$TMPV"' EXIT

CATALOG="$ROOT/deploy/fusion_mesh/fusion_virtual_systems_catalog_s4.json"
PROJ="${FUSION_FORENSIC_PROJECTION:-$ROOT/deploy/fusion_mesh/fusion_projection.json}"
BENCH_DIR="$ROOT/deploy/fusion_mesh/config/benchmarks"
UI_PORT="${FUSION_UI_PORT:-8910}"
S4_BASE="${FUSION_FORENSIC_S4_URL:-http://127.0.0.1:${UI_PORT}}"
LONG_RUN_JSONL="$EVID/long_run_signals.jsonl"
FUSION_BIN="$ROOT/services/fusion_control_mac/dist/FusionControl.app/Contents/MacOS/fusion_control"

if ! command -v jq >/dev/null 2>&1; then
  echo "REFUSED: jq required" >&2
  exit 1
fi
if [[ ! -f "$CATALOG" ]]; then
  echo "REFUSED: missing $CATALOG" >&2
  exit 1
fi

FAIL_STATIC=0
note_fail() { echo "FAIL $*" >&2; FAIL_STATIC=1; }

# --- Projection ---
if [[ -f "$PROJ" ]]; then
  proj_slice="$(jq -c '{plant_flavor: (.plant_flavor // "generic"), dif_profile: (.dif_profile // "default"), benchmark_surface_id: (.benchmark_surface_id // ""), schema: .schema}' "$PROJ")"
else
  proj_slice='{"error":"missing_projection_file"}'
  note_fail "fusion_projection.json missing"
fi

bench_id="$(jq -r '.benchmark_surface_id // empty' <<<"$proj_slice")"
bench_file="$BENCH_DIR/${bench_id}.json"
if [[ -n "$bench_id" && -f "$bench_file" ]]; then
  proj_benchmark_witness="MATCH_FILE"
elif [[ -n "$bench_id" ]]; then
  proj_benchmark_witness="MISSING_FILE"
  note_fail "benchmark_surface_id=$bench_id has no file under config/benchmarks"
else
  proj_benchmark_witness="UNSET"
fi

# --- All M8 benchmark surfaces (plant-type measurement envelopes) ---
benchmark_rows="[]"
if [[ -d "$BENCH_DIR" ]]; then
  while IFS= read -r -d '' f; do
    base="$(basename "$f" .json)"
    rel="${f#$ROOT/}"
    if jq -e '.schema == "gaiaftcl_m8_benchmark_surface_v1" and (.id // "") != ""' "$f" >/dev/null 2>&1; then
      bid="$(jq -r '.id' "$f")"
      benchmark_rows="$(jq -n --argjson arr "$benchmark_rows" --arg id "$bid" --arg fp "$rel" '$arr + [{id: $id, file: $fp, schema_ok: true}]')"
    else
      note_fail "invalid benchmark JSON $rel"
      benchmark_rows="$(jq -n --argjson arr "$benchmark_rows" --arg id "$base" --arg fp "$rel" '$arr + [{id: $id, file: $fp, schema_ok: false}]')"
    fi
  done < <(find "$BENCH_DIR" -maxdepth 1 -name '*.json' -print0 2>/dev/null || true)
fi

production_rows="$(jq -c '[.production_systems[] | {id, label, requires, bridge_key}]' "$CATALOG")"
v_ids="$(jq -r '.virtual_systems[]?.id // empty' "$CATALOG" | sort -u)"

# --- Virtual catalog rows (one witness per id) ---
: >"$TMPV"
while read -r vid; do
  [[ -z "$vid" ]] && continue
  status="WITNESSED"
  detail=""
  case "$vid" in
    metal_validation)
      if [[ -x "$FUSION_BIN" ]]; then
        detail="FusionControl binary executable"
      else
        status="S4_ONLY"
        detail="FusionControl binary missing — build not witnessed on this host"
      fi
      ;;
    long_run_virtual_loop)
      if [[ -f "$ROOT/scripts/fusion_cell_long_run_runner.sh" ]]; then
        detail="fusion_cell_long_run_runner.sh present"
      else
        status="FAIL"
        detail="runner missing"
        note_fail "long_run runner missing"
      fi
      if [[ -f "$LONG_RUN_JSONL" ]]; then
        lr_lines="$(wc -l <"$LONG_RUN_JSONL" | tr -d ' ')"
        lr_last="$(tail -n1 "$LONG_RUN_JSONL" 2>/dev/null | jq -c '{control_signal, ts, schema}' 2>/dev/null || echo '{}')"
        detail="$detail; ledger_lines=$lr_lines ledger_tail=$lr_last"
      else
        detail="$detail; ledger absent"
      fi
      ;;
    benchmark_surfaces)
      bc="$(jq 'length' <<<"$benchmark_rows")"
      detail="m8 benchmark files enumerated: $bc"
      ;;
    *)
      status="UNKNOWN_ID"
      detail="extend fusion_plant_forensic.sh case for this catalog id"
      ;;
  esac
  jq -n --arg id "$vid" --arg st "$status" --arg det "$detail" '{id: $id, witness_status: $st, detail: $det}' >>"$TMPV"
done <<<"$v_ids"

virtual_rows="$(jq -s '.' "$TMPV")"
if [[ -z "$v_ids" ]]; then v_count=0; else v_count="$(echo "$v_ids" | grep -c . || true)"; fi
virt_len="$(jq 'length' <<<"$virtual_rows")"
catalog_complete="true"
if [[ "$virt_len" != "$v_count" ]]; then
  catalog_complete="false"
  note_fail "virtual witness rows ($virt_len) != catalog virtual ids ($v_count)"
fi

# --- Live S4 API ---
live_json="null"
live_http="SKIPPED"
prod_witness="[]"
if [[ "${FUSION_FORENSIC_SKIP_LIVE:-0}" != "1" ]]; then
  url="${S4_BASE%/}/api/fusion/s4-projection"
  body="$EVID/.s4_forensic_body.json"
  errf="$EVID/.s4_forensic_curl.err"
  rm -f "$body" "$errf"
  live_http="$(curl -sS -m 12 -o "$body" -w '%{http_code}' "$url" 2>"$errf" || echo "000")"
  if [[ "$live_http" == "200" && -s "$body" ]]; then
    live_json="$(jq -c '{
      schema: .schema,
      ts_utc: .ts_utc,
      flow_gates: .flow_gates,
      production_systems_ui: .production_systems_ui,
      long_run: {running: .long_run.running, pid: .long_run.pid, signals_jsonl: .long_run.signals_jsonl}
    }' "$body" 2>/dev/null || echo '{"parse_error":true}')"
    prod_witness="$(jq -n --argjson api "$(cat "$body")" --argjson cat "$production_rows" '
      ($cat) as $c | ($api.production_systems_ui // []) as $ui
      | $c
      | map(
          . as $p
          | ($ui | map(select(.id == $p.id)) | .[0]) as $row
          | {
              id: $p.id,
              label: $p.label,
              catalog_requires: $p.requires,
              ui_enabled: ($row.enabled // null),
              ui_grey_reasons: ($row.grey_reasons // null),
              witness: (if $row == null then "MISSING_UI_ROW"
                        elif ($row.enabled == true) then "ENABLED"
                        else "GREYED_OUT" end)
            }
        )
    ')"
  else
    prod_witness="[]"
    live_json="$(jq -n --arg c "$live_http" --arg e "$(head -c 300 "$errf" 2>/dev/null || true)" '{unreachable: true, http_status: $c, curl_err_tail: $e}')"
  fi
  rm -f "$body" "$errf"
fi

if [[ "${FUSION_FORENSIC_REQUIRE_LIVE:-0}" == "1" && "$live_http" != "200" ]]; then
  echo "REFUSED: FUSION_FORENSIC_REQUIRE_LIVE=1 but HTTP $live_http" >&2
  exit 1
fi

# --- Vitest (gate math) ---
npm_witness="SKIPPED"
if [[ "${FUSION_FORENSIC_SKIP_NPM:-0}" != "1" && -d "$ROOT/services/gaiaos_ui_web/node_modules" ]]; then
  if (cd "$ROOT/services/gaiaos_ui_web" && GAIA_ROOT="$ROOT" npm run test:unit:fusion --silent >/dev/null 2>&1); then
    npm_witness="PASS_unit_fusion"
  else
    npm_witness="FAIL"
    note_fail "npm run test:unit:fusion"
  fi
fi

bench_file_count="$(find "$BENCH_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
bench_ok="$(jq '[.[] | select(.schema_ok == true)] | length' <<<"$benchmark_rows")"
benchmark_inventory_ok="true"
if [[ "$bench_ok" != "$bench_file_count" ]] || [[ "$bench_file_count" -eq 0 ]]; then
  benchmark_inventory_ok="false"
  note_fail "benchmark files=$bench_file_count valid_schema=$bench_ok (must match and be non-zero)"
fi

jq -n \
  --arg schema gaiaftcl_fusion_plant_forensic_v1 \
  --arg at "$TS" \
  --arg root "$ROOT" \
  --arg s4base "$S4_BASE" \
  --arg http "$live_http" \
  --arg projw "$proj_benchmark_witness" \
  --arg bfc "$bench_file_count" \
  --argjson proj "$proj_slice" \
  --argjson benchmarks "$benchmark_rows" \
  --argjson virtual_witness "$virtual_rows" \
  --argjson production_catalog "$production_rows" \
  --argjson live "$live_json" \
  --argjson prod_witness "$prod_witness" \
  --arg npmw "$npm_witness" \
  --arg cc "$catalog_complete" \
  --arg bi "$benchmark_inventory_ok" \
  --argjson fs "$FAIL_STATIC" \
  '{
    schema: $schema,
    generated_at_utc: $at,
    gaia_root: $root,
    s4_base_url_used: $s4base,
    projection: ($proj + {active_benchmark_file_witness: $projw}),
    m8_benchmark_surfaces: $benchmarks,
    catalog_virtual_systems: $virtual_witness,
    catalog_production_systems: $production_catalog,
    live_s4_api: {http_status: $http, snapshot: $live, production_ui_witness: $prod_witness},
    vitest_fusion_units: $npmw,
    closure: {
      every_virtual_system_witnessed: ($cc == "true"),
      all_benchmark_files_valid: ($bi == "true"),
      m8_benchmark_file_count: ($bfc | tonumber),
      static_failure_flag: $fs,
      notes: [
        "Catalog: virtual_systems + production_systems in fusion_virtual_systems_catalog_s4.json; M8 benchmarks under deploy/fusion_mesh/config/benchmarks/.",
        "Live production rows prove UI gates (moor/bridge/hardware); ENABLED means requirements met — not the same as physical plant operation.",
        "Virtual Metal batches remain S4 compute receipts (tokamak_mode virtual in ledger)."
      ]
    }
  }' >"$OUT"

echo "Wrote $OUT"
if [[ "$FAIL_STATIC" -ne 0 ]]; then
  echo "REFUSED: static forensic failures (closure.static_failure_flag=1)" >&2
  exit 1
fi
echo "CALORIE: fusion plant forensic complete; live_http=$live_http"
exit 0
