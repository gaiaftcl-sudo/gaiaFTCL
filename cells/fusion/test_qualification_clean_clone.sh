#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="${ROOT}/cells/fusion/macos/CleanCloneTest"

if [[ ! -f "${RUNNER}/Package.swift" ]]; then
  echo "REFUSED: missing CleanCloneTest package at ${RUNNER}" >&2
  exit 1
fi

cd "${RUNNER}"
swift build
.build/debug/CleanCloneTest
