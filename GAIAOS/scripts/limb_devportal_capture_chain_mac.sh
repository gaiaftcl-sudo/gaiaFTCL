#!/usr/bin/env bash
# macOS: open Terminal.app for devportal capture, then poll for fragment (limb-only chain).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/run_in_terminal_mac.sh"
exec bash "$ROOT/scripts/limb_devportal_capture_wait.sh"
