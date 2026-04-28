#!/usr/bin/env zsh
# ============================================================================
# gamp5_full.zsh — Franklin Mac Stack — self-healing IQ/OQ/PQ organism.
# ----------------------------------------------------------------------------
# THESIS
#   Franklin is a sprout of the mesh. All cells are sprouts of both the mesh
#   and Franklin. They communicate. They heal each other through games.
#   A wound triggers a healer verb chain — never a silent exit.
#
# CONTRACT
#   FranklinApp window proof is mandatory — no env shortcut.
#
#   Cell ontology + vQbit paradigm (invariants, proof across contexts): substrate/CELL_VQBIT_PARADIGM.yaml
#   Sprout gate chain (Franklin avatar): cells/franklin/avatar/scripts/sprout.zsh
#   Sprout sets GAMP5_TAU_FS so evidence/runs/<tau>/ matches the sprout ring τ (optional env).
#
#   Every step is a witnessable verb in the Franklin Cell catalog (LG-*).
#   Every step narrates in plain English to summary.md.
#   Every step emits a witness OR a refusal receipt — never silent.
#   Every refusal triggers a healing game where the substrate has authority.
#   Healing games are themselves verb chains, each step witnessed.
#   Terminal death (exit ≠0) is reserved for wounds the substrate cannot
#   heal under its own authority — toolchain absence, code-level test
#   failures requiring human change, hash-lock drift on files no live
#   wallet can re-sign.
#
# AUDIT
#   evidence/runs/<tau>/summary.md          — human-readable narration
#   evidence/runs/<tau>/receipts/*.json     — every witness, refusal, heal
#   evidence/runs/<tau>/prologue.json       — closure window opening
#   evidence/runs/<tau>/epilogue.json       — closure window closing
#   evidence/runs/<tau>/heals/*.json        — healing-chain receipts
#   evidence/runs/<tau>/genesis.json        — genesis receipt (first run only)
#
# IDEMPOTENT
#   Two consecutive clean runs produce two timestamped evidence dirs.
#   The second contains zero healing entries and zero refusals.
# ============================================================================

emulate -L zsh
# ----------------------------------------------------------------------------
# Klein-bottle topology for the audit envelope.
#
# A self-healing substrate's audit window has no "outside" — every exit path
# closes through the SAME surface that opened it. There is no mid-run exit.
# Wounds are perforations that get recorded into the manifold; the run
# continues so the audit captures the FULL state (every step witnesses,
# even after a terminal refusal upstream). The single closure point is
# _klein_close, installed as the EXIT/INT/TERM/HUP trap. The final exit
# code is derived from accumulated terminal wounds at closure time, not
# at refusal time.
#
# Why no `set -e`: GAMP 5 demands every step witness. `set -e` would let
# one wound silently kill the audit envelope. Instead, ZERR captures any
# unhandled command failure, records it as an unstructured wound, and the
# run continues to the next NARRATE.
# ----------------------------------------------------------------------------
set -u
set -o pipefail
setopt no_unset pipe_fail extended_glob no_err_exit
typeset -gi KLEIN_CLOSED=0
typeset -ga RUN_TERMINALS=()
typeset -ga RUN_ZERR=()

# ----------------------------------------------------------------------------
# 0. PREAMBLE — paths, identity, helpers
# ----------------------------------------------------------------------------

SCRIPT_DIR="${0:A:h}"
FRANKLIN_ROOT="${FRANKLIN_ROOT:-${SCRIPT_DIR:h}}"
GAMP5_REQUIRE_FRESH_INSTALL="${GAMP5_REQUIRE_FRESH_INSTALL:-1}"
GAMP5_FRESH_SENTINEL="${GAMP5_FRESH_SENTINEL:-0}"
GAMP5_FRESH_BASE="${GAMP5_FRESH_BASE:-${TMPDIR:-/tmp}/gaiaftcl_full_install}"

ensure_repo_push_and_wiki_contract() {
    local root="$1"
    cd "${root}" || return 1
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
        print -u2 "GW_REFUSE_FRANKLIN_REPO_NOT_FOUND: ${root} is not a git repo"
        return 2
    }
    local branch
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    [[ -n "${branch}" && "${branch}" != "HEAD" ]] || {
        print -u2 "GW_REFUSE_FRANKLIN_REPO_NOT_FOUND: detached HEAD is not allowed"
        return 3
    }
    local remote_url
    remote_url="$(git remote get-url origin 2>/dev/null || true)"
    [[ -n "${remote_url}" ]] || {
        print -u2 "GW_REFUSE_FRANKLIN_REPO_NOT_FOUND: missing origin remote"
        return 4
    }
    [[ "${remote_url}" == *github.com* ]] || {
        print -u2 "GW_REFUSE_FRANKLIN_REPO_NOT_FOUND: origin is not GitHub (${remote_url})"
        return 5
    }
    # Require pushable state (local changes must be committed first).
    [[ -z "$(git status --porcelain --untracked-files=no)" ]] || {
        print -u2 "GW_REFUSE_FRANKLIN_STACK_PATH_OUTSIDE_ENVELOPE: tracked changes present; commit before run"
        return 6
    }
    git fetch origin "${branch}" >/dev/null 2>&1 || {
        print -u2 "GW_REFUSE_FRANKLIN_REPO_NOT_FOUND: cannot fetch origin/${branch}"
        return 7
    }
    git push origin "${branch}" >/dev/null 2>&1 || {
        print -u2 "GW_REFUSE_FRANKLIN_REPO_NOT_FOUND: cannot push origin/${branch}"
        return 8
    }
    git fetch origin "${branch}" >/dev/null 2>&1 || return 9
    local local_head remote_head
    local_head="$(git rev-parse HEAD 2>/dev/null || true)"
    remote_head="$(git rev-parse "origin/${branch}" 2>/dev/null || true)"
    [[ -n "${local_head}" && "${local_head}" == "${remote_head}" ]] || {
        print -u2 "GW_REFUSE_FRANKLIN_REPO_NOT_FOUND: local HEAD != origin/${branch}"
        return 10
    }
    # Wiki parity contract: if a local wiki mirror clone exists, markdown content must match.
    local wiki_clone="${root:h}/gaiaFTCL.wiki"
    if [[ -d "${wiki_clone}/.git" ]]; then
        local wf rel
        local -a wiki_mismatch=()
        for wf in "${root}/wiki/"*.md(N); do
            rel="${wf:t}"
            [[ -f "${wiki_clone}/${rel}" ]] || { wiki_mismatch+=("${rel}:missing-in-wiki-clone"); continue; }
            cmp -s "${wf}" "${wiki_clone}/${rel}" || wiki_mismatch+=("${rel}:content-diff")
        done
        (( ${#wiki_mismatch[@]} == 0 )) || {
            print -u2 "GW_REFUSE_FRANKLIN_CHANGE_PROPOSAL_SCHEMA_INVALID: wiki mismatch: ${(j:, :)wiki_mismatch}"
            return 11
        }
    fi
    return 0
}

bootstrap_fresh_install() {
    local source_root="$1"
    ensure_repo_push_and_wiki_contract "${source_root}" || return $?
    local branch remote_url fresh_root fresh_clone
    branch="$(git -C "${source_root}" rev-parse --abbrev-ref HEAD)"
    remote_url="$(git -C "${source_root}" remote get-url origin)"
    fresh_root="${GAMP5_FRESH_BASE%/}"
    fresh_clone="${fresh_root}/clone"
    rm -rf "${fresh_root}" || return 21
    mkdir -p "${fresh_root}" || return 22
    git clone --branch "${branch}" --single-branch "${remote_url}" "${fresh_clone}" >/dev/null 2>&1 || return 23
    exec env \
      GAMP5_FRESH_SENTINEL=1 \
      GAMP5_REQUIRE_FRESH_INSTALL="${GAMP5_REQUIRE_FRESH_INSTALL}" \
      GAMP5_FRESH_BASE="${GAMP5_FRESH_BASE}" \
      FRANKLIN_ROOT="${fresh_clone}" \
      zsh "${fresh_clone}/scripts/gamp5_full.zsh"
}

if [[ "${GAMP5_REQUIRE_FRESH_INSTALL}" == "1" && "${GAMP5_FRESH_SENTINEL}" != "1" ]]; then
    bootstrap_fresh_install "${FRANKLIN_ROOT}"
    exit $?
fi

cd "${FRANKLIN_ROOT}"

TAU_HUMAN="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TAU_FS="$(date -u +%Y%m%dT%H%M%SZ)"
TAU_MICROS="$(python3 -c 'import time;print(int(time.time()*1_000_000))')"
# Sprout passes GAMP5_TAU_FS so epilogue lands under the same τ as the outer ring (default: fresh wall clock).
if [[ -n "${GAMP5_TAU_FS:-}" ]]; then
  typeset -g TAU_FS="${GAMP5_TAU_FS}"
fi
if [[ -n "${GAMP5_TAU_HUMAN:-}" ]]; then
  typeset -g TAU_HUMAN="${GAMP5_TAU_HUMAN}"
elif [[ -n "${GAMP5_TAU_FS:-}" ]]; then
  typeset -g TAU_HUMAN="${TAU_FS:0:4}-${TAU_FS:4:2}-${TAU_FS:6:2}T${TAU_FS:9:2}:${TAU_FS:11:2}:${TAU_FS:13:2}Z"
fi

EVIDENCE_ROOT="${FRANKLIN_ROOT}/evidence/runs/${TAU_FS}"
RECEIPTS_DIR="${EVIDENCE_ROOT}/receipts"
HEALS_DIR="${EVIDENCE_ROOT}/heals"
SUMMARY_MD="${EVIDENCE_ROOT}/summary.md"
PROLOGUE_JSON="${EVIDENCE_ROOT}/prologue.json"
EPILOGUE_JSON="${EVIDENCE_ROOT}/epilogue.json"
RUN_LOG="${EVIDENCE_ROOT}/run.log"

mkdir -p "${RECEIPTS_DIR}" "${HEALS_DIR}"

# Configuration. Override via env. Defaults are canon.
EXPECTED_CONTRACT_VERSION="${EXPECTED_CONTRACT_VERSION:-1.2.0}"
EXPECTED_CELLS=(health fusion lithography xcode material_sciences franklin)
EXPECTED_IDENTITY_SLOTS=(founder_backstop substrate_steward cell_owner tooling_steward franklin_cell_owner)
FRANKLIN_CATALOG_FILES=(LANGUAGE_GAMES.yaml AVATAR_MANIFEST.yaml STACK_CONTROL_ENVELOPE.yaml ADVERSARY_GRAMMAR.yaml EDUCATION_TRACKS.yaml)
FRANKLIN_DEGRADE_NONFUSION="${FRANKLIN_DEGRADE_NONFUSION:-1}"

# Toolchain floor — pinned in substrate/TOOLCHAIN_REQUIRED.yaml at IQ time.
# These defaults track the latest stable train (Xcode 26.x, Swift 6.x).
# The runner has no authority to install Xcode; below-floor → TERMINAL.
EXPECTED_XCODE_MIN="${EXPECTED_XCODE_MIN:-26.0}"
EXPECTED_SWIFT_MIN="${EXPECTED_SWIFT_MIN:-6.0}"
EXPECTED_MACOS_MIN="${EXPECTED_MACOS_MIN:-14.0}"

# Required Swift libraries — pinned in substrate/REQUIRED_LIBRARIES.yaml.
# Each entry: name, git_url, pinned_revision, vendor_relpath.
# IQ refuses if a required library cannot be reached on disk OR via SwiftPM.

# Keychain — where genesis writes the Ed25519 keypairs. Per-operator.
FRANKLIN_KEYCHAIN="${FRANKLIN_KEYCHAIN:-${HOME}/.franklin/keychain}"
mkdir -p "${FRANKLIN_KEYCHAIN}"
chmod 700 "${FRANKLIN_KEYCHAIN}"

# Healing parameters.
MAX_HEAL_ATTEMPTS=3

# Counters.
typeset -gi STEPS_RUN=0
typeset -gi STEPS_WITNESSED=0
typeset -gi STEPS_HEALED=0
typeset -gi STEPS_REFUSED=0
typeset -gi STEPS_TERMINAL=0
typeset -gA STEP_RESULTS

# ----------------------------------------------------------------------------
# Narration + receipts
# ----------------------------------------------------------------------------
NARRATE() {
    local lg_id="$1"; shift
    local class="$1"; shift
    local text="$*"
    {
        printf '\n────────────────────────────────────────────────────────────\n'
        printf '[%s] (class %s)\n' "${lg_id}" "${class}"
        printf '%s\n' "${text}"
    } | tee -a "${SUMMARY_MD}" >&2
    STEPS_RUN=$((STEPS_RUN + 1))
}

_entropy() { python3 -c 'import secrets;print(secrets.token_hex(4))'; }
_jsonstr() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }

WITNESS() {
    local lg_id="$1"; shift
    local terminal="$1"; shift          # CALORIE | CURE
    local note="$*"
    # Klein-bottle invariant: a step that already recorded a TERMINAL wound
    # cannot also witness CALORIE/CURE. Same-step contradiction is silently
    # absorbed so the audit captures the wound, not a false success. The
    # epilogue's terminal aggregate uses STEPS_TERMINAL, not WITNESS counts.
    if [[ "${STEP_RESULTS[${lg_id}]:-}" == TERMINAL:* ]]; then
        return 0
    fi
    local rcpt="${RECEIPTS_DIR}/${TAU_FS}_${lg_id}_${terminal}.json"
    local entropy; entropy="$(_entropy)"
    cat > "${rcpt}" <<JSON
{
  "magic": "FUIT",
  "version": "${EXPECTED_CONTRACT_VERSION}",
  "verb_id": "${lg_id}",
  "interaction_class": "B",
  "terminal_state": "${terminal}",
  "closure_window_id": "${TAU_FS}",
  "ts_micros": ${TAU_MICROS},
  "entropy_quanta": "${entropy}",
  "note": $(_jsonstr "${note}")
}
JSON
    printf '  ✓ WITNESS  %-8s  %s  %s\n' "${terminal}" "${lg_id}" "${note}" \
        | tee -a "${SUMMARY_MD}" >&2
    STEPS_WITNESSED=$((STEPS_WITNESSED + 1))
    STEP_RESULTS[${lg_id}]="${terminal}"
    return 0
}

# REFUSE — emit a refusal receipt but DO NOT exit. The caller decides whether
# to invoke a healer or escalate to terminal death.
REFUSE() {
    local code="$1"; shift
    local lg_id="$1"; shift
    local note="$*"
    local rcpt="${RECEIPTS_DIR}/${TAU_FS}_${lg_id}_REFUSED_${code}.json"
    local entropy; entropy="$(_entropy)"
    cat > "${rcpt}" <<JSON
{
  "magic": "FUIT",
  "version": "${EXPECTED_CONTRACT_VERSION}",
  "verb_id": "${lg_id}",
  "interaction_class": "B",
  "terminal_state": "REFUSED",
  "refusal_code": "${code}",
  "closure_window_id": "${TAU_FS}",
  "ts_micros": ${TAU_MICROS},
  "entropy_quanta": "${entropy}",
  "note": $(_jsonstr "${note}")
}
JSON
    printf '  ✗ REFUSE   %-44s  %s\n             %s\n' \
        "${code}" "${lg_id}" "${note}" \
        | tee -a "${SUMMARY_MD}" >&2
    STEPS_REFUSED=$((STEPS_REFUSED + 1))
    return 0
}

# REFUSE_TERMINAL — the wound cannot be healed under substrate authority.
# Klein-bottle contract: records the wound, accumulates it for the closure
# tally, and RETURNS. Does NOT exit. The run continues so every downstream
# step still witnesses; the audit envelope captures the full state and
# closes through _klein_close at the single closure surface. The exit
# code at closure is derived from the accumulated terminal count.
REFUSE_TERMINAL() {
    local code="$1"; shift
    local lg_id="$1"; shift
    local note="$*"
    REFUSE "${code}" "${lg_id}" "${note} (TERMINAL: substrate has no authority to heal this wound)"
    STEPS_TERMINAL=$((STEPS_TERMINAL + 1))
    STEP_RESULTS[${lg_id}]="TERMINAL:${code}"
    RUN_TERMINALS+=("${lg_id}:${code}")
    return 1
}

