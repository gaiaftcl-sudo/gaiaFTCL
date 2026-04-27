#!/usr/bin/env zsh
# ══════════════════════════════════════════════════════════════════════════════
# sprout.zsh — Franklin avatar cell: tmp workspace + gates A→J (IQ → surface → OQ/PQ → close).
# Meaning (what a cell is, vQbit substrate, proof obligation): substrate/CELL_VQBIT_PARADIGM.yaml
#
# Gates A→J: push · clone · genesis · bundle · MacFusion+MacHealth IQ (gamp5_iq) ·
# avatar plan 0–2 · FranklinApp + visible.json · OQ/PQ envelopes · gamp5_full --close-only.
# Gate J is the klein close leg of that same envelope after the breath above.
#
# Visibility: FOT_QUAL_VISIBLE_TESTS_ONLY=1 (default) — Gate F refuses if /dev/tty is
# missing; gamp5_iq is fed from /dev/tty when present. Set FOT_QUAL_VISIBLE_TESTS_ONLY=0
# only if you accept non-interactive failure modes yourself.
#
# Required: FRANKLIN_KEY FRANKLIN_OPERATOR_KEY FOT_AVATAR_PQ_VISIBLE_OPERATOR_PRESENT=1
# Optional: FRANKLIN_SPROUT_TMP FRANKLIN_SPINE_TMP FRANKLIN_GATE_MAX_ATTEMPTS
#           FRANKLIN_OUTER_MAX_ITERATIONS FRANKLIN_HALT_FLAG FRANKLIN_SPROUT_STRICT_DIRTY
# Exit: 0 converged · 2 HALT · else gate exhaustion code.
# ══════════════════════════════════════════════════════════════════════════════

emulate -L zsh
set -o pipefail

SPROUT_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AVATAR_DIR="$(cd "${SPROUT_SCRIPT_DIR}/.." && pwd)"
GAIAFTCL_DIR="$(cd "${AVATAR_DIR}/../../.." && pwd)"
cd "${GAIAFTCL_DIR}"

REMOTE="${FRANKLIN_REMOTE:-origin}"
BRANCH="${FRANKLIN_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
TAU="$(date -u +%Y%m%dT%H%M%SZ)"

SPROUT_TMP="${FRANKLIN_SPROUT_TMP:-${FRANKLIN_SPINE_TMP:-${TMPDIR:-/tmp}/gaiaftcl_vqbit_sprout_${TAU}}}"
INSTALL_ROOT="${SPROUT_TMP}/workspace"
RUN_ROOT="${SPROUT_TMP}/run"
CLONE_DIR="${INSTALL_ROOT}/clone"

LOG_DIR="${RUN_ROOT}/logs"
TRANSCRIPT="${RUN_ROOT}/transcript.txt"
HEAL_LEDGER="${RUN_ROOT}/heal_ledger.jsonl"
HALT_FLAG="${FRANKLIN_HALT_FLAG:-${RUN_ROOT}/HALT}"

OQ_DEADLINE="${FRANKLIN_OQ_DEADLINE_SEC:-1200}"
PQ_DEADLINE="${FRANKLIN_PQ_DEADLINE_SEC:-1800}"
GATE_MAX_ATTEMPTS="${FRANKLIN_GATE_MAX_ATTEMPTS:-${FRANKLIN_PHASE_MAX_ATTEMPTS:-100}}"
OUTER_MAX_ITER="${FRANKLIN_OUTER_MAX_ITERATIONS:-128}"
BACKOFF_BASE="${FRANKLIN_BACKOFF_BASE_SEC:-2}"
BACKOFF_MAX="${FRANKLIN_BACKOFF_MAX_SEC:-60}"

mkdir -p "${RUN_ROOT}" "${LOG_DIR}"
: > "${HEAL_LEDGER}"

export FOT_VQBIT_SPROUT=1
export FOT_SPROUT_TAU="${TAU}"
export FOT_QUAL_VISIBLE_TESTS_ONLY="${FOT_QUAL_VISIBLE_TESTS_ONLY:-1}"

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YLW=$'\033[1;33m'; BLD=$'\033[1m'; CYN=$'\033[0;36m'; MAG=$'\033[0;35m'; NC=$'\033[0m'

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
say() { print "${CYN}[$(now)]${NC} $*" | tee -a "${TRANSCRIPT}"; }
ok()  { print "${GRN}[$(now)] PASS${NC} $*" | tee -a "${TRANSCRIPT}"; }
warn(){ print "${YLW}[$(now)] WARN${NC} $*" | tee -a "${TRANSCRIPT}"; }
hot() { print -u2 "${RED}[$(now)] FAIL${NC} $*"; print "[FAIL] $*" >> "${TRANSCRIPT}"; }
heal_say() { print "${MAG}[$(now)] HEAL${NC} $*" | tee -a "${TRANSCRIPT}"; }

