#!/usr/bin/env bash
# Tools: nmap, curl, jq, python3/dirsearch, ffuf, subfinder, XSStrike (if installed)
# Behavior: outputs are shown live in the terminal. Nothing is persisted to disk.
# Usage: ./dexter.sh

set -o errexit
set -o pipefail
set -o nounset

# -----------------------
# Config & detection
# -----------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIRSEARCH_PY="$SCRIPT_DIR/dirsearch/dirsearch.py"

command_exists() { command -v "$1" >/dev/null 2>&1; }

detect_xsstrike() {
  if command_exists xsstrike; then
    XS_CMD=(xsstrike)
    XS_TYPE="binary"
    return 0
  fi
  if [[ -f "$SCRIPT_DIR/XSStrike/xsstrike.py" ]]; then
    XS_CMD=(python3 "$SCRIPT_DIR/XSStrike/xsstrike.py")
    XS_TYPE="local_repo"
    return 0
  fi
  if [[ -f "$SCRIPT_DIR/xsstrike.py" ]]; then
    XS_CMD=(python3 "$SCRIPT_DIR/xsstrike.py")
    XS_TYPE="local_file"
    return 0
  fi
  if command_exists python3; then
    if python3 - <<'PY' 2>/dev/null; then
import pkgutil
print(bool(pkgutil.find_loader("xsstrike")))
PY
      XS_CMD=(python3 -m xsstrike)
      XS_TYPE="python_module"
      return 0
    fi
  fi
  return 1
}

detect_subfinder() { command_exists subfinder; }
detect_nmap() { command_exists nmap; }
detect_ffuf() { command_exists ffuf; }
detect_curl() { command_exists curl; }
detect_jq() { command_exists jq; }
detect_python3() { command_exists python3; }

# -----------------------
# Neon colors & header
# -----------------------
if tput setaf 1 >/dev/null 2>&1; then
  CLR_GREEN="$(tput setaf 2)"
  CLR_CYAN="$(tput setaf 6)"
  CLR_MAG="$(tput setaf 5)"
  CLR_YELLOW="$(tput setaf 3)"
  CLR_RESET="$(tput sgr0)"
else
  CLR_GREEN=""
  CLR_CYAN=""
  CLR_MAG=""
  CLR_RESET=""
  CLR_YELLOW=""
fi

show_banner() {
  cat <<'BANNER'
▓█████▄ ▓█████ ▒██   ██▒▄▄▄█████▓▓█████  ██▀███  
▒██▀ ██▌▓█   ▀ ▒▒ █ █ ▒░▓  ██▒ ▓▒▓█   ▀ ▓██ ▒ ██▒
░██   █▌▒███   ░░  █   ░▒ ▓██░ ▒░▒███   ▓██ ░▄█ ▒
░▓█▄   ▌▒▓█  ▄  ░ █ █ ▒ ░ ▓██▓ ░ ▒▓█  ▄ ▒██▀▀█▄  
░▒████▓ ░▒████▒▒██▒ ▒██▒  ▒██▒ ░ ░▒████▒░██▓ ▒██▒
 ▒▒▓  ▒ ░░ ▒░ ░▒▒ ░ ░▓ ░  ▒ ░░   ░░ ▒░ ░░ ▒▓ ░▒▓░
 ░ ▒  ▒  ░ ░  ░░░   ░▒ ░    ░     ░ ░  ░  ░▒ ░ ▒░
 ░ ░  ░    ░    ░    ░    ░         ░     ░░   ░ 
   ░       ░  ░ ░    ░              ░  ░   ░     
 ░                                               
BANNER
}

neon_header() {
  clear
  printf "%b" "${CLR_CYAN}"
  show_banner
  printf "%b\n" "${CLR_RESET}"
  printf "%b" "${CLR_GREEN}"
  echo "Tonight is the night"
  printf "%b\n\n" "${CLR_RESET}"
}

# -----------------------
# Wordlist discovery (for ffuf)
# -----------------------
SECLISTS_DIR="$SCRIPT_DIR/seclists"
WORDLISTS_DIR="$SCRIPT_DIR/wordlists"