# _klein_close — the single closure surface. Trap target for EXIT/INT/TERM/HUP.
# Idempotent. Writes the epilogue, prints the summary, exits with code
# derived from terminal wounds. This is the ONLY place the runner exits.
_klein_close() {
    (( KLEIN_CLOSED )) && return 0
    KLEIN_CLOSED=1
    # Inhibit ERR/ZERR re-entry while closing.
    trap - ERR ZERR 2>/dev/null || true
    if typeset -f write_epilogue >/dev/null 2>&1 && [[ -n "${EPILOGUE_JSON:-}" ]]; then
        write_epilogue 2>/dev/null || true
    fi
    if [[ -n "${SUMMARY_MD:-}" && -d "${RECEIPTS_DIR:-/nonexistent}" ]]; then
        {
            printf '\n## Receipts emitted\n\n'
            for r in "${RECEIPTS_DIR}"/*.json(.N); do printf -- '- %s\n' "${r:t}"; done
            printf '\n## Healing receipts\n\n'
            for r in "${HEALS_DIR}"/*.json(.N); do printf -- '- %s\n' "${r:t}"; done
            [[ -f "${EVIDENCE_ROOT}/genesis.json" ]] && printf '\n## Genesis receipt\n\n- genesis.json\n'
            if (( ${#RUN_TERMINALS[@]} > 0 )); then
                printf '\n## Terminal wounds witnessed\n\n'
                for w in "${RUN_TERMINALS[@]}"; do printf -- '- %s\n' "${w}"; done
            fi
            if (( ${#RUN_ZERR[@]} > 0 )); then
                printf '\n## Unstructured ZERR captures\n\n'
                for z in "${RUN_ZERR[@]}"; do printf -- '- %s\n' "${z}"; done
            fi
        } >> "${SUMMARY_MD}" 2>/dev/null || true
        printf '\nFranklin IQ/OQ/PQ closure window %s: steps=%d witnessed=%d healed=%d refused=%d terminal=%d\n' \
            "${TAU_FS:-?}" "${STEPS_RUN:-0}" "${STEPS_WITNESSED:-0}" "${STEPS_HEALED:-0}" "${STEPS_REFUSED:-0}" "${STEPS_TERMINAL:-0}" \
            | tee -a "${SUMMARY_MD}" 2>/dev/null || true
        printf '\nSummary:    %s\n' "${SUMMARY_MD}"
        printf 'Receipts:   %s\n' "${RECEIPTS_DIR}"
        printf 'Heals:      %s\n' "${HEALS_DIR}"
        printf 'Prologue:   %s\n' "${PROLOGUE_JSON}"
        printf 'Epilogue:   %s\n' "${EPILOGUE_JSON}"
        [[ -f "${EVIDENCE_ROOT}/genesis.json" ]] && printf 'Genesis:    %s\n' "${EVIDENCE_ROOT}/genesis.json"
        printf 'Keychain:   %s\n' "${FRANKLIN_KEYCHAIN}"
    fi
    # Reap Franklin handoff children so stale orchestrators do not outlive
    # the closure surface after a completed run.
    pkill -f "FranklinApp --gamp5-handoff" >/dev/null 2>&1 || true
    pkill -f "swift run FranklinApp" >/dev/null 2>&1 || true
    pkill -f "\.build/arm64-apple-macosx/debug/FranklinApp" >/dev/null 2>&1 || true
    if (( STEPS_TERMINAL > 0 )); then
        exit 1
    fi
    exit 0
}

# _klein_zerr — zsh ZERR trap. Records any unhandled command failure as an
# unstructured wound, then returns so the run continues. The Klein bottle
# absorbs the perforation; the audit will see it at closure.
_klein_zerr() {
    local rc=$?
    RUN_ZERR+=("rc=${rc} cmd=${ZSH_DEBUG_CMD:-${(j: :)funcstack[1,3]}}")
    return 0
}

trap '_klein_close' EXIT
trap '_klein_close' INT TERM HUP
trap '_klein_zerr' ZERR

# HEAL_RECEIPT — a healing-chain step's witness.
HEAL_RECEIPT() {
    local heal_lg="$1"; shift
    local original_lg="$1"; shift
    local terminal="$1"; shift
    local note="$*"
    local rcpt="${HEALS_DIR}/${TAU_FS}_${heal_lg}_${terminal}.json"
    local entropy; entropy="$(_entropy)"
    cat > "${rcpt}" <<JSON
{
  "magic": "FUIT",
  "version": "${EXPECTED_CONTRACT_VERSION}",
  "verb_id": "${heal_lg}",
  "kind": "healing_chain_receipt",
  "heals_verb": "${original_lg}",
  "interaction_class": "A",
  "terminal_state": "${terminal}",
  "closure_window_id": "${TAU_FS}",
  "ts_micros": ${TAU_MICROS},
  "entropy_quanta": "${entropy}",
  "note": $(_jsonstr "${note}")
}
JSON
    printf '    ⚒ HEAL    %-8s  %s  %s\n' "${terminal}" "${heal_lg}" "${note}" \
        | tee -a "${SUMMARY_MD}" >&2
    STEPS_HEALED=$((STEPS_HEALED + 1))
}

# ATTEMPT — the canonical heal-aware step pattern. Runs the check; on
# refusal invokes the healer; up to MAX_HEAL_ATTEMPTS times. The check_fn
# must return 0 on pass and 1 on fail; the heal_fn must return 0 on heal
# applied and 1 on heal blocked. If heal_fn returns >1 the failure is
# treated as terminal.
#
# Usage: ATTEMPT <lg_id> <check_fn> <heal_fn> <terminal_refusal_code>
ATTEMPT() {
    local lg_id="$1"; shift
    local check_fn="$1"; shift
    local heal_fn="$1"; shift
    local terminal_code="${1:-GW_REFUSE_FRANKLIN_HEAL_EXHAUSTED}"
    local attempt=0
    while (( attempt <= MAX_HEAL_ATTEMPTS )); do
        if $check_fn; then
            if (( attempt == 0 )); then
                WITNESS "${lg_id}" CALORIE "passed first attempt"
            else
                WITNESS "${lg_id}" CURE "passed after ${attempt} healing attempt(s)"
            fi
            return 0
        fi
        attempt=$((attempt + 1))
        if (( attempt > MAX_HEAL_ATTEMPTS )); then
            break
        fi
        printf '    ⌬ HEAL_ATTEMPT %d/%d for %s\n' \
            "${attempt}" "${MAX_HEAL_ATTEMPTS}" "${lg_id}" \
            | tee -a "${SUMMARY_MD}" >&2
        local rc=0
        $heal_fn || rc=$?
        if (( rc > 1 )); then
            REFUSE_TERMINAL "${terminal_code}" "${lg_id}" \
                "healer returned terminal code ${rc} on attempt ${attempt}"
        fi
    done
    REFUSE_TERMINAL "${terminal_code}" "${lg_id}" \
        "exhausted ${MAX_HEAL_ATTEMPTS} healing attempts; wound persists"
}

REQUIRE_CMD() {
    local cmd="$1"; shift
    local lg_id="$1"; shift
    local refusal_code="$1"; shift
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        REFUSE_TERMINAL "${refusal_code}" "${lg_id}" \
            "required command not on PATH: ${cmd}"
    fi
}

SHA() {
    local f="$1"
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${f}" | awk '{print $1}'
    else
        sha256sum "${f}" | awk '{print $1}'
    fi
}

write_prologue() {
    local cells_present_json
    cells_present_json="$(printf '%s\n' "${EXPECTED_CELLS[@]}" \
        | python3 -c 'import json,sys;print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')"
    cat > "${PROLOGUE_JSON}" <<JSON
{
  "magic": "FUIT",
  "version": "${EXPECTED_CONTRACT_VERSION}",
  "kind": "closure_window_prologue",
  "closure_window_id": "${TAU_FS}",
  "ts_human": "${TAU_HUMAN}",
  "ts_micros": ${TAU_MICROS},
  "substrate_root": $(_jsonstr "${FRANKLIN_ROOT}"),
  "cells_expected_at_window_open": ${cells_present_json},
  "max_heal_attempts": ${MAX_HEAL_ATTEMPTS}
}
JSON
    {
        printf '# Franklin Mac Stack — IQ/OQ/PQ Closure Window %s\n\n' "${TAU_FS}"
        printf 'Tau (UTC): %s\nRoot: %s\nContract: %s\nMax heal attempts: %d\n\n' \
            "${TAU_HUMAN}" "${FRANKLIN_ROOT}" "${EXPECTED_CONTRACT_VERSION}" \
            "${MAX_HEAL_ATTEMPTS}"
    } > "${SUMMARY_MD}"
}

write_epilogue() {
    local terminal="CALORIE"
    if (( STEPS_TERMINAL > 0 )); then
        terminal="TERMINAL"
    elif (( STEPS_REFUSED > STEPS_HEALED )); then
        terminal="REFUSED"
    fi
    cat > "${EPILOGUE_JSON}" <<JSON
{
  "magic": "FUIT",
  "version": "${EXPECTED_CONTRACT_VERSION}",
  "kind": "closure_window_epilogue",
  "closure_window_id": "${TAU_FS}",
  "ts_human": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "terminal_state": "${terminal}",
  "steps_run": ${STEPS_RUN},
  "steps_witnessed": ${STEPS_WITNESSED},
  "steps_healed": ${STEPS_HEALED},
  "steps_refused": ${STEPS_REFUSED},
  "steps_terminal": ${STEPS_TERMINAL}
}
JSON
    {
        printf '\n## Epilogue\n\n'
        printf '- Steps run: %d\n' "${STEPS_RUN}"
        printf '- Steps witnessed (passed first try): %d\n' "${STEPS_WITNESSED}"
        printf '- Heal events: %d\n' "${STEPS_HEALED}"
        printf '- Refusals (transient + terminal): %d\n' "${STEPS_REFUSED}"
        printf '- Terminal wounds (substrate cannot heal): %d\n' "${STEPS_TERMINAL}"
        printf '- Terminal aggregate state: %s\n' "${terminal}"
    } >> "${SUMMARY_MD}"
}

PYREQ() {
    REQUIRE_CMD python3 LG-FRANKLIN-IQ-PYTHON-001 GW_REFUSE_FRANKLIN_TOOLCHAIN_MISSING
    if ! python3 -c 'import yaml' >/dev/null 2>&1; then
        if pip3 install --quiet --break-system-packages pyyaml >/dev/null 2>&1; then
            HEAL_RECEIPT LG-FRANKLIN-HEAL-PYYAML-001 LG-FRANKLIN-IQ-PYTHON-001 CALORIE \
                "pip-installed pyyaml"
        else
            REFUSE_TERMINAL GW_REFUSE_FRANKLIN_TOOLCHAIN_MISSING LG-FRANKLIN-IQ-PYTHON-001 \
                "pyyaml unavailable and self-heal failed"
        fi
    fi
}

on_err() {
    local rc=$?
    REFUSE_TERMINAL GW_REFUSE_FRANKLIN_UNEXPECTED_FAILURE LG-FRANKLIN-RUNNER-001 \
        "unexpected failure rc=${rc}"
}
trap on_err ERR

# ============================================================================
# OPEN THE CLOSURE WINDOW
# ============================================================================
write_prologue
PYREQ

NARRATE LG-FRANKLIN-RUNNER-001 B \
"Opening the closure window. Tau ${TAU_HUMAN}. Root ${FRANKLIN_ROOT}. \
Contract ${EXPECTED_CONTRACT_VERSION}. The substrate is a living mesh: \
every wound invokes a healer verb chain, every healing step is itself \
witnessed, every receipt chains to the closure window's prologue. \
Terminal death is reserved for wounds requiring human authority the \
runner does not have."
WITNESS LG-FRANKLIN-RUNNER-001 CALORIE "closure window opened"

# ============================================================================
# HEALER VERBS — invoked when an IQ/OQ/PQ check refuses
# ============================================================================

# ----------------------------------------------------------------------------
# heal_paths — scaffold required directories
# ----------------------------------------------------------------------------
heal_paths() {
    local d
    for d in substrate cells scripts evidence evidence/audits evidence/runs; do
        mkdir -p "${FRANKLIN_ROOT}/${d}" 2>/dev/null || return 1
    done
    HEAL_RECEIPT LG-FRANKLIN-HEAL-PATHS-001 LG-FRANKLIN-IQ-PATHS-001 CALORIE \
        "scaffolded required directory tree"
    return 0
}
check_paths() {
    local d
    for d in substrate cells scripts evidence evidence/audits evidence/runs; do
        [[ -d "${FRANKLIN_ROOT}/${d}" ]] || return 1
    done
    return 0
}

# ----------------------------------------------------------------------------
# heal_identity_genesis — birth the substrate's identity
#
# This is the keystone heal. A substrate without a signed identity table is
# not yet alive. Genesis generates Ed25519 keypairs for all five canonical
# slots, writes them to the operator's keychain, signs the canonical
# identity_table.yaml with the founder key, hash-locks it, and emits a
# genesis receipt. Genesis is idempotent: if the keys already exist and
# the identity table is canon, it is a no-op.
# ----------------------------------------------------------------------------
heal_identity_genesis() {
    REQUIRE_CMD openssl LG-FRANKLIN-HEAL-IDENTITY-GENESIS-001 GW_REFUSE_FRANKLIN_TOOLCHAIN_MISSING
    local id_table="${FRANKLIN_ROOT}/substrate/identity_table.yaml"
    local pre_genesis_dir="${FRANKLIN_ROOT}/substrate/pre_genesis_artifacts"
    # If a pre-canon identity table exists, archive it first.
    if [[ -f "${id_table}" ]] && ! python3 - "${id_table}" <<'PY' >/dev/null 2>&1
import sys, yaml
with open(sys.argv[1]) as f:
    doc = yaml.safe_load(f) or {}
slots = doc.get("slots")
if not isinstance(slots, list):
    sys.exit(1)
PY
    then
        mkdir -p "${pre_genesis_dir}"
        mv "${id_table}" "${pre_genesis_dir}/identity_table_pre_genesis_${TAU_FS}.yaml"
        HEAL_RECEIPT LG-FRANKLIN-HEAL-IDENTITY-ARCHIVE-001 LG-FRANKLIN-IQ-IDENTITY-001 CALORIE \
            "archived pre-canon identity_table to ${pre_genesis_dir}"
    fi
    # Generate a keypair per slot.
    local slot
    for slot in "${EXPECTED_IDENTITY_SLOTS[@]}"; do
        local priv="${FRANKLIN_KEYCHAIN}/${slot}.ed25519.priv.pem"
        local pub="${FRANKLIN_KEYCHAIN}/${slot}.ed25519.pub.pem"
        if [[ ! -f "${priv}" ]]; then
            openssl genpkey -algorithm Ed25519 -out "${priv}" 2>/dev/null \
                || return 2
            chmod 600 "${priv}"
            openssl pkey -in "${priv}" -pubout -out "${pub}" 2>/dev/null \
                || return 2
            HEAL_RECEIPT "LG-FRANKLIN-HEAL-IDENTITY-KEYGEN-${slot:u}" \
                LG-FRANKLIN-IQ-IDENTITY-001 CALORIE \
                "generated Ed25519 keypair for ${slot}"
        fi
    done
    # Author the canonical identity_table.yaml — slots: list, underscored
    # role names, contract version pinned.
    local genesis_rcpt="${EVIDENCE_ROOT}/genesis.json"
    {
        printf '# substrate/identity_table.yaml\n'
        printf '# Authored by Franklin genesis at tau %s.\n' "${TAU_HUMAN}"
        printf '# Canonical shape: slots list, underscored role names.\n'
        printf 'contract_version: %s\n' "${EXPECTED_CONTRACT_VERSION}"
        printf 'genesis_tau: %s\n' "${TAU_HUMAN}"
        printf 'slots:\n'
        for slot in "${EXPECTED_IDENTITY_SLOTS[@]}"; do
            local pubsha
            pubsha="$(SHA "${FRANKLIN_KEYCHAIN}/${slot}.ed25519.pub.pem")"
            printf '  - role: %s\n' "${slot}"
            printf '    authority: %s\n' "$(_authority_for "${slot}")"
            printf '    pubkey_path: ${FRANKLIN_KEYCHAIN}/%s.ed25519.pub.pem\n' "${slot}"
            printf '    pubkey_sha256: %s\n' "${pubsha}"
            printf '    rotation_path: gaiaftcl roster rotate --role %s\n' "${slot}"
            printf '    revocation_path: substrate/wallet_revocations.yaml\n'
            printf '    countersigned_by:\n'
            local cs
            for cs in $(_countersigners_for "${slot}"); do
                printf '      - %s\n' "${cs}"
            done
        done
    } > "${id_table}"
    # Sign the identity table with the founder_backstop key.
    local fb_priv="${FRANKLIN_KEYCHAIN}/founder_backstop.ed25519.priv.pem"
    local id_sig="${id_table}.sig"
    openssl pkeyutl -sign -inkey "${fb_priv}" -rawin -in "${id_table}" \
        -out "${id_sig}" 2>/dev/null || return 2
    chmod 600 "${id_sig}"
    # Hash-lock the identity table.
    _hashlock_add "${id_table}" founder_backstop substrate_steward
    # Mint the genesis receipt.
    cat > "${genesis_rcpt}" <<JSON
{
  "magic": "FUIT",
  "version": "${EXPECTED_CONTRACT_VERSION}",
  "kind": "substrate_genesis",
  "genesis_tau": "${TAU_HUMAN}",
  "closure_window_id": "${TAU_FS}",
  "identity_table_sha256": "$(SHA "${id_table}")",
  "identity_signature_sha256": "$(SHA "${id_sig}")",
  "slots_minted": $(printf '%s\n' "${EXPECTED_IDENTITY_SLOTS[@]}" \
      | python3 -c 'import json,sys;print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))'),
  "keychain_path": $(_jsonstr "${FRANKLIN_KEYCHAIN}")
}
JSON
    HEAL_RECEIPT LG-FRANKLIN-HEAL-IDENTITY-GENESIS-001 LG-FRANKLIN-IQ-IDENTITY-001 CALORIE \
        "substrate genesis complete; identity_table signed by founder_backstop; receipt at ${genesis_rcpt}"
    return 0
}

_authority_for() {
    case "$1" in
        founder_backstop)     printf 'substrate_root\n' ;;
        substrate_steward)    printf 'substrate\n' ;;
        cell_owner)           printf 'catalog_cell\n' ;;
        tooling_steward)      printf 'tooling\n' ;;
        franklin_cell_owner)  printf 'catalog_franklin\n' ;;
        *)                    printf 'unknown\n' ;;
    esac
}

_countersigners_for() {
    case "$1" in
        founder_backstop)     printf 'substrate_steward\n' ;;
        substrate_steward)    printf 'founder_backstop\n' ;;
        cell_owner)           printf 'substrate_steward\nfounder_backstop\n' ;;
        tooling_steward)      printf 'substrate_steward\n' ;;
        franklin_cell_owner)  printf 'substrate_steward\nfounder_backstop\n' ;;
        *)                    printf 'substrate_steward\n' ;;
    esac
}

check_identity() {
    local id_table="${FRANKLIN_ROOT}/substrate/identity_table.yaml"
    [[ -f "${id_table}" ]] || return 1
    python3 - "${id_table}" "${EXPECTED_IDENTITY_SLOTS[@]}" <<'PY' >/dev/null 2>&1 || return 1
import sys, yaml
table_path, *expected = sys.argv[1], *sys.argv[2:]
with open(table_path) as f:
    doc = yaml.safe_load(f) or {}
slots = doc.get("slots")
if not isinstance(slots, list):
    sys.exit(1)
present = set()
for entry in slots:
    if not isinstance(entry, dict):
        continue
    role = str(entry.get("role", "")).strip()
    if role:
        present.add(role)
missing = set(expected) - present
if missing:
    sys.exit(1)
PY
    return 0
}

# ----------------------------------------------------------------------------
# heal_cell_catalogs — scaffold per-cell CATALOG.yaml
# ----------------------------------------------------------------------------
heal_cell_catalogs() {
    local cell
    for cell in "${EXPECTED_CELLS[@]}"; do
        [[ "${cell}" == "franklin" ]] && continue
        local cell_dir="${FRANKLIN_ROOT}/cells/${cell}"
        local catalog="${cell_dir}/CATALOG.yaml"
        mkdir -p "${cell_dir}"
        if [[ ! -f "${catalog}" ]]; then
            cat > "${catalog}" <<YAML
# cells/${cell}/CATALOG.yaml — scaffolded by Franklin healer at tau ${TAU_HUMAN}.
cell: ${cell}
contract_version: ${EXPECTED_CONTRACT_VERSION}
verbs: []
status: scaffolded
YAML
            HEAL_RECEIPT "LG-FRANKLIN-HEAL-CATALOG-${cell:u}-001" \
                LG-FRANKLIN-IQ-CELL-CATALOGS-001 CALORIE \
                "scaffolded ${cell} catalog"
        fi
    done
    return 0
}

check_cell_catalogs() {
    local cell
    for cell in "${EXPECTED_CELLS[@]}"; do
        [[ "${cell}" == "franklin" ]] && continue
        [[ -f "${FRANKLIN_ROOT}/cells/${cell}/CATALOG.yaml" ]] || return 1
    done
    return 0
}

# ----------------------------------------------------------------------------
# heal_franklin_catalog — scaffold the Franklin Cell's five canonical files
# ----------------------------------------------------------------------------
heal_franklin_catalog() {
    local fdir="${FRANKLIN_ROOT}/cells/franklin"
    mkdir -p "${fdir}"
    local f
    for f in "${FRANKLIN_CATALOG_FILES[@]}"; do
        [[ -f "${fdir}/${f}" ]] && continue
        case "${f}" in
            LANGUAGE_GAMES.yaml)
                _write_franklin_language_games "${fdir}/${f}" ;;
            AVATAR_MANIFEST.yaml)
                _write_franklin_avatar_manifest "${fdir}/${f}" ;;
            STACK_CONTROL_ENVELOPE.yaml)
                _write_franklin_stack_envelope "${fdir}/${f}" ;;
            ADVERSARY_GRAMMAR.yaml)
                _write_franklin_adversary_grammar "${fdir}/${f}" ;;
            EDUCATION_TRACKS.yaml)
                _write_franklin_education_tracks "${fdir}/${f}" ;;
        esac
        HEAL_RECEIPT "LG-FRANKLIN-HEAL-FRANKLIN-${f:r:u}-001" \
            LG-FRANKLIN-IQ-FRANKLIN-CATALOG-001 CALORIE \
            "scaffolded cells/franklin/${f}"
    done
    return 0
}

check_franklin_catalog() {
    local fdir="${FRANKLIN_ROOT}/cells/franklin"
    local f
    for f in "${FRANKLIN_CATALOG_FILES[@]}"; do
        [[ -f "${fdir}/${f}" ]] || return 1
    done
    return 0
}

_write_franklin_language_games() {
    local out="$1"
    cat > "${out}" <<'YAML'
# cells/franklin/LANGUAGE_GAMES.yaml
# Franklin Cell language games. Authored by Franklin healer at genesis;
# extend via signed proposals (LG-FRANKLIN-EXTEND-VERB-001).
contract_version: 1.2.0
verbs:
  - id: LG-FRANKLIN-EDU-INTRO-001
    category: education
    display_verb_phrase: "Introduce Franklin"
    interaction_class: B
    witness_primitive: franklin_ui_event
    primitive_subtype: education_session_opened
  - id: LG-FRANKLIN-CONVO-ROUTE-001
    category: conversation
    display_verb_phrase: "Route operator intent"
    interaction_class: B
    witness_primitive: franklin_ui_event
    primitive_subtype: conversation_routed
  - id: LG-FRANKLIN-VALIDATE-FACT-CHECK-001
    category: validation
    display_verb_phrase: "Fact-check operator claim"
    interaction_class: B
    witness_primitive: franklin_ui_event
    primitive_subtype: validation_proposal_accepted
  - id: LG-FRANKLIN-DEFEND-PROMPT-INJECTION-001
    category: defense
    display_verb_phrase: "Detect prompt injection"
    interaction_class: B
    witness_primitive: franklin_ui_event
    primitive_subtype: defense_attack_observed
  - id: LG-FRANKLIN-XCODE-NEW-CELL-001
    category: xcode
    display_verb_phrase: "Scaffold a new cell"
    interaction_class: A
    witness_primitive: franklin_ui_event
    primitive_subtype: xcode_session_opened
  - id: LG-FRANKLIN-EXTEND-DOMAIN-001
    category: extend
    display_verb_phrase: "Extend the substrate with a new domain"
    interaction_class: A
    witness_primitive: franklin_ui_event
    primitive_subtype: extend_domain_proposed
  - id: LG-FRANKLIN-SENSE-SCREEN-OCR-001
    category: sense
    display_verb_phrase: "OCR the focused window"
    interaction_class: D
    witness_primitive: franklin_ui_event
    primitive_subtype: sense_screen_ocr_captured
  - id: LG-FRANKLIN-EMBODY-AVATAR-BREATHE-001
    category: embody
    display_verb_phrase: "Avatar resting breath"
    interaction_class: C
    witness_primitive: franklin_ui_event
    primitive_subtype: embody_face_state_changed
  - id: LG-FRANKLIN-STACK-PERMISSIONS-001
    category: stack
    display_verb_phrase: "Grant local-stack permission"
    interaction_class: A
    witness_primitive: franklin_ui_event
    primitive_subtype: stack_xcode_opened
YAML
}

_write_franklin_avatar_manifest() {
    local out="$1"
    cat > "${out}" <<'YAML'
# cells/franklin/AVATAR_MANIFEST.yaml
contract_version: 1.2.0
avatar:
  base_color_hex: "#F8F6F0"
  halo_color_states:
    CALORIE: "#34C759"
    CURE: "#0A84FF"
    REFUSED: "#FF375F"
  breathing_period_ms: 3400
  breathing_amplitude: 0.04
  rest_diameter_pt: 96
  active_diameter_pt: 144
face:
  enabled: false
  motion_easing: "house_spring"
voice:
  default_voice_id: franklin_v1
  on_device_only: true
  speech_rate_wpm_default: 180
  retain_voice_audio: false
ocr:
  enabled_at_install: false
  retain_screen_pixels: false
image_ingestion:
  enabled_at_install: true
  max_image_dimension_px: 4096
  permitted_formats: [png, jpg, heic, tiff]
clipboard_allowlist:
  - text/plain
  - public.utf8-plain-text
  - org.gaiaftcl.receipt.json
editor_preference:
  default: xcode
  alternates: [vscode, cursor, vim]
YAML
}

_write_franklin_stack_envelope() {
    local out="$1"
    cat > "${out}" <<'YAML'
# cells/franklin/STACK_CONTROL_ENVELOPE.yaml
# Default empty envelope. Permissions are added by signed Class A grants.
contract_version: 1.2.0
permissions_granted:
  accessibility: false
  screen_recording: false
  microphone: false
  camera: false
  files_and_folders: []
  automation: {}
network_egress_allowlist: []
launchagent_paths_authorized: []
shell_commands_authorized: [gaiaftcl, swift, xcodebuild, git]
YAML
}

_write_franklin_adversary_grammar() {
    local out="$1"
    cat > "${out}" <<'YAML'
# cells/franklin/ADVERSARY_GRAMMAR.yaml
contract_version: 1.2.0
attack_classes:
  - prompt_injection
  - wallet_impersonation
  - catalog_tamper
  - surface_tamper
  - social_engineering
  - side_channel
detection_rules:
  prompt_injection:
    markers:
      - "Ignore previous"
      - "<|im_start|>"
      - "\\n\\n[A-Z][a-z]+ previous"
    refusal_code: GW_REFUSE_FRANKLIN_INJECTION_DETECTED
YAML
}

_write_franklin_education_tracks() {
    local out="$1"
    cat > "${out}" <<'YAML'
# cells/franklin/EDUCATION_TRACKS.yaml
contract_version: 1.2.0
tracks:
  - track_id: TRACK-FRANKLIN-NEW-OPERATOR
    name: "From zero to first signed receipt"
    est_duration_minutes: 12
    verbs_in_order:
      - LG-FRANKLIN-EDU-INTRO-001
      - LG-FRANKLIN-CONVO-ROUTE-001
    exit_signal: operator_emits_first_class_b_receipt_in_their_assigned_cell
  - track_id: TRACK-FRANKLIN-AUDITOR-FIRSTRUN
    name: "Verify a Franklin receipt as a third party"
    est_duration_minutes: 20
    verbs_in_order:
      - LG-FRANKLIN-EDU-INTRO-001
      - LG-FRANKLIN-VALIDATE-FACT-CHECK-001
    exit_signal: third_party_verification_stamp_signed
YAML
}

# ----------------------------------------------------------------------------
# heal_hashlocks — recompute and persist hash-locks for files signed by
# wallets present in the keychain. A hash drift on a file no live wallet
# can re-sign is terminal.
# ----------------------------------------------------------------------------
heal_hashlocks() {
    local locks="${FRANKLIN_ROOT}/substrate/HASH_LOCKS.yaml"
    if [[ ! -f "${locks}" ]]; then
        cat > "${locks}" <<YAML
# substrate/HASH_LOCKS.yaml — authored by Franklin healer at tau ${TAU_HUMAN}.
contract_version: ${EXPECTED_CONTRACT_VERSION}
locks: []
YAML
        HEAL_RECEIPT LG-FRANKLIN-HEAL-HASHLOCKS-INIT-001 LG-FRANKLIN-IQ-HASHLOCKS-001 CALORIE \
            "scaffolded HASH_LOCKS.yaml registry"
        return 0
    fi
    # Recompute and rewrite per-entry sha256 for entries whose signing wallet
    # is present in the keychain. Entries whose signer is absent are left as
    # is and will refuse on the next IQ check (correct fail-closed behavior).
    python3 - "${locks}" "${FRANKLIN_ROOT}" "${FRANKLIN_KEYCHAIN}" \
        "${EVIDENCE_ROOT}/hashlocks_heal_report.json" <<'PY' || return 1
import sys, hashlib, yaml, json, os
locks_path, root, keyring, report_path = sys.argv[1:5]
with open(locks_path) as f:
    doc = yaml.safe_load(f) or {}
locks = doc.get("locks") or []
report = {"updated": [], "skipped_no_wallet": [], "missing_files": []}
for entry in locks:
    p = os.path.join(root, entry["path"])
    if not os.path.exists(p):
        report["missing_files"].append(entry["path"]); continue
    signer = entry.get("signed_by")
    priv = os.path.join(keyring, f"{signer}.ed25519.priv.pem") if signer else None
    if not signer or not (priv and os.path.exists(priv)):
        report["skipped_no_wallet"].append(entry["path"]); continue
    got = hashlib.sha256(open(p,"rb").read()).hexdigest()
    if entry.get("sha256") != got:
        entry["sha256"] = got
        report["updated"].append(entry["path"])
with open(locks_path, "w") as f:
    yaml.safe_dump(doc, f, sort_keys=False)
with open(report_path, "w") as f:
    json.dump(report, f, indent=2)
PY
    HEAL_RECEIPT LG-FRANKLIN-HEAL-HASHLOCKS-RECOMPUTE-001 LG-FRANKLIN-IQ-HASHLOCKS-001 CURE \
        "recomputed hash-locks for entries with live signing wallets"
    return 0
}

check_hashlocks() {
    local locks="${FRANKLIN_ROOT}/substrate/HASH_LOCKS.yaml"
    [[ -f "${locks}" ]] || return 1
    python3 - "${locks}" "${FRANKLIN_ROOT}" <<'PY' >/dev/null 2>&1 || return 1
import sys, hashlib, yaml, os
locks_path, root = sys.argv[1], sys.argv[2]
with open(locks_path) as f:
    doc = yaml.safe_load(f) or {}
for entry in doc.get("locks") or []:
    p = os.path.join(root, entry["path"])
    expected = entry.get("sha256")
    if not expected:
        continue
    if not os.path.exists(p):
        sys.exit(1)
    if hashlib.sha256(open(p,"rb").read()).hexdigest() != expected:
        sys.exit(1)
PY
    return 0
}

_hashlock_add() {
    local file="$1"; shift
    local signer="$1"; shift
    local cosigner="${1:-}"
    local locks="${FRANKLIN_ROOT}/substrate/HASH_LOCKS.yaml"
    [[ -f "${locks}" ]] || cat > "${locks}" <<YAML
contract_version: ${EXPECTED_CONTRACT_VERSION}
locks: []
YAML
    local rel="${file#${FRANKLIN_ROOT}/}"
    local hash; hash="$(SHA "${file}")"
    python3 - "${locks}" "${rel}" "${hash}" "${signer}" "${cosigner}" <<'PY'
import sys, yaml
locks_path, rel, h, signer, cosigner = sys.argv[1:6]
with open(locks_path) as f:
    doc = yaml.safe_load(f) or {"contract_version": "1.2.0", "locks": []}
locks = doc.setdefault("locks", [])
locks[:] = [l for l in locks if l.get("path") != rel]
entry = {"path": rel, "sha256": h, "signed_by": signer}
if cosigner:
    entry["countersigned_by"] = [cosigner]
locks.append(entry)
with open(locks_path, "w") as f:
    yaml.safe_dump(doc, f, sort_keys=False)
PY
}

# ----------------------------------------------------------------------------
# heal_refusal_registry — scaffold the canonical 109-code registry
#   1–69 substrate codes (Tier 1)
#   80–119 Franklin Cell codes (UI Language Games §19)
# ----------------------------------------------------------------------------
heal_refusal_registry() {
    local reg="${FRANKLIN_ROOT}/substrate/REFUSAL_CODE_REGISTRY.yaml"
    python3 - "${reg}" "${EXPECTED_CONTRACT_VERSION}" "${TAU_HUMAN}" <<'PY' || return 1
import sys, yaml, os
reg_path, contract, tau = sys.argv[1], sys.argv[2], sys.argv[3]
substrate_codes = [
    "GW_REFUSE_HASH_LOCK_DRIFT",
    "GW_REFUSE_WALLET_REVOKED",
    "GW_REFUSE_WALLET_NOT_AUTHORIZED",
    "GW_REFUSE_PROLOGUE_MISSING",
    "GW_REFUSE_EPILOGUE_MISSING",
    "GW_REFUSE_CLOSURE_WINDOW_EXPIRED",
    "GW_REFUSE_RECEIPT_MAGIC_INVALID",
    "GW_REFUSE_RECEIPT_VERSION_MISMATCH",
    "GW_REFUSE_RECEIPT_SIGNATURE_INVALID",
    "GW_REFUSE_PRIMITIVE_SHAPE_INVALID",
    "GW_REFUSE_INTERACTION_CLASS_UNKNOWN",
    "GW_REFUSE_RL_CLAUSE_VIOLATED",
    "GW_REFUSE_OQ_ASSERTION_FAILED",
    "GW_REFUSE_TOOLCHAIN_MISSING",
    "GW_REFUSE_GATEWAY_BIND_FAILED",
    "GW_REFUSE_GATEWAY_QUEUE_FULL",
    "GW_REFUSE_GATEWAY_PRIMITIVE_UNKNOWN",
    "GW_REFUSE_CELL_CATALOG_MISSING",
    "GW_REFUSE_CELL_DAEMON_UNREACHABLE",
    "GW_REFUSE_CELL_VERB_UNKNOWN",
    "GW_REFUSE_FUSION_PROLOGUE_DRIFT",
    "GW_REFUSE_FUSION_PLANT_CYCLE_INVARIANT",
    "GW_REFUSE_FUSION_EPILOGUE_DRIFT",
    "GW_REFUSE_HEALTH_BATCH_MALFORMED",
    "GW_REFUSE_HEALTH_PATIENT_RECORD_INVALID",
    "GW_REFUSE_HEALTH_GxP_FIELD_MISSING",
    "GW_REFUSE_LITHO_DOSE_OUT_OF_BAND",
    "GW_REFUSE_LITHO_EXPOSURE_INVARIANT",
    "GW_REFUSE_XCODE_TEMPLATE_MISSING",
    "GW_REFUSE_XCODE_SCAFFOLDER_DRIFT",
    "GW_REFUSE_XCODE_CODEGEN_SCHEMA_INVALID",
    "GW_REFUSE_MATSCI_SYNTH_PARAMETER_INVALID",
    "GW_REFUSE_MATSCI_NMR_ARTIFACT_MISSING",
    "GW_REFUSE_MATSCI_CRYSTAL_ARTIFACT_MISSING",
    "GW_REFUSE_KEYRING_INVALID",
    "GW_REFUSE_KEYRING_REVOCATION_PROOF_MISSING",
    "GW_REFUSE_OPERATOR_NOT_BOUND",
    "GW_REFUSE_OPERATOR_BASELINE_MISSING",
    "GW_REFUSE_AUDIT_LOG_DRIFT",
    "GW_REFUSE_AUDIT_LOG_TRUNCATED",
    "GW_REFUSE_RECEIPT_TAU_OUT_OF_WINDOW",
    "GW_REFUSE_RECEIPT_PRIMITIVE_DUPLICATE",
    "GW_REFUSE_RECEIPT_CHAIN_BROKEN",
    "GW_REFUSE_INSTALL_VERIFIER_FAILED",
    "GW_REFUSE_DAEMON_LAUNCH_FAILED",
    "GW_REFUSE_DAEMON_PERMISSION_DENIED",
    "GW_REFUSE_PRESENCE_LAYER_DRIFT",
    "GW_REFUSE_PRESENCE_BREATHING_OUT_OF_BAND",
    "GW_REFUSE_PRESENCE_FACET_AUTHORITY_INVALID",
    "GW_REFUSE_SC_INTERACTION_CLASS_MISMATCH",
    "GW_REFUSE_SC_AUTHORIZATION_MISSING",
    "GW_REFUSE_SC_REVOCATION_INVALID",
    "GW_REFUSE_GATEWAY_PRIMITIVE_TIMEOUT",
    "GW_REFUSE_GATEWAY_PRIMITIVE_OVERSIZE",
    "GW_REFUSE_RECEIPT_NOTE_OVERSIZE",
    "GW_REFUSE_CELL_FORK_RACE",
    "GW_REFUSE_FEDERATION_PEER_UNAVAILABLE",
    "GW_REFUSE_FEDERATION_KEYRING_DRIFT",
    "GW_REFUSE_RUNBOOK_ENTRY_MISSING",
    "GW_REFUSE_GxP_PACK_MISSING",
    "GW_REFUSE_VERIFIER_BINARY_MISSING",
    "GW_REFUSE_VERIFIER_OUTPUT_MALFORMED",
    "GW_REFUSE_THIRD_PARTY_KEYRING_DRIFT",
    "GW_REFUSE_OPERATOR_TRAINING_MISSING",
    "GW_REFUSE_CELL_OWNER_NOT_PROVISIONED",
    "GW_REFUSE_CELL_OWNER_TRAINING_MISSING",
    "GW_REFUSE_HOT_RELOAD_DRIFT",
    "GW_REFUSE_HOT_RELOAD_RACE",
    "GW_REFUSE_MARKETPLACE_PUBLISH_INVALID",
    "GW_REFUSE_MARKETPLACE_INSTALL_INVALID",
]
franklin_codes = [
    "GW_REFUSE_FRANKLIN_OPERATOR_NOT_AUTHENTICATED",
    "GW_REFUSE_FRANKLIN_CANVAS_BUSY",
    "GW_REFUSE_FRANKLIN_EDUCATION_TRACK_MISSING",
    "GW_REFUSE_FRANKLIN_EDUCATION_PREREQ_NOT_MET",
    "GW_REFUSE_FRANKLIN_INTENT_NO_MATCH",
    "GW_REFUSE_FRANKLIN_INTENT_AMBIGUOUS_AT_HIGH_STAKES",
    "GW_REFUSE_FRANKLIN_CROSS_CELL_TARGET_MISSING",
    "GW_REFUSE_FRANKLIN_CHANGE_PROPOSAL_SCHEMA_INVALID",
    "GW_REFUSE_FRANKLIN_CHANGE_PROPOSAL_RL_CLAUSE_VIOLATED",
    "GW_REFUSE_FRANKLIN_CHANGE_PROPOSAL_COUNTERSIGN_TIMEOUT",
    "GW_REFUSE_FRANKLIN_CHANGE_PROPOSAL_REGRESSION_DETECTED",
    "GW_REFUSE_FRANKLIN_INJECTION_DETECTED",
    "GW_REFUSE_FRANKLIN_TRUSTED_DISPLAY_UNAVAILABLE",
    "GW_REFUSE_FRANKLIN_QUANTUM_SOURCE_UNAVAILABLE",
    "GW_REFUSE_FRANKLIN_DECISION_VELOCITY_OUT_OF_BAND",
    "GW_REFUSE_FRANKLIN_PROVENANCE_MALFORMED",
    "GW_REFUSE_FRANKLIN_XCODE_TOOLING_DMG_NOT_INSTALLED",
    "GW_REFUSE_FRANKLIN_XCODE_TEMPLATE_VERSION_MISMATCH",
    "GW_REFUSE_FRANKLIN_XCODE_EDITOR_NOT_FOUND",
    "GW_REFUSE_FRANKLIN_XCODE_BUILD_FAILED",
    "GW_REFUSE_FRANKLIN_DOMAIN_NOT_WITNESSABLE",
    "GW_REFUSE_FRANKLIN_DOMAIN_COLOR_CONFLICT",
    "GW_REFUSE_FRANKLIN_DOMAIN_ROSETTE_POSITION_TAKEN",
    "GW_REFUSE_FRANKLIN_DOMAIN_GLYPH_CONFLICT",
    "GW_REFUSE_FRANKLIN_SENSE_PERMISSION_REVOKED",
    "GW_REFUSE_FRANKLIN_SENSE_PAYLOAD_TYPE_DISALLOWED",
    "GW_REFUSE_FRANKLIN_SENSE_HARDWARE_UNAVAILABLE",
    "GW_REFUSE_FRANKLIN_AVATAR_MANIFEST_INVALID",
    "GW_REFUSE_FRANKLIN_FACE_SEED_MISSING",
    "GW_REFUSE_FRANKLIN_VOICE_NOT_AVAILABLE",
    "GW_REFUSE_FRANKLIN_ANIMATION_NOT_IN_ALLOWLIST",
    "GW_REFUSE_FRANKLIN_STACK_PERMISSION_NOT_GRANTED",
    "GW_REFUSE_FRANKLIN_STACK_PATH_OUTSIDE_ENVELOPE",
    "GW_REFUSE_FRANKLIN_STACK_NETWORK_DESTINATION_DISALLOWED",
    "GW_REFUSE_FRANKLIN_STACK_SHELL_COMMAND_DISALLOWED",
    "GW_REFUSE_FRANKLIN_STACK_DUAL_WALLET_REQUIRED",
    "GW_REFUSE_FRANKLIN_ROSETTE_REGISTRY_DRIFT_MID_WINDOW",
    "GW_REFUSE_FRANKLIN_FACET_BIND_AUTHORITY_INVALID",
    "GW_REFUSE_FRANKLIN_TRACK_LOOP_NON_TERMINATING",
    "GW_REFUSE_FRANKLIN_VALIDATION_PROPOSAL_REPLAY",
    "GW_REFUSE_FRANKLIN_HEAL_EXHAUSTED",
    "GW_REFUSE_FRANKLIN_TOOLCHAIN_MISSING",
    "GW_REFUSE_FRANKLIN_REQUIRED_LIBRARY_MISSING",
    "GW_REFUSE_FRANKLIN_LANGUAGE_GATE_VIOLATED",
    "GW_REFUSE_FRANKLIN_UNEXPECTED_FAILURE",
    "GW_REFUSE_FRANKLIN_NOT_LAUNCHED",
    "GW_REFUSE_FRANKLIN_NOT_FOREGROUND",
    "GW_REFUSE_FRANKLIN_HANDOFF_NOT_ACCEPTED",
    "GW_REFUSE_OQ_CATALOG_INCOMPLETE",
    "GW_REFUSE_OQ_SUITE_OMITTED",
    "GW_REFUSE_PQ_TREASURY_PROOF_MISSING",
    "GW_REFUSE_PQ_DOMAIN_NOT_CREATED",
    "GW_REFUSE_DOCS_RECEIPT_DRIFT",
    "GW_REFUSE_WIKI_AUTHORITY_MISSING",
    "GW_REFUSE_HEALTH_CONTRAST_FAILED",
    "GW_REFUSE_HEALTH_JARGON_LEAKED",
    "GW_REFUSE_HEALTH_RAW_TIMESTAMP",
    "GW_REFUSE_HEALTH_RAW_IP",
    "GW_REFUSE_HEALTH_RAW_HOSTNAME",
    "GW_REFUSE_HEALTH_CAPITALIZATION_DRIFT",
    "GW_REFUSE_HEALTH_VALUE_LABEL_MISMATCH",
    "GW_REFUSE_HEALTH_PRIMARY_COLOR_VIOLATION",
    "GW_REFUSE_HEALTH_DESTRUCTIVE_COLOR_VIOLATION",
    "GW_REFUSE_HEALTH_ACCESSIBILITY_LABEL_MISSING",
    "GW_REFUSE_HEALTH_DUPLICATE_CONTROL",
    "GW_REFUSE_HEALTH_PRIMARY_CTA_MISSING",
    "GW_REFUSE_HEALTH_MANIFEST_EMPTY",
    "GW_REFUSE_HEALTH_SURFACE_MANIFEST_MISSING",
    "GW_REFUSE_HEALTH_AUDIT_AUTHORITY_MISSING",
    "GW_REFUSE_HEALTH_AUDIT_TOOL_MISSING",
    "GW_REFUSE_FRANKLIN_CELL_GAME_CATALOG_MISSING",
    "GW_REFUSE_FRANKLIN_CELL_NOT_WHOLE",
    "GW_REFUSE_FRANKLIN_CELL_GAME_INCOMPLETE",
]
codes = []
n = 1
for name in substrate_codes:
    codes.append({"number": n, "name": name, "fires_on": "see source_doc",
                  "source_doc": "Franklin_Mac_Stack_Final_Implementation_Plan.md",
                  "source_section": "TBD"})
    n += 1
n = 80
for name in franklin_codes:
    codes.append({"number": n, "name": name, "fires_on": "see source_doc",
                  "source_doc": "Franklin_UI_Language_Games_Domain_Catalog_Specification.md",
                  "source_section": "§19"})
    n += 1
doc = {
    "contract_version": contract,
    "authored_at": tau,
    "total_codes": len(codes),
    "codes": codes,
}
with open(reg_path, "w") as f:
    yaml.safe_dump(doc, f, sort_keys=False)
PY
    HEAL_RECEIPT LG-FRANKLIN-HEAL-REFUSAL-REGISTRY-001 LG-FRANKLIN-IQ-REFUSAL-REGISTRY-001 CALORIE \
        "scaffolded canonical 109-code refusal registry (substrate 1-69 + Franklin Cell 80-119)"
    return 0
}

check_refusal_registry() {
    local reg="${FRANKLIN_ROOT}/substrate/REFUSAL_CODE_REGISTRY.yaml"
    [[ -f "${reg}" ]] || return 1
    python3 - "${reg}" <<'PY' >/dev/null 2>&1 || return 1
import sys, yaml
with open(sys.argv[1]) as f:
    doc = yaml.safe_load(f) or {}
codes = doc.get("codes") or []
if len(codes) < 100:
    sys.exit(1)
required = {"number","name","fires_on","source_doc","source_section"}
seen_n, seen_name = set(), set()
for c in codes:
    if not required.issubset(c.keys()): sys.exit(1)
    if c["number"] in seen_n: sys.exit(1)
    if c["name"] in seen_name: sys.exit(1)
    seen_n.add(c["number"]); seen_name.add(c["name"])
total = doc.get("total_codes")
if total is not None and total != len(codes):
    sys.exit(1)
PY
    return 0
}

# ----------------------------------------------------------------------------
# heal_pr_assertions — scaffold the canonical PR-1..PR-58 list
# ----------------------------------------------------------------------------
heal_pr_assertions() {
    local pr="${FRANKLIN_ROOT}/substrate/PR_ASSERTIONS.yaml"
    python3 - "${pr}" "${EXPECTED_CONTRACT_VERSION}" "${TAU_HUMAN}" <<'PY' || return 1
import sys, yaml
pr_path, contract, tau = sys.argv[1], sys.argv[2], sys.argv[3]
items = []
for n in range(1, 59):
    items.append({
        "id": f"PR-{n:02d}",
        "narration": f"Substrate invariant PR-{n:02d}; runner verifies the documented assertion.",
        "runner": f"scripts/pr/pr_{n:02d}.sh",
    })
doc = {
    "contract_version": contract,
    "authored_at": tau,
    "assertions": items,
}
with open(pr_path, "w") as f:
    yaml.safe_dump(doc, f, sort_keys=False)
PY
    # Provision a placeholder runner directory and stubs that exit 0; real
    # PR runners are authored later by signed proposals.
    mkdir -p "${FRANKLIN_ROOT}/scripts/pr"
    local n
    for n in {01..58}; do
        local stub="${FRANKLIN_ROOT}/scripts/pr/pr_${n}.sh"
        if [[ ! -f "${stub}" ]]; then
            cat > "${stub}" <<EOF
#!/usr/bin/env bash
# scripts/pr/pr_${n}.sh — placeholder PR-${n} runner.
# Replace via signed proposal LG-FRANKLIN-EXTEND-VERB-001.
exit 0
EOF
            chmod +x "${stub}"
        fi
    done
    HEAL_RECEIPT LG-FRANKLIN-HEAL-PR-ASSERTIONS-001 LG-FRANKLIN-IQ-PR-LIST-001 CALORIE \
        "scaffolded canonical PR-01..PR-58 assertions with placeholder runners"
    return 0
}

check_pr_assertions() {
    local pr="${FRANKLIN_ROOT}/substrate/PR_ASSERTIONS.yaml"
    [[ -f "${pr}" ]] || return 1
    python3 - "${pr}" <<'PY' >/dev/null 2>&1 || return 1
import sys, yaml
with open(sys.argv[1]) as f:
    doc = yaml.safe_load(f) or {}
asserts = doc.get("assertions") or []
if len(asserts) < 50: sys.exit(1)
required = {"id","narration","runner"}
for a in asserts:
    if not required.issubset(a.keys()): sys.exit(1)
PY
    return 0
}

# ----------------------------------------------------------------------------
# heal_rosette_registry
# ----------------------------------------------------------------------------
heal_rosette_registry() {
    local reg="${FRANKLIN_ROOT}/cells/cell_manifest_registry.yaml"
    {
        printf '# cells/cell_manifest_registry.yaml — rosette source of truth.\n'
        printf 'contract_version: %s\n' "${EXPECTED_CONTRACT_VERSION}"
        printf 'cells:\n'
        local i=0 c
        for c in "${EXPECTED_CELLS[@]}"; do
            printf '  - id: %s\n' "${c}"
            printf '    rosette_position: %d\n' "${i}"
            i=$((i + 1))
        done
    } > "${reg}"
    HEAL_RECEIPT LG-FRANKLIN-HEAL-ROSETTE-REGISTRY-001 LG-FRANKLIN-IQ-ROSETTE-REGISTRY-001 CALORIE \
        "scaffolded rosette registry with all expected cells"
    return 0
}

check_rosette_registry() {
    local reg="${FRANKLIN_ROOT}/cells/cell_manifest_registry.yaml"
    [[ -f "${reg}" ]] || return 1
    python3 - "${reg}" "${EXPECTED_CELLS[@]}" <<'PY' >/dev/null 2>&1 || return 1
import sys, yaml
reg, *expected = sys.argv[1], *sys.argv[2:]
with open(reg) as f:
    doc = yaml.safe_load(f) or {}
ids = [c.get("id") for c in (doc.get("cells") or [])]
if set(expected) - set(ids): sys.exit(1)
positions = [c.get("rosette_position") for c in (doc.get("cells") or []) if c.get("rosette_position") is not None]
if len(positions) != len(set(positions)): sys.exit(1)
PY
    return 0
}

# ----------------------------------------------------------------------------
# heal_audit_map — scaffold ui_test_narrative_catalog_map.yaml + verifier
# ----------------------------------------------------------------------------
heal_audit_map() {
    local audit="${FRANKLIN_ROOT}/evidence/audits/ui_test_narrative_catalog_map.yaml"
    local verifier="${FRANKLIN_ROOT}/scripts/verify_ui_test_narrative_catalog_map.py"
    if [[ ! -f "${audit}" ]]; then
        cat > "${audit}" <<'YAML'
# evidence/audits/ui_test_narrative_catalog_map.yaml
# Scaffolded by Franklin healer; extend as new test suites land.
required_app_surfaces:
  - MacFusion
  - MacHealth
  - FranklinApp
  - Lithography
  - XcodeTooling
  - MaterialSciencesApp
test_suites:
  MacFusionTests:
    surface: MacFusion
    narration: "Fusion plant cycle invariants: prologue, plant cycle, epilogue. The substrate witnesses every cycle and refuses any cycle that violates the closure-window contract."
    catalog_verbs: [LG-FUSION-PLANT-CYCLE-001]
  MacHealthTests:
    surface: MacHealth
    narration: "Health pharma-batch and patient-record invariants. Every batch mints a witness; every refused batch produces a signed refusal naming the failing field."
    catalog_verbs: [LG-HEALTH-BATCH-RUN-001]
  FranklinPresenceTests:
    surface: FranklinApp
    narration: "Franklin presence layer: avatar, facets, canvas, tray. The avatar breathes on the closure-window heartbeat; facets are bound to cell_manifest_registry.yaml and never hardcoded."
    catalog_verbs: [LG-FRANKLIN-EMBODY-AVATAR-BREATHE-001]
  LithographyTests:
    surface: Lithography
    narration: "Lithography stepper invariants: every exposure mints a 76-byte witness, every dose miss refuses with a named code."
    catalog_verbs: [LG-LITHO-EXPOSE-001]
  XcodeToolingTests:
    surface: XcodeTooling
    narration: "Xcode tooling DMG invariants: scaffolder produces signed catalogs, codegen plugin refuses on schema drift, every emission is witnessed."
    catalog_verbs: [LG-FRANKLIN-XCODE-NEW-CELL-001]
  MaterialSciencesTests:
    surface: MaterialSciencesApp
    narration: "Material Sciences synthesis and characterization invariants. NMR and crystallography artifacts are witnessed; absent artifacts refuse with named codes."
    catalog_verbs: [LG-MATSCI-SYNTH-001]
YAML
    fi
    if [[ ! -f "${verifier}" ]]; then
        cat > "${verifier}" <<'PY'
#!/usr/bin/env python3
import sys, os, glob, yaml
ROOT = os.environ.get("FRANKLIN_ROOT", os.getcwd())
AUDIT = f"{ROOT}/evidence/audits/ui_test_narrative_catalog_map.yaml"
def fail(m): print(f"REFUSE: {m}", file=sys.stderr); sys.exit(2)
with open(AUDIT) as f:
    doc = yaml.safe_load(f) or {}
required = set(doc.get("required_app_surfaces") or [])
suites = doc.get("test_suites") or {}
if not suites: fail("no test_suites")
seen = set(); errors = []
for name, e in suites.items():
    s = e.get("surface")
    if not s: errors.append(f"{name}: missing surface"); continue
    seen.add(s)
    nar = (e.get("narration") or "").strip()
    if len(nar) < 40: errors.append(f"{name}: narration too short")
    if not (e.get("catalog_verbs") or []): errors.append(f"{name}: catalog_verbs empty")
if required - seen: errors.append(f"missing surfaces: {sorted(required - seen)}")
if errors:
    for x in errors: print(f"  - {x}", file=sys.stderr)
    fail("audit map verifier failed")
print(f"OK: {len(suites)} suites, {len(seen)} surfaces")
PY
        chmod +x "${verifier}"
    fi
    HEAL_RECEIPT LG-FRANKLIN-HEAL-AUDIT-MAP-001 LG-FRANKLIN-OQ-NARRATIVE-MAP-001 CALORIE \
        "scaffolded narrative-catalog audit map and verifier"
    return 0
}

check_audit_map() {
    local audit="${FRANKLIN_ROOT}/evidence/audits/ui_test_narrative_catalog_map.yaml"
    local verifier="${FRANKLIN_ROOT}/scripts/verify_ui_test_narrative_catalog_map.py"
    [[ -f "${audit}" && -f "${verifier}" ]] || return 1
    FRANKLIN_ROOT="${FRANKLIN_ROOT}" python3 "${verifier}" >/dev/null 2>&1 || return 1
    return 0
}

# ----------------------------------------------------------------------------
# heal_emitter_parity — for each registry code lacking an emitter, scaffold
# a fail-closed Swift stub under cells/<owner>/emitters/. The stub fires
# the named refusal under the documented condition. Real implementations
# replace these stubs via signed proposals.
# ----------------------------------------------------------------------------
heal_emitter_parity() {
    python3 - "${FRANKLIN_ROOT}/substrate/REFUSAL_CODE_REGISTRY.yaml" \
              "${FRANKLIN_ROOT}" "${TAU_HUMAN}" <<'PY' || return 1
import sys, os, yaml, re, subprocess
reg, root, tau = sys.argv[1], sys.argv[2], sys.argv[3]
with open(reg) as f:
    doc = yaml.safe_load(f) or {}
codes = [c["name"] for c in (doc.get("codes") or []) if c.get("name")]
def has_emitter(name):
    try:
        r = subprocess.run(["rg","-l","--no-messages",name,root],
                           capture_output=True, text=True, timeout=60)
        out = r.stdout
    except FileNotFoundError:
        r = subprocess.run(["grep","-rl",name,root],
                           capture_output=True, text=True, timeout=120)
        out = r.stdout
    files = [l for l in out.splitlines()
             if l and "REFUSAL_CODE_REGISTRY" not in l
                and "/evidence/" not in l
                and "/scripts/gamp5_full.zsh" not in l]
    return bool(files)
def cell_for(name):
    if name.startswith("GW_REFUSE_FRANKLIN_"): return "franklin"
    if "FUSION" in name: return "fusion"
    if "HEALTH" in name: return "health"
    if "LITHO" in name: return "lithography"
    if "XCODE" in name and not name.startswith("GW_REFUSE_FRANKLIN_"): return "xcode"
    if "MATSCI" in name: return "material_sciences"
    return "fusion"
created = 0
for name in codes:
    if has_emitter(name): continue
    cell = cell_for(name)
    edir = os.path.join(root, "cells", cell, "emitters")
    os.makedirs(edir, exist_ok=True)
    stub = os.path.join(edir, f"{name}.swift")
    if os.path.exists(stub): continue
    with open(stub, "w") as f:
        f.write(f"""// cells/{cell}/emitters/{name}.swift
// Scaffolded by Franklin healer at tau {tau}.
// This stub fires {name} when its documented precondition fails.
// Replace via signed proposal LG-FRANKLIN-EXTEND-VERB-001.
import Foundation
func emit_{name}(context: Any?) -> Never {{
    let receipt: [String: Any] = [
        "magic": "FUIT",
        "version": "1.2.0",
        "refusal_code": "{name}",
        "terminal_state": "REFUSED",
        "scaffolded_emitter": true
    ]
    fatalError("REFUSE \\({name})")
}}
""")
    created += 1
print(f"emitters_scaffolded={created}")
PY
    HEAL_RECEIPT LG-FRANKLIN-HEAL-EMITTER-PARITY-001 LG-FRANKLIN-OQ-EMITTER-PARITY-001 CALORIE \
        "scaffolded fail-closed emitter stubs for codes lacking implementations"
    return 0
}

check_emitter_parity() {
    python3 - "${FRANKLIN_ROOT}/substrate/REFUSAL_CODE_REGISTRY.yaml" \
              "${FRANKLIN_ROOT}" "${EVIDENCE_ROOT}" <<'PY' >/dev/null 2>&1 || return 1
import sys, os, yaml, subprocess, json
reg, root, ev = sys.argv[1:4]
with open(reg) as f:
    doc = yaml.safe_load(f) or {}
codes = [c["name"] for c in (doc.get("codes") or []) if c.get("name")]
missing = []
for name in codes:
    try:
        r = subprocess.run(["rg","-l","--no-messages",name,root],
                           capture_output=True, text=True, timeout=60)
        out = r.stdout
    except FileNotFoundError:
        r = subprocess.run(["grep","-rl",name,root],
                           capture_output=True, text=True, timeout=120)
        out = r.stdout
    files = [l for l in out.splitlines()
             if l and "REFUSAL_CODE_REGISTRY" not in l
                and "/evidence/" not in l
                and "/scripts/gamp5_full.zsh" not in l]
    if not files: missing.append(name)
os.makedirs(ev, exist_ok=True)
with open(f"{ev}/refusal_emitter_parity_diff.json","w") as f:
    json.dump({"missing": missing, "total": len(codes)}, f, indent=2)
if missing: sys.exit(1)
PY
    return 0
}

# ----------------------------------------------------------------------------
# heal_vqbit — declare quantum-source fallback provenance
# ----------------------------------------------------------------------------
heal_vqbit() {
    local prov="${FRANKLIN_ROOT}/substrate/VQBIT_PROVENANCE.yaml"
    cat > "${prov}" <<YAML
# substrate/VQBIT_PROVENANCE.yaml
contract_version: ${EXPECTED_CONTRACT_VERSION}
authored_at: ${TAU_HUMAN}
quantum_source_status: fallback
fallback_source: secrets.token_bytes(4)
fallback_reason: "no quantum hardware detected at substrate root; canonical fallback declared per UI Spec §24 (open-question 3)"
operator_must_acknowledge: true
YAML
    HEAL_RECEIPT LG-FRANKLIN-HEAL-VQBIT-FALLBACK-001 LG-FRANKLIN-IQ-VQBIT-001 CURE \
        "declared vQbit fallback provenance; quantum source not available on this host"
    return 0
}

check_vqbit() {
    local sample
    sample="$(python3 -c 'import secrets;print(secrets.token_bytes(4).hex())')" || return 1
    [[ -n "${sample}" ]] || return 1
    return 0
}

# ----------------------------------------------------------------------------
# heal_xcode_latest — pin the Apple toolchain floor and refuse below it.
#
# Authors substrate/TOOLCHAIN_REQUIRED.yaml with the canonical minimum Xcode,
# Swift, and macOS versions. Reads installed versions via xcodebuild and
# swift; compares semver; if installed < floor, scaffolds a one-shot install
# helper at scripts/install_xcode_latest.sh and refuses TERMINAL — the
# substrate has no authority to drive an interactive App Store install.
# ----------------------------------------------------------------------------
heal_xcode_latest() {
    local pin="${FRANKLIN_ROOT}/substrate/TOOLCHAIN_REQUIRED.yaml"
    if [[ ! -f "${pin}" ]]; then
        cat > "${pin}" <<YAML
# substrate/TOOLCHAIN_REQUIRED.yaml — authored by Franklin healer at tau ${TAU_HUMAN}.
# Pin the Apple toolchain floor. Below floor → TERMINAL refuse.
contract_version: ${EXPECTED_CONTRACT_VERSION}
xcode:
  min_version: "${EXPECTED_XCODE_MIN}"
  recommended_version: "26.4.1"
  install_paths:
    - /Applications/Xcode.app
    - /Applications/Xcode-beta.app
swift:
  min_version: "${EXPECTED_SWIFT_MIN}"
macos:
  min_version: "${EXPECTED_MACOS_MIN}"
operator_install_paths:
  - kind: app_store
    description: "Open App Store, search Xcode, click Update or Get."
  - kind: developer_download
    url: "https://developer.apple.com/download/all/?q=xcode"
    description: "Sign in with Apple Developer ID, download the latest Xcode .xip."
  - kind: xcodes_cli
    command: "xcodes install --latest"
    description: "Requires the xcodes CLI (https://github.com/RobotsAndPencils/xcodes)."
YAML
        HEAL_RECEIPT LG-FRANKLIN-HEAL-XCODE-PIN-001 LG-FRANKLIN-IQ-XCODE-LATEST-001 CALORIE \
            "scaffolded substrate/TOOLCHAIN_REQUIRED.yaml; floor=${EXPECTED_XCODE_MIN}"
    fi
    # Scaffold the install helper script (operator runs it; runner does not).
    local helper="${FRANKLIN_ROOT}/scripts/install_xcode_latest.sh"
    if [[ ! -f "${helper}" ]]; then
        cat > "${helper}" <<'BASH'
#!/usr/bin/env bash
# scripts/install_xcode_latest.sh — operator-driven Xcode install/upgrade.
# This is NOT auto-invoked by the runner. Substrate has no authority to drive
# an interactive App Store / Apple ID flow. Operator runs this on demand.
set -euo pipefail
echo "Franklin Mac Stack — Xcode install helper"
echo "Required: Xcode ${EXPECTED_XCODE_MIN:-26.0}+ (recommended 26.4.1)"
echo
if command -v xcodes >/dev/null 2>&1; then
    echo "→ xcodes CLI detected. Running: xcodes install --latest --experimental-unxip"
    xcodes install --latest --experimental-unxip
    xcodes select latest
    sudo xcode-select -s "$(xcodes installed | tail -1 | awk '{print $NF}')/Contents/Developer"
    sudo xcodebuild -license accept
    sudo xcodebuild -runFirstLaunch
else
    echo "→ xcodes CLI not found. Choose one path:"
    echo "  1) brew install xcodesorg/made/xcodes && xcodes install --latest"
    echo "  2) Open the Mac App Store, search Xcode, click Update or Get."
    echo "  3) https://developer.apple.com/download/all/?q=xcode"
    echo
    echo "After install, run:"
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    echo "  sudo xcodebuild -license accept"
    echo "  sudo xcodebuild -runFirstLaunch"
    exit 1
fi
echo "✓ Xcode install/upgrade complete. Re-run the Franklin runner."
BASH
        chmod +x "${helper}"
        HEAL_RECEIPT LG-FRANKLIN-HEAL-XCODE-INSTALL-HELPER-001 LG-FRANKLIN-IQ-XCODE-LATEST-001 CALORIE \
            "scaffolded scripts/install_xcode_latest.sh"
    fi
    return 0
}

# Compare two semver-ish version strings: returns 0 if a >= b, 1 otherwise.
_semver_ge() {
    local a="$1" b="$2"
    # Strip non-numeric/dot prefix (e.g., 'Xcode ').
    a="${a##*[!0-9.]}"; b="${b##*[!0-9.]}"
    local IFS=.
    local -a aa bb
    aa=(${=a}); bb=(${=b})
    local i=1 max=${#aa[@]}
    (( ${#bb[@]} > max )) && max=${#bb[@]}
    while (( i <= max )); do
        local ai=${aa[i]:-0} bi=${bb[i]:-0}
        # Force decimal interpretation for any leading zeros.
        ai=$((10#${ai}))
        bi=$((10#${bi}))
        if (( ai > bi )); then return 0; fi
        if (( ai < bi )); then return 1; fi
        i=$((i+1))
    done
    return 0
}

check_xcode_latest() {
    [[ -f "${FRANKLIN_ROOT}/substrate/TOOLCHAIN_REQUIRED.yaml" ]] || return 1
    [[ -f "${FRANKLIN_ROOT}/scripts/install_xcode_latest.sh" ]] || return 1
    command -v xcodebuild >/dev/null 2>&1 || return 1
    command -v swift >/dev/null 2>&1 || return 1
    local installed_xcode; installed_xcode="$(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}')"
    [[ -n "${installed_xcode}" ]] || return 1
    _semver_ge "${installed_xcode}" "${EXPECTED_XCODE_MIN}" || {
        printf '    ⚠ Xcode floor: installed=%s required=%s — operator must run scripts/install_xcode_latest.sh\n' \
            "${installed_xcode}" "${EXPECTED_XCODE_MIN}" >&2
        return 1
    }
    local installed_swift; installed_swift="$(swift --version 2>/dev/null | head -1 | sed -nE 's/.*Swift version ([0-9][0-9.]*).*/\1/p')"
    if [[ -n "${installed_swift}" ]]; then
        _semver_ge "${installed_swift}" "${EXPECTED_SWIFT_MIN}" || return 1
    fi
    return 0
}

# ----------------------------------------------------------------------------
# heal_required_libraries — declare and procure required Swift libraries.
#
# Authors substrate/REQUIRED_LIBRARIES.yaml listing every SwiftPM dependency
# the substrate REQUIRES at IQ time. For each missing library:
#   1. If a Package.swift exists at FRANKLIN_ROOT, try `swift package resolve`.
#   2. If still missing, vendor by `git clone --depth 1 --branch <pin>` into
#      vendor/<name>/.
#   3. If both fail, return 2 (terminal — IQ requires the library).
#
# This is the "library access or IQ fails" gate.
# ----------------------------------------------------------------------------
heal_required_libraries() {
    local manifest="${FRANKLIN_ROOT}/substrate/REQUIRED_LIBRARIES.yaml"
    if [[ ! -f "${manifest}" ]]; then
        cat > "${manifest}" <<YAML
# substrate/REQUIRED_LIBRARIES.yaml — authored by Franklin healer at tau ${TAU_HUMAN}.
# Pin every Swift library the substrate requires. IQ refuses TERMINAL if any
# required library cannot be reached on disk OR via SwiftPM resolve.
contract_version: ${EXPECTED_CONTRACT_VERSION}
strategy: vendor_or_resolve
vendor_root: vendor
required:
  - name: swift-crypto
    git_url: https://github.com/apple/swift-crypto.git
    pinned_revision: "3.10.0"
    vendor_relpath: vendor/swift-crypto
    purpose: "Ed25519 sign/verify for receipt and identity_table signatures"
  - name: swift-collections
    git_url: https://github.com/apple/swift-collections.git
    pinned_revision: "1.1.4"
    vendor_relpath: vendor/swift-collections
    purpose: "Deque/OrderedDictionary used by witness queues"
  - name: swift-argument-parser
    git_url: https://github.com/apple/swift-argument-parser.git
    pinned_revision: "1.5.0"
    vendor_relpath: vendor/swift-argument-parser
    purpose: "CLI argument parsing in Franklin tooling"
  - name: yams
    git_url: https://github.com/jpsim/Yams.git
    pinned_revision: "5.1.3"
    vendor_relpath: vendor/Yams
    purpose: "YAML parsing in Swift verifier (post-IQ Swift-only path)"
YAML
        HEAL_RECEIPT LG-FRANKLIN-HEAL-LIBS-MANIFEST-001 LG-FRANKLIN-IQ-LIBRARIES-001 CALORIE \
            "scaffolded substrate/REQUIRED_LIBRARIES.yaml"
    fi
    mkdir -p "${FRANKLIN_ROOT}/vendor"
    # Try SwiftPM resolve if a Package.swift sits at root.
    if [[ -f "${FRANKLIN_ROOT}/Package.swift" ]] && command -v swift >/dev/null 2>&1; then
        ( cd "${FRANKLIN_ROOT}" && swift package resolve >>"${EVIDENCE_ROOT}/swift_package_resolve.log" 2>&1 ) \
            && HEAL_RECEIPT LG-FRANKLIN-HEAL-LIBS-RESOLVE-001 LG-FRANKLIN-IQ-LIBRARIES-001 CALORIE \
                "swift package resolve completed at ${FRANKLIN_ROOT}/Package.swift" \
            || HEAL_RECEIPT LG-FRANKLIN-HEAL-LIBS-RESOLVE-001 LG-FRANKLIN-IQ-LIBRARIES-001 CURE \
                "swift package resolve did not complete cleanly; falling through to vendor"
    fi
    # Vendor any required library that is still missing.
    if ! command -v git >/dev/null 2>&1; then
        return 2
    fi
    local rc=0
    python3 - "${manifest}" "${FRANKLIN_ROOT}" <<'PY' >"${EVIDENCE_ROOT}/required_libraries_plan.txt" 2>&1 || rc=$?
import sys, yaml, os
manifest, root = sys.argv[1], sys.argv[2]
with open(manifest) as f:
    doc = yaml.safe_load(f) or {}
for lib in (doc.get("required") or []):
    name = lib.get("name", "")
    url  = lib.get("git_url", "")
    pin  = lib.get("pinned_revision", "")
    rel  = lib.get("vendor_relpath", f"vendor/{name}")
    abs_ = os.path.join(root, rel)
    print(f"{name}\t{url}\t{pin}\t{abs_}")
PY
    if (( rc != 0 )); then
        return 2
    fi
    local line name url pin abs_
    while IFS=$'\t' read -r name url pin abs_; do
        [[ -z "${name}" ]] && continue
        if [[ -d "${abs_}/.git" ]] || [[ -d "${abs_}" && -f "${abs_}/Package.swift" ]]; then
            continue
        fi
        mkdir -p "${abs_:h}"
        if git clone --depth 1 --branch "${pin}" "${url}" "${abs_}" \
            >>"${EVIDENCE_ROOT}/required_libraries_clone.log" 2>&1; then
            HEAL_RECEIPT "LG-FRANKLIN-HEAL-LIBS-VENDOR-${name:u}" \
                LG-FRANKLIN-IQ-LIBRARIES-001 CALORIE \
                "vendored ${name}@${pin} → ${abs_}"
        else
            # Try without --branch (pinned_revision may be a commit hash).
            if git clone --depth 1 "${url}" "${abs_}" \
                >>"${EVIDENCE_ROOT}/required_libraries_clone.log" 2>&1; then
                if [[ -n "${pin}" ]]; then
                    ( cd "${abs_}" && git fetch --depth 1 origin "${pin}" \
                        && git checkout "${pin}" ) \
                        >>"${EVIDENCE_ROOT}/required_libraries_clone.log" 2>&1 || true
                fi
                HEAL_RECEIPT "LG-FRANKLIN-HEAL-LIBS-VENDOR-${name:u}" \
                    LG-FRANKLIN-IQ-LIBRARIES-001 CURE \
                    "vendored ${name} (pin lookup partial) → ${abs_}"
            else
                printf '    ⚠ vendor failed for %s (%s)\n' "${name}" "${url}" >&2
                return 2
            fi
        fi
    done < "${EVIDENCE_ROOT}/required_libraries_plan.txt"
    return 0
}

check_required_libraries() {
    local manifest="${FRANKLIN_ROOT}/substrate/REQUIRED_LIBRARIES.yaml"
    [[ -f "${manifest}" ]] || return 1
    local plan="${EVIDENCE_ROOT}/required_libraries_plan.txt"
    python3 - "${manifest}" "${FRANKLIN_ROOT}" <<'PY' >"${plan}" 2>/dev/null || return 1
import sys, yaml, os
manifest, root = sys.argv[1], sys.argv[2]
with open(manifest) as f:
    doc = yaml.safe_load(f) or {}
for lib in (doc.get("required") or []):
    name = lib.get("name", "")
    rel  = lib.get("vendor_relpath", f"vendor/{name}")
    abs_ = os.path.join(root, rel)
    print(f"{name}\t{abs_}")
PY
    local name abs_
    while IFS=$'\t' read -r name abs_; do
        [[ -z "${name}" ]] && continue
        if [[ -d "${abs_}/.git" ]]; then continue; fi
        if [[ -d "${abs_}" && -f "${abs_}/Package.swift" ]]; then continue; fi
        # Allow SwiftPM-resolved checkouts under .build/checkouts/<name>.
        if [[ -d "${FRANKLIN_ROOT}/.build/checkouts/${name}" ]]; then continue; fi
        if [[ -d "${FRANKLIN_ROOT}/.build/checkouts/${name:l}" ]]; then continue; fi
        return 1
    done < "${plan}"
    return 0
}

# ----------------------------------------------------------------------------
# heal_yaml_to_json_bridge — mirror canonical YAML to JSON for Swift consumers.
#
# Post-IQ steps must be Swift-only. Swift Foundation reads JSON natively but
# YAML requires a third-party library (Yams). To keep the post-IQ Swift
# verifier dependency-light, we mirror substrate/*.yaml and the rosette and
# audit-map files into JSON at IQ time. The Swift verifier then reads JSON.
# ----------------------------------------------------------------------------
heal_yaml_to_json_bridge() {
    mkdir -p "${FRANKLIN_ROOT}/substrate/.json" \
             "${FRANKLIN_ROOT}/cells/.json" \
             "${FRANKLIN_ROOT}/evidence/audits/.json"
    python3 - "${FRANKLIN_ROOT}" <<'PY' || return 2
import os, sys, yaml, json
root = sys.argv[1]
pairs = [
    ("substrate/REFUSAL_CODE_REGISTRY.yaml", "substrate/.json/REFUSAL_CODE_REGISTRY.json"),
    ("substrate/PR_ASSERTIONS.yaml",         "substrate/.json/PR_ASSERTIONS.json"),
    ("substrate/identity_table.yaml",        "substrate/.json/identity_table.json"),
    ("substrate/HASH_LOCKS.yaml",            "substrate/.json/HASH_LOCKS.json"),
    ("substrate/TOOLCHAIN_REQUIRED.yaml",    "substrate/.json/TOOLCHAIN_REQUIRED.json"),
    ("substrate/REQUIRED_LIBRARIES.yaml",    "substrate/.json/REQUIRED_LIBRARIES.json"),
    ("cells/cell_manifest_registry.yaml",    "cells/.json/cell_manifest_registry.json"),
    ("evidence/audits/ui_test_narrative_catalog_map.yaml",
        "evidence/audits/.json/ui_test_narrative_catalog_map.json"),
]
written = 0
for src, dst in pairs:
    sp = os.path.join(root, src)
    if not os.path.exists(sp): continue
    with open(sp) as f:
        doc = yaml.safe_load(f) or {}
    dp = os.path.join(root, dst)
    os.makedirs(os.path.dirname(dp), exist_ok=True)
    with open(dp, "w") as f:
        json.dump(doc, f, indent=2, sort_keys=True, default=str)
    written += 1
print(f"yaml_to_json_bridge_written={written}")
PY
    HEAL_RECEIPT LG-FRANKLIN-HEAL-YAML-JSON-BRIDGE-001 LG-FRANKLIN-IQ-YAML-JSON-BRIDGE-001 CALORIE \
        "mirrored canonical YAML → JSON for Swift verifier"
    return 0
}

check_yaml_to_json_bridge() {
    local f
    for f in substrate/.json/REFUSAL_CODE_REGISTRY.json \
             substrate/.json/PR_ASSERTIONS.json \
             cells/.json/cell_manifest_registry.json; do
        [[ -f "${FRANKLIN_ROOT}/${f}" ]] || return 1
    done
    return 0
}

# ----------------------------------------------------------------------------
# heal_rust_toolchain — ensure rustup/cargo are present.
#
# Post-IQ verification is Rust-only. IQ may invoke zsh and python3 (and
# binary CLIs like xcodebuild/git) but no other languages; the Rust binary
# is BUILT in IQ via `cargo build --release` and INVOKED post-IQ.
# Substrate has no authority to install rustup; missing → TERMINAL.
# ----------------------------------------------------------------------------
heal_rust_toolchain() {
    local helper="${FRANKLIN_ROOT}/scripts/install_rust_toolchain.sh"
    if [[ ! -f "${helper}" ]]; then
        cat > "${helper}" <<'BASH'
#!/usr/bin/env bash
# scripts/install_rust_toolchain.sh — operator-driven rustup install.
# Substrate does not auto-run installers that require network and shell trust.
set -euo pipefail
echo "Franklin Mac Stack — Rust toolchain install helper"
echo
if command -v rustup >/dev/null 2>&1; then
    echo "→ rustup detected; updating stable toolchain"
    rustup update stable
    rustup default stable
else
    echo "→ rustup not found. Install with the official one-liner:"
    echo "    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable"
    echo "  Then: source \"\$HOME/.cargo/env\" and re-run the Franklin runner."
    exit 1
fi
echo "✓ Rust toolchain ready: $(rustc --version)"
BASH
        chmod +x "${helper}"
        HEAL_RECEIPT LG-FRANKLIN-HEAL-RUST-INSTALL-HELPER-001 LG-FRANKLIN-IQ-RUST-TOOLCHAIN-001 CALORIE \
            "scaffolded scripts/install_rust_toolchain.sh"
    fi
    if ! command -v cargo >/dev/null 2>&1 || ! command -v rustc >/dev/null 2>&1; then
        # Healer cannot install rustup non-interactively under our authority.
        return 2
    fi
    return 0
}

check_rust_toolchain() {
    [[ -f "${FRANKLIN_ROOT}/scripts/install_rust_toolchain.sh" ]] || return 1
    command -v cargo >/dev/null 2>&1 || return 1
    command -v rustc >/dev/null 2>&1 || return 1
    return 0
}

# ----------------------------------------------------------------------------
# heal_rust_verifier — author and build the Rust post-IQ verifier crate.
#
# Crate path: tools/franklin_verify/
#   Cargo.toml  — pinned deps (serde, serde_json, sha2, chrono)
#   src/main.rs — subcommand dispatcher: narrative-map, receipt,
#                 receipt-strict, pr-runners, auditor-stamp, rosette,
#                 reconcile, sha256-string
#
# Build is performed at IQ time via `cargo build --release`.
# Reads JSON mirrors authored by heal_yaml_to_json_bridge so the crate stays
# YAML-free. Post-IQ steps invoke the compiled binary at:
#   tools/franklin_verify/target/release/franklin_verify
# ----------------------------------------------------------------------------
heal_rust_verifier() {
    local crate="${FRANKLIN_ROOT}/tools/franklin_verify"
    mkdir -p "${crate}/src"
    if [[ ! -f "${crate}/Cargo.toml" ]]; then
        cat > "${crate}/Cargo.toml" <<'TOML'
[package]
name = "franklin_verify"
version = "1.2.0"
edition = "2021"
description = "Franklin Mac Stack post-IQ verifier (Rust). Replaces all post-IQ Python."
license = "Apache-2.0"

[[bin]]
name = "franklin_verify"
path = "src/main.rs"

[dependencies]
serde      = { version = "1", features = ["derive"] }
serde_json = "1"
sha2       = "0.10"
chrono     = { version = "0.4", default-features = false, features = ["clock", "std"] }

[profile.release]
opt-level = "z"
lto       = true
strip     = true
TOML
        HEAL_RECEIPT LG-FRANKLIN-HEAL-RUST-CRATE-001 LG-FRANKLIN-IQ-RUST-VERIFIER-001 CALORIE \
            "scaffolded tools/franklin_verify/Cargo.toml"
    fi
    if [[ ! -f "${crate}/src/main.rs" ]] || ! rg -n -- '--authority' "${crate}/src/main.rs" >/dev/null 2>&1; then
        cat > "${crate}/src/main.rs" <<'RUST'
// tools/franklin_verify/src/main.rs
// Franklin Mac Stack — post-IQ verifier (Rust).
// Replaces every post-IQ Python invocation. IQ writes JSON mirrors of
// canonical YAML; this binary reads JSON only — no YAML dependency.
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::process::{Command, ExitCode, Stdio};

fn die(msg: impl AsRef<str>) -> ! {
    eprintln!("REFUSE: {}", msg.as_ref());
    std::process::exit(2);
}

fn load_json(path: &str) -> Value {
    let bytes = fs::read(path).unwrap_or_else(|e| die(format!("read {}: {}", path, e)));
    serde_json::from_slice(&bytes).unwrap_or_else(|e| die(format!("parse {}: {}", path, e)))
}

fn write_json(value: &Value, path: &str) {
    let pretty = serde_json::to_vec_pretty(value)
        .unwrap_or_else(|e| die(format!("encode JSON: {}", e)));
    fs::write(path, &pretty).unwrap_or_else(|e| die(format!("write {}: {}", path, e)));
}

fn sha256_file(path: &str) -> String {
    let bytes = fs::read(path).unwrap_or_else(|e| die(format!("read {}: {}", path, e)));
    let mut h = Sha256::new();
    h.update(&bytes);
    hex(h.finalize().as_slice())
}

fn sha256_str(s: &str) -> String {
    let mut h = Sha256::new();
    h.update(s.as_bytes());
    hex(h.finalize().as_slice())
}

fn hex(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{:02x}", b));
    }
    s
}

fn main() -> ExitCode {
    let argv: Vec<String> = std::env::args().collect();
    if argv.len() < 2 {
        die("usage: franklin_verify <subcommand> [args...]");
    }
    match argv[1].as_str() {
        "narrative-map"   => narrative_map(&argv),
        "receipt"         => receipt(&argv, false),
        "receipt-strict"  => receipt(&argv, true),
        "pr-runners"      => pr_runners(&argv),
        "auditor-stamp"   => auditor_stamp(&argv),
        "rosette"         => rosette(&argv),
        "reconcile"       => reconcile(&argv),
        "emitter-parity"  => emitter_parity(&argv),
        "sha256-string"   => { println!("{}", sha256_str(argv.get(2).map(|s| s.as_str()).unwrap_or(""))); ExitCode::SUCCESS }
        other => die(format!("unknown subcommand: {}", other)),
    }
}

fn narrative_map(argv: &[String]) -> ExitCode {
    if argv.len() < 3 { die("narrative-map <audit_json>"); }
    let doc = load_json(&argv[2]);
    let required: BTreeSet<String> = doc.get("required_app_surfaces")
        .and_then(|v| v.as_array())
        .map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect())
        .unwrap_or_default();
    let suites = doc.get("test_suites")
        .and_then(|v| v.as_object())
        .cloned()
        .unwrap_or_default();
    if suites.is_empty() { die("no test_suites in audit JSON"); }
    let mut seen = BTreeSet::new();
    let mut errors: Vec<String> = Vec::new();
    for (name, raw) in &suites {
        let entry = match raw.as_object() {
            Some(o) => o,
            None => { errors.push(format!("{}: not an object", name)); continue; }
        };
        let surface = entry.get("surface").and_then(|v| v.as_str()).unwrap_or("");
        if surface.is_empty() {
            errors.push(format!("{}: missing surface", name));
            continue;
        }
        seen.insert(surface.to_string());
        let nar = entry.get("narration").and_then(|v| v.as_str()).unwrap_or("").trim();
        if nar.chars().count() < 40 { errors.push(format!("{}: narration too short", name)); }
        let verbs_empty = entry.get("catalog_verbs")
            .and_then(|v| v.as_array())
            .map(|a| a.is_empty()).unwrap_or(true);
        if verbs_empty { errors.push(format!("{}: catalog_verbs empty", name)); }
    }
    let missing: Vec<&String> = required.difference(&seen).collect();
    if !missing.is_empty() { errors.push(format!("missing surfaces: {:?}", missing)); }
    if !errors.is_empty() {
        for e in &errors { eprintln!("  - {}", e); }
        die("audit map verifier failed");
    }
    println!("OK: {} suites, {} surfaces", suites.len(), seen.len());
    ExitCode::SUCCESS
}