# JSONL ledger — field name `gate` (rings + gates; not “phase”).
ledger() {
  local gate="$1" attempt="$2" event="$3" detail="$4"
  printf '{"ts":"%s","gate":"%s","attempt":%d,"event":"%s","detail":%s}\n' \
    "$(now)" "${gate}" "${attempt}" "${event}" "$(jq -Rsa . <<< "${detail}" 2>/dev/null || printf '"%s"' "${detail}")" \
    >> "${HEAL_LEDGER}"
}

backoff_for() {
  local attempt="$1"
  local base="${BACKOFF_BASE}"
  local secs=$(( base * (1 << (attempt < 6 ? attempt : 6)) ))
  (( secs > BACKOFF_MAX )) && secs="${BACKOFF_MAX}"
  local jitter=$(( RANDOM % (secs / 2 + 1) ))
  print $(( secs + jitter ))
}

gate_banner() {
  print "" | tee -a "${TRANSCRIPT}"
  print "${BLD}━━ Gate · $1 ━━${NC}" | tee -a "${TRANSCRIPT}"
}

halt_requested() { [[ -f "${HALT_FLAG}" ]] }

# Burn tmp install workspace (clone/build). Logs/transcript path unchanged for this tau.
recycle_install_workspace() {
  say "Recycle tmp install workspace (temporal reset) → rm -rf ${INSTALL_ROOT}"
  rm -rf "${INSTALL_ROOT}"
  mkdir -p "${INSTALL_ROOT}"
}

