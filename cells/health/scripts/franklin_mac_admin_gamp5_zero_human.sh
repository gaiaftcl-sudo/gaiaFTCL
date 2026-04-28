#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "${ROOT}"
zsh "cells/franklin/scripts/franklin_gamp5_validate.sh"