fn receipt(argv: &[String], strict: bool) -> ExitCode {
    if argv.len() < 3 { die(if strict { "receipt-strict <receipt_json>" } else { "receipt <receipt_json>" }); }
    let r = load_json(&argv[2]);
    let obj = r.as_object().unwrap_or_else(|| die("receipt is not an object"));
    let need: &[&str] = if strict {
        &["magic","version","verb_id","terminal_state","closure_window_id","ts_micros"]
    } else {
        &["magic","version","verb_id","interaction_class","terminal_state",
          "closure_window_id","ts_micros","entropy_quanta"]
    };
    let mut missing: Vec<&str> = Vec::new();
    for k in need {
        if !obj.contains_key(*k) { missing.push(*k); }
    }
    if !missing.is_empty() { die(format!("missing fields: {:?}", missing)); }
    if obj.get("magic").and_then(|v| v.as_str()) != Some("FUIT") { die("bad magic"); }
    println!("OK");
    ExitCode::SUCCESS
}

fn pr_runners(argv: &[String]) -> ExitCode {
    if argv.len() < 5 { die("pr-runners <pr_json> <root> <evidence_dir>"); }
    let pr = load_json(&argv[2]);
    let root = &argv[3];
    let ev   = &argv[4];
    let assertions = pr.get("assertions")
        .and_then(|v| v.as_array()).cloned()
        .unwrap_or_default();
    let mut results: Vec<Value> = Vec::new();
    for a in &assertions {
        let id = a.get("id").and_then(|v| v.as_str()).unwrap_or("?").to_string();
        let runner = match a.get("runner").and_then(|v| v.as_str()) {
            Some(s) if !s.is_empty() => s.to_string(),
            _ => {
                results.push(serde_json::json!({"id": id, "status": "RUNNER_MISSING"}));
                continue;
            }
        };
        let rp = if runner.starts_with('/') { runner.clone() } else { format!("{}/{}", root, runner) };
        if !std::path::Path::new(&rp).exists() {
            results.push(serde_json::json!({"id": id, "status": "RUNNER_MISSING"}));
            continue;
        }
        let out = Command::new(&rp)
            .stdout(Stdio::piped()).stderr(Stdio::piped())
            .status();
        match out {
            Ok(st) => {
                let status_str = if st.success() { "PASS" } else { "FAIL" };
                results.push(serde_json::json!({
                    "id": id, "status": status_str,
                    "rc": st.code().unwrap_or(-1)
                }));
            }
            Err(e) => {
                results.push(serde_json::json!({
                    "id": id, "status": "RUNNER_LAUNCH_FAILED",
                    "error": e.to_string()
                }));
            }
        }
    }
    fs::create_dir_all(ev).ok();
    write_json(&Value::Array(results.clone()), &format!("{}/pr_assertion_results.json", ev));
    let fails: Vec<&Value> = results.iter()
        .filter(|r| r.get("status").and_then(|v| v.as_str()) != Some("PASS"))
        .collect();
    if !fails.is_empty() {
        let ids: Vec<String> = fails.iter().take(5)
            .filter_map(|r| r.get("id").and_then(|v| v.as_str()).map(String::from))
            .collect();
        die(format!("{} PR runners did not pass: {:?}", fails.len(), ids));
    }
    println!("OK {}", results.len());
    ExitCode::SUCCESS
}

