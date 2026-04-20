#!/usr/bin/env bash
# health_cell_gamp5_validate.sh — GaiaHealth cell + Qualification Catalog (GAMP5 posture)
#
# Runs, in order:
#   1. wiki/lint_wiki.sh — markdown link hygiene for wiki/*.md (top-level)
#   2. gamp5_qualification_catalog_check.py — §8 / OWL-NUTRITION / GAMP markers + blob→file existence
#   3. owl_nutrition_iqoqpq_validate.sh — IQ/OQ/PQ for OWL-NUTRITION + wasm_constitutional tests
#   4. cargo test --workspace — all cells/health Rust crates (wasm + biologit + renderer)
#
# Usage (from repository root):
#   bash cells/health/scripts/health_cell_gamp5_validate.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEALTH_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${HEALTH_ROOT}/../.." && pwd)"

section() {
  printf "\n\033[0;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n"
  printf "\033[1;36m%s\033[0m\n" "$1"
  printf "\033[0;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n\n"
}

cd "${REPO_ROOT}"

section "1/4 Wiki lint (Qualification Catalog + top-level wiki .md)"
./wiki/lint_wiki.sh

section "2/4 GAMP5 — Qualification Catalog structure + blob link resolution"
python3 "${HEALTH_ROOT}/scripts/gamp5_qualification_catalog_check.py"

section "3/4 OWL-NUTRITION IQ / OQ / PQ (nutrition schemas + wasm_constitutional)"
bash "${HEALTH_ROOT}/scripts/owl_nutrition_iqoqpq_validate.sh"

section "4/4 Health workspace — cargo test (all member crates)"
cd "${HEALTH_ROOT}"
cargo test --workspace

printf "\n\033[0;32mPASS\033[0m — health_cell_gamp5_validate.sh complete (wiki + GAMP5 catalog + OWL-NUTRITION + full health workspace tests).\n"
