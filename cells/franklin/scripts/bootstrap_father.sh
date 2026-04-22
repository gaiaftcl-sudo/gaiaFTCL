#!/usr/bin/env zsh
# F1: secp256k1 Father key via OpenSSL; private off-JSON; evidence JSON in cells/health/evidence/.
# Private: Keychain (preferred) or cells/franklin/state/.father_secp256k1.pem (0600).
# Usage: zsh cells/franklin/scripts/bootstrap_father.sh [REPO_ROOT]
set -euo pipefail
REPO="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SVC="com.fortressai.franklin.identity"
ACC="father_secp256k1_pem"
EVD="${REPO}/cells/health/evidence"
ST="${REPO}/cells/franklin/state"
mkdir -p "$EVD" "$ST"
TMP="$(mktemp -t frk.XXXXXX)"
openssl ecparam -name secp256k1 -genkey -noout -out "$TMP"
PUB_PEM="$(openssl ec -in "$TMP" -pubout 2>/dev/null)"
PRIV_PEM="$(cat "$TMP")"
STORAGE=""
if command -v security >/dev/null 2>&1; then
  if security find-generic-password -s "$SVC" -a "$ACC" >/dev/null 2>&1; then
    if [[ "${FRANKLIN_BOOTSTRAP_FORCE:-0}" != "1" ]]; then
      echo "REFUSED: Keychain item exists ($SVC / $ACC). Set FRANKLIN_BOOTSTRAP_FORCE=1 to replace (dev only)." >&2
      exit 1
    fi
    security delete-generic-password -s "$SVC" -a "$ACC" 2>/dev/null || true
  fi
  if printf '%s' "$PRIV_PEM" | security add-generic-password -s "$SVC" -a "$ACC" -w - -U 2>/dev/null; then
    STORAGE="keychain|${SVC}|${ACC}"
  fi
fi
if [[ -z "$STORAGE" ]]; then
  KEYF="${ST}/.father_secp256k1.pem"
  umask 077
  printf '%s' "$PRIV_PEM" > "$KEYF"
  chmod 600 "$KEYF" || true
  STORAGE="file|cells/franklin/state/.father_secp256k1.pem|chmod600"
  echo "WARN: stored Father private key in $KEYF (Keychain not used). Protect this host." >&2
fi
TS="$(date -u "+%Y-%m-%dT%H%M%SZ")"
OUT="${EVD}/franklin_bootstrap_receipt_${TS}.json"
FRANKLIN_SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$FRANKLIN_SCRIPTS/_franklin_bin.zsh"
if ! franklin_require_bin; then
  exit 1
fi
PUBF="$(mktemp -t frkpub.XXXXXX)"
trap 'rm -f "$TMP" "$PUBF"' 0
printf '%s' "$PUB_PEM" > "$PUBF"
"$FRANKLIN_BIN" emit-bootstrap --out "$OUT" --repo "$REPO" --ts "$TS" --storage "$STORAGE" --pub-pem "$PUBF"
"$FRANKLIN_BIN" sign-bootstrap --repo "$REPO" "$OUT" || { echo "bootstrap: sign step failed" >&2; exit 1; }