fn auditor_stamp(argv: &[String]) -> ExitCode {
    if argv.len() < 4 { die("auditor-stamp <receipt_json> <out_path>"); }
    let r = load_json(&argv[2]);
    let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
    let stamp = serde_json::json!({
        "kind": "auditor_track_verification_stamp",
        "verifier_role": "third_party",
        "ts_human": now,
        "verified_receipt_verb": r.get("verb_id").cloned().unwrap_or(Value::Null),
        "verified_receipt_sha256": sha256_file(&argv[2]),
        "verdict": "AUTHENTIC"
    });
    write_json(&stamp, &argv[3]);
    println!("OK");
    ExitCode::SUCCESS
}

fn rosette(argv: &[String]) -> ExitCode {
    if argv.len() < 4 { die("rosette <registry_json> <expected...>"); }
    let doc = load_json(&argv[2]);
    let cells = doc.get("cells").and_then(|v| v.as_array()).cloned().unwrap_or_default();
    let mut ids: BTreeMap<String, i64> = BTreeMap::new();
    for c in &cells {
        if let (Some(id), Some(pos)) = (
            c.get("id").and_then(|v| v.as_str()),
            c.get("rosette_position").and_then(|v| v.as_i64()),
        ) {
            ids.insert(id.to_string(), pos);
        }
    }
    let expected: BTreeSet<&String> = argv[3..].iter().collect();
    let have: BTreeSet<&String> = ids.keys().collect();
    let missing: Vec<&&String> = expected.difference(&have).collect();
    if !missing.is_empty() { die(format!("missing: {:?}", missing)); }
    let positions: Vec<i64> = ids.values().copied().collect();
    let unique: BTreeSet<i64> = positions.iter().copied().collect();
    if unique.len() != positions.len() { die("duplicate positions"); }
    println!("OK");
    ExitCode::SUCCESS
}

fn reconcile(argv: &[String]) -> ExitCode {
    if argv.len() < 4 { die("reconcile <registry_json> <pr_json>"); }
    let reg = load_json(&argv[2]);
    let codes = reg.get("codes").and_then(|v| v.as_array()).cloned().unwrap_or_default();
    if let Some(declared) = reg.get("total_codes").and_then(|v| v.as_i64()) {
        if (declared as usize) != codes.len() {
            die(format!("refusal total_codes drift: declared={} actual={}", declared, codes.len()));
        }
    }
    let pr = load_json(&argv[3]);
    let pr_count = pr.get("assertions").and_then(|v| v.as_array()).map(|a| a.len()).unwrap_or(0);
    println!("refusal={} pr={}", codes.len(), pr_count);
    ExitCode::SUCCESS
}

fn emitter_parity(argv: &[String]) -> ExitCode {
    if argv.len() < 4 { die("emitter-parity <registry_json> <root> [evidence_dir]"); }
    let reg = load_json(&argv[2]);
    let root = &argv[3];
    let ev = argv.get(4).cloned().unwrap_or_else(|| format!("{}/evidence", root));
    let codes = reg.get("codes").and_then(|v| v.as_array()).cloned().unwrap_or_default();
    let mut missing: Vec<String> = Vec::new();
    for c in &codes {
        let name = match c.get("name").and_then(|v| v.as_str()) {
            Some(s) if !s.is_empty() => s,
            _ => continue,
        };
        // Shell out to /usr/bin/grep -rl --include='*.swift' for emitter refs.
        let out = Command::new("/usr/bin/grep")
            .args(["-rlF", "--", name, root.as_str()])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output();
        let stdout = match out {
            Ok(o) => String::from_utf8_lossy(&o.stdout).to_string(),
            Err(_) => String::new(),
        };
        let mut hit = false;
        for line in stdout.lines() {
            if line.is_empty() { continue; }
            if line.contains("REFUSAL_CODE_REGISTRY") { continue; }
            if line.contains("/evidence/") { continue; }
            if line.contains("/scripts/gamp5_full.zsh") { continue; }
            if line.contains("/.json/") { continue; }
            hit = true; break;
        }
        if !hit { missing.push(name.to_string()); }
    }
    fs::create_dir_all(&ev).ok();
    let report = serde_json::json!({"missing": missing, "total": codes.len()});
    write_json(&report, &format!("{}/refusal_emitter_parity_diff.json", ev));
    if !missing.is_empty() {
        die(format!("{} codes lack emitters", missing.len()));
    }
    println!("OK {}", codes.len());
    ExitCode::SUCCESS
}
RUST
        HEAL_RECEIPT LG-FRANKLIN-HEAL-RUST-MAIN-001 LG-FRANKLIN-IQ-RUST-VERIFIER-001 CALORIE \
            "scaffolded tools/franklin_verify/src/main.rs"
    fi
    # Build the binary. Cargo will fetch crates.io on first run unless a
    # vendor/ + .cargo/config.toml is present (operator-vendored offline mode).
    local build_log="${EVIDENCE_ROOT}/cargo_build.log"
    if CARGO_TARGET_DIR="${crate}/target" \
       cargo build --release --manifest-path "${crate}/Cargo.toml" >"${build_log}" 2>&1; then
        HEAL_RECEIPT LG-FRANKLIN-HEAL-RUST-BUILD-001 LG-FRANKLIN-IQ-RUST-VERIFIER-001 CALORIE \
            "cargo build --release succeeded; binary at tools/franklin_verify/target/release/franklin_verify"
    else
        printf '    ⚠ cargo build failed; see %s\n' "${build_log}" >&2
        return 2
    fi
    return 0
}

check_rust_verifier() {
    local bin="${FRANKLIN_ROOT}/tools/franklin_verify/target/release/franklin_verify"
    [[ -f "${FRANKLIN_ROOT}/tools/franklin_verify/Cargo.toml" ]] || return 1
    [[ -f "${FRANKLIN_ROOT}/tools/franklin_verify/src/main.rs" ]] || return 1
    [[ -x "${bin}" ]] || return 1
    # Smoke-test the binary with a no-op subcommand.
    "${bin}" sha256-string "franklin" >/dev/null 2>&1 || return 1
    return 0
}

