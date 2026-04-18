#!/usr/bin/env bash
# Run G_FREESTYLE_L0 axiom bulk audit on truth_envelopes.
# Reports pass/fail counts for Axiom 1 (non-extractive) and Axiom 2 (Geodetic Floor).
#
# Usage:
#   ./scripts/run_axiom_audit.sh
#   ARANGO_URL=http://localhost:8529 ./scripts/run_axiom_audit.sh
#   ARANGO_URL=http://77.42.85.60:8529 ./scripts/run_axiom_audit.sh  # from outside mesh

cd "$(dirname "$0")/.."
exec python3 scripts/run_axiom_audit.py