collect_wordlists() {
  files=()
  for d in "$SECLISTS_DIR" "$WORDLISTS_DIR"; do
    [[ -d "$d" ]] || continue
    while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$d" -type f -maxdepth 6 -print0 2>/dev/null)
  done
}

choose_wordlist() {
  collect_wordlists
  if [[ ${#files[@]} -eq 0 ]]; then
    printf "%b" "${CLR_MAG}No wordlists found in seclists/ or wordlists/. Enter full path or cancel.${CLR_RESET}\n"
    read -r -p "Full path to wordlist (or Enter to cancel): " path
    [[ -z "$path" || ! -f "$path" ]] && return 1
    echo "$path"
    return 0
  fi

  echo "Found ${#files[@]} wordlists (showing up to first 200):"
  local max=200
  local i=0
  for f in "${files[@]}"; do
    ((i++))
    printf "%4d) %s\n" "$i" "$f"
    ((i == max)) && break
  done
  echo "0) Enter custom path"
  while true; do
    read -r -p "Choose index: " idx
    if [[ "$idx" =~ ^[0-9]+$ ]]; then
      if [[ "$idx" -eq 0 ]]; then
        read -r -p "Enter full path to wordlist: " cp
        [[ -f "$cp" ]] && {
          echo "$cp"
          return 0
        } || printf "%b" "${CLR_MAG}File not found.${CLR_RESET}\n"
      elif ((idx >= 1 && idx <= ${#files[@]})); then
        echo "${files[idx - 1]}"
        return 0
      else
        printf "%b" "${CLR_MAG}Index out of range.${CLR_RESET}\n"
      fi
    else
      printf "%b" "${CLR_MAG}Please enter numeric index.${CLR_RESET}\n"
    fi
  done
}

# -----------------------
# Tools: real-time output (no file writes)
# -----------------------
run_nmap() {
  if ! detect_nmap; then
    printf "%b" "${CLR_MAG}nmap not found. Skipping.${CLR_RESET}\n"
    return
  fi
  read -r -p "Target (domain or IP): " TGT
  [[ -z "$TGT" ]] && {
    echo "Cancelled."
    return
  }
  echo "Choose preset: 1) Quick (-sV)  2) Aggressive (-A -sC -sV)  3) All ports (-p- -sV) 4) OS & scripts (-O -sC -sV) 5) Custom"
  read -r -p "Choice [1]: " c
  c="${c:-1}"
  case $c in
  1) OPTS="-sV" ;;
  2) OPTS="-A -sC -sV" ;;
  3) OPTS="-p- -sV" ;;
  4) OPTS="-O -sC -sV" ;;
  5) read -r -p "Enter custom nmap flags: " OPTS ;;
  *) OPTS="-sV" ;;
  esac
  read -r -p "Extra ports (comma separated) or Enter to skip: " EXTRA
  [[ -n "$EXTRA" ]] && OPTS="$OPTS -p $EXTRA"
  printf "%b" "${CLR_CYAN}[*] Running: nmap $OPTS $TGT${CLR_RESET}\n\n"
  # Run directly and show output in real-time
  nmap $OPTS "$TGT"
  printf "%b\n" "${CLR_GREEN}[+] nmap finished${CLR_RESET}\n"
}

run_crtsh() {
  if ! detect_curl; then
    printf "%b" "${CLR_MAG}curl not found. Skipping crt.sh.${CLR_RESET}\n"
    return
  fi
  read -r -p "Domain (example.com): " D
  [[ -z "$D" ]] && {
    echo "Cancelled."
    return
  }
  printf "%b" "${CLR_CYAN}[*] Querying crt.sh for: $D${CLR_RESET}\n\n"
  # Show results live, parsed if jq available
  if detect_jq; then
    curl -s "https://crt.sh/?q=%25.$D&output=json" |
      jq -r '.[].name_value' 2>/dev/null |
      sed 's/\*\.//g' |
      tr '[:upper:]' '[:lower:]' |
      sort -u |
      awk '{print " - "$0}'
  else
    curl -s "https://crt.sh/?q=%25.$D&output=json" |
      sed -n 's/.*"name_value":[ ]*"\([^"]*\)".*/ - \1/p' |
      sed 's/\*\.//g' |
      tr '[:upper:]' '[:lower:]' |
      sort -u
  fi
  printf "%b\n" "${CLR_GREEN}[+] crt.sh query finished${CLR_RESET}\n"
}