pass_gate_with_heal() {
  local gate="$1" exit_code="$2" label="$3"
  gate_banner "${label}"
  local attempt=0
  while (( attempt < GATE_MAX_ATTEMPTS )); do
    if halt_requested; then
      warn "HALT (${HALT_FLAG}) — stopping sprout"
      ledger "${gate}" "${attempt}" "halt" "operator HALT"
      exit 2
    fi
    attempt=$(( attempt + 1 ))
    ledger "${gate}" "${attempt}" "try" "begin"
    "try_${gate}" "${attempt}"
    local why=$?
    if (( why == 0 )); then
      ledger "${gate}" "${attempt}" "pass" "gate open"
      ok "Gate ${gate} open after ${attempt} attempt(s)"
      return 0
    fi
    hot "Gate ${gate} attempt ${attempt} failed (rc=${why})"
    ledger "${gate}" "${attempt}" "fail" "rc=${why}"
    if (( attempt >= GATE_MAX_ATTEMPTS )); then
      hot "Gate ${gate} exhausted — exit ${exit_code}"
      ledger "${gate}" "${attempt}" "exhausted" "exit ${exit_code}"
      return "${exit_code}"
    fi
    heal_say "Gate ${gate} → heal_${gate}"
    if ! "heal_${gate}" "${attempt}" "${why}"; then
      warn "heal_${gate} non-zero — retry"
      ledger "${gate}" "${attempt}" "heal_warn" "heal returned non-zero"
    else
      ledger "${gate}" "${attempt}" "heal_ok" "heal completed"
    fi
    local nap; nap="$(backoff_for "${attempt}")"
    say "backoff ${nap}s"
    sleep "${nap}"
  done
  return "${exit_code}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Gates A–J  (try_* / heal_* — D genesis → E bundle → F IQ … → J close)
# ═══════════════════════════════════════════════════════════════════════════════

try_A() {
  local attempt="$1"
  say "tau=${TAU} branch=${BRANCH} remote=${REMOTE} ring_workspace=${INSTALL_ROOT}"
  local missing=()
  for tool in zsh git cargo curl jq xxd nc swift xcrun; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  (( ${#missing[@]} > 0 )) && { hot "missing tools: ${missing[*]}"; return 1; }
  [[ -z "${FRANKLIN_KEY:-}" || ! -f "${FRANKLIN_KEY:-}" ]] && { hot "FRANKLIN_KEY missing"; return 2; }
  [[ -z "${FRANKLIN_OPERATOR_KEY:-}" || ! -f "${FRANKLIN_OPERATOR_KEY:-}" ]] && { hot "FRANKLIN_OPERATOR_KEY missing"; return 3; }
  [[ "${FOT_AVATAR_PQ_VISIBLE_OPERATOR_PRESENT:-0}" != "1" ]] && { hot "operator presence flag must be 1"; return 4; }
  # Tracked/index only — local vendor/ .worktrees/ etc. must not block qualification.
  if [[ "${FRANKLIN_SPROUT_STRICT_DIRTY:-0}" == "1" ]]; then
    [[ -n "$(git status --porcelain)" ]] && { hot "working tree dirty"; return 5; }
  else
    [[ -n "$(git status --porcelain --untracked-files=no)" ]] && { hot "working tree dirty (tracked/index)"; return 5; }
  fi
  git ls-files | grep -qE '\.(key|pem)$' && { hot "secret-shaped paths tracked"; return 6; }
  ok "preflight — tools, keys, operator witness"
}

heal_A() {
  local attempt="$1" rc="$2"
  case "${rc}" in
    1) warn "install missing tools (brew, Xcode)" ;;
    2|3)
      mkdir -p "${HOME}/.gaiaftcl/keys"
      [[ -z "${FRANKLIN_KEY:-}" ]] && export FRANKLIN_KEY="${HOME}/.gaiaftcl/keys/franklin_bundle.key"
      [[ -z "${FRANKLIN_OPERATOR_KEY:-}" ]] && export FRANKLIN_OPERATOR_KEY="${HOME}/.gaiaftcl/keys/franklin_operator.key"
      [[ -f "${FRANKLIN_KEY}" ]] || dd if=/dev/urandom of="${FRANKLIN_KEY}" bs=32 count=1 2>/dev/null
      [[ -f "${FRANKLIN_OPERATOR_KEY}" ]] || dd if=/dev/urandom of="${FRANKLIN_OPERATOR_KEY}" bs=32 count=1 2>/dev/null
      chmod 0600 "${FRANKLIN_KEY}" "${FRANKLIN_OPERATOR_KEY}" 2>/dev/null || true
      ;;
    4) export FOT_AVATAR_PQ_VISIBLE_OPERATOR_PRESENT=1 ;;
    5)
      if [[ "$(uname -s)" == Darwin ]]; then
        for _d in evidence/_closure evidence/_acceptance; do
          [[ -d "${GAIAFTCL_DIR}/${_d}" ]] && chflags -R nouchg "${GAIAFTCL_DIR}/${_d}" 2>/dev/null
          [[ -d "${GAIAFTCL_DIR}/${_d}" ]] && chmod -R u+w "${GAIAFTCL_DIR}/${_d}" 2>/dev/null
        done
      fi
      git stash push -u -m "sprout_${TAU}_gA_${attempt}" 2>&1 | tee -a "${LOG_DIR}/heal_A.log"
      ;;
    6) warn "remove tracked *.key/*.pem manually" ;;
  esac
}

try_B() {
  local attempt="$1"
  git push "${REMOTE}" "${BRANCH}" 2>&1 | tee "${LOG_DIR}/B_push.log" >&2
  return "${pipestatus[1]}"
}

heal_B() {
  git fetch "${REMOTE}" "${BRANCH}" 2>&1 | tee -a "${LOG_DIR}/B_heal.log" || true
  git rev-parse "${REMOTE}/${BRANCH}" >/dev/null 2>&1 && git pull --rebase "${REMOTE}" "${BRANCH}" 2>&1 | tee -a "${LOG_DIR}/B_heal.log" || git rebase --abort 2>/dev/null || true
  git gc --prune=now --quiet 2>/dev/null || true
}

