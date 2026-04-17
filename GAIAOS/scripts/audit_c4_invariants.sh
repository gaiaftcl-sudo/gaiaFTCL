#!/usr/bin/env bash
# C4 Chess Player auditor: mount → fusion visual (self-heal) → planetary gate (NATS poke loop) → sealed DOCX.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"
UI="$ROOT/services/gaiaos_ui_web"
EV="$ROOT/evidence/release"
mkdir -p "$EV"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_JSON="$EV/C4_INVARIANT_AUDIT_${TS}.json"

RETRIES="${C4_AUDIT_RETRIES:-$(python3 "$ROOT/scripts/get_self_heal_retries.py" --repo-root "$ROOT" --step-id B7-zero-ghost 2>/dev/null || echo 3)}"

die() {
  echo "REFUSED: $*" >&2
  python3 -c "import json; json.dump({'terminal':'REFUSED','reason':'''${1//\'/\\\'}''','ts':'$TS'}, open('$OUT_JSON','w'), indent=2)" 2>/dev/null || true
  exit 1
}

log() { printf '%s\n' "$*"; }

log "━━ ♟ Move 1: Mounting invariant (hdiutil + df /Volumes/GaiaFusion) ━━"
if [[ "$(uname -s)" != "Darwin" ]]; then
  die "Darwin required for hdiutil mount gate"
fi
if ! bash "$ROOT/scripts/mount_gaiafusion_dmg.sh"; then
  die "mount_gaiafusion_dmg.sh failed (hardware block after remediations)"
fi

log "━━ ♟ Move 2: Visual invariant (headed Fusion UI Dashboard PNG) ━━"
fusion_ok=0
for ((a = 1; a <= RETRIES; a++)); do
  if [[ "$a" -gt 1 ]] || [[ "${C4_FUSION_REMEDIATE_FIRST:-1}" == "1" ]]; then
    bash "$ROOT/scripts/remediate_fusion_visual_mac.sh" || true
  fi
  if (
    cd "$UI"
    FUSION_VISUAL_WITNESS=1 npx playwright test tests/fusion/fusion_dashboard_visual_witness.spec.ts \
      --config=playwright.fusion.config.ts --headed
  ); then
    fusion_ok=1
    break
  fi
  log "WARN: fusion visual attempt $a failed, remediating..."
  sleep 3
done
if [[ "$fusion_ok" -ne 1 ]]; then
  die "fusion_dashboard_visual_witness.spec.ts failed after $RETRIES remediated attempts"
fi

log "━━ ♟ Move 3: Planetary invariant (Discord /cell + optional NATS scout poke loop) ━━"
export DISCORD_PLAYWRIGHT_PROFILE="${DISCORD_PLAYWRIGHT_PROFILE:-gaiaftcl}"
if ! bash "$ROOT/scripts/chess_planetary_gate.sh"; then
  log "WARN: chess_planetary_gate returned non-zero (continuing with last witness JSON)"
fi

EARTH_AUDIT="$ROOT/evidence/discord/C4_CELL_EARTH_AUDIT.json"
if [[ ! -f "$EARTH_AUDIT" ]]; then
  die "missing $EARTH_AUDIT"
fi

log "━━ ♟ Move 4: Sealing invariant (DOCX + --c4-semantics + --require-c4-semantics) ━━"
RP="$(ls -t "$ROOT/evidence/discord"/RELEASE_REPORT_*.json 2>/dev/null | head -1 || true)"
if [[ -z "$RP" ]]; then
  die "no RELEASE_REPORT_*.json; run closure battery first"
fi
DOCX_OUT="$ROOT/evidence/discord/C4_SEALED_RELEASE_${TS}.docx"
python3 "$ROOT/scripts/generate_release_docx.py" \
  --repo-root "$ROOT" \
  --json "$RP" \
  --output "$DOCX_OUT" \
  --c4-semantics "$ROOT/evidence/discord/RELEASE_C4_SEMANTICS.md" \
  --require-c4-semantics

C4_TERM="$(python3 -c "import json;print(json.load(open('$EARTH_AUDIT')).get('terminal','PARTIAL'))")"
FINAL="CALORIE"
if [[ "$C4_TERM" != "CALORIE" ]]; then
  FINAL="PARTIAL"
fi

export ROOT TS FINAL DOCX_OUT OUT_JSON RP

python3 <<PY
import json, os
from pathlib import Path
root = Path(os.environ["ROOT"])
earth_path = root / "evidence" / "discord" / "C4_CELL_EARTH_AUDIT.json"
earth = json.loads(earth_path.read_text(encoding="utf-8"))
out = {
    "ts_utc": os.environ["TS"],
    "terminal": os.environ["FINAL"],
    "mount": "OK",
    "fusion_png": str(root / "evidence" / "fusion_control" / "fusion_dashboard_witness.png"),
    "earth_audit": earth,
    "docx": os.environ["DOCX_OUT"],
    "closure_report_used": os.environ["RP"],
}
Path(os.environ["OUT_JSON"]).write_text(json.dumps(out, indent=2), encoding="utf-8")
print(json.dumps(out, indent=2))
PY

log "STATE: $FINAL"
log "RECEIPT_DOCX: $DOCX_OUT"
log "AUDIT_JSON: $OUT_JSON"
