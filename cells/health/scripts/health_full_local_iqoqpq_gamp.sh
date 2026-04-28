#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "${ROOT}"
zsh "cells/health/scripts/health_cell_gamp5_validate.sh"