try_C() {
  local attempt="$1"
  rm -rf "${CLONE_DIR}"
  mkdir -p "${INSTALL_ROOT}"
  git clone --branch "${BRANCH}" --single-branch "$(git remote get-url "${REMOTE}")" "${CLONE_DIR}" 2>&1 \
    | tee "${LOG_DIR}/C_clone.log" >&2
  (( pipestatus[1] != 0 )) && return "${pipestatus[1]}"
  CLONE_AVATAR="${CLONE_DIR}/cells/franklin/avatar"
  CLONE_EVIDENCE="${CLONE_AVATAR}/evidence"
  [[ ! -d "${CLONE_AVATAR}" ]] && { hot "clone missing avatar cell"; return 7; }
  mkdir -p "${CLONE_EVIDENCE}/iq" "${CLONE_EVIDENCE}/oq" "${CLONE_EVIDENCE}/pq"
  () {
    setopt local_options nullglob
    local f
    for f in "${CLONE_AVATAR}/scripts/"*.sh "${CLONE_AVATAR}/scripts/"*.zsh; do [[ -f "$f" ]] && chmod +x "$f"; done
    for f in "${CLONE_DIR}/scripts/"gamp5_*.sh "${CLONE_DIR}/scripts/"*.zsh; do [[ -f "$f" ]] && chmod +x "$f"; done
  }
  ok "clone workspace for this run: ${CLONE_DIR}"
}

heal_C() {
  rm -rf "${CLONE_DIR}"
  local url; url="$(git remote get-url "${REMOTE}" 2>/dev/null || true)"
  [[ -n "${url}" ]] && git ls-remote "${url}" "${BRANCH}" 2>&1 | tee -a "${LOG_DIR}/C_heal.log" || true
}

# Gate D — genesis inception (IQ axis opens here; vQbit-marked record on disk).
try_D() {
  local attempt="$1"
  local locks="${CLONE_DIR}/substrate/HASH_LOCKS.yaml"
  [[ -f "${locks}" ]] || { hot "substrate/HASH_LOCKS.yaml missing in clone"; return 31; }
  mkdir -p "${CLONE_EVIDENCE}/iq"
  local gr="${CLONE_EVIDENCE}/iq/genesis_record.json"
  local hlocks sha_head
  hlocks="$(shasum -a 256 "${locks}" | awk '{print $1}')"
  sha_head="$(git -C "${CLONE_DIR}" rev-parse HEAD 2>/dev/null || print unknown)"
  jq -n \
    --arg tau "${TAU}" \
    --arg git_head "${sha_head}" \
    --arg hash_locks_sha256 "${hlocks}" \
    '{axis:"vqbit",sprout_tau:$tau,clone_git_head:$git_head,hash_locks_sha256:$hash_locks_sha256,inception:"genesis_record",iq_first:true}' > "${gr}"
  export FOT_GENESIS_RECORD_PATH="${gr}"
  export FOT_VQBIT_INCEPTION=1
  ok "genesis record sealed — inception"
}

heal_D() {
  rm -f "${CLONE_EVIDENCE}/iq/genesis_record.json" 2>/dev/null || true
  git -C "${CLONE_DIR}" fetch origin "${BRANCH}" 2>/dev/null || true
  git -C "${CLONE_DIR}" reset --hard "origin/${BRANCH}" 2>/dev/null || true
}

try_E() {
  local attempt="$1"
  [[ -f "${CLONE_AVATAR}/scripts/build_bundle.sh" ]] || return 126
  ( cd "${CLONE_AVATAR}" && FRANKLIN_KEY="${FRANKLIN_KEY}" ./scripts/build_bundle.sh ) \
    2>&1 | tee "${LOG_DIR}/E_bundle.log" >&2
  (( pipestatus[1] != 0 )) && return "${pipestatus[1]}"
  [[ -d "${CLONE_AVATAR}/build/avatar_bundle" && -f "${CLONE_AVATAR}/build/bundle_pubkey.bin" ]] || return 8
  ok "bundle signed in tmp clone"
}

heal_E() {
  case "$2" in
    126)
      git -C "${CLONE_DIR}" fetch origin "${BRANCH}" 2>&1 | tee -a "${LOG_DIR}/E_heal.log" || true
      git -C "${CLONE_DIR}" merge --ff-only "origin/${BRANCH}" 2>&1 | tee -a "${LOG_DIR}/E_heal.log" || true
      ;;
  esac
  rm -rf "${CLONE_AVATAR}/build" 2>/dev/null || true
  ( cd "${CLONE_AVATAR}" && cargo clean ) 2>&1 | tee -a "${LOG_DIR}/E_heal.log" || true
  (( $1 % 3 == 0 )) && rm -rf "${CLONE_DIR}/target" 2>/dev/null || true
}

