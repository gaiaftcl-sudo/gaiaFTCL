# GaiaFTCL Turbo UI — Borland-era boxed frames (source from bash scripts).
# Sets: B DIM RST CY BR GR RD BG FG W (width inner content)

turbo_init_colors() {
  if [[ -t 1 ]]; then
    B='\033[1m'
    DIM='\033[2m'
    RST='\033[0m'
    CY='\033[36m'
    BR='\033[33m'
    GR='\033[32m'
    RD='\033[31m'
    BG='\033[44m'
    FG='\033[97m'
  else
    B=''
    DIM=''
    RST=''
    CY=''
    BR=''
    GR=''
    RD=''
    BG=''
    FG=''
  fi
  W="${TURBO_FRAME_W:-64}"
}

turbo_clear() {
  clear 2>/dev/null || true
}

turbo_line() {
  printf '%*s' "$W" '' | tr ' ' "${1:--}"
}

turbo_top() {
  printf '%s╔' "$CY"
  turbo_line '═'
  printf '╗%s\n' "$RST"
}

turbo_mid() {
  printf '%s╠' "$CY"
  turbo_line '═'
  printf '╣%s\n' "$RST"
}

turbo_bot() {
  printf '%s╚' "$CY"
  turbo_line '═'
  printf '╝%s\n' "$RST"
}

turbo_row() {
  local plain="$1"
  printf '%s║ %s%-62s%s ║%s\n' "$CY" "$RST" "$plain" "$CY" "$RST"
}

turbo_row_val() {
  local k="$1" v="$2"
  printf '%s║ %s%-20s%s : %s%-36s%s ║%s\n' "$CY" "$BR" "$k" "$RST" "$B" "$v" "$CY" "$RST"
}

# Title bar (blue background line); pass inner text (~41 chars or less recommended)
turbo_title_bar() {
  local title="$1"
  local pad=$((W + 2 - ${#title}))
  [[ $pad -lt 0 ]] && pad=0
  printf '%s' "$BG$FG$B"
  printf ' %s' "$title"
  printf '%*s' "$pad" '' | tr ' ' ' '
  printf '%s\n' "$RST"
}
