#!/usr/bin/env bash
# C⁴ witness gate: before Discord Playwright, refuse missing/empty storage or absent "cookies" key.
# Usage: bash scripts/playwright_discord_witness_preflight.sh [gaiaftcl|face_of_madness|fom] [--emit-export]
# Resolution: DISCORD_PLAYWRIGHT_STORAGE_STATE → repo .playwright-discord → ~/.playwright-discord → discover (GAIA_ROOT + home doc dirs)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${1:-gaiaftcl}"
EMIT_EXPORT=0
if [[ "${2:-}" == "--emit-export" ]]; then
  EMIT_EXPORT=1
fi

discover_witness() {
  local leaf="$1"
  local found=""
  while IFS= read -r -d '' f; do
    found="$f"
    break
  done < <(
    find "$ROOT" \( -path "*/node_modules/*" -o -path "*/.git/*" \) -prune -o -name "$leaf" -type f -print0 2>/dev/null
  )
  if [[ -n "$found" ]]; then
    printf '%s' "$found"
    return 0
  fi
  local d
  for d in "${HOME}/Documents" "${HOME}/Downloads" "${HOME}/Desktop"; do
    [[ -d "$d" ]] || continue
    while IFS= read -r -d '' f; do
      found="$f"
      break
    done < <(find "$d" -maxdepth 10 \( -path "*/node_modules/*" -o -path "*/.git/*" \) -prune -o -name "$leaf" -type f -print0 2>/dev/null)
    [[ -n "$found" ]] && break
  done
  if [[ -n "$found" ]]; then
    printf '%s' "$found"
    return 0
  fi
  return 1
}

if [[ -n "${DISCORD_PLAYWRIGHT_STORAGE_STATE:-}" ]]; then
  WITNESS="${DISCORD_PLAYWRIGHT_STORAGE_STATE}"
else
  pl="$(printf '%s' "$PROFILE" | tr '[:upper:]' '[:lower:]')"
  case "$pl" in
    gaiaftcl | gaia) LEAF="storage-gaiaftcl.json" ;;
    face_of_madness | fom) LEAF="storage-face-of-madness.json" ;;
    *)
      echo "REFUSED: unknown profile '$PROFILE' (use gaiaftcl or face_of_madness)" >&2
      exit 2
      ;;
  esac
  REPO="$ROOT/services/gaiaos_ui_web/.playwright-discord/$LEAF"
  HOME_W="${HOME}/.playwright-discord/$LEAF"
  if [[ -f "$REPO" ]]; then
    WITNESS="$REPO"
  elif [[ -f "$HOME_W" ]]; then
    WITNESS="$HOME_W"
  else
    if dw="$(discover_witness "$LEAF")" && [[ -n "$dw" ]]; then
      WITNESS="$dw"
      echo "CURE: witness found outside canonical path — using: $WITNESS (copy to $HOME_W to standardize)" >&2
    else
      echo "REFUSED: missing Discord storage state (no cookies witness).
  Checked: $REPO
           $HOME_W
  Discover: GAIAOS tree under $ROOT and ~/Documents|Downloads|Desktop (maxdepth 10) for $LEAF
  Limb: set DISCORD_PLAYWRIGHT_STORAGE_STATE or seal via npm run playwright:discord:codegen:<profile> from gaiaos_ui_web (no Founder terminal delegation)." >&2
      exit 2
    fi
  fi
fi

if [[ ! -f "$WITNESS" ]]; then
  echo "REFUSED: DISCORD_PLAYWRIGHT_STORAGE_STATE path not a file: $WITNESS" >&2
  exit 2
fi

if [[ ! -s "$WITNESS" ]]; then
  echo "REFUSED: witness file is empty (0 bytes): $WITNESS" >&2
  exit 2
fi

if ! grep -q '"cookies"' "$WITNESS"; then
  echo "REFUSED: no '\"cookies\"' key in witness: $WITNESS" >&2
  exit 2
fi

bytes="$(wc -c < "$WITNESS" | tr -d ' ')"
echo "CALORIE: Discord witness OK — $WITNESS (${bytes} bytes, cookies key present)" >&2

if [[ "$EMIT_EXPORT" -eq 1 ]]; then
  printf 'export DISCORD_PLAYWRIGHT_STORAGE_STATE=%q\n' "$WITNESS"
fi