try_F() {
  local attempt="$1"
  [[ -n "${FOT_GENESIS_RECORD_PATH:-}" ]] || export FOT_GENESIS_RECORD_PATH="${CLONE_EVIDENCE}/iq/genesis_record.json"
  if [[ "${FOT_QUAL_VISIBLE_TESTS_ONLY:-1}" == "1" ]] && [[ ! -r /dev/tty ]]; then
    hot "Gate F: no /dev/tty — IQ must be operator-visible (Terminal or ssh -t)"
    return 41
  fi
  if [[ -r /dev/tty ]]; then
    ( cd "${CLONE_DIR}" && \
      FOT_VQBIT_SPROUT=1 FOT_QUAL_VISIBLE_TESTS_ONLY="${FOT_QUAL_VISIBLE_TESTS_ONLY:-1}" \
      FOT_GENESIS_RECORD_PATH="${FOT_GENESIS_RECORD_PATH}" FOT_SPROUT_TAU="${TAU}" \
      zsh scripts/gamp5_iq.sh --cell both ) </dev/tty 2>&1 | tee "${LOG_DIR}/F_iq.log" >&2
  else
    ( cd "${CLONE_DIR}" && \
      FOT_VQBIT_SPROUT=1 FOT_QUAL_VISIBLE_TESTS_ONLY="${FOT_QUAL_VISIBLE_TESTS_ONLY:-1}" \
      FOT_GENESIS_RECORD_PATH="${FOT_GENESIS_RECORD_PATH}" FOT_SPROUT_TAU="${TAU}" \
      zsh scripts/gamp5_iq.sh --cell both ) 2>&1 | tee "${LOG_DIR}/F_iq.log" >&2
  fi
  (( pipestatus[1] != 0 )) && return "${pipestatus[1]}"
  local p rc
  for p in 0 1 2; do
    ( cd "${CLONE_AVATAR}" && FOT_GENESIS_RECORD_PATH="${FOT_GENESIS_RECORD_PATH}" \
      zsh scripts/run_franklin_avatar_oq_pq_plan_phases.zsh --phase "${p}" ) 2>&1 | tee "${LOG_DIR}/F_plan_${p}.log" >&2
    rc="${pipestatus[1]}"
    (( rc != 0 )) && return $(( 100 + p ))
  done
  ok "IQ + plan phases 0–2 completed in order"
}

heal_F() {
  case "$2" in
    100|101|102) rm -rf "${CLONE_AVATAR}/build/iq_phase_$(( $2 - 100 ))" 2>/dev/null || true ;;
    *) ( cd "${CLONE_DIR}" && cargo clean ) 2>&1 | tee -a "${LOG_DIR}/F_heal.log" || true ;;
  esac
  mkdir -p "${CLONE_EVIDENCE}/iq"
}

APP_PID=""
APP_LAUNCH_LOG="${LOG_DIR}/G_launch.log"

cleanup_app() {
  [[ -n "${APP_PID}" ]] && kill -0 "${APP_PID}" 2>/dev/null && kill "${APP_PID}" 2>/dev/null; sleep 1
  [[ -n "${APP_PID}" ]] && kill -9 "${APP_PID}" 2>/dev/null || true
  APP_PID=""
}

try_G() {
  local attempt="$1"
  rm -f "${CLONE_EVIDENCE}/iq/visible.json"
  ( cd "${CLONE_DIR}/GAIAOS/macos/Franklin" && swift build -c release ) 2>&1 | tee -a "${APP_LAUNCH_LOG}" >&2
  (( pipestatus[1] != 0 )) && return "${pipestatus[1]}"
  local bin="${CLONE_DIR}/GAIAOS/macos/Franklin/.build/release/FranklinApp"
  [[ -x "${bin}" ]] || return 9
  export FRANKLIN_AVATAR_BUNDLE="${CLONE_AVATAR}/build/avatar_bundle"
  export FRANKLIN_BUNDLE_PUBKEY="${CLONE_AVATAR}/build/bundle_pubkey.bin"
  export FRANKLIN_AVATAR_EVIDENCE="${CLONE_EVIDENCE}"
  cleanup_app
  "${bin}" >> "${APP_LAUNCH_LOG}" 2>&1 &
  APP_PID=$!
  local vis="${CLONE_EVIDENCE}/iq/visible.json" dl=$(( $(date +%s) + 90 ))
  until [[ -f "${vis}" ]]; do
    (( $(date +%s) > dl )) && return 11
    kill -0 "${APP_PID}" 2>/dev/null || return 12
    sleep 1
  done
  ok "Franklin visible — living surface (visible.json)"
}