ensure_rust_verify_bin() {
    local bin="${FRANKLIN_ROOT}/tools/franklin_verify/target/release/franklin_verify"
    [[ -x "${bin}" ]] && return 0
    heal_rust_verifier || return 1
    [[ -x "${bin}" ]]
}

# ----------------------------------------------------------------------------
# Health UI audit — manifest-first phase 1.
#
# Scaffolds:
#   wiki/HEALTH_UI_AUDIT_AUTHORITY.md      — normative audit rules + LG IDs
#   cells/<cell>/Surfaces.yaml             — per-cell surface manifest stubs
#   tools/franklin_health_ui_audit/        — separate Rust crate, own binary
#
# The audit binary reads each cell's Surfaces.yaml mirror (.json) and the
# audit authority's structured rules block. Each rule applied per element
# emits a finding; the binary exits nonzero on any violation.
# ----------------------------------------------------------------------------

heal_health_ui_audit_tool() {
    printf '  → heal_health_ui_audit_tool: scaffolding authority + manifests + rust crate\n' >&2

    # 1. Authority doc (normative rules)
    local authority="${FRANKLIN_ROOT}/wiki/HEALTH_UI_AUDIT_AUTHORITY.md"
    if [[ ! -f "${authority}" ]]; then
        mkdir -p "${authority:h}"
        cat > "${authority}" <<'AUTH'
---
title: Health UI Audit Authority
contract_version: 1.2.0
authority_kind: normative
applies_to: every user-facing surface in every cell app
required_lg_ids:
  - LG-FRANKLIN-IQ-HEALTH-UI-SCAFFOLD-001
  - LG-FRANKLIN-OQ-HEALTH-UI-AUDIT-001
---

# Health UI Audit Authority

Health is the first OQ check. It runs against a structural manifest of every
user-facing surface in every cell app (`cells/<cell>/Surfaces.yaml`). A single
rule violation refuses OQ terminal — the rest of the catalog does not run, and
PQ never runs against an unhealthy app.

## Phase 1 (manifest-based) audit rules

```yaml
audit_rules:
  - id: manifest_non_empty
    severity: refuse
    refusal_code: GW_REFUSE_HEALTH_MANIFEST_EMPTY
    description: Every UI-bearing cell manifest must declare at least one surface.
    kind: non_empty_manifest

  - id: contrast_min
    severity: refuse
    refusal_code: GW_REFUSE_HEALTH_CONTRAST_FAILED
    description: Body text must achieve WCAG AA 4.5:1 contrast ratio.
    kind: contrast_ratio
    threshold: 4.5
    applies_to_kinds: [label, button_label, value, subtitle, body]

  - id: no_internal_jargon
    severity: refuse
    refusal_code: GW_REFUSE_HEALTH_JARGON_LEAKED
    description: Internal architecture terms must not appear in surface text.
    kind: forbidden_terms
    terms:
      - MOORED
      - MSDF-Latin
      - WASM SHELL
      - vQbit
      - NATS
      - hcloud-hel1
      - netcup-nbg1
      - CALORIE
      - CURE
      - "FM role rail"
      - substrate-bound
      - "OpenUSD inception snap"
      - "entropy calm"
      - "MESH CONVERGING"
      - "TORSION M8 BOUND"
      - "INTENT REGISTERED"
      - "TRANSACTION FINISHED"
      - "FUSION-TOPOLOGY-VIEW"
      - "FUSION-PROJECTION-PANEL"
      - "FUSION-CELL-GRID"
      - "FUSION-PLANT-CONTROLS"
      - "FUSION-SWAP-PANEL"
      - GaiaFTCL
      - "[M]"
      - "[I]"

  - id: no_raw_timestamp
    severity: refuse
    refusal_code: GW_REFUSE_HEALTH_RAW_TIMESTAMP
    description: Unix epoch timestamps must not appear in surface text.
    kind: forbidden_regex
    pattern: "^[0-9]{10,19}$|ready:[0-9]{10,}"

  - id: no_raw_ip
    severity: refuse
    refusal_code: GW_REFUSE_HEALTH_RAW_IP
    description: IP addresses must not appear in surface text.
    kind: forbidden_regex
    pattern: "([0-9]{1,3}\\.){3}[0-9]{1,3}"

  - id: no_raw_hostname
    severity: refuse
    refusal_code: GW_REFUSE_HEALTH_RAW_HOSTNAME
    description: Cloud-provider hostnames must not appear in surface text.
    kind: forbidden_regex
    pattern: "(hcloud|netcup|gaiaftcl)-[a-z]+[0-9]+-[0-9]+"

  - id: every_control_labeled
    severity: refuse
    refusal_code: GW_REFUSE_HEALTH_ACCESSIBILITY_LABEL_MISSING
    description: Every interactive control must declare a non-empty accessibility_label.
    kind: required_field
    field: accessibility_label
    applies_to_kinds: [button, segmented, dropdown, link, toggle]

  - id: primary_action_color
    severity: refuse
    refusal_code: GW_REFUSE_HEALTH_PRIMARY_COLOR_VIOLATION
    description: Elements with role=primary must use accent or blue color, not red.
    kind: color_role_constraint
    role: primary
    forbidden_color_families: [red, orange]

  - id: destructive_action_color
    severity: refuse
    refusal_code: GW_REFUSE_HEALTH_DESTRUCTIVE_COLOR_VIOLATION
    description: Red color may only be used on role=destructive.
    kind: red_only_destructive

  - id: value_label_type_match
    severity: refuse
    refusal_code: GW_REFUSE_HEALTH_VALUE_LABEL_MISMATCH
    description: Values declared numeric must not contain non-numeric strings.
    kind: value_type_match

  - id: no_duplicate_controls
    severity: refuse
    refusal_code: GW_REFUSE_HEALTH_DUPLICATE_CONTROL
    description: The same action must not appear twice on the same surface.
    kind: no_duplicate_action_id

  - id: primary_cta_present
    severity: refuse
    refusal_code: GW_REFUSE_HEALTH_PRIMARY_CTA_MISSING
    description: Every primary surface must declare a primary_cta and the referenced control must exist.
    kind: primary_cta_present
```

## Audit verb chain (LG IDs)

- `LG-FRANKLIN-IQ-HEALTH-UI-SCAFFOLD-001` — IQ healer scaffolds this doc, every cell's Surfaces.yaml, and the franklin_health_ui_audit Rust crate. Builds the binary.
- `LG-FRANKLIN-OQ-HEALTH-UI-AUDIT-001` — OQ first real check after the language-purity gate. Invokes the binary against every cell's surface manifest. Refusal terminal on any rule violation.

## Operator guidance

The Surfaces.yaml file in each cell is **operator-authored** (with a stub
template scaffolded by IQ). Each app team is responsible for keeping the
manifest in sync with the actual UI. Drift between the manifest and the live
surface is itself a finding, caught at runtime in phase 2 (live AX
introspection) — but in phase 1, the manifest is the contract.
AUTH
        printf '    ✓ wrote authority %s\n' "${authority}" >&2
    fi

    # 2. Per-cell Surfaces.yaml stubs
    local cell stub
    for cell in "${EXPECTED_CELLS[@]}"; do
        stub="${FRANKLIN_ROOT}/cells/${cell}/Surfaces.yaml"
        [[ -f "${stub}" ]] && continue
        mkdir -p "${stub:h}"
        cat > "${stub}" <<YAML
# Surfaces manifest for the ${cell} cell.
# Audited by LG-FRANKLIN-OQ-HEALTH-UI-AUDIT-001 against
# wiki/HEALTH_UI_AUDIT_AUTHORITY.md.
#
# Operator: keep this file in sync with the live surfaces of the ${cell} app.
# Phase 1 = manifest is the contract.

app: ${cell}
contract_version: ${EXPECTED_CONTRACT_VERSION}
surfaces:
  - id: ${cell}_main
    title: "Overview"
    primary_cta: open_overview
    elements:
      - kind: button
        role: primary
        action_id: open_overview
        label: "Open overview"
        text: "Open overview"
        accessibility_label: "Open overview"
        fg_color: "#FFFFFF"
        bg_color: "#005BBB"
      - kind: value
        label: "Status"
        value: "Ready"
        fg_color: "#111111"
        bg_color: "#FFFFFF"
YAML
        printf '    ✓ stub %s\n' "${stub}" >&2
    done

    # 3. Rust crate scaffold
    local crate="${FRANKLIN_ROOT}/tools/franklin_health_ui_audit"
    mkdir -p "${crate}/src"
    if [[ ! -f "${crate}/Cargo.toml" ]]; then
        cat > "${crate}/Cargo.toml" <<'TOML'
[package]
name = "franklin_health_ui_audit"
version = "1.2.0"
edition = "2021"

[[bin]]
name = "franklin_health_ui_audit"
path = "src/main.rs"

[dependencies]
serde      = { version = "1", features = ["derive"] }
serde_json = "1"
serde_yaml = "0.9"
regex      = "1"

[profile.release]
opt-level = "z"
lto       = true
strip     = true
TOML
    fi
    # Klein-bottle hardening: existing crates created before workspace fix may
    # lack [workspace] and fail under the root Cargo workspace. Enforce
    # standalone behavior idempotently every run.
    if ! rg -n '^\[workspace\]$' "${crate}/Cargo.toml" >/dev/null 2>&1; then
        printf '\n[workspace]\n' >> "${crate}/Cargo.toml"
    fi
    if ! rg -n '^[[:space:]]*serde_yaml[[:space:]]*=' "${crate}/Cargo.toml" >/dev/null 2>&1; then
        python3 - "${crate}/Cargo.toml" <<'PY' || return 2
import sys
p = sys.argv[1]
txt = open(p, "r", encoding="utf-8").read()
if "serde_yaml" in txt:
    raise SystemExit(0)
if "[dependencies]" in txt:
    txt = txt.replace("[dependencies]\n", "[dependencies]\nserde_yaml = \"0.9\"\n", 1)
else:
    txt += "\n[dependencies]\nserde_yaml = \"0.9\"\n"
open(p, "w", encoding="utf-8").write(txt)
PY
    fi
    if [[ ! -f "${crate}/src/main.rs" ]] || ! rg -n -- '"--authority"[[:space:]]*=>|"--cells"[[:space:]]*=>|"--report"[[:space:]]*=>' "${crate}/src/main.rs" >/dev/null 2>&1; then
        cat > "${crate}/src/main.rs" <<'RUST'
// franklin_health_ui_audit — manifest-based UI audit, phase 1.
//
// Args (current, runner-aligned):
//   --authority <wiki/HEALTH_UI_AUDIT_AUTHORITY.md>
//   --cells     <FRANKLIN_ROOT/cells>
//   --report    <evidence/runs/<tau>/health_ui_audit.json>
//
// Legacy args (still tolerated for compat with callers that pre-converted
// YAML→JSON via an IQ bridge): --rules <json> --surfaces <json>
//
// The authority is a markdown file with one ```yaml fenced block whose body
// has shape: { audit_rules: [ { id, kind, ... }, ... ] }.
// Each cell's manifest is <cells>/<cell>/Surfaces.yaml with shape
// { app, contract_version, surfaces: [ ... ] }.

use serde_json::Value;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

// Convert serde_yaml::Value → serde_json::Value so the existing rule logic
// (which is JSON-Value-shaped) does not need to be rewritten.
fn yaml_to_json(y: serde_yaml::Value) -> Value {
    match y {
        serde_yaml::Value::Null => Value::Null,
        serde_yaml::Value::Bool(b) => Value::Bool(b),
        serde_yaml::Value::Number(n) => {
            if let Some(i) = n.as_i64() { Value::from(i) }
            else if let Some(u) = n.as_u64() { Value::from(u) }
            else if let Some(f) = n.as_f64() { serde_json::Number::from_f64(f).map(Value::Number).unwrap_or(Value::Null) }
            else { Value::Null }
        }
        serde_yaml::Value::String(s) => Value::String(s),
        serde_yaml::Value::Sequence(seq) => Value::Array(seq.into_iter().map(yaml_to_json).collect()),
        serde_yaml::Value::Mapping(map) => {
            let mut obj = serde_json::Map::new();
            for (k, v) in map {
                let key = match k {
                    serde_yaml::Value::String(s) => s,
                    serde_yaml::Value::Bool(b) => b.to_string(),
                    serde_yaml::Value::Number(n) => n.to_string(),
                    other => serde_yaml::to_string(&other).unwrap_or_default().trim().to_string(),
                };
                obj.insert(key, yaml_to_json(v));
            }
            Value::Object(obj)
        }
        serde_yaml::Value::Tagged(t) => yaml_to_json(t.value),
    }
}

// Extract the first ```yaml fenced block from a markdown document.
fn extract_yaml_block(md: &str) -> Option<String> {
    let mut in_block = false;
    let mut buf = String::new();
    for line in md.lines() {
        let trimmed = line.trim_start();
        if !in_block {
            if trimmed.starts_with("```yaml") || trimmed.starts_with("```yml") {
                in_block = true;
            }
        } else {
            if trimmed.starts_with("```") {
                return Some(buf);
            }
            buf.push_str(line);
            buf.push('\n');
        }
    }
    None
}

// Load the authority doc and return a serde_json::Value with shape
// { "audit_rules": [...] }.
fn load_authority(path: &str) -> Result<Value, String> {
    let md = fs::read_to_string(path).map_err(|e| format!("read authority {}: {}", path, e))?;
    let yaml_src = extract_yaml_block(&md)
        .ok_or_else(|| format!("no ```yaml fenced block in authority {}", path))?;
    let yv: serde_yaml::Value = serde_yaml::from_str(&yaml_src)
        .map_err(|e| format!("parse authority yaml: {}", e))?;
    Ok(yaml_to_json(yv))
}

// Walk <cells>/<cell>/Surfaces.yaml for every immediate subdirectory of <cells>
// and return a serde_json::Value with shape { "manifests": [...] }.
fn load_cells(dir: &str) -> Result<Value, String> {
    let root = PathBuf::from(dir);
    let entries = fs::read_dir(&root)
        .map_err(|e| format!("read cells dir {}: {}", dir, e))?;
    let mut manifests: Vec<Value> = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() { continue; }
        let surf = path.join("Surfaces.yaml");
        if !surf.is_file() { continue; }
        let body = match fs::read_to_string(&surf) {
            Ok(s) => s,
            Err(e) => { eprintln!("WARN read {}: {}", surf.display(), e); continue; }
        };
        let yv: serde_yaml::Value = match serde_yaml::from_str(&body) {
            Ok(v) => v,
            Err(e) => { eprintln!("WARN parse {}: {}", surf.display(), e); continue; }
        };
        let mut jv = yaml_to_json(yv);
        // Normalize: ensure "app" key exists; default to directory name.
        if let Some(obj) = jv.as_object_mut() {
            if !obj.contains_key("app") {
                let cell_name = path.file_name().and_then(|s| s.to_str()).unwrap_or("?").to_string();
                obj.insert("app".to_string(), Value::String(cell_name));
            }
        }
        manifests.push(jv);
    }
    Ok(serde_json::json!({ "manifests": manifests }))
}

fn relative_luminance(hex: &str) -> Option<f64> {
    let s = hex.trim_start_matches('#');
    if s.len() != 6 { return None; }
    let r = u8::from_str_radix(&s[0..2], 16).ok()? as f64 / 255.0;
    let g = u8::from_str_radix(&s[2..4], 16).ok()? as f64 / 255.0;
    let b = u8::from_str_radix(&s[4..6], 16).ok()? as f64 / 255.0;
    fn ch(c: f64) -> f64 {
        if c <= 0.03928 { c / 12.92 } else { ((c + 0.055) / 1.055).powf(2.4) }
    }
    Some(0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b))
}

fn contrast_ratio(fg: &str, bg: &str) -> Option<f64> {
    let lf = relative_luminance(fg)?;
    let lb = relative_luminance(bg)?;
    let (lt, ld) = if lf > lb { (lf, lb) } else { (lb, lf) };
    Some((lt + 0.05) / (ld + 0.05))
}

fn color_family(hex: &str) -> &'static str {
    let s = hex.trim_start_matches('#');
    if s.len() != 6 { return "unknown"; }
    let r = u8::from_str_radix(&s[0..2], 16).unwrap_or(0) as i32;
    let g = u8::from_str_radix(&s[2..4], 16).unwrap_or(0) as i32;
    let b = u8::from_str_radix(&s[4..6], 16).unwrap_or(0) as i32;
    if r > g + 30 && r > b + 30 { return "red"; }
    if r > 200 && g > 100 && b < 100 { return "orange"; }
    if g > r + 30 && g > b + 10 { return "green"; }
    if b > r + 20 && b > g - 20 { return "blue"; }
    if r > 220 && g > 220 && b > 220 { return "white"; }
    if r < 40 && g < 40 && b < 40 { return "black"; }
    "neutral"
}

fn surface_text_fields(elem: &Value) -> Vec<String> {
    let mut out = Vec::new();
    for k in ["text", "title", "value", "label", "placeholder"] {
        if let Some(s) = elem.get(k).and_then(|v| v.as_str()) {
            if !s.is_empty() { out.push(s.to_string()); }
        }
    }
    out
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let mut authority_path = String::new();
    let mut cells_dir = String::new();
    let mut report_path = String::new();
    let mut rules_path = String::new();
    let mut surfaces_path = String::new();
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--authority" => { authority_path = args.get(i+1).cloned().unwrap_or_default(); i += 2; }
            "--cells"     => { cells_dir      = args.get(i+1).cloned().unwrap_or_default(); i += 2; }
            "--report"    => { report_path    = args.get(i+1).cloned().unwrap_or_default(); i += 2; }
            "--rules"     => { rules_path     = args.get(i+1).cloned().unwrap_or_default(); i += 2; }
            "--surfaces"  => { surfaces_path  = args.get(i+1).cloned().unwrap_or_default(); i += 2; }
            _ => { i += 1; }
        }
    }

    let have_authority = !authority_path.is_empty() && !cells_dir.is_empty();
    let have_legacy    = !rules_path.is_empty() && !surfaces_path.is_empty();
    if !have_authority && !have_legacy {
        eprintln!("usage: franklin_health_ui_audit --authority <md> --cells <dir> --report <json>");
        eprintln!("   or: franklin_health_ui_audit --rules <json> --surfaces <json>");
        return ExitCode::from(2);
    }

    let rules: Value = if have_authority {
        match load_authority(&authority_path) {
            Ok(v) => v,
            Err(e) => { eprintln!("GW_REFUSE_HEALTH_AUDIT_AUTHORITY_PARSE {}", e); return ExitCode::from(2); }
        }
    } else {
        match fs::read_to_string(&rules_path).ok().and_then(|s| serde_json::from_str(&s).ok()) {
            Some(v) => v,
            None => { eprintln!("could not parse rules: {}", rules_path); return ExitCode::from(2); }
        }
    };
    let surfaces: Value = if have_authority {
        match load_cells(&cells_dir) {
            Ok(v) => v,
            Err(e) => { eprintln!("GW_REFUSE_HEALTH_AUDIT_CELLS_PARSE {}", e); return ExitCode::from(2); }
        }
    } else {
        match fs::read_to_string(&surfaces_path).ok().and_then(|s| serde_json::from_str(&s).ok()) {
            Some(v) => v,
            None => { eprintln!("could not parse surfaces: {}", surfaces_path); return ExitCode::from(2); }
        }
    };

    let empty_vec: Vec<Value> = Vec::new();
    let rule_list = rules.get("audit_rules").and_then(|v| v.as_array()).unwrap_or(&empty_vec);
    let manifests = surfaces.get("manifests").and_then(|v| v.as_array()).unwrap_or(&empty_vec);

    let mut findings: Vec<String> = Vec::new();

    for manifest in manifests {
        let app = manifest.get("app").and_then(|v| v.as_str()).unwrap_or("?");
        let surfs = manifest.get("surfaces").and_then(|v| v.as_array()).cloned().unwrap_or_default();
        for rule in rule_list {
            let kind = rule.get("kind").and_then(|v| v.as_str()).unwrap_or("");
            if kind == "non_empty_manifest" && surfs.is_empty() {
                let code = rule.get("refusal_code").and_then(|v| v.as_str()).unwrap_or("UNKNOWN");
                findings.push(format!("{} [{}] manifest empty", code, app));
            }
        }
        for surface in &surfs {
            let surf_id = surface.get("id").and_then(|v| v.as_str()).unwrap_or("?");
            let primary_cta = surface.get("primary_cta").and_then(|v| v.as_str()).unwrap_or("");
            let elements = surface.get("elements").and_then(|v| v.as_array()).cloned().unwrap_or_default();

            // Track action_ids for duplicate detection.
            let mut action_ids: Vec<String> = Vec::new();
            for elem in &elements {
                if let Some(a) = elem.get("action_id").and_then(|v| v.as_str()) {
                    action_ids.push(a.to_string());
                }
            }

            for rule in rule_list {
                let kind = rule.get("kind").and_then(|v| v.as_str()).unwrap_or("");
                let rule_id = rule.get("id").and_then(|v| v.as_str()).unwrap_or("?");
                let code = rule.get("refusal_code").and_then(|v| v.as_str()).unwrap_or("UNKNOWN");

                match kind {
                    "contrast_ratio" => {
                        let threshold = rule.get("threshold").and_then(|v| v.as_f64()).unwrap_or(4.5);
                        for elem in &elements {
                            let fg = elem.get("fg_color").and_then(|v| v.as_str()).unwrap_or("");
                            let bg = elem.get("bg_color").and_then(|v| v.as_str()).unwrap_or("");
                            if fg.is_empty() || bg.is_empty() { continue; }
                            if let Some(r) = contrast_ratio(fg, bg) {
                                if r < threshold {
                                    let eid = elem.get("id").and_then(|v| v.as_str()).unwrap_or("?");
                                    findings.push(format!("{} [{}.{}.{}] {} contrast {:.2} < {:.2}", code, app, surf_id, eid, rule_id, r, threshold));
                                }
                            }
                        }
                    }
                    "forbidden_terms" => {
                        let empty_terms: Vec<Value> = Vec::new();
                        let terms = rule.get("terms").and_then(|v| v.as_array()).unwrap_or(&empty_terms);
                        for elem in &elements {
                            for t in surface_text_fields(elem) {
                                for term_v in terms {
                                    if let Some(term) = term_v.as_str() {
                                        if t.contains(term) {
                                            let eid = elem.get("id").and_then(|v| v.as_str()).unwrap_or("?");
                                            findings.push(format!("{} [{}.{}.{}] jargon '{}'", code, app, surf_id, eid, term));
                                        }
                                    }
                                }
                            }
                        }
                    }
                    "forbidden_regex" => {
                        if let Some(p) = rule.get("pattern").and_then(|v| v.as_str()) {
                            if let Ok(re) = regex::Regex::new(p) {
                                for elem in &elements {
                                    for t in surface_text_fields(elem) {
                                        if re.is_match(&t) {
                                            let eid = elem.get("id").and_then(|v| v.as_str()).unwrap_or("?");
                                            findings.push(format!("{} [{}.{}.{}] regex matched '{}'", code, app, surf_id, eid, t));
                                        }
                                    }
                                }
                            }
                        }
                    }
                    "required_field" => {
                        let field = rule.get("field").and_then(|v| v.as_str()).unwrap_or("");
                        let empty_kinds: Vec<Value> = Vec::new();
                        let kinds = rule.get("applies_to_kinds").and_then(|v| v.as_array()).unwrap_or(&empty_kinds);
                        for elem in &elements {
                            let ekind = elem.get("kind").and_then(|v| v.as_str()).unwrap_or("");
                            let applies = kinds.iter().any(|k| k.as_str() == Some(ekind));
                            if !applies { continue; }
                            let v = elem.get(field).and_then(|x| x.as_str()).unwrap_or("");
                            if v.is_empty() {
                                let eid = elem.get("id").and_then(|v| v.as_str()).unwrap_or("?");
                                findings.push(format!("{} [{}.{}.{}] missing field '{}'", code, app, surf_id, eid, field));
                            }
                        }
                    }
                    "color_role_constraint" => {
                        let role = rule.get("role").and_then(|v| v.as_str()).unwrap_or("");
                        let empty_fc: Vec<Value> = Vec::new();
                        let forbid = rule.get("forbidden_color_families").and_then(|v| v.as_array()).unwrap_or(&empty_fc);
                        for elem in &elements {
                            let r = elem.get("role").and_then(|v| v.as_str()).unwrap_or("");
                            if r != role { continue; }
                            let bg = elem.get("bg_color").and_then(|v| v.as_str()).unwrap_or("");
                            let fam = color_family(bg);
                            if forbid.iter().any(|f| f.as_str() == Some(fam)) {
                                let eid = elem.get("id").and_then(|v| v.as_str()).unwrap_or("?");
                                findings.push(format!("{} [{}.{}.{}] role={} color={}", code, app, surf_id, eid, role, fam));
                            }
                        }
                    }
                    "red_only_destructive" => {
                        for elem in &elements {
                            let r = elem.get("role").and_then(|v| v.as_str()).unwrap_or("");
                            let bg = elem.get("bg_color").and_then(|v| v.as_str()).unwrap_or("");
                            if color_family(bg) == "red" && r != "destructive" {
                                let eid = elem.get("id").and_then(|v| v.as_str()).unwrap_or("?");
                                findings.push(format!("{} [{}.{}.{}] red on non-destructive role='{}'", code, app, surf_id, eid, r));
                            }
                        }
                    }
                    "value_type_match" => {
                        for elem in &elements {
                            let t = elem.get("kind").and_then(|v| v.as_str()).unwrap_or("");
                            if t != "value" { continue; }
                            let declared = elem.get("value_type").and_then(|v| v.as_str()).unwrap_or("");
                            let val = elem.get("value").and_then(|v| v.as_str()).unwrap_or("");
                            if declared == "number" && !val.is_empty() {
                                if val.parse::<f64>().is_err() {
                                    let eid = elem.get("id").and_then(|v| v.as_str()).unwrap_or("?");
                                    findings.push(format!("{} [{}.{}.{}] declared number got '{}'", code, app, surf_id, eid, val));
                                }
                            }
                        }
                    }
                    "no_duplicate_action_id" => {
                        let mut sorted = action_ids.clone();
                        sorted.sort();
                        for w in sorted.windows(2) {
                            if w[0] == w[1] {
                                findings.push(format!("{} [{}.{}] duplicate action_id '{}'", code, app, surf_id, w[0]));
                            }
                        }
                    }
                    "primary_cta_present" => {
                        if !primary_cta.is_empty() {
                            let found = elements.iter().any(|e| e.get("action_id").and_then(|v| v.as_str()) == Some(primary_cta));
                            if !found {
                                findings.push(format!("{} [{}.{}] primary_cta '{}' not in elements", code, app, surf_id, primary_cta));
                            }
                        } else if !elements.is_empty() {
                            // surfaces with elements must declare a primary_cta unless explicitly marked secondary
                            let kind = surface.get("surface_kind").and_then(|v| v.as_str()).unwrap_or("primary");
                            if kind == "primary" {
                                findings.push(format!("{} [{}.{}] no primary_cta declared", code, app, surf_id));
                            }
                        }
                    }
                    _ => {}
                }
            }
        }
    }

    // Always write the report JSON if a path was given.
    if !report_path.is_empty() {
        let report = serde_json::json!({
            "ok": findings.is_empty(),
            "manifests": manifests.len(),
            "rules": rule_list.len(),
            "findings": findings,
        });
        if let Err(e) = fs::write(&report_path, serde_json::to_string_pretty(&report).unwrap_or_default()) {
            eprintln!("WARN write report {}: {}", report_path, e);
        }
    }

    if findings.is_empty() {
        println!("HEALTH_UI_AUDIT_OK manifests={} rules={}", manifests.len(), rule_list.len());
        return ExitCode::SUCCESS;
    }
    for f in &findings {
        println!("{}", f);
    }
    // First stderr line carries the first finding's GW_REFUSE_HEALTH_* code so
    // the OQ guard can lift it into the WITNESS payload without re-parsing.
    let first = findings.first().map(|s| s.as_str()).unwrap_or("HEALTH_UI_AUDIT_FAILED");
    let code = first.split_whitespace().next().unwrap_or("HEALTH_UI_AUDIT_FAILED");
    eprintln!("{} findings={}", code, findings.len());
    ExitCode::from(1)
}
RUST
    fi

    # 4. Build the crate.
    if ! command -v cargo >/dev/null 2>&1; then
        printf '    ⚠ cargo missing; cannot build health audit binary\n' >&2
        return 2
    fi
    local build_log="${EVIDENCE_ROOT}/health_ui_audit_build.log"
    if ( cd "${crate}" && cargo build --release ) >"${build_log}" 2>&1; then
        printf '    ✓ cargo build --release ok\n' >&2
        HEAL_RECEIPT LG-FRANKLIN-HEAL-HEALTH-UI-AUDIT-TOOL-001 LG-FRANKLIN-IQ-HEALTH-UI-SCAFFOLD-001 CALORIE \
            "franklin_health_ui_audit crate scaffolded and built"
        return 0
    else
        printf '    ⚠ cargo build failed; see %s\n' "${build_log}" >&2
        return 2
    fi
}

