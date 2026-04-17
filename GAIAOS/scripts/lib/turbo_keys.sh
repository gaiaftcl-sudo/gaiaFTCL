# turbo_read_key — F1–F12 + digits + printable (bash 3.2+ / macOS).
# Prints to stdout: f1..f12, or single character for digit/letter.
# Uses read -t for CSI tail (macOS supports fractional -t).

turbo_read_key() {
  local c0 c1 rest
  IFS= read -rsn1 c0 || { echo ""; return; }
  if [[ "$c0" != $'\e' ]]; then
    printf '%s' "$c0"
    return
  fi
  if ! IFS= read -rsn1 -t 0.05 c1 2>/dev/null; then
    printf '%s' "$c0"
    return
  fi
  if [[ "$c1" == 'O' ]]; then
    IFS= read -rsn1 -t 0.05 c0 2>/dev/null || true
    case "$c0" in
      P) printf 'f1'; return ;;
      Q) printf 'f2'; return ;;
      R) printf 'f3'; return ;;
      S) printf 'f4'; return ;;
    esac
    printf '\eO%s' "$c0"
    return
  fi
  if [[ "$c1" != '[' ]]; then
    printf '\e%s' "$c1"
    return
  fi
  rest=""
  while IFS= read -rsn1 -t 0.05 c0 2>/dev/null; do
    rest+="$c0"
    [[ "$c0" == '~' ]] && break
  done
  case "$rest" in
    11~) printf 'f1' ;;
    12~) printf 'f2' ;;
    13~) printf 'f3' ;;
    14~) printf 'f4' ;;
    15~) printf 'f5' ;;
    17~) printf 'f6' ;;
    18~) printf 'f7' ;;
    19~) printf 'f8' ;;
    20~) printf 'f9' ;;
    21~) printf 'f10' ;;
    23~) printf 'f11' ;;
    24~) printf 'f12' ;;
    1~) printf 'f1' ;;  # some terminals
    2~) printf 'f2' ;;
    3~) printf 'f3' ;;
    4~) printf 'f4' ;;
    5~) printf 'f5' ;;
    6~) printf 'f6' ;;
    7~) printf 'f7' ;;
    8~) printf 'f8' ;;
    9~) printf 'f9' ;;
    10~) printf 'f10' ;;
    *) printf '\e[%s' "$rest" ;;
  esac
}