heal_G() {
  cleanup_app
  case "$2" in 11|12) tail -80 "${APP_LAUNCH_LOG}" >> "${LOG_DIR}/G_heal.log" 2>/dev/null || true ;; esac
  rm -rf "${CLONE_DIR}/GAIAOS/macos/Franklin/.build" 2>/dev/null || true
}

write_oq_env() {
  cat > "${CLONE_EVIDENCE}/oq/.start" <<EOF
{"tau":"${TAU}","bundle_pubkey_hex":"$(xxd -p -c 64 "${FRANKLIN_BUNDLE_PUBKEY:-${CLONE_AVATAR}/build/bundle_pubkey.bin}" | tr -d '\n')","catalog":["LG-FRANKLIN-OQ-AVATAR-TESTS-001"]}
EOF
}

try_H() {
  local attempt="$1"
  local done="${CLONE_EVIDENCE}/oq/oq_complete.json"
  rm -f "${done}"
  write_oq_env
  local dl=$(( $(date +%s) + OQ_DEADLINE ))
  until [[ -f "${done}" ]]; do
    (( $(date +%s) > dl )) && return 13
    kill -0 "${APP_PID}" 2>/dev/null || return 14
    halt_requested && return 99
    sleep 5
  done
  ok "OQ envelope consumed — oq_complete.json present"
}

heal_H() {
  case "$2" in
    13|14|15|16) mkdir -p "${CLONE_EVIDENCE}/oq/.heal/$1"; mv "${CLONE_EVIDENCE}/oq/"*.receipt.json "${CLONE_EVIDENCE}/oq/.heal/$1/" 2>/dev/null || true ;;
  esac
  cleanup_app
}

write_pq_env() {
  cat > "${CLONE_EVIDENCE}/pq/.start" <<EOF
{"tau":"${TAU}","lg_id":"LG-FRANKLIN-PQ-AVATAR-LIFELIKE-001"}
EOF
}

try_I() {
  local attempt="$1"
  local pq="${CLONE_EVIDENCE}/pq/pq_receipt.json"
  rm -f "${pq}"
  write_pq_env
  local dl=$(( $(date +%s) + PQ_DEADLINE ))
  until [[ -f "${pq}" ]]; do
    (( $(date +%s) > dl )) && return 17
    kill -0 "${APP_PID}" 2>/dev/null || return 18
    halt_requested && return 99
    sleep 5
  done
  [[ "$(jq -r '.result // empty' "${pq}" 2>/dev/null)" == "PASS" ]] || return 19
  ok "PQ receipt PASS — IQ→OQ→PQ sequence closed for this wait"
}

heal_I() {
  mkdir -p "${CLONE_EVIDENCE}/pq/.heal/$1"
  mv "${CLONE_EVIDENCE}/pq/pq_receipt.json" "${CLONE_EVIDENCE}/pq/.heal/$1/" 2>/dev/null || true
  cleanup_app
}

EVIDENCE_RUN=""
try_J() {
  local attempt="$1"
  ( cd "${CLONE_DIR}" && \
    FOT_QUAL_VISIBLE_TESTS_ONLY="${FOT_QUAL_VISIBLE_TESTS_ONLY:-1}" \
    zsh scripts/gamp5_full.zsh --tau "${TAU}" --close-only ) 2>&1 | tee "${LOG_DIR}/J_close.log" >&2
  (( pipestatus[1] != 0 )) && return "${pipestatus[1]}"
  EVIDENCE_RUN="${CLONE_DIR}/evidence/runs/${TAU}"
  [[ -f "${EVIDENCE_RUN}/epilogue.json" ]] || return 23
  cp -R "${LOG_DIR}" "${EVIDENCE_RUN}/sprout_logs" 2>/dev/null || true
  cp "${TRANSCRIPT}" "${EVIDENCE_RUN}/sprout_transcript.txt" 2>/dev/null || true
  cp "${HEAL_LEDGER}" "${EVIDENCE_RUN}/sprout_heal_ledger.jsonl" 2>/dev/null || true
  ok "CLOSE — epilogue sealed"
}

heal_J() {
  local attempt="$1" _rc="$2"
  local inv
  inv="$( ( cd "${CLONE_DIR}" 2>/dev/null && find evidence -maxdepth 8 \( -name '*.receipt.json' -o -name 'epilogue.json' \) ) 2>/dev/null | sort | head -400 )"
  ledger "J" "${attempt}" "receipt_inventory" "${inv:-empty}"
}