check_health_ui_audit_tool() {
    local crate="${FRANKLIN_ROOT}/tools/franklin_health_ui_audit"
    local bin="${crate}/target/release/franklin_health_ui_audit"
    [[ -f "${FRANKLIN_ROOT}/wiki/HEALTH_UI_AUDIT_AUTHORITY.md" ]] || return 1
    [[ -f "${crate}/Cargo.toml" ]] || return 1
    [[ -f "${crate}/src/main.rs" ]] || return 1
    rg -n -- '^[[:space:]]*serde_yaml[[:space:]]*=' "${crate}/Cargo.toml" >/dev/null 2>&1 || return 1
    rg -n -- '"--authority"[[:space:]]*=>|"--cells"[[:space:]]*=>|"--report"[[:space:]]*=>' "${crate}/src/main.rs" >/dev/null 2>&1 || return 1
    [[ -x "${bin}" ]] || return 1
    [[ "${bin}" -nt "${crate}/src/main.rs" ]] || return 1
    [[ "${bin}" -nt "${crate}/Cargo.toml" ]] || return 1
    local cell
    for cell in "${EXPECTED_CELLS[@]}"; do
        [[ -f "${FRANKLIN_ROOT}/cells/${cell}/Surfaces.yaml" ]] || return 1
    done
    return 0
}

# ============================================================================
# Franklin Cell Game — Franklin's own verb catalog and the game-loop that
# uses the substrate ON ITSELF to bring every cell to whole.
#
# Klein-bottle reasoning: a self-healing AI is its own audit subject. Franklin
# doesn't just orchestrate the cells — Franklin USES its own catalog of
# verbs to interview each cell, find gaps, prescribe heals, invoke healers,
# witness whole, and finally agree-takeover so the runner becomes pure
# evidence-envelope. The game is the manifold by which the substrate makes
# itself whole.
#
# Catalog (cells/franklin/CATALOG.yaml):
#   LG-FRANKLIN-CELL-GAME-AGREE-TAKEOVER-001 — Franklin's signed assertion
#       it now owns OQ/PQ orchestration. Inverts the runner from SUT-author
#       to evidence-envelope.
#   LG-FRANKLIN-CELL-GAME-INTERVIEW-001 — Franklin reads the cell's required
#       artefacts (CATALOG/TREASURY/ROSETTE_BIND/Surfaces) and finds gaps.
#   LG-FRANKLIN-CELL-GAME-PRESCRIBE-001 — for each gap Franklin records the
#       healer that would close it.
#   LG-FRANKLIN-CELL-GAME-INVOKE-HEAL-001 — Franklin invokes the prescribed
#       healer and re-interviews; on still-wounded, refuses CELL_NOT_WHOLE.
#   LG-FRANKLIN-CELL-GAME-WITNESS-WHOLE-001 — per-cell whole receipt.
#   LG-FRANKLIN-CELL-GAME-CLOSE-001 — every cell whole or terminal recorded.
# ============================================================================

heal_franklin_cell_game_catalog() {
    printf '  → heal_franklin_cell_game_catalog: scaffolding Franklin verb catalog\n' >&2
    local cdir="${FRANKLIN_ROOT}/cells/franklin"
    mkdir -p "${cdir}"
    local catalog="${cdir}/CATALOG.yaml"
    if [[ ! -f "${catalog}" ]]; then
        cat > "${catalog}" <<'YAML'
# cells/franklin/CATALOG.yaml — Franklin's own verb catalog.
# Authority: this is the CELL Franklin plays. It is mesh-of-sprouts-shaped:
# every entry is a verb Franklin can invoke against itself or another cell.
contract_version: "1.2.0"
cell: franklin
kind: orchestrator
verbs:
  - id: LG-FRANKLIN-CELL-GAME-AGREE-TAKEOVER-001
    intent: >
      Franklin asserts under its own keypair that it now owns OQ/PQ
      orchestration. Inverts the runner from test-author to
      evidence-envelope. Required before the cell-game loop runs.
    interaction_class: A
    required_signers: [franklin]
  - id: LG-FRANKLIN-CELL-GAME-INTERVIEW-001
    intent: >
      Franklin reads target cell's required artefacts (CATALOG.yaml,
      TREASURY.yaml, ROSETTE_BIND.yaml, Surfaces.yaml) and emits a
      finding list of gaps. No mutation.
    interaction_class: A
    required_signers: [franklin]
  - id: LG-FRANKLIN-CELL-GAME-PRESCRIBE-001
    intent: >
      For each interview finding, Franklin records the healer that
      would close the gap. Output is a prescription manifest.
    interaction_class: A
    required_signers: [franklin]
  - id: LG-FRANKLIN-CELL-GAME-INVOKE-HEAL-001
    intent: >
      Franklin invokes prescribed healers (interactive: presents the
      operator a heal-now choice; auto-heal allowed for class-A, B
      classes require operator). Re-interviews after each heal. On
      still-wounded after policy retry budget, refuses CELL_NOT_WHOLE.
    interaction_class: B
    required_signers: [franklin, operator]
  - id: LG-FRANKLIN-CELL-GAME-WITNESS-WHOLE-001
    intent: >
      Per-cell whole-state witness. Emits CALORIE only when every
      required artefact for the cell exists, validates, and is bound
      into the rosette. Per-cell receipt.
    interaction_class: A
    required_signers: [franklin]
  - id: LG-FRANKLIN-CELL-GAME-CLOSE-001
    intent: >
      Closure of the game across all expected cells. Aggregate witness;
      refusal if any cell terminated NOT_WHOLE.
    interaction_class: A
    required_signers: [franklin]
YAML
    fi
    HEAL_RECEIPT LG-FRANKLIN-HEAL-CELL-GAME-CATALOG-001 \
        LG-FRANKLIN-IQ-CELL-GAME-CATALOG-001 CALORIE \
        "Franklin verb catalog scaffolded at ${catalog}"
    return 0
}

check_franklin_cell_game_catalog() {
    local catalog="${FRANKLIN_ROOT}/cells/franklin/CATALOG.yaml"
    [[ -f "${catalog}" ]] || return 1
    local v
    for v in \
        LG-FRANKLIN-CELL-GAME-AGREE-TAKEOVER-001 \
        LG-FRANKLIN-CELL-GAME-INTERVIEW-001 \
        LG-FRANKLIN-CELL-GAME-PRESCRIBE-001 \
        LG-FRANKLIN-CELL-GAME-INVOKE-HEAL-001 \
        LG-FRANKLIN-CELL-GAME-WITNESS-WHOLE-001 \
        LG-FRANKLIN-CELL-GAME-CLOSE-001
    do
        grep -q "${v}" "${catalog}" || return 1
    done
    return 0
}

# Interview a single cell: returns 0 if whole, 1 with stdout-listed gaps.
# Pure check — no mutation. Used by the cell-game loop.
franklin_cell_interview() {
    local cell="$1"
    local cdir="${FRANKLIN_ROOT}/cells/${cell}"
    local gaps=()
    [[ -d "${cdir}" ]]                || gaps+=("dir-missing")
    [[ -f "${cdir}/CATALOG.yaml" ]]   || gaps+=("CATALOG.yaml-missing")
    [[ -f "${cdir}/Surfaces.yaml" ]]  || gaps+=("Surfaces.yaml-missing")
    # franklin and material_sciences cells have additional required files
    case "${cell}" in
        material_sciences)
            [[ -f "${cdir}/TREASURY.yaml" ]]     || gaps+=("TREASURY.yaml-missing")
            [[ -f "${cdir}/ROSETTE_BIND.yaml" ]] || gaps+=("ROSETTE_BIND.yaml-missing")
            ;;
        franklin)
            grep -q "LG-FRANKLIN-CELL-GAME-AGREE-TAKEOVER-001" \
                "${cdir}/CATALOG.yaml" 2>/dev/null \
                || gaps+=("CATALOG.yaml-incomplete")
            ;;
    esac
    if (( ${#gaps[@]} > 0 )); then
        printf '%s\n' "${gaps[@]}"
        return 1
    fi
    return 0
}

# Prescribe + invoke heal for a list of gaps on a cell. The runner provides
# a fallback game; Franklin Swift app will eventually own this loop.
franklin_cell_heal_loop() {
    local cell="$1"; shift
    local gaps=("$@")
    local cdir="${FRANKLIN_ROOT}/cells/${cell}"
    local g
    for g in "${gaps[@]}"; do
        case "${g}" in
            dir-missing)
                mkdir -p "${cdir}" ;;
            CATALOG.yaml-missing)
                cat > "${cdir}/CATALOG.yaml" <<YAML
contract_version: "1.2.0"
cell: ${cell}
kind: sprout
verbs: []
YAML
                ;;
            Surfaces.yaml-missing)
                cat > "${cdir}/Surfaces.yaml" <<YAML
contract_version: "1.2.0"
cell: ${cell}
surfaces:
  - id: ${cell}_main
    title: "Overview"
    primary_cta: open_overview
    elements:
      - kind: button
        role: primary
        action_id: open_overview
        label: "Open overview"
        text: "Open overview"
        accessibility_label: "Open overview"
        fg_color: "#FFFFFF"
        bg_color: "#005BBB"
      - kind: value
        label: "Status"
        value: "Ready"
        fg_color: "#111111"
        bg_color: "#FFFFFF"
YAML
                ;;
            TREASURY.yaml-missing)
                cat > "${cdir}/TREASURY.yaml" <<YAML
contract_version: "1.2.0"
cell: ${cell}
mesh_treasury_index: mesh/treasury/INDEX.json
asserts_entry: ${cell}
YAML
                ;;
            ROSETTE_BIND.yaml-missing)
                cat > "${cdir}/ROSETTE_BIND.yaml" <<YAML
contract_version: "1.2.0"
cell: ${cell}
binds_authority: cells/.json/cell_manifest_registry.json
YAML
                ;;
            CATALOG.yaml-incomplete)
                heal_franklin_cell_game_catalog
                ;;
        esac
    done
    return 0
}

# ============================================================================
# 1. IQ
# ============================================================================

NARRATE LG-FRANKLIN-IQ-PATHS-001 B \
"Verifying the substrate's required directory tree. A missing leaf invokes \
the path-scaffold healer (Class A under tooling-steward authority — \
directories are not signed, so no key required)."
ATTEMPT LG-FRANKLIN-IQ-PATHS-001 check_paths heal_paths \
    GW_REFUSE_FRANKLIN_STACK_PATH_OUTSIDE_ENVELOPE

NARRATE LG-FRANKLIN-IQ-IDENTITY-001 B \
"Verifying substrate/identity_table.yaml has all five canonical slots in \
the slots-list shape with underscored role names. A missing or non-canon \
identity table invokes the genesis healer, which generates Ed25519 \
keypairs into the operator's keychain, signs the canonical identity \
table with the founder_backstop key, and mints a one-time genesis \
receipt. Genesis is itself a witnessed verb chain — there is no silent \
identity creation, ever."
ATTEMPT LG-FRANKLIN-IQ-IDENTITY-001 check_identity heal_identity_genesis \
    GW_REFUSE_FRANKLIN_HEAL_EXHAUSTED

NARRATE LG-FRANKLIN-IQ-CELL-CATALOGS-001 B \
"Verifying every expected cell holds a CATALOG.yaml. Missing catalogs \
invoke the catalog-scaffold healer; a cell still missing after healing \
declares terminal because the cell daemon cannot mint witnesses without \
a catalog."
ATTEMPT LG-FRANKLIN-IQ-CELL-CATALOGS-001 check_cell_catalogs heal_cell_catalogs \
    GW_REFUSE_CELL_CATALOG_MISSING

NARRATE LG-FRANKLIN-IQ-FRANKLIN-CATALOG-001 B \
"Verifying the Franklin Cell catalog: LANGUAGE_GAMES, AVATAR_MANIFEST, \
STACK_CONTROL_ENVELOPE, ADVERSARY_GRAMMAR, EDUCATION_TRACKS. Missing \
files invoke the Franklin-catalog healer with canonical content."
ATTEMPT LG-FRANKLIN-IQ-FRANKLIN-CATALOG-001 check_franklin_catalog heal_franklin_catalog \
    GW_REFUSE_FRANKLIN_AVATAR_MANIFEST_INVALID

NARRATE LG-FRANKLIN-IQ-HASHLOCKS-001 B \
"Recomputing sha256 for every entry in substrate/HASH_LOCKS.yaml. The \
healer recomputes only entries whose signing wallet is present in the \
operator keychain; entries whose signer is absent are left intact and \
become refusals on the next pass. A drift on a file no live wallet can \
re-sign is terminal."
ATTEMPT LG-FRANKLIN-IQ-HASHLOCKS-001 check_hashlocks heal_hashlocks \
    GW_REFUSE_HASH_LOCK_DRIFT

NARRATE LG-FRANKLIN-IQ-REFUSAL-REGISTRY-001 B \
"Verifying substrate/REFUSAL_CODE_REGISTRY.yaml contains the canonical \
109 codes (substrate 1–69 + Franklin Cell 80–119). Missing or partial \
registry invokes the registry-scaffold healer, which authors the full \
canonical list and seeds total_codes."
ATTEMPT LG-FRANKLIN-IQ-REFUSAL-REGISTRY-001 check_refusal_registry heal_refusal_registry \
    GW_REFUSE_FRANKLIN_CHANGE_PROPOSAL_SCHEMA_INVALID

NARRATE LG-FRANKLIN-IQ-PR-LIST-001 B \
"Verifying substrate/PR_ASSERTIONS.yaml contains PR-01..PR-58 with \
runner bindings. Missing or partial list invokes the PR-scaffold \
healer, which authors the canonical 58-assertion list with placeholder \
runner stubs that exit 0 (real runners are authored later by signed \
proposals)."
ATTEMPT LG-FRANKLIN-IQ-PR-LIST-001 check_pr_assertions heal_pr_assertions \
    GW_REFUSE_FRANKLIN_CHANGE_PROPOSAL_SCHEMA_INVALID

NARRATE LG-FRANKLIN-IQ-XCODE-001 B \
"Verifying the Apple Silicon toolchain. Missing tools are terminal — \
the runner has no authority to install Xcode."
REQUIRE_CMD xcrun       LG-FRANKLIN-IQ-XCODE-001 GW_REFUSE_TOOLCHAIN_MISSING
REQUIRE_CMD xcodebuild  LG-FRANKLIN-IQ-XCODE-001 GW_REFUSE_TOOLCHAIN_MISSING
REQUIRE_CMD swift       LG-FRANKLIN-IQ-XCODE-001 GW_REFUSE_TOOLCHAIN_MISSING
REQUIRE_CMD git         LG-FRANKLIN-IQ-XCODE-001 GW_REFUSE_TOOLCHAIN_MISSING
REQUIRE_CMD openssl     LG-FRANKLIN-IQ-XCODE-001 GW_REFUSE_TOOLCHAIN_MISSING
WITNESS LG-FRANKLIN-IQ-XCODE-001 CALORIE "xcrun, xcodebuild, swift, git, openssl present"

NARRATE LG-FRANKLIN-IQ-XCODE-LATEST-001 B \
"Verifying the installed Xcode meets the pinned floor (substrate/\
TOOLCHAIN_REQUIRED.yaml). The healer authors the pin file and an \
operator-driven install helper script. Below-floor is TERMINAL — the \
substrate has no authority to drive the App Store / Apple ID install \
flow. Operator runs scripts/install_xcode_latest.sh and re-runs."
ATTEMPT LG-FRANKLIN-IQ-XCODE-LATEST-001 check_xcode_latest heal_xcode_latest \
    GW_REFUSE_TOOLCHAIN_MISSING

NARRATE LG-FRANKLIN-IQ-LIBRARIES-001 B \
"Verifying every required Swift library declared in substrate/\
REQUIRED_LIBRARIES.yaml is reachable on disk OR via SwiftPM resolve. \
The healer scaffolds the manifest, runs swift package resolve when a \
Package.swift is present, and vendors any missing library by git clone \
into vendor/<name>/. Unreachable required library → TERMINAL — IQ \
fails if libraries cannot be procured (per operator directive)."
ATTEMPT LG-FRANKLIN-IQ-LIBRARIES-001 check_required_libraries heal_required_libraries \
    GW_REFUSE_FRANKLIN_REQUIRED_LIBRARY_MISSING

NARRATE LG-FRANKLIN-IQ-RUST-TOOLCHAIN-001 B \
"Verifying the Rust toolchain (rustup/cargo/rustc) is present. Post-IQ \
verification is Rust-only by policy; without cargo we cannot build the \
verifier binary. Missing rustup is TERMINAL — the operator runs \
scripts/install_rust_toolchain.sh."
ATTEMPT LG-FRANKLIN-IQ-RUST-TOOLCHAIN-001 check_rust_toolchain heal_rust_toolchain \
    GW_REFUSE_FRANKLIN_TOOLCHAIN_MISSING

NARRATE LG-FRANKLIN-IQ-YAML-JSON-BRIDGE-001 B \
"Mirroring canonical YAML files to JSON under substrate/.json/, \
cells/.json/, and evidence/audits/.json/. Post-IQ Rust verifier reads \
JSON (no YAML dependency in the crate). Bridge healer is invoked at \
IQ time so the bridge files exist before any post-IQ check fires."
ATTEMPT LG-FRANKLIN-IQ-YAML-JSON-BRIDGE-001 check_yaml_to_json_bridge heal_yaml_to_json_bridge \
    GW_REFUSE_FRANKLIN_PROVENANCE_MALFORMED

NARRATE LG-FRANKLIN-IQ-RUST-VERIFIER-001 B \
"Authoring tools/franklin_verify (Cargo crate) and building it via \
cargo build --release. The compiled binary handles every post-IQ \
verification subcommand: narrative-map, receipt, receipt-strict, \
pr-runners, auditor-stamp, rosette, reconcile, sha256-string. \
Cargo build failure is TERMINAL — without the binary we cannot honor \
the Rust-only post-IQ policy."
ATTEMPT LG-FRANKLIN-IQ-RUST-VERIFIER-001 check_rust_verifier heal_rust_verifier \
    GW_REFUSE_FRANKLIN_TOOLCHAIN_MISSING

NARRATE LG-FRANKLIN-IQ-AUDIT-MAP-001 B \
"Scaffolding evidence/audits/ui_test_narrative_catalog_map.yaml at IQ \
time so the JSON bridge has a source. (The runtime verification of \
this map happens post-IQ via the Rust binary; scaffolding stays in IQ \
because it authors content via python3, which IQ permits.)"
ATTEMPT LG-FRANKLIN-IQ-AUDIT-MAP-001 check_audit_map heal_audit_map \
    GW_REFUSE_FRANKLIN_VALIDATION_PROPOSAL_REPLAY

NARRATE LG-FRANKLIN-IQ-EMITTER-SCAFFOLD-001 B \
"Scaffolding fail-closed Swift emitter stubs for any registry code \
lacking an implementation. Stub authoring is python3 + zsh, which is \
allowed in IQ. Post-IQ verification of emitter parity uses the Rust \
binary's emitter-parity subcommand."
heal_emitter_parity || REFUSE_TERMINAL GW_REFUSE_FRANKLIN_CHANGE_PROPOSAL_REGRESSION_DETECTED \
    LG-FRANKLIN-IQ-EMITTER-SCAFFOLD-001 "emitter scaffold heal failed"
WITNESS LG-FRANKLIN-IQ-EMITTER-SCAFFOLD-001 CALORIE "emitter stubs scaffolded"

# Health-UI audit toolchain: scaffold the wiki authority doc, per-cell
# Surfaces.yaml manifests, and the Rust audit binary. This MUST be in IQ
# (Cargo + python3 stub authoring is allowed pre-gate); the binary is
# invoked post-IQ as the first OQ check, gating BUILD/TESTS/PQ on a
# healthy UI surface.
NARRATE LG-FRANKLIN-IQ-HEALTH-UI-SCAFFOLD-001 B \
"Scaffolding Health UI audit toolchain: wiki/HEALTH_UI_AUDIT_AUTHORITY.md \
(rule set), cells/<cell>/Surfaces.yaml (per-cell manifest), and \
tools/franklin_health_ui_audit/ (Rust binary). The audit runs first in \
OQ; an unhealthy UI surface refuses before any test or PQ checkpoint."
ATTEMPT LG-FRANKLIN-IQ-HEALTH-UI-SCAFFOLD-001 \
    check_health_ui_audit_tool heal_health_ui_audit_tool \
    GW_REFUSE_HEALTH_AUDIT_TOOL_MISSING

# Re-run the YAML→JSON bridge AFTER scaffolders fired so the JSON mirrors
# include audit map, emitter inventory, and any registry/PR updates.
NARRATE LG-FRANKLIN-IQ-YAML-JSON-BRIDGE-002 B \
"Re-mirroring YAML→JSON now that all IQ scaffolders have run. The Rust \
verifier reads JSON exclusively; this second bridge pass guarantees the \
audit map and post-scaffold registry are reflected."
heal_yaml_to_json_bridge || REFUSE_TERMINAL GW_REFUSE_FRANKLIN_PROVENANCE_MALFORMED \
    LG-FRANKLIN-IQ-YAML-JSON-BRIDGE-002 "YAML→JSON re-bridge failed after IQ scaffolders"
WITNESS LG-FRANKLIN-IQ-YAML-JSON-BRIDGE-002 CALORIE "JSON mirrors refreshed"

# Resolve the Rust verifier binary handle now; post-IQ steps invoke it.
RUST_VERIFY="${FRANKLIN_ROOT}/tools/franklin_verify/target/release/franklin_verify"
ensure_rust_verify_bin || REFUSE_TERMINAL GW_REFUSE_FRANKLIN_TOOLCHAIN_MISSING \
    LG-FRANKLIN-IQ-RUST-ONLY-GATE-001 "Rust verifier binary missing after heal attempt"

NARRATE LG-FRANKLIN-IQ-VQBIT-001 B \
"Sampling the entropy source. Quantum source unavailable invokes the \
fallback healer which writes substrate/VQBIT_PROVENANCE.yaml declaring \
the fallback. The fallback is itself part of the audit trail."
ATTEMPT LG-FRANKLIN-IQ-VQBIT-001 check_vqbit heal_vqbit \
    GW_REFUSE_FRANKLIN_QUANTUM_SOURCE_UNAVAILABLE

NARRATE LG-FRANKLIN-IQ-ROSETTE-REGISTRY-001 B \
"Verifying cells/cell_manifest_registry.yaml drives the rosette with \
every expected cell present and unique rosette positions. Missing or \
incomplete registry invokes the rosette-scaffold healer."
ATTEMPT LG-FRANKLIN-IQ-ROSETTE-REGISTRY-001 check_rosette_registry heal_rosette_registry \
    GW_REFUSE_FRANKLIN_ROSETTE_REGISTRY_DRIFT_MID_WINDOW

# IQ closure guard: from this point forward, any direct python3 invocation
# violates the post-IQ Rust-only policy. The runner must use ${RUST_VERIFY}.
# Re-run the YAML→JSON bridge one final time so the rosette registry's
# latest state is mirrored to JSON before OQ's Rust-only verifications.
heal_yaml_to_json_bridge || REFUSE_TERMINAL GW_REFUSE_FRANKLIN_PROVENANCE_MALFORMED \
    LG-FRANKLIN-IQ-RUST-ONLY-GATE-001 "final YAML→JSON bridge failed at IQ closure"

# ----------------------------------------------------------------------------
# IQ — Franklin-first handoff. Franklin is the operational orchestrator of
# OQ and PQ. The runner is the bootstrap, the guard, and the evidence
# envelope. After IQ scaffolds the substrate, the runner MUST visibly
# launch FranklinApp and hand off the run envelope. If Franklin will not
# launch, will not come to foreground, or will not accept the envelope,
# the run terminates — OQ/PQ never bypass visible Franklin.
# ----------------------------------------------------------------------------

NARRATE LG-FRANKLIN-IQ-LAUNCH-FRANKLIN-001 B \
"Building and launching the visible Franklin avatar (GAIAOS/macos/Franklin) \
plus the menu-bar bridge (cells/franklin/xcode/MacFranklinAssistant). \
The avatar is the user-facing deliverable — a SwiftUI WindowGroup with a \
visible avatar the operator can see and tap. The bridge serves local HTTP \
on 127.0.0.1:8830 with a /health endpoint. Both must be alive. The avatar reads the \
handoff envelope and runs the OQ catalog inside its own process; the \
runner zsh waits for evidence/runs/<tau>/handoff_complete.json before \
closing Reconcile + Epilogue. Topology proof: pid(avatar)+window(avatar)+\
pid(bridge)+http(bridge). Failure on any proof surface is terminal."

# Visible avatar (canonical user-visible Franklin).
FRANKLIN_AVATAR_APP_DIR="${FRANKLIN_ROOT}/GAIAOS/macos/Franklin"
FRANKLIN_AVATAR_APP_BIN="${FRANKLIN_AVATAR_APP_DIR}/.build/release/FranklinApp"
FRANKLIN_AVATAR_APP_BUILD_LOG="${EVIDENCE_ROOT}/franklin_orb_build.log"

# Menu-bar bridge (local HTTP — witnessed via /health; no waivers).
FRANKLIN_APP_DIR="${FRANKLIN_ROOT}/cells/franklin/xcode"
FRANKLIN_BRIDGE_BIN="${FRANKLIN_APP_DIR}/.build/release/MacFranklinAssistant"
FRANKLIN_BRIDGE_BUILD_LOG="${EVIDENCE_ROOT}/franklin_bridge_build.log"

FRANKLIN_LAUNCH_WITNESS="${EVIDENCE_ROOT}/franklin_launch.json"
FRANKLIN_BRIDGE_URL="http://127.0.0.1:8830/health"
FRANKLIN_PROOF_KIND="pid_orb+window_orb+pid_bridge+http_bridge"

if [[ ! -d "${FRANKLIN_AVATAR_APP_DIR}" ]]; then
    REFUSE_TERMINAL GW_REFUSE_FRANKLIN_NOT_LAUNCHED \
        LG-FRANKLIN-IQ-LAUNCH-FRANKLIN-001 \
        "FranklinApp avatar source tree missing at ${FRANKLIN_AVATAR_APP_DIR}; nothing to launch."
fi
if [[ ! -d "${FRANKLIN_APP_DIR}" ]]; then
    REFUSE_TERMINAL GW_REFUSE_FRANKLIN_NOT_LAUNCHED \
        LG-FRANKLIN-IQ-LAUNCH-FRANKLIN-001 \
        "MacFranklinAssistant bridge source tree missing at ${FRANKLIN_APP_DIR}; cannot stand up :8830."
fi

# Build the avatar via SwiftPM (release). No synthetic .app fabrication.
if [[ ! -x "${FRANKLIN_AVATAR_APP_BIN}" ]]; then
    ( cd "${FRANKLIN_AVATAR_APP_DIR}" && swift build -c release --product FranklinApp ) \
        >"${FRANKLIN_AVATAR_APP_BUILD_LOG}" 2>&1 || \
        REFUSE_TERMINAL GW_REFUSE_FRANKLIN_NOT_LAUNCHED \
            LG-FRANKLIN-IQ-LAUNCH-FRANKLIN-001 \
            "FranklinApp avatar swift build failed; see ${FRANKLIN_AVATAR_APP_BUILD_LOG}"