run_dirsearch() {
  if ! detect_python3 || [[ ! -f "$DIRSEARCH_PY" ]]; then
    printf "%b" "${CLR_MAG}dirsearch not found at $DIRSEARCH_PY or python3 missing. Skipping.${CLR_RESET}\n"
    return
  fi
  read -r -p "Base URL (e.g. http://example.com): " base
  [[ -z "$base" ]] && {
    echo "Cancelled."
    return
  }
  read -r -p "Extensions (comma separated, default: php,html,js,txt): " exts
  exts="${exts:-php,html,js,txt}"
  read -r -p "Threads (default 10): " th
  th="${th:-10}"
  printf "%b" "${CLR_CYAN}[*] Running dirsearch (-e $exts -t $th) against $base${CLR_RESET}\n\n"
  # Show dirsearch output live
  python3 "$DIRSEARCH_PY" -u "$base" -e "$exts" -t "$th"
  printf "%b\n" "${CLR_GREEN}[+] dirsearch finished${CLR_RESET}\n"
}

run_ffuf() {
  if ! detect_ffuf; then
    printf "%b" "${CLR_MAG}ffuf not found. Skipping.${CLR_RESET}\n"
    return
  fi
  read -r -p "Target URL (use FUZZ placeholder, e.g. http://example.com/FUZZ): " tgt
  [[ -z "$tgt" ]] && {
    echo "Cancelled."
    return
  }
  [[ "$tgt" != *FUZZ* ]] && tgt="${tgt%/}/FUZZ" && printf "%b" "${CLR_YELLOW}[i] Target adjusted to: $tgt${CLR_RESET}\n"
  read -r -p "Host header (or Enter to skip): " host
  WL="$(choose_wordlist)" || {
    printf "%b" "${CLR_MAG}Wordlist selection cancelled. Aborting ffuf.${CLR_RESET}\n"
    return
  }
  read -r -p "Status codes to include (default 200,301,403,401): " sc
  sc="${sc:-200,301,403,401}"
  read -r -p "Filter by response size (example 6109) or Enter to skip: " fs
  FS_FLAG=()
  [[ -n "$fs" ]] && FS_FLAG=(-fs "$fs")
  read -r -p "Threads (-t) [default 40]: " th
  th="${th:-40}"
  printf "%b" "${CLR_CYAN}[*] Running ffuf: -w $WL -u $tgt -mc $sc -t $th${CLR_RESET}\n\n"
  # Build command and run live (no -o to avoid saving). ffuf prints results interactively.
  CMD=(ffuf -w "$WL" -u "$tgt" -mc "$sc" "${FS_FLAG[@]}" -t "$th" -recursion=false -ac)
  [[ -n "$host" ]] && CMD+=(-H "Host: $host")
  "${CMD[@]}"
  printf "%b\n" "${CLR_GREEN}[+] ffuf finished${CLR_RESET}\n"
}

run_subfinder() {
  if ! detect_subfinder; then
    printf "%b" "${CLR_MAG}subfinder not found. Skipping.${CLR_RESET}\n"
    return
  fi
  read -r -p "Domain for subfinder (example.com): " d
  [[ -z "$d" ]] && {
    echo "Cancelled."
    return
  }
  printf "%b" "${CLR_CYAN}[*] Running subfinder for: $d${CLR_RESET}\n\n"
  # Show subfinder output live (one per line). Use -silent to reduce noise if supported.
  # Prefer to not buffer: run directly
  subfinder -d "$d"
  printf "%b\n" "${CLR_GREEN}[+] subfinder finished${CLR_RESET}\n"
}