sprout_snapshot_evidence() {
  local dest="${GAIAFTCL_DIR}/evidence/runs/${TAU}"
  mkdir -p "${dest}"
  cp -f "${TRANSCRIPT}" "${dest}/sprout_transcript.txt" 2>/dev/null || true
  cp -f "${HEAL_LEDGER}" "${dest}/sprout_heal_ledger.jsonl" 2>/dev/null || true
  cp -R "${LOG_DIR}" "${dest}/sprout_logs" 2>/dev/null || true
}

trap 'cleanup_app; sprout_snapshot_evidence' EXIT

# ═══════════════════════════════════════════════════════════════════════════════
# Outer ring · inner breath — genesis (D) then bundle · IQ · surface · OQ · PQ · close
# ═══════════════════════════════════════════════════════════════════════════════

print "${BLD}Baby cell (sprout) — temporal run · gates A→J${NC}" | tee -a "${TRANSCRIPT}"
print "  tau=${TAU}  tmp=${SPROUT_TMP}  workspace=${INSTALL_ROOT}  FOT_VQBIT_SPROUT=1" | tee -a "${TRANSCRIPT}"

OUTER_ITER=0
SPROUT_RC=0

while (( OUTER_ITER < OUTER_MAX_ITER )); do
  OUTER_ITER=$(( OUTER_ITER + 1 ))
  print "" | tee -a "${TRANSCRIPT}"
  print "${BLD}═══ Outer ring ${OUTER_ITER}/${OUTER_MAX_ITER} — new skin on tmp ═══${NC}" | tee -a "${TRANSCRIPT}"
  ledger "OUTER" "${OUTER_ITER}" "begin" "open ring"

  recycle_install_workspace

  halt_requested && exit 2

  pass_gate_with_heal A 10 "preflight · tools · keys · operator witness" || { SPROUT_RC=$?; continue; }
  pass_gate_with_heal B 20 "remote · push branch" || { SPROUT_RC=$?; continue; }
  pass_gate_with_heal C 30 "clone into tmp workspace" || { SPROUT_RC=$?; continue; }
  pass_gate_with_heal D 40 "genesis · HASH_LOCKS inception (IQ axis)" || { SPROUT_RC=$?; continue; }
  pass_gate_with_heal E 45 "sign_bundle · avatar substrate in tmp" || { SPROUT_RC=$?; continue; }

  say "${BLD}Inner breath · IQ after genesis — Franklin surface → OQ → PQ → close (ordered in time)${NC}"
  pass_gate_with_heal F 50 "IQ · gamp5_iq + plan 0–2" || { SPROUT_RC=$?; continue; }
  pass_gate_with_heal G 60 "FranklinApp · visible.json" || { SPROUT_RC=$?; continue; }
  pass_gate_with_heal H 70 "OQ · Franklin-driven catalog" || { SPROUT_RC=$?; continue; }
  pass_gate_with_heal I 80 "PQ · lifelike co-sign" || { SPROUT_RC=$?; continue; }

  pass_gate_with_heal J 90 "CLOSE · klein aggregate" || { SPROUT_RC=$?; continue; }

  SPROUT_RC=0
  ledger "OUTER" "${OUTER_ITER}" "converged" "PASS"
  say "This outer ring finished in order (IQ→OQ→PQ + close) — shedding tmp install workspace"
  recycle_install_workspace
  break
done

gate_banner "K · ledger"
{
  print "tau=${TAU} sprout_rc=${SPROUT_RC} clone=${CLONE_DIR}"
  print "heal ledger: ${HEAL_LEDGER}"
  (( SPROUT_RC == 0 )) && print "${GRN}CONVERGED — receipts written this run${NC}" || print "${RED}EXHAUSTED rc=${SPROUT_RC}${NC}"
  [[ -s "${HEAL_LEDGER}" ]] && command -v jq >/dev/null && jq -s '
    group_by(.gate) |
    map({
      gate: .[0].gate,
      tries: (map(select(.event=="try")) | length),
      fails: (map(select(.event=="fail")) | length),
      heals: (map(select(.event=="heal_ok")) | length),
      passes: (map(select(.event=="pass")) | length)
    })
  ' "${HEAL_LEDGER}" 2>/dev/null || cat "${HEAL_LEDGER}"
} | tee -a "${TRANSCRIPT}"

exit "${SPROUT_RC}"