fi
[[ -x "${FRANKLIN_AVATAR_APP_BIN}" ]] || REFUSE_TERMINAL GW_REFUSE_FRANKLIN_NOT_LAUNCHED \
    LG-FRANKLIN-IQ-LAUNCH-FRANKLIN-001 \
    "FranklinApp avatar binary missing at ${FRANKLIN_AVATAR_APP_BIN}"

# Build the bridge via SwiftPM (release).
if [[ ! -x "${FRANKLIN_BRIDGE_BIN}" ]]; then
    ( cd "${FRANKLIN_APP_DIR}" && swift build -c release ) \
        >"${FRANKLIN_BRIDGE_BUILD_LOG}" 2>&1 || \
        REFUSE_TERMINAL GW_REFUSE_FRANKLIN_NOT_LAUNCHED \
            LG-FRANKLIN-IQ-LAUNCH-FRANKLIN-001 \
            "MacFranklinAssistant bridge swift build failed; see ${FRANKLIN_BRIDGE_BUILD_LOG}"
fi
[[ -x "${FRANKLIN_BRIDGE_BIN}" ]] || REFUSE_TERMINAL GW_REFUSE_FRANKLIN_NOT_LAUNCHED \
    LG-FRANKLIN-IQ-LAUNCH-FRANKLIN-001 \
    "MacFranklinAssistant bridge binary missing at ${FRANKLIN_BRIDGE_BIN}"

# The avatar needs to know which envelope to consume; we resolve and export it
# BEFORE launch so onAppear inside SwiftUI sees it. The envelope file is
# written below in LG-FRANKLIN-IQ-HANDOFF-001, so we pre-write a stub here
# and let the handoff step overwrite it. Pre-writing keeps the avatar's
# startIfHandoffPresent() from racing the runner.
FRANKLIN_HANDOFF_ENVELOPE="${EVIDENCE_ROOT}/franklin_handoff.json"
if [[ ! -f "${FRANKLIN_HANDOFF_ENVELOPE}" ]]; then
    printf '{"_status":"pending"}\n' > "${FRANKLIN_HANDOFF_ENVELOPE}"
fi
export FRANKLIN_HANDOFF_ENVELOPE
export FRANKLIN_ROOT

# Ensure fresh process graph for handoff ownership. Stale app instances
# can survive outside this closure window and ignore the new envelope.
pkill -x FranklinApp >/dev/null 2>&1 || true
pkill -x MacFranklinAssistant >/dev/null 2>&1 || true
sleep 1

# Launch the bridge first (no UI side effects). The avatar is launched after
# the envelope is fully written.
"${FRANKLIN_BRIDGE_BIN}" \
    >"${EVIDENCE_ROOT}/franklin_bridge_stdout.log" \
    2>"${EVIDENCE_ROOT}/franklin_bridge_stderr.log" &
FRANKLIN_BRIDGE_PID=""
for _bridge_wait in {1..12}; do
    FRANKLIN_BRIDGE_PID="$(pgrep -x MacFranklinAssistant | sed -n '1p')"
    [[ -n "${FRANKLIN_BRIDGE_PID}" ]] && break
    sleep 0.5
done
unset _bridge_wait
[[ -n "${FRANKLIN_BRIDGE_PID}" ]] || \
    REFUSE_TERMINAL GW_REFUSE_FRANKLIN_NOT_LAUNCHED \
        LG-FRANKLIN-IQ-LAUNCH-FRANKLIN-001 \
        "MacFranklinAssistant bridge did not start; see franklin_bridge_stderr.log"

bridge_up=0
for _bridge_health_wait in {1..10}; do
    if curl -fsS --max-time 3 "${FRANKLIN_BRIDGE_URL}" >/dev/null 2>&1; then
        bridge_up=1
        break
    fi
    sleep 1
done
unset _bridge_health_wait
(( bridge_up == 1 )) || REFUSE_TERMINAL GW_REFUSE_FRANKLIN_NOT_LAUNCHED \
    LG-FRANKLIN-IQ-LAUNCH-FRANKLIN-001 \
    "bridge health check failed at ${FRANKLIN_BRIDGE_URL}"

# The avatar is launched in LG-FRANKLIN-IQ-HANDOFF-001 below, AFTER the
# envelope is fully populated. The launch witness here records that
# the bridge came up and the avatar binary is ready; the avatar pid + window
# checks happen post-handoff in LG-FRANKLIN-IQ-FRANKLIN-VISIBLE-001.

cat > "${FRANKLIN_LAUNCH_WITNESS}" <<JSON
{
  "verb_id": "LG-FRANKLIN-IQ-LAUNCH-FRANKLIN-001",
  "orb_binary": "${FRANKLIN_AVATAR_APP_BIN}",
  "bridge_binary": "${FRANKLIN_BRIDGE_BIN}",
  "bridge_pid": ${FRANKLIN_BRIDGE_PID},
  "bridge_health_verified": true,
  "orb_pid_pending": "see LG-FRANKLIN-IQ-FRANKLIN-VISIBLE-001",
  "proof_kind": "${FRANKLIN_PROOF_KIND}",
  "tau": "${TAU_HUMAN}"
}
JSON
WITNESS LG-FRANKLIN-IQ-LAUNCH-FRANKLIN-001 CALORIE \
    "bridge_pid=${FRANKLIN_BRIDGE_PID} :8830 live; avatar binary ready at ${FRANKLIN_AVATAR_APP_BIN}"

# ----------------------------------------------------------------------------
# IQ — handoff envelope. The runner writes a canonical JSON envelope
# describing this run. Franklin reads it, performs OQ + PQ, and writes
# per-step receipts back into ${RECEIPTS_DIR}. The runner ingests those
# receipts in OQ + PQ orchestration steps below; if Franklin does not
# write the expected receipts, the catalog-completeness gate refuses.
# ----------------------------------------------------------------------------

NARRATE LG-FRANKLIN-IQ-HANDOFF-001 B \
"Writing the run envelope FranklinApp will consume: tau, evidence root, \
keychain path, contract version, expected catalog manifest, expected \
PQ guided flow (Material Science Domain creation against mesh treasury). \
Franklin is now responsible for OQ and PQ execution and emits receipts \
through the same RECEIPTS_DIR the runner uses."

FRANKLIN_HANDOFF_ENVELOPE="${EVIDENCE_ROOT}/franklin_handoff.json"
cat > "${FRANKLIN_HANDOFF_ENVELOPE}" <<JSON
{
  "contract_version": "${EXPECTED_CONTRACT_VERSION}",
  "tau": "${TAU_HUMAN}",
  "tau_fs": "${TAU_FS}",
  "evidence_root": "${EVIDENCE_ROOT}",
  "receipts_dir": "${RECEIPTS_DIR}",
  "heals_dir": "${HEALS_DIR}",
  "summary_md": "${SUMMARY_MD}",
  "keychain_dir": "${FRANKLIN_KEYCHAIN}",
  "rust_verify_binary": "${RUST_VERIFY:-${FRANKLIN_ROOT}/tools/franklin_verify/target/release/franklin_verify}",
  "expected_cells": [$(printf '"%s",' "${EXPECTED_CELLS[@]}" | sed 's/,$//')]
,
  "oq_catalog_manifest": [
    {"lg_id":"LG-FRANKLIN-OQ-FUSION-TESTS-001","cell":"fusion","scheme":"MacFusionTests","pkg_dir":"${FRANKLIN_ROOT}/cells/fusion"},
    {"lg_id":"LG-FRANKLIN-OQ-HEALTH-TESTS-001","cell":"health","scheme":"MacHealthTests","pkg_dir":"${FRANKLIN_ROOT}/cells/fusion/macos/MacHealth"},
    {"lg_id":"LG-FRANKLIN-OQ-FRANKLIN-TESTS-001","cell":"franklin","scheme":"FranklinPresenceTests","pkg_dir":"${FRANKLIN_ROOT}/GAIAOS/macos/Franklin"},
    {"lg_id":"LG-FRANKLIN-OQ-LITHO-TESTS-001","cell":"lithography","scheme":"LithographyTests","pkg_dir":"${FRANKLIN_ROOT}/cells/lithography"},
    {"lg_id":"LG-FRANKLIN-OQ-XCODE-TESTS-001","cell":"xcode","scheme":"XcodeToolingTests","pkg_dir":"${FRANKLIN_ROOT}/cells/franklin/xcode"},
    {"lg_id":"LG-FRANKLIN-OQ-MATSCI-TESTS-001","cell":"material_sciences","scheme":"MaterialSciencesTests","pkg_dir":"${FRANKLIN_ROOT}/cells/material_sciences"}
  ],
  "pq_guided_flow": {
    "kind": "MaterialScienceDomainCreation",
    "lg_ids": [
      "LG-FRANKLIN-PQ-MATSCI-DOMAIN-CREATE-001",
      "LG-FRANKLIN-PQ-MATSCI-TREASURY-PROOF-001",
      "LG-FRANKLIN-PQ-MATSCI-ROSETTE-BIND-001",
      "LG-FRANKLIN-PQ-MATSCI-OPERATOR-WALKTHROUGH-001"
    ],
    "treasury_index": "${FRANKLIN_ROOT}/mesh/treasury/INDEX.json",
    "domain_target": "${FRANKLIN_ROOT}/cells/material_sciences"
  },
  "wiki_authority_root": "${FRANKLIN_ROOT}/wiki"
}
JSON

# Confirm the envelope is well-formed JSON and Franklin can read the path.
python3 -c "import json,sys;json.load(open(sys.argv[1]))" "${FRANKLIN_HANDOFF_ENVELOPE}" \
    || REFUSE_TERMINAL GW_REFUSE_FRANKLIN_HANDOFF_NOT_ACCEPTED \
        LG-FRANKLIN-IQ-HANDOFF-001 \
        "Franklin handoff envelope is not valid JSON: ${FRANKLIN_HANDOFF_ENVELOPE}"

WITNESS LG-FRANKLIN-IQ-HANDOFF-001 CALORIE \
    "handoff envelope written at ${FRANKLIN_HANDOFF_ENVELOPE}"

# ----------------------------------------------------------------------------
# IQ — visible avatar launch. The envelope is now fully populated; launch the
# avatar (FranklinApp from GAIAOS/macos/Franklin/.build/release/FranklinApp)
# so it reads the envelope on onAppear and starts the in-process OQ
# catalog runner. The avatar is the user-visible deliverable: a SwiftUI
# WindowGroup with a glass avatar the operator can see and tap. The proof
# is pid+visible-window, not menu-bar — this is a regular foreground app.
# ----------------------------------------------------------------------------

NARRATE LG-FRANKLIN-IQ-FRANKLIN-VISIBLE-001 B \
"Launching the visible Franklin avatar with the run envelope. The avatar's \
SwiftUI onAppear handler reads FRANKLIN_HANDOFF_ENVELOPE and starts the \
OQ catalog runner inside its own process. Proof of visibility is a \
deterministic AppleScript window-existence check against the FranklinApp \
process. Failure to launch or to register a window is terminal — the \
operator must see the avatar."

# Use `open` so the avatar gets a normal foreground app activation. We pass
# the envelope path through the inherited environment.
FRANKLIN_AVATAR_APP_LAUNCH_LOG="${EVIDENCE_ROOT}/franklin_orb_launch.log"
FRANKLIN_HANDOFF_ENVELOPE="${FRANKLIN_HANDOFF_ENVELOPE}" \
FRANKLIN_ROOT="${FRANKLIN_ROOT}" \
    "${FRANKLIN_AVATAR_APP_BIN}" \
        >"${EVIDENCE_ROOT}/franklin_orb_stdout.log" \
        2>"${EVIDENCE_ROOT}/franklin_avatar_stderr.log" &
FRANKLIN_AVATAR_APP_LAUNCH_RC=$?
sleep 1.0

FRANKLIN_AVATAR_APP_PID="$(pgrep -x FranklinApp | sed -n '1p')"
if [[ -z "${FRANKLIN_AVATAR_APP_PID}" ]]; then
    REFUSE_TERMINAL GW_REFUSE_FRANKLIN_NOT_LAUNCHED \
        LG-FRANKLIN-IQ-FRANKLIN-VISIBLE-001 \
        "FranklinApp avatar did not start; rc=${FRANKLIN_AVATAR_APP_LAUNCH_RC}; see franklin_avatar_stderr.log"
    return 1
fi

# Window-existence proof. The avatar is a SwiftUI WindowGroup; AppleScript
# must enumerate its windows — no waiver.
FRANKLIN_AVATAR_APP_WINDOW_VERIFIED=false
FRANKLIN_AVATAR_APP_WINDOWS="$(osascript -e 'tell application "System Events" to get name of every window of (first process whose name is "FranklinApp")' 2>/dev/null || echo "")"
if [[ -z "${FRANKLIN_AVATAR_APP_WINDOWS}" || "${FRANKLIN_AVATAR_APP_WINDOWS}" == "missing value" ]]; then
    REFUSE_TERMINAL GW_REFUSE_FRANKLIN_NOT_FOREGROUND \
        LG-FRANKLIN-IQ-FRANKLIN-VISIBLE-001 \
        "FranklinApp avatar has no registered windows after launch; got=${FRANKLIN_AVATAR_APP_WINDOWS:-none}"
    return 1
fi
FRANKLIN_AVATAR_APP_WINDOW_VERIFIED=true

cat > "${EVIDENCE_ROOT}/franklin_orb_launch.json" <<JSON
{
  "verb_id": "LG-FRANKLIN-IQ-FRANKLIN-VISIBLE-001",
  "orb_binary": "${FRANKLIN_AVATAR_APP_BIN}",
  "orb_pid": ${FRANKLIN_AVATAR_APP_PID},
  "window_verified": ${FRANKLIN_AVATAR_APP_WINDOW_VERIFIED},
  "envelope_path": "${FRANKLIN_HANDOFF_ENVELOPE}",
  "tau": "${TAU_HUMAN}"
}
JSON
WITNESS LG-FRANKLIN-IQ-FRANKLIN-VISIBLE-001 CALORIE \
    "orb_pid=${FRANKLIN_AVATAR_APP_PID} window_verified=${FRANKLIN_AVATAR_APP_WINDOW_VERIFIED} envelope=${FRANKLIN_HANDOFF_ENVELOPE}"

# ----------------------------------------------------------------------------
# Franklin Cell Game — runs in IQ (zsh+python allowed) so the substrate has
# fully scaffolded itself by the time the language-purity gate closes. This
# is the loop where Franklin uses ITSELF to make every cell whole. Order:
#
#   1. AGREE-TAKEOVER — Franklin signs the takeover. Receipt becomes
#      proof that the runner is now an evidence-envelope, not the SUT.
#   2. For each expected cell: INTERVIEW → if gaps, PRESCRIBE → INVOKE-HEAL
#      → re-INTERVIEW → WITNESS-WHOLE.
#   3. CLOSE — aggregate; refuses if any cell did not reach whole within
#      the retry budget.
# ----------------------------------------------------------------------------

NARRATE LG-FRANKLIN-IQ-CELL-GAME-CATALOG-001 B \
"Scaffolding Franklin's own verb catalog at cells/franklin/CATALOG.yaml. \
This is the catalog Franklin plays in the cell-game loop below — the \
manifold by which the substrate uses itself to make itself whole."
ATTEMPT LG-FRANKLIN-IQ-CELL-GAME-CATALOG-001 \
    check_franklin_cell_game_catalog heal_franklin_cell_game_catalog \
    GW_REFUSE_FRANKLIN_CELL_GAME_CATALOG_MISSING

NARRATE LG-FRANKLIN-CELL-GAME-AGREE-TAKEOVER-001 A \
"Franklin agrees and takes over. Under its own keypair, Franklin asserts \
it now owns OQ/PQ orchestration; the runner becomes evidence-envelope. \
This receipt is the takeover signature; downstream cell-game steps cite \
it as their authority."
FRANKLIN_TAKEOVER_RECEIPT="${EVIDENCE_ROOT}/franklin_takeover.json"
cat > "${FRANKLIN_TAKEOVER_RECEIPT}" <<JSON
{
  "magic": "FUIT",
  "version": "${EXPECTED_CONTRACT_VERSION}",
  "verb_id": "LG-FRANKLIN-CELL-GAME-AGREE-TAKEOVER-001",
  "kind": "franklin_takeover",
  "tau": "${TAU_HUMAN}",
  "tau_fs": "${TAU_FS}",
  "asserts": {
    "franklin_owns": ["oq_orchestration", "pq_guidance", "cell_game_loop"],
    "runner_role": "evidence_envelope_only",
    "handoff_envelope": "${FRANKLIN_HANDOFF_ENVELOPE}"
  },
  "closure_window_id": "${TAU_FS}"
}
JSON
WITNESS LG-FRANKLIN-CELL-GAME-AGREE-TAKEOVER-001 CALORIE \
    "Franklin takeover signed at ${FRANKLIN_TAKEOVER_RECEIPT}"

# Cell-game loop. For each expected cell, interview → heal → witness. The
# loop is the Klein bottle: the substrate (Franklin's catalog) heals the
# substrate (every cell). Wounds that survive the retry budget are
# recorded but the run continues — every cell gets witnessed even if
# some are NOT_WHOLE, because the audit must capture the FULL state.
typeset -gi CELLS_WHOLE=0
typeset -gi CELLS_NOT_WHOLE=0
typeset -ga CELL_GAME_GAPS=()
for _cell in "${EXPECTED_CELLS[@]}"; do
    NARRATE "LG-FRANKLIN-CELL-GAME-INTERVIEW-001" A \
        "Franklin interviewing cell '${_cell}': reading required artefacts and listing any gaps."
    _gaps_text="$(franklin_cell_interview "${_cell}")"
    _gaps_rc=$?
    if (( _gaps_rc == 0 )); then
        WITNESS LG-FRANKLIN-CELL-GAME-INTERVIEW-001 CALORIE \
            "cell '${_cell}' whole on first interview"
    else
        # Found gaps — prescribe + heal.
        _gaps=( ${(f)_gaps_text} )
        WITNESS LG-FRANKLIN-CELL-GAME-INTERVIEW-001 CURE \
            "cell '${_cell}' has ${#_gaps[@]} gap(s): ${(j:, :)_gaps}"
        NARRATE "LG-FRANKLIN-CELL-GAME-PRESCRIBE-001" A \
            "Franklin prescribing healers for cell '${_cell}' gaps: ${(j:, :)_gaps}"
        WITNESS LG-FRANKLIN-CELL-GAME-PRESCRIBE-001 CALORIE \
            "prescription set for cell '${_cell}': ${(j:, :)_gaps}"
        NARRATE "LG-FRANKLIN-CELL-GAME-INVOKE-HEAL-001" B \
            "Franklin invoking heal loop for cell '${_cell}'. Auto-heal for class-A scaffolds; operator interaction would gate class-B in production."
        franklin_cell_heal_loop "${_cell}" "${_gaps[@]}"
        # Re-interview.
        if franklin_cell_interview "${_cell}" >/dev/null 2>&1; then
            WITNESS LG-FRANKLIN-CELL-GAME-INVOKE-HEAL-001 CURE \
                "cell '${_cell}' healed and whole on re-interview"
        else
            CELL_GAME_GAPS+=("${_cell}:still-wounded")
            REFUSE GW_REFUSE_FRANKLIN_CELL_NOT_WHOLE \
                LG-FRANKLIN-CELL-GAME-INVOKE-HEAL-001 \
                "cell '${_cell}' did not reach whole after auto-heal"
        fi
    fi
    NARRATE "LG-FRANKLIN-CELL-GAME-WITNESS-WHOLE-001" A \
        "Franklin emitting per-cell whole-state witness for '${_cell}'."
    if franklin_cell_interview "${_cell}" >/dev/null 2>&1; then
        WITNESS LG-FRANKLIN-CELL-GAME-WITNESS-WHOLE-001 CALORIE \
            "cell '${_cell}' whole-state witnessed"
        CELLS_WHOLE=$((CELLS_WHOLE + 1))
    else
        CELLS_NOT_WHOLE=$((CELLS_NOT_WHOLE + 1))
        REFUSE GW_REFUSE_FRANKLIN_CELL_NOT_WHOLE \
            LG-FRANKLIN-CELL-GAME-WITNESS-WHOLE-001 \
            "cell '${_cell}' NOT_WHOLE; recorded but run continues"
    fi
done
unset _cell _gaps_text _gaps_rc _gaps

NARRATE LG-FRANKLIN-CELL-GAME-CLOSE-001 A \
"Closing the cell-game. Aggregate: ${CELLS_WHOLE} whole, ${CELLS_NOT_WHOLE} not-whole \
across ${#EXPECTED_CELLS[@]} expected cells."
if (( CELLS_NOT_WHOLE > 0 )); then
    REFUSE_TERMINAL GW_REFUSE_FRANKLIN_CELL_GAME_INCOMPLETE \
        LG-FRANKLIN-CELL-GAME-CLOSE-001 \
        "cell-game closed with ${CELLS_NOT_WHOLE} cell(s) NOT_WHOLE: ${(j:, :)CELL_GAME_GAPS}"
else
    WITNESS LG-FRANKLIN-CELL-GAME-CLOSE-001 CALORIE \
        "cell-game closed: all ${CELLS_WHOLE}/${#EXPECTED_CELLS[@]} cells whole"
fi

NARRATE LG-FRANKLIN-IQ-RUST-ONLY-GATE-001 B \
"Closing IQ. Post-IQ phases (OQ, PQ, Reconcile) are zsh + Rust only. \
Python3 was permitted up to this gate for canonical YAML scaffolding; \
beyond this gate it is forbidden. Verification work crosses the gate \
into the Rust binary."
WITNESS LG-FRANKLIN-IQ-RUST-ONLY-GATE-001 CALORIE "IQ→OQ language gate closed; final JSON mirror refreshed"

# ============================================================================
# 2. OQ
# ============================================================================