run_xsstrike() {
  if ! detect_xsstrike; then
    printf "%b" "${CLR_MAG}XSStrike not found. Skipping.${CLR_RESET}\n"
    return
  fi
  read -r -p "Enter full target URL (e.g. https://target.com/path?x=1): " url
  [[ -z "$url" ]] && {
    echo "Cancelled."
    return
  }
  echo "XSStrike modes: 1) Quick  2) Crawl  3) Blind  4) Custom flags"
  read -r -p "Choice [1]: " m
  m="${m:-1}"
  CMD=("${XS_CMD[@]}")
  case $m in
  1) CMD+=(-u "$url") ;;
  2) CMD+=(-u "$url" --crawl) ;;
  3) CMD+=(-u "$url" --blind) ;;
  4)
    read -r -p "Enter custom flags (example: -u \"$url\" --crawl): " cf
    [[ -z "$cf" ]] && {
      echo "Cancelled."
      return
    }
    # Run via sh -c to allow arbitrary flags; show live
    printf "%b" "${CLR_CYAN}[*] Running XSStrike custom: ${cf}${CLR_RESET}\n\n"
    if [[ "${XS_TYPE:-}" == "binary" ]]; then
      sh -c "xsstrike $cf"
    else
      sh -c "${XS_CMD[*]} $cf"
    fi
    printf "%b\n" "${CLR_GREEN}[+] XSStrike (custom) finished${CLR_RESET}\n"
    return
    ;;
  *) CMD+=(-u "$url") ;;
  esac

  printf "%b" "${CLR_CYAN}[*] Running XSStrike: ${CMD[*]}${CLR_RESET}\n\n"
  "${CMD[@]}"
  printf "%b\n" "${CLR_GREEN}[+] XSStrike finished${CLR_RESET}\n"
}

# -----------------------
# Run all available (in-order), showing live results
# -----------------------
run_all() {
  neon_header
  printf "%b" "${CLR_CYAN}[*] Running all available modules (live output)...${CLR_RESET}\n\n"
  detect_subfinder && run_subfinder || printf "%b" "${CLR_YELLOW}[i] subfinder not available, skipping.${CLR_RESET}\n"
  detect_curl && run_crtsh || printf "%b" "${CLR_YELLOW}[i] curl not available, skipping crt.sh.${CLR_RESET}\n"
  detect_nmap && run_nmap || printf "%b" "${CLR_YELLOW}[i] nmap not available, skipping.${CLR_RESET}\n"
  [[ -f "$DIRSEARCH_PY" && detect_python3 ]] && run_dirsearch || printf "%b" "${CLR_YELLOW}[i] dirsearch or python3 not available, skipping.${CLR_RESET}\n"
  detect_ffuf && run_ffuf || printf "%b" "${CLR_YELLOW}[i] ffuf not available, skipping.${CLR_RESET}\n"
  detect_xsstrike && run_xsstrike || printf "%b" "${CLR_YELLOW}[i] XSStrike not available, skipping.${CLR_RESET}\n"
  printf "%b\n" "${CLR_GREEN}[+] run_all finished${CLR_RESET}\n"
}

# -----------------------
# Persistent menu (exit with 0)
# -----------------------
main_loop() {
  neon_header
  while true; do
    printf "%b" "${CLR_CYAN}--------------------------------------------${CLR_RESET}\n"
    printf "%b" "${CLR_GREEN}"
    echo "  1) Run all available modules (live)"
    echo "  2) Nmap (live)"
    echo "  3) Subdomain enumeration (crt.sh) (live)"
    echo "  4) Subfinder (live)"
    echo "  5) Dirsearch (live)"
    echo "  6) FFUF (live)"
    echo "  7) XSStrike (live)"
    echo "  8) Show banner"
    echo "  9) Clear screen"
    echo "  0) Exit"
    printf "%b\n" "${CLR_RESET}"
    read -r -p "Select option: " opt
    case "$opt" in
    1) run_all ;;
    2) run_nmap ;;
    3) run_crtsh ;;
    4) run_subfinder ;;
    5) run_dirsearch ;;
    6) run_ffuf ;;
    7) run_xsstrike ;;
    8) neon_header ;;
    9)
      clear
      neon_header
      ;;
    0)
      printf "%b" "${CLR_MAG}Goodbye — exiting panel.${CLR_RESET}\n"
      break
      ;;
    *) printf "%b" "${CLR_MAG}Invalid choice.${CLR_RESET}\n" ;;
    esac
    echo
    read -r -p "Press Enter to return to menu..."
    neon_header
  done
}

# Start
if ! detect_jq; then printf "%b" "${CLR_YELLOW}[!] Note: jq not found. crt.sh output parsing will fallback to basic parsing.${CLR_RESET}\n"; fi
neon_header
main_loop