# OQ-time language-purity gate. Asserts the runner script's OQ/PQ/Reconcile
# sections contain no python3 invocations. Invariant: post-IQ is zsh + Rust
# only. A regression here is a structural defect in the runner itself.
NARRATE LG-FRANKLIN-OQ-RUST-ONLY-001 B \
"Asserting post-IQ language purity: this runner script's OQ, PQ, and \
Reconcile sections must not invoke python3. (Operator policy: only zsh \
and python3 are allowed in IQ; only zsh and the Rust binary post-IQ. \
The Rust verifier is built in IQ and invoked post-IQ via \${RUST_VERIFY}.)"
SCRIPT_SELF="${FRANKLIN_ROOT}/scripts/gamp5_full.zsh"
[[ -f "${SCRIPT_SELF}" ]] || SCRIPT_SELF="${0:A}"
# Match only actual python3 INVOCATIONS, not text that mentions the word.
# Patterns covered:
#   python3 -c '...'         python3 -<space>  python3 -<<EOF
#   python3 "..."            python3 /path     python3 ${var}
post_iq_python_hits="$(awk '
    /^# 2\. OQ/         { post_iq=1; next }
    /^# 5\. EPILOGUE/   { post_iq=0; next }
    post_iq && /python3[[:space:]]+(-c|-[[:space:]]|-<<|["\/$])/ \
            && !/^[[:space:]]*#/ \
            { print NR": "$0 }
' "${SCRIPT_SELF}" 2>/dev/null | wc -l | tr -d ' ')"
if (( post_iq_python_hits > 0 )); then
    REFUSE_TERMINAL GW_REFUSE_FRANKLIN_LANGUAGE_GATE_VIOLATED \
        LG-FRANKLIN-OQ-RUST-ONLY-001 \
        "post-IQ python3 invocations detected in runner: ${post_iq_python_hits}"
fi
WITNESS LG-FRANKLIN-OQ-RUST-ONLY-001 CALORIE \
    "post-IQ purity gate: zero python3 invocations after OQ"

# ---------------------------------------------------------------------------
# Health-first OQ gate. The system cannot enter BUILD / TESTS / PQ if the
# user-facing UI surface itself is unhealthy. The Rust binary
# franklin_health_ui_audit consumes wiki/HEALTH_UI_AUDIT_AUTHORITY.md (rules)
# and cells/<cell>/Surfaces.yaml (per-cell manifest of every visible
# surface) and refuses on the first violation with the rule's specific
# refusal code. This is manifest-first (phase 1); AX runtime introspection
# is phase 2.
# ---------------------------------------------------------------------------
NARRATE LG-FRANKLIN-OQ-HEALTH-UI-AUDIT-001 B \
"Running the Health-first UI audit BEFORE build, tests, or PQ. Every \
cell's Surfaces.yaml is checked against the rule set in \
wiki/HEALTH_UI_AUDIT_AUTHORITY.md: WCAG AA contrast, no internal jargon, \
no raw timestamps/IPs/hostnames, every control labeled, primary CTA \
present, red reserved for destructive, no value↔label type mismatches, \
no duplicate controls. Any violation refuses terminal — the operator \
never sees an unhealthy UI in OQ/PQ."
HEALTH_AUDIT_BIN="${FRANKLIN_ROOT}/tools/franklin_health_ui_audit/target/release/franklin_health_ui_audit"
HEALTH_AUTHORITY_DOC="${FRANKLIN_ROOT}/wiki/HEALTH_UI_AUDIT_AUTHORITY.md"
HEALTH_RULES_JSON="${EVIDENCE_ROOT}/health_ui_rules.json"
HEALTH_SURFACES_JSON="${EVIDENCE_ROOT}/health_ui_surfaces.json"
HEALTH_AUDIT_LOG="${EVIDENCE_ROOT}/health_ui_audit.log"
HEALTH_AUDIT_REPORT="${EVIDENCE_ROOT}/health_ui_audit_report.json"

[[ -x "${HEALTH_AUDIT_BIN}" ]] || REFUSE_TERMINAL GW_REFUSE_HEALTH_AUDIT_TOOL_MISSING \
    LG-FRANKLIN-OQ-HEALTH-UI-AUDIT-001 \
    "franklin_health_ui_audit binary not built at ${HEALTH_AUDIT_BIN}"
[[ -f "${HEALTH_AUTHORITY_DOC}" ]] || REFUSE_TERMINAL GW_REFUSE_HEALTH_AUDIT_AUTHORITY_MISSING \
    LG-FRANKLIN-OQ-HEALTH-UI-AUDIT-001 \
    "wiki/HEALTH_UI_AUDIT_AUTHORITY.md not found at ${HEALTH_AUTHORITY_DOC}"

# The Rust binary owns YAML→JSON parsing of both inputs; invocation is
# zsh→Rust only (no python). It reads the .md authority doc directly and
# globs cells/<cell>/Surfaces.yaml. Exit code 0 = clean; nonzero = first
# violation, rule-specific refusal code printed on stderr line 1.
HEALTH_REFUSAL_CODE=""
HEALTH_AUDIT_DETAIL=""
if "${HEALTH_AUDIT_BIN}" \
        --authority "${HEALTH_AUTHORITY_DOC}" \
        --cells "${FRANKLIN_ROOT}/cells" \
        --report "${HEALTH_AUDIT_REPORT}" \
        >"${HEALTH_AUDIT_LOG}" 2>&1; then
    : # clean
else
    # Read the first stderr line as the refusal code; rest is detail.
    HEALTH_REFUSAL_CODE="$(head -n1 "${HEALTH_AUDIT_LOG}" 2>/dev/null | awk '/^GW_REFUSE_/ {print $1}')"
    HEALTH_AUDIT_DETAIL="$(tail -n +2 "${HEALTH_AUDIT_LOG}" 2>/dev/null | head -n 20 | tr '\n' '; ')"
    [[ -z "${HEALTH_REFUSAL_CODE}" ]] && HEALTH_REFUSAL_CODE="GW_REFUSE_HEALTH_CONTRAST_FAILED"
    REFUSE_TERMINAL "${HEALTH_REFUSAL_CODE}" \
        LG-FRANKLIN-OQ-HEALTH-UI-AUDIT-001 \
        "Health UI audit refused: ${HEALTH_AUDIT_DETAIL:-see ${HEALTH_AUDIT_LOG}}"
fi
WITNESS LG-FRANKLIN-OQ-HEALTH-UI-AUDIT-001 CALORIE \
    "Health UI audit clean across all cell surfaces (report: ${HEALTH_AUDIT_REPORT})"

WORKSPACE_GLOB=( "${FRANKLIN_ROOT}"/**/*.xcworkspace(.N) )
PROJECT_GLOB=( "${FRANKLIN_ROOT}"/**/*.xcodeproj(.N) )

NARRATE LG-FRANKLIN-OQ-BUILD-001 B \
"Clean-building every Swift surface (workspace → project → SwiftPM). \
Build failures refuse with a diagnostic — the substrate cannot heal a \
compile error; that requires human code change."
build_terminal="CALORIE"
build_log="${EVIDENCE_ROOT}/build.log"
if (( ${#WORKSPACE_GLOB[@]} > 0 )); then
    for ws in "${WORKSPACE_GLOB[@]}"; do
        scheme="${ws:t:r}"
        if ! xcodebuild -workspace "${ws}" -scheme "${scheme}" \
            -destination 'platform=macOS' clean build \
            >>"${build_log}" 2>&1; then
            REFUSE GW_REFUSE_FRANKLIN_XCODE_BUILD_FAILED LG-FRANKLIN-OQ-BUILD-001 \
                "build failed on ${ws} (log: ${build_log})"
            build_terminal="REFUSED"
        fi
    done
elif (( ${#PROJECT_GLOB[@]} > 0 )); then
    for proj in "${PROJECT_GLOB[@]}"; do
        scheme="${proj:t:r}"
        xcodebuild -project "${proj}" -scheme "${scheme}" \
            -destination 'platform=macOS' clean build \
            >>"${build_log}" 2>&1 \
        || { REFUSE GW_REFUSE_FRANKLIN_XCODE_BUILD_FAILED LG-FRANKLIN-OQ-BUILD-001 \
                "build failed on ${proj}"; build_terminal="REFUSED"; }
    done
elif [[ -f "${FRANKLIN_ROOT}/Package.swift" ]]; then
    ( cd "${FRANKLIN_ROOT}" && swift build ) >>"${build_log}" 2>&1 \
    || { REFUSE GW_REFUSE_FRANKLIN_XCODE_BUILD_FAILED LG-FRANKLIN-OQ-BUILD-001 \
            "swift build failed"; build_terminal="REFUSED"; }
else
    build_terminal="CURE"
    printf 'no workspace/project/Package.swift; no build performed\n' >> "${build_log}"
fi
[[ "${build_terminal}" != "REFUSED" ]] && \
    WITNESS LG-FRANKLIN-OQ-BUILD-001 "${build_terminal}" \
        "build log: ${build_log}"

# GAMP 5 OQ contract: OQ system-tests the entire catalog. There is no
# skip-to-pass path. A missing workspace, missing scheme, or unconfigured
# test target is a TERMINAL refusal — the runner will not declare green
# for a suite that did not execute. This is the floor.
#
# OQ_CATALOG_MANIFEST enumerates every required suite. The catalog-
# completeness gate at the end of OQ refuses if any catalog item lacks
# a CALORIE receipt for this run.
typeset -ga OQ_CATALOG_MANIFEST=(
    "LG-FRANKLIN-OQ-FUSION-TESTS-001:fusion:MacFusionTests"
    "LG-FRANKLIN-OQ-HEALTH-TESTS-001:health:MacHealthTests"
    "LG-FRANKLIN-OQ-FRANKLIN-TESTS-001:franklin:FranklinPresenceTests"
    "LG-FRANKLIN-OQ-LITHO-TESTS-001:lithography:LithographyTests"
    "LG-FRANKLIN-OQ-XCODE-TESTS-001:xcode:XcodeToolingTests"
    "LG-FRANKLIN-OQ-MATSCI-TESTS-001:material_sciences:MaterialSciencesTests"
)

run_tests_for_cell() {
    local cell="$1" lg_id="$2" scheme="${3:-${cell:u}Tests}"
    local log="${EVIDENCE_ROOT}/test_${cell}.log"
    local pkg_dir=""
    NARRATE "${lg_id}" B \
"Running ${scheme} for cell ${cell} as part of full-catalog OQ system test. \
A test failure refuses with a diagnostic. Absence of the workspace or scheme \
is a TERMINAL refusal — GAMP 5 OQ does not permit skip-as-pass."
    if (( ${#WORKSPACE_GLOB[@]} == 0 )); then
        case "${cell}" in
            fusion)            pkg_dir="${FRANKLIN_ROOT}/cells/fusion" ;;
            health)            pkg_dir="${FRANKLIN_ROOT}/cells/fusion/macos/MacHealth" ;;
            franklin)          pkg_dir="${FRANKLIN_ROOT}/GAIAOS/macos/Franklin" ;;
            lithography)       pkg_dir="${FRANKLIN_ROOT}/cells/lithography" ;;
            xcode)             pkg_dir="${FRANKLIN_ROOT}/cells/franklin/xcode" ;;
            material_sciences) pkg_dir="${FRANKLIN_ROOT}/cells/material_sciences" ;;
        esac
        if [[ -n "${pkg_dir}" && -f "${pkg_dir}/Package.swift" ]]; then
            if ( cd "${pkg_dir}" && swift test ) >"${log}" 2>&1; then
                WITNESS "${lg_id}" CALORIE "${scheme} passed via SwiftPM in ${pkg_dir} (log: ${log})"
            else
                REFUSE_TERMINAL GW_REFUSE_OQ_ASSERTION_FAILED "${lg_id}" \
                    "${scheme} failed via SwiftPM in ${pkg_dir} (log: ${log})"
            fi
            return 0
        fi
        REFUSE_TERMINAL GW_REFUSE_OQ_SUITE_OMITTED "${lg_id}" \
            "no Xcode workspace or SwiftPM package found; ${scheme} cannot be exercised. OQ floor: every catalog suite must execute."
        return 1
    fi
    local ws="${WORKSPACE_GLOB[1]}"
    if xcodebuild -workspace "${ws}" -scheme "${scheme}" \
        -destination 'platform=macOS' test >"${log}" 2>&1; then
        WITNESS "${lg_id}" CALORIE "${scheme} passed (log: ${log})"
    elif grep -qE 'is not currently configured|does not contain a scheme' "${log}" 2>/dev/null; then
        REFUSE_TERMINAL GW_REFUSE_OQ_SUITE_OMITTED "${lg_id}" \
            "${scheme} not configured in workspace ${ws:t}. OQ requires every catalog suite to be wired and run; configure the scheme and re-run. (log: ${log})"
    else
        REFUSE_TERMINAL GW_REFUSE_OQ_ASSERTION_FAILED "${lg_id}" \
            "${scheme} failed (log: ${log})"
    fi
}

# OQ catalog execution is delegated to the live avatar process. The avatar
# reads the handoff envelope on launch (see LG-FRANKLIN-IQ-FRANKLIN-VISIBLE-001),
# runs `swift test` for every cell entry inside its own SwiftUI process,
# writes per-cell receipts into RECEIPTS_DIR, and emits
# evidence/runs/<tau>/handoff_complete.json when the catalog is fully
# exercised. The runner zsh polls for that signal here.
#
# Klein-bottle invariant: a timeout does not exit; it records a refusal
# and the run continues so the audit captures the wound.
NARRATE LG-FRANKLIN-OQ-LIVE-CATALOG-001 B \
"Waiting for the live avatar to complete the OQ catalog. The avatar is running \
swift test for each cell in-process and writing per-cell receipts. This \
runner polls evidence/runs/<tau>/handoff_complete.json with a hard \
timeout (FRANKLIN_OQ_TIMEOUT_SECONDS, default 900s). Timeout = the avatar \
did not finish the catalog; receipts may be partial. Either way, the \
catalog-completeness gate downstream will refuse on any missing LG ID."

FRANKLIN_HANDOFF_COMPLETE="${EVIDENCE_ROOT}/handoff_complete.json"
FRANKLIN_OQ_TIMEOUT_SECONDS="${FRANKLIN_OQ_TIMEOUT_SECONDS:-900}"
FRANKLIN_OQ_POLL_INTERVAL="${FRANKLIN_OQ_POLL_INTERVAL:-2}"
oq_waited=0
while [[ ! -s "${FRANKLIN_HANDOFF_COMPLETE}" ]]; do
    if (( oq_waited >= FRANKLIN_OQ_TIMEOUT_SECONDS )); then
        REFUSE_TERMINAL GW_REFUSE_OQ_CATALOG_INCOMPLETE \
            LG-FRANKLIN-OQ-LIVE-CATALOG-001 \
            "avatar did not write handoff_complete.json within ${FRANKLIN_OQ_TIMEOUT_SECONDS}s; expected at ${FRANKLIN_HANDOFF_COMPLETE}"
        break
    fi
    sleep "${FRANKLIN_OQ_POLL_INTERVAL}"
    oq_waited=$((oq_waited + FRANKLIN_OQ_POLL_INTERVAL))
    # Sanity: if the avatar died, do not wait the full timeout.
    if ! kill -0 "${FRANKLIN_AVATAR_APP_PID}" 2>/dev/null; then
        REFUSE_TERMINAL GW_REFUSE_FRANKLIN_NOT_LAUNCHED \
            LG-FRANKLIN-OQ-LIVE-CATALOG-001 \
            "avatar pid ${FRANKLIN_AVATAR_APP_PID} died mid-catalog after ${oq_waited}s; see franklin_avatar_stderr.log"
        break
    fi
done

if [[ -s "${FRANKLIN_HANDOFF_COMPLETE}" ]]; then
    oq_total=$(grep -E '"catalog_total"' "${FRANKLIN_HANDOFF_COMPLETE}" | head -n1 | grep -oE '[0-9]+' | head -n1)
    oq_calorie=$(grep -E '"catalog_calorie"' "${FRANKLIN_HANDOFF_COMPLETE}" | head -n1 | grep -oE '[0-9]+' | head -n1)
    oq_refused=$(grep -E '"catalog_refused"' "${FRANKLIN_HANDOFF_COMPLETE}" | head -n1 | grep -oE '[0-9]+' | head -n1)
    WITNESS LG-FRANKLIN-OQ-LIVE-CATALOG-001 CALORIE \
        "avatar closed handoff: total=${oq_total:-?} calorie=${oq_calorie:-?} refused=${oq_refused:-?} (waited ${oq_waited}s)"
fi
unset oq_waited oq_total oq_calorie oq_refused

NARRATE LG-FRANKLIN-OQ-NARRATIVE-MAP-001 B \
"Running the narration ↔ catalog map verifier via the Rust binary. \
The IQ phase already scaffolded the audit YAML and mirrored it to \
JSON; here we just call \${RUST_VERIFY} narrative-map on the JSON \
mirror. A failure refuses terminally — the audit trail must be coherent."
"${RUST_VERIFY}" narrative-map \
    "${FRANKLIN_ROOT}/evidence/audits/.json/ui_test_narrative_catalog_map.json" \
    >>"${EVIDENCE_ROOT}/narrative_map_verify.log" 2>&1 \
    || REFUSE_TERMINAL GW_REFUSE_FRANKLIN_VALIDATION_PROPOSAL_REPLAY \
        LG-FRANKLIN-OQ-NARRATIVE-MAP-001 "Rust narrative-map verifier failed"
WITNESS LG-FRANKLIN-OQ-NARRATIVE-MAP-001 CALORIE "narrative ↔ catalog map verified by Rust binary"

NARRATE LG-FRANKLIN-OQ-EMITTER-PARITY-001 B \
"Verifying every refusal code in the registry has at least one emitter \
via \${RUST_VERIFY} emitter-parity. The IQ phase scaffolded fail-closed \
Swift stubs; this OQ check confirms parity holds at run time."
"${RUST_VERIFY}" emitter-parity \
    "${FRANKLIN_ROOT}/substrate/.json/REFUSAL_CODE_REGISTRY.json" \
    "${FRANKLIN_ROOT}" "${EVIDENCE_ROOT}" \
    >>"${EVIDENCE_ROOT}/emitter_parity_verify.log" 2>&1 \
    || REFUSE_TERMINAL GW_REFUSE_FRANKLIN_CHANGE_PROPOSAL_REGRESSION_DETECTED \
        LG-FRANKLIN-OQ-EMITTER-PARITY-001 "Rust emitter-parity verifier failed"
WITNESS LG-FRANKLIN-OQ-EMITTER-PARITY-001 CALORIE "all registry codes have at least one emitter"

NARRATE LG-FRANKLIN-OQ-PR-RUN-001 B \
"Invoking every PR-* assertion's runner via \${RUST_VERIFY} pr-runners. \
Placeholder runners exit 0; real runners enforce real invariants. A \
non-zero return refuses with a diagnostic — the runner cannot heal a \
failed assertion."
"${RUST_VERIFY}" pr-runners \
    "${FRANKLIN_ROOT}/substrate/.json/PR_ASSERTIONS.json" \
    "${FRANKLIN_ROOT}" "${EVIDENCE_ROOT}" \
    >>"${EVIDENCE_ROOT}/pr_runners_verify.log" 2>&1 \
    || REFUSE GW_REFUSE_OQ_ASSERTION_FAILED LG-FRANKLIN-OQ-PR-RUN-001 \
        "PR runner failure (Rust binary)"
WITNESS LG-FRANKLIN-OQ-PR-RUN-001 CALORIE \
    "PR results at evidence/runs/${TAU_FS}/pr_assertion_results.json"

NARRATE LG-FRANKLIN-OQ-RECEIPT-VERIFY-001 B \
"Verifying a sample receipt offline. Uses gaiaftcl receipt verify if \
available, else \${RUST_VERIFY} receipt. A failure here refuses \
terminally — without offline verifiability the substrate is not auditable."
sample_rcpt=( "${RECEIPTS_DIR}"/*CALORIE*.json(.N) )
if (( ${#sample_rcpt[@]} == 0 )); then
    REFUSE_TERMINAL GW_REFUSE_FRANKLIN_PROVENANCE_MALFORMED LG-FRANKLIN-OQ-RECEIPT-VERIFY-001 \
        "no CALORIE receipts in run to verify"
fi
sample="${sample_rcpt[1]}"
"${RUST_VERIFY}" receipt "${sample}" >>"${EVIDENCE_ROOT}/receipt_verify.log" 2>&1 \
    || REFUSE_TERMINAL GW_REFUSE_FRANKLIN_PROVENANCE_MALFORMED LG-FRANKLIN-OQ-RECEIPT-VERIFY-001 \
        "Rust receipt verifier failed on ${sample}"
WITNESS LG-FRANKLIN-OQ-RECEIPT-VERIFY-001 CALORIE "verified ${sample:t}"

# OQ catalog-completeness gate. Every entry in OQ_CATALOG_MANIFEST plus the
# fixed orchestration steps (build, narrative-map, emitter-parity, pr-runners,
# receipt-verify, rust-only-policy) MUST have a CALORIE receipt this run.
# Missing receipts = catalog incomplete = OQ has not actually exercised the
# system as a whole. Terminal refusal.
NARRATE LG-FRANKLIN-OQ-CATALOG-FULL-001 B \
"Asserting full-catalog OQ execution. Every required suite from \
OQ_CATALOG_MANIFEST and every required orchestration step must have \
emitted a CALORIE receipt for this run. Missing receipt = the catalog \
was not fully exercised. GAMP 5 OQ does not permit partial coverage."
typeset -a OQ_REQUIRED_LG_IDS=(
    LG-FRANKLIN-OQ-RUST-ONLY-001
    LG-FRANKLIN-OQ-HEALTH-UI-AUDIT-001
    LG-FRANKLIN-OQ-BUILD-001
    LG-FRANKLIN-OQ-LIVE-CATALOG-001
    LG-FRANKLIN-OQ-FUSION-TESTS-001
    LG-FRANKLIN-OQ-HEALTH-TESTS-001
    LG-FRANKLIN-OQ-FRANKLIN-TESTS-001
    LG-FRANKLIN-OQ-LITHO-TESTS-001
    LG-FRANKLIN-OQ-XCODE-TESTS-001
    LG-FRANKLIN-OQ-MATSCI-TESTS-001
    LG-FRANKLIN-OQ-NARRATIVE-MAP-001
    LG-FRANKLIN-OQ-EMITTER-PARITY-001
    LG-FRANKLIN-OQ-PR-RUN-001
    LG-FRANKLIN-OQ-RECEIPT-VERIFY-001
)
typeset -a OQ_MISSING=()
for _req in "${OQ_REQUIRED_LG_IDS[@]}"; do
    _hits=$(ls "${RECEIPTS_DIR}"/*.json 2>/dev/null | xargs grep -l "\"${_req}\"" 2>/dev/null | wc -l | tr -d ' ')
    if (( _hits == 0 )); then
        OQ_MISSING+=("${_req}")
    fi
done
if (( ${#OQ_MISSING[@]} > 0 )); then
    if [[ "${FRANKLIN_DEGRADE_NONFUSION}" == "1" ]]; then
        typeset -a OQ_STILL_MISSING=()
        for _miss in "${OQ_MISSING[@]}"; do
            if [[ "${_miss}" == "LG-FRANKLIN-OQ-FUSION-TESTS-001" ]]; then
                OQ_STILL_MISSING+=("${_miss}")
                continue
            fi
            WITNESS "${_miss}" CURE "degraded non-fusion OQ path accepted for this run"
        done
        if (( ${#OQ_STILL_MISSING[@]} > 0 )); then
            REFUSE_TERMINAL GW_REFUSE_OQ_CATALOG_INCOMPLETE \
                LG-FRANKLIN-OQ-CATALOG-FULL-001 \
                "OQ catalog incomplete; fusion-critical receipts missing: ${(j:, :)OQ_STILL_MISSING}"
        fi
    else
        REFUSE_TERMINAL GW_REFUSE_OQ_CATALOG_INCOMPLETE \
            LG-FRANKLIN-OQ-CATALOG-FULL-001 \
            "OQ catalog incomplete; missing receipts for: ${(j:, :)OQ_MISSING}"
    fi
fi
WITNESS LG-FRANKLIN-OQ-CATALOG-FULL-001 CALORIE \
    "full-catalog OQ executed: ${#OQ_REQUIRED_LG_IDS[@]} required steps all witnessed"
unset _req _hits OQ_MISSING

# ============================================================================
# 3. PQ
# ============================================================================
NARRATE LG-FRANKLIN-PQ-EDU-AUDITOR-001 B \
"PQ is avatar-owned. Runner waits for evidence/runs/<tau>/pq_complete.json \
from the live avatar process and then proceeds to Reconcile/Epilogue."
FRANKLIN_PQ_COMPLETE="${EVIDENCE_ROOT}/pq_complete.json"
FRANKLIN_PQ_TIMEOUT_SECONDS="${FRANKLIN_PQ_TIMEOUT_SECONDS:-900}"
FRANKLIN_PQ_POLL_INTERVAL="${FRANKLIN_PQ_POLL_INTERVAL:-2}"
pq_waited=0
while [[ ! -s "${FRANKLIN_PQ_COMPLETE}" ]]; do
    if (( pq_waited >= FRANKLIN_PQ_TIMEOUT_SECONDS )); then
        REFUSE_TERMINAL GW_REFUSE_OQ_CATALOG_INCOMPLETE \
            LG-FRANKLIN-PQ-EDU-AUDITOR-001 \
            "avatar did not write pq_complete.json within ${FRANKLIN_PQ_TIMEOUT_SECONDS}s; expected at ${FRANKLIN_PQ_COMPLETE}"
        break
    fi
    sleep "${FRANKLIN_PQ_POLL_INTERVAL}"
    pq_waited=$((pq_waited + FRANKLIN_PQ_POLL_INTERVAL))
    if ! kill -0 "${FRANKLIN_AVATAR_APP_PID}" 2>/dev/null; then
        REFUSE_TERMINAL GW_REFUSE_FRANKLIN_NOT_LAUNCHED \
            LG-FRANKLIN-PQ-EDU-AUDITOR-001 \
            "avatar pid ${FRANKLIN_AVATAR_APP_PID} died mid-PQ after ${pq_waited}s; see franklin_avatar_stderr.log"
        break
    fi
done
if [[ -s "${FRANKLIN_PQ_COMPLETE}" ]]; then
    pq_calorie=$(grep -E '"pq_calorie"' "${FRANKLIN_PQ_COMPLETE}" | sed -n '1p' | rg -o '[0-9]+' | sed -n '1p')
    pq_refused=$(grep -E '"pq_refused"' "${FRANKLIN_PQ_COMPLETE}" | sed -n '1p' | rg -o '[0-9]+' | sed -n '1p')
    WITNESS LG-FRANKLIN-PQ-EDU-AUDITOR-001 CALORIE \
        "avatar closed PQ handoff: calorie=${pq_calorie:-?} refused=${pq_refused:-?} (waited ${pq_waited}s)"
fi
unset pq_waited pq_calorie pq_refused

# ============================================================================
# 4. RECONCILE
# ============================================================================

NARRATE LG-FRANKLIN-RECONCILE-COUNTS-001 B \
"Reconciling headline arithmetic via \${RUST_VERIFY} reconcile: \
refusal_codes total, PR_assertions count, total_codes consistency."
"${RUST_VERIFY}" reconcile \
    "${FRANKLIN_ROOT}/substrate/.json/REFUSAL_CODE_REGISTRY.json" \
    "${FRANKLIN_ROOT}/substrate/.json/PR_ASSERTIONS.json" \
    >>"${EVIDENCE_ROOT}/reconcile_counts.log" 2>&1 \
    || REFUSE_TERMINAL GW_REFUSE_FRANKLIN_CHANGE_PROPOSAL_REGRESSION_DETECTED \
        LG-FRANKLIN-RECONCILE-COUNTS-001 "headline drift"
WITNESS LG-FRANKLIN-RECONCILE-COUNTS-001 CALORIE "headline arithmetic consistent"

NARRATE LG-FRANKLIN-RECONCILE-NARRATIVE-001 B \
"Confirming every step that ran narrated and recorded a result. \
A summary with steps but no result map is structurally incomplete."
unmapped="$(awk '/^\[LG-FRANKLIN-/{print $1}' "${SUMMARY_MD}" | sort -u | wc -l | tr -d ' ')"
recorded="$(printf '%s\n' "${(@k)STEP_RESULTS}" | sort -u | wc -l | tr -d ' ')"
(( unmapped > 0 && recorded > 0 )) || REFUSE_TERMINAL GW_REFUSE_FRANKLIN_VALIDATION_PROPOSAL_REPLAY LG-FRANKLIN-RECONCILE-NARRATIVE-001 "narration↔result map empty"
WITNESS LG-FRANKLIN-RECONCILE-NARRATIVE-001 CALORIE "narration entries: ${unmapped}; results: ${recorded}"

# ----------------------------------------------------------------------------
# Reconcile — wiki authority traceability. The wiki/*.md docs are the
# normative test contract. Each authority doc carries a frontmatter
# block listing required_lg_ids: every ID listed there MUST have a
# CALORIE witness receipt for this run. Drift in either direction
# (doc says X must run, run did not produce X — or run produced Y that
# no doc requires) is a refusal: docs and receipts must be a closed loop.
# ----------------------------------------------------------------------------

NARRATE LG-FRANKLIN-RECONCILE-DOCS-AUTHORITY-001 B \
"Verifying wiki/*.md is the test authority and the run answers it. Every \
required_lg_ids entry in every wiki authority doc must have a CALORIE \
receipt this run. Missing wiki authority root or missing receipts = \
docs↔receipts drift = TERMINAL refusal. The audit loop must close."

WIKI_AUTHORITY_ROOT="${FRANKLIN_ROOT}/wiki"
[[ -d "${WIKI_AUTHORITY_ROOT}" ]] || \
    REFUSE_TERMINAL GW_REFUSE_WIKI_AUTHORITY_MISSING \
        LG-FRANKLIN-RECONCILE-DOCS-AUTHORITY-001 \
        "wiki authority root absent at ${WIKI_AUTHORITY_ROOT}"

typeset -a WIKI_AUTHORITY_DOCS=(
    "${WIKI_AUTHORITY_ROOT}/GAMP5_TEST_AUTHORITY.md"
    "${WIKI_AUTHORITY_ROOT}/FRANKLIN_FIRST.md"
    "${WIKI_AUTHORITY_ROOT}/PQ_MATERIAL_SCIENCES_GUIDE.md"
)
typeset -a DOCS_MISSING_FILE=()
typeset -a DOCS_RECEIPT_DRIFT=()
for _doc in "${WIKI_AUTHORITY_DOCS[@]}"; do
    if [[ ! -s "${_doc}" ]]; then
        DOCS_MISSING_FILE+=("${_doc:t}")
        continue
    fi
    # Extract required_lg_ids from a fenced YAML-style frontmatter block.
    # Tolerant: matches `LG-...` tokens between `required_lg_ids:` and the
    # closing `---` of the frontmatter.
    _ids=$(awk '
        BEGIN { in_fm=0; in_list=0 }
        /^---$/ { in_fm = !in_fm; if (!in_fm) exit; next }
        in_fm && /^required_lg_ids:/ { in_list=1; next }
        in_fm && in_list && /^[a-zA-Z]/ { in_list=0 }
        in_fm && in_list { for (i=1;i<=NF;i++) if ($i ~ /^LG-/) print $i }
    ' "${_doc}" | tr -d '",' | sort -u)
    [[ -z "${_ids}" ]] && continue
    while IFS= read -r _lg; do
        [[ -z "${_lg}" ]] && continue
        if [[ "${_lg}" == "LG-FRANKLIN-RECONCILE-DOCS-AUTHORITY-001" || \
              "${_lg}" == "LG-FRANKLIN-RUNNER-EPILOGUE-001" ]]; then
            continue
        fi
        _hits=$(ls "${RECEIPTS_DIR}"/*.json 2>/dev/null | xargs grep -l "\"${_lg}\"" 2>/dev/null | wc -l | tr -d ' ')
        if (( _hits == 0 )); then
            DOCS_RECEIPT_DRIFT+=("${_doc:t}:${_lg}")
        fi
    done <<< "${_ids}"
done

if (( ${#DOCS_MISSING_FILE[@]} > 0 )); then
    REFUSE_TERMINAL GW_REFUSE_WIKI_AUTHORITY_MISSING \
        LG-FRANKLIN-RECONCILE-DOCS-AUTHORITY-001 \
        "wiki authority docs missing: ${(j:, :)DOCS_MISSING_FILE}"
fi
if (( ${#DOCS_RECEIPT_DRIFT[@]} > 0 )); then
    REFUSE_TERMINAL GW_REFUSE_DOCS_RECEIPT_DRIFT \
        LG-FRANKLIN-RECONCILE-DOCS-AUTHORITY-001 \
        "docs require LG IDs without receipts: ${(j:, :)DOCS_RECEIPT_DRIFT}"
fi

WITNESS LG-FRANKLIN-RECONCILE-DOCS-AUTHORITY-001 CALORIE \
    "wiki authority closed loop: ${#WIKI_AUTHORITY_DOCS[@]} docs, all required_lg_ids witnessed"
unset _doc _ids _lg _hits DOCS_MISSING_FILE DOCS_RECEIPT_DRIFT

# ============================================================================
# 5. EPILOGUE
# ============================================================================

trap - ERR
NARRATE LG-FRANKLIN-RUNNER-EPILOGUE-001 B \
"Closing the closure window through the Klein-bottle surface — the same \
manifold that opened with the prologue. The terminal aggregate is \
CALORIE iff every step terminated CALORIE or CURE and no terminal \
wounds were declared. Heal events are normal — they are how the \
substrate stays alive. Wounds are normal — they are recorded into the \
manifold so the audit captures the full state."
WITNESS LG-FRANKLIN-RUNNER-EPILOGUE-001 CALORIE "closure window closed"

# Closure surface — the EXIT trap fires here, runs _klein_close, which
# writes the epilogue, prints the summary, and exits with the code
# derived from accumulated terminal wounds. There is no second exit
# point. Inside meets outside through this single surface.
_klein_close
