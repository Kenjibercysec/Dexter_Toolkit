#!/usr/bin/env bash
# Tools: nmap, curl, jq, python3/dirsearch, ffuf, subfinder, XSStrike, httpx, rustscan, sqlmap, bloodhound, evil-winrm, impacket (if installed)
# Behavior: outputs are shown live in the terminal. Nothing is persisted to disk.
# Usage: ./dexter.sh

set -o pipefail
set -o nounset

# -----------------------
# Config & detection
# -----------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIRSEARCH_PY="$SCRIPT_DIR/dirsearch/dirsearch.py"
VENV_DIR="$SCRIPT_DIR/.venv"
DIRSEARCH_DIR="$SCRIPT_DIR/dirsearch"
XS_DIR="$SCRIPT_DIR/XSStrike"
SQLMAP_DIR="$SCRIPT_DIR/sqlmap"
IMPK_DIR="$SCRIPT_DIR/impacket"
# Caminhos alternativos para Docker
DOCKER_SQLMAP_DIR="/opt/tools/sqlmap"
DOCKER_IMPK_DIR="/opt/tools/impacket"

# Adicionar Go bin ao PATH se existir
if command -v go >/dev/null 2>&1; then
  GOBIN="$(go env GOBIN 2>/dev/null || echo "")"
  if [[ -z "$GOBIN" ]]; then
    GOPATH="$(go env GOPATH 2>/dev/null || echo "$HOME/go")"
    GOBIN="$GOPATH/bin"
  fi
  if [[ -d "$GOBIN" ]] && [[ ":$PATH:" != *":$GOBIN:"* ]]; then
    export PATH="$GOBIN:$PATH"
  fi
fi

command_exists() { command -v "$1" >/dev/null 2>&1; }

# -----------------------
# Python venv setup
# -----------------------
setup_venv() {
  if ! command_exists python3; then
    return 1
  fi

  # Criar venv se não existir
  if [[ ! -d "$VENV_DIR" ]]; then
    printf "%b" "${CLR_CYAN}[*] Creating Python virtual environment...${CLR_RESET}\n"
    if ! python3 -m venv "$VENV_DIR" 2>/dev/null; then
      printf "%b" "${CLR_YELLOW}[!] Failed to create venv, using system Python${CLR_RESET}\n"
      PYTHON_CMD="python3"
      PIP_CMD="pip3"
      return 1
    fi
  fi

  # Ativar venv e definir comandos
  if [[ -f "$VENV_DIR/bin/activate" ]]; then
    # Linux/macOS
    # shellcheck source=/dev/null
    source "$VENV_DIR/bin/activate" 2>/dev/null || true
    PYTHON_CMD="$VENV_DIR/bin/python"
    PIP_CMD="$VENV_DIR/bin/pip"
  elif [[ -f "$VENV_DIR/Scripts/activate" ]]; then
    # Windows (Git Bash)
    # shellcheck source=/dev/null
    source "$VENV_DIR/Scripts/activate" 2>/dev/null || true
    PYTHON_CMD="$VENV_DIR/Scripts/python"
    PIP_CMD="$VENV_DIR/Scripts/pip"
  else
    # Fallback para python3 do sistema
    PYTHON_CMD="python3"
    PIP_CMD="pip3"
    return 0
  fi

  # Verificar se os comandos existem
  if [[ ! -f "$PYTHON_CMD" ]] || [[ ! -f "$PIP_CMD" ]]; then
    printf "%b" "${CLR_YELLOW}[!] venv executables not found, using system Python${CLR_RESET}\n"
    PYTHON_CMD="python3"
    PIP_CMD="pip3"
    return 0
  fi

  # Instalar/atualizar dependências do dirsearch
  if [[ -f "$DIRSEARCH_DIR/requirements.txt" ]]; then
    if [[ ! -f "$VENV_DIR/.dirsearch_installed" ]] || \
       [[ "$DIRSEARCH_DIR/requirements.txt" -nt "$VENV_DIR/.dirsearch_installed" ]]; then
      printf "%b" "${CLR_CYAN}[*] Installing dirsearch dependencies...${CLR_RESET}\n"
      "$PIP_CMD" install -q --upgrade pip 2>/dev/null || true
      if "$PIP_CMD" install -q -r "$DIRSEARCH_DIR/requirements.txt" 2>/dev/null; then
        touch "$VENV_DIR/.dirsearch_installed"
      else
        printf "%b" "${CLR_YELLOW}[!] Warning: Failed to install some dirsearch dependencies${CLR_RESET}\n"
      fi
    fi
  fi

  # Instalar/atualizar dependências do XSStrike
  if [[ -f "$XS_DIR/requirements.txt" ]]; then
    if [[ ! -f "$VENV_DIR/.xsstrike_installed" ]] || \
       [[ "$XS_DIR/requirements.txt" -nt "$VENV_DIR/.xsstrike_installed" ]]; then
      printf "%b" "${CLR_CYAN}[*] Installing XSStrike dependencies...${CLR_RESET}\n"
      "$PIP_CMD" install -q --upgrade pip 2>/dev/null || true
      if "$PIP_CMD" install -q -r "$XS_DIR/requirements.txt" 2>/dev/null; then
        touch "$VENV_DIR/.xsstrike_installed"
      else
        printf "%b" "${CLR_YELLOW}[!] Warning: Failed to install some XSStrike dependencies${CLR_RESET}\n"
      fi
    fi
  fi

  export PYTHON_CMD PIP_CMD
  return 0
}

detect_xsstrike() {
  if command_exists xsstrike; then
    XS_CMD=(xsstrike)
    XS_TYPE="binary"
    return 0
  fi
  local py_cmd="${PYTHON_CMD:-python3}"
  if [[ -f "$SCRIPT_DIR/XSStrike/xsstrike.py" ]]; then
    XS_CMD=("$py_cmd" "$SCRIPT_DIR/XSStrike/xsstrike.py")
    XS_TYPE="local_repo"
    return 0
  fi
  if [[ -f "$SCRIPT_DIR/xsstrike.py" ]]; then
    XS_CMD=("$py_cmd" "$SCRIPT_DIR/xsstrike.py")
    XS_TYPE="local_file"
    return 0
  fi
  if command_exists "$py_cmd" 2>/dev/null || [[ -f "$py_cmd" ]]; then
    if "$py_cmd" - <<'PY' 2>/dev/null; then
import pkgutil
print(bool(pkgutil.find_loader("xsstrike")))
PY
      XS_CMD=("$py_cmd" -m xsstrike)
      XS_TYPE="python_module"
      return 0
    fi
  fi
  return 1
}

detect_subfinder() {
  if command_exists subfinder; then
    SUBFINDER_CMD="subfinder"
    return 0
  fi
  # Tentar encontrar no Go bin configurado
  if [[ -n "${GOBIN:-}" ]] && [[ -f "$GOBIN/subfinder" ]]; then
    SUBFINDER_CMD="$GOBIN/subfinder"
    return 0
  fi
  # Tentar GOPATH padrão (~/$USER/go/bin) mesmo sem go no PATH
  if [[ -z "${GOBIN:-}" ]]; then
    DEFAULT_GOPATH="${HOME}/go/bin"
    if [[ -f "$DEFAULT_GOPATH/subfinder" ]]; then
      SUBFINDER_CMD="$DEFAULT_GOPATH/subfinder"
      return 0
    fi
  fi
  # Local típico em sistemas que instalam em /usr/local/bin
  if [[ -f "/usr/local/bin/subfinder" ]]; then
    SUBFINDER_CMD="/usr/local/bin/subfinder"
    return 0
  fi
  return 1
}

detect_ffuf() {
  if command_exists ffuf; then
    FFUF_CMD="ffuf"
    return 0
  fi
  # Tentar encontrar no Go bin configurado
  if [[ -n "${GOBIN:-}" ]] && [[ -f "$GOBIN/ffuf" ]]; then
    FFUF_CMD="$GOBIN/ffuf"
    return 0
  fi
  # Tentar GOPATH padrão (~/$USER/go/bin) mesmo sem go no PATH
  if [[ -z "${GOBIN:-}" ]]; then
    DEFAULT_GOPATH="${HOME}/go/bin"
    if [[ -f "$DEFAULT_GOPATH/ffuf" ]]; then
      FFUF_CMD="$DEFAULT_GOPATH/ffuf"
      return 0
    fi
  fi
  # Local típico em sistemas que instalam em /usr/local/bin
  if [[ -f "/usr/local/bin/ffuf" ]]; then
    FFUF_CMD="/usr/local/bin/ffuf"
    return 0
  fi
  return 1
}

detect_nmap() { command_exists nmap; }
detect_curl() { command_exists curl; }
detect_jq() { command_exists jq; }
detect_python3() {
  if [[ -n "${PYTHON_CMD:-}" ]] && [[ -f "${PYTHON_CMD:-}" ]]; then
    return 0
  fi
  command_exists python3
}

detect_httpx() {
  if command_exists httpx; then
    HTTPX_CMD="httpx"
    return 0
  fi
  # Tentar encontrar no Go bin configurado
  if [[ -n "${GOBIN:-}" ]] && [[ -f "$GOBIN/httpx" ]]; then
    HTTPX_CMD="$GOBIN/httpx"
    return 0
  fi
  # Tentar GOPATH padrão
  if [[ -z "${GOBIN:-}" ]]; then
    DEFAULT_GOPATH="${HOME}/go/bin"
    if [[ -f "$DEFAULT_GOPATH/httpx" ]]; then
      HTTPX_CMD="$DEFAULT_GOPATH/httpx"
      return 0
    fi
  fi
  # Docker ou /usr/local/bin
  if [[ -f "/usr/local/bin/httpx" ]]; then
    HTTPX_CMD="/usr/local/bin/httpx"
    return 0
  fi
  return 1
}

detect_rustscan() {
  if command_exists rustscan; then
    RUSTSCAN_CMD="rustscan"
    return 0
  fi
  # Tentar /usr/local/bin (Docker)
  if [[ -f "/usr/local/bin/rustscan" ]]; then
    RUSTSCAN_CMD="/usr/local/bin/rustscan"
    return 0
  fi
  return 1
}

detect_sqlmap() {
  if command_exists sqlmap; then
    SQLMAP_CMD="sqlmap"
    SQLMAP_TYPE="binary"
    return 0
  fi
  local py_cmd="${PYTHON_CMD:-python3}"
  # Tentar /opt/tools (Docker) primeiro
  if [[ -f "$DOCKER_SQLMAP_DIR/sqlmap.py" ]]; then
    SQLMAP_CMD=("$py_cmd" "$DOCKER_SQLMAP_DIR/sqlmap.py")
    SQLMAP_TYPE="docker_repo"
    return 0
  fi
  # Tentar repositório local
  if [[ -f "$SQLMAP_DIR/sqlmap.py" ]]; then
    SQLMAP_CMD=("$py_cmd" "$SQLMAP_DIR/sqlmap.py")
    SQLMAP_TYPE="local_repo"
    return 0
  fi
  # Tentar /usr/local/bin (Docker link simbólico)
  if [[ -f "/usr/local/bin/sqlmap" ]]; then
    SQLMAP_CMD="/usr/local/bin/sqlmap"
    SQLMAP_TYPE="binary"
    return 0
  fi
  return 1
}

detect_bloodhound() {
  if command_exists bloodhound-python; then
    BLOODHOUND_CMD="bloodhound-python"
    BLOODHOUND_TYPE="binary"
    return 0
  fi
  local py_cmd="${PYTHON_CMD:-python3}"
  # Tentar como módulo Python
  if "$py_cmd" -c "import bloodhound" 2>/dev/null; then
    BLOODHOUND_CMD=("$py_cmd" -m bloodhound)
    BLOODHOUND_TYPE="python_module"
    return 0
  fi
  # Tentar bloodhound-ce
  if command_exists bloodhound-ce; then
    BLOODHOUND_CMD="bloodhound-ce"
    BLOODHOUND_TYPE="binary"
    return 0
  fi
  return 1
}

detect_evilwinrm() {
  # Tentar versão Python primeiro
  if command_exists evil-winrm; then
    EVILWINRM_CMD="evil-winrm"
    EVILWINRM_TYPE="python"
    return 0
  fi
  # Tentar versão Ruby
  if command_exists evil_winrm; then
    EVILWINRM_CMD="evil_winrm"
    EVILWINRM_TYPE="ruby"
    return 0
  fi
  # Tentar via gem
  if gem list evil-winrm 2>/dev/null | grep -q evil-winrm; then
    EVILWINRM_CMD="evil-winrm"
    EVILWINRM_TYPE="ruby"
    return 0
  fi
  return 1
}

detect_impacket() {
  # Verificar se scripts principais existem
  local py_cmd="${PYTHON_CMD:-python3}"
  # Tentar Docker primeiro
  if [[ -f "$DOCKER_IMPK_DIR/examples/secretsdump.py" ]]; then
    IMPK_CMD="$py_cmd"
    IMPK_DIR="$DOCKER_IMPK_DIR"
    IMPK_TYPE="docker_repo"
    return 0
  fi
  # Tentar repositório local
  if [[ -f "$IMPK_DIR/examples/secretsdump.py" ]]; then
    IMPK_CMD="$py_cmd"
    IMPK_DIR="$IMPK_DIR"
    IMPK_TYPE="local_repo"
    return 0
  fi
  # Tentar wrappers binários (Docker)
  if command_exists secretsdump; then
    IMPK_CMD=""
    IMPK_TYPE="wrappers"
    return 0
  fi
  # Tentar via pip install
  if "$py_cmd" -c "import impacket" 2>/dev/null; then
    IMPK_CMD="$py_cmd"
    IMPK_TYPE="python_module"
    # Tentar encontrar exemplos
    local impk_base="$("$py_cmd" -c "import impacket; import os; print(os.path.dirname(impacket.__file__))" 2>/dev/null)"
    if [[ -d "${impk_base}/examples" ]]; then
      IMPK_DIR="${impk_base}/examples"
    fi
    return 0
  fi
  return 1
}

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
  if nmap $OPTS "$TGT" 2>&1; then
    printf "%b\n" "${CLR_GREEN}[+] nmap finished${CLR_RESET}\n"
  else
    printf "%b\n" "${CLR_MAG}[!] nmap encountered an error.${CLR_RESET}\n"
  fi
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
  if ! detect_python3; then
    printf "%b" "${CLR_MAG}python3 not found. Skipping dirsearch.${CLR_RESET}\n"
    return
  fi
  if [[ ! -f "$DIRSEARCH_PY" ]]; then
    printf "%b" "${CLR_MAG}dirsearch not found at $DIRSEARCH_PY. Skipping.${CLR_RESET}\n"
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
  cd "$SCRIPT_DIR" || exit 1
  local py_cmd="${PYTHON_CMD:-python3}"
  if "$py_cmd" "$DIRSEARCH_PY" -u "$base" -e "$exts" -t "$th" 2>&1; then
    printf "%b\n" "${CLR_GREEN}[+] dirsearch finished${CLR_RESET}\n"
  else
    printf "%b\n" "${CLR_MAG}[!] dirsearch encountered an error.${CLR_RESET}\n"
  fi
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
  CMD=("${FFUF_CMD:-ffuf}" -w "$WL" -u "$tgt" -mc "$sc" "${FS_FLAG[@]}" -t "$th" -recursion=false -ac)
  [[ -n "$host" ]] && CMD+=(-H "Host: $host")
  if "${CMD[@]}" 2>&1; then
    printf "%b\n" "${CLR_GREEN}[+] ffuf finished${CLR_RESET}\n"
  else
    printf "%b\n" "${CLR_MAG}[!] ffuf encountered an error.${CLR_RESET}\n"
  fi
}

run_subfinder() {
  if ! detect_subfinder; then
    printf "%b" "${CLR_MAG}subfinder not found. Skipping.${CLR_RESET}\n"
    printf "%b" "${CLR_YELLOW}[i] Tip: If installed via 'go install', ensure $(go env GOPATH)/bin is in your PATH${CLR_RESET}\n"
    return
  fi
  read -r -p "Domain for subfinder (example.com): " d
  [[ -z "$d" ]] && {
    echo "Cancelled."
    return
  }
  
  # Extrair domínio de URL se necessário (remover http://, https://, www., trailing slash)
  d="${d#http://}"
  d="${d#https://}"
  d="${d#www.}"
  d="${d%/}"
  d="${d%%/*}"
  
  printf "%b" "${CLR_CYAN}[*] Running subfinder for: $d${CLR_RESET}\n"
  printf "%b" "${CLR_CYAN}[*] This may take a moment...${CLR_RESET}\n\n"
  
  # Executar subfinder e capturar output, filtrando logs
  local subdomains=()
  local subdomains_found=0
  
  while IFS= read -r line; do
    # Ignorar linhas de log e banner
    if [[ "$line" =~ ^\[INF\] ]] || \
       [[ "$line" =~ ^__ ]] || \
       [[ "$line" =~ projectdiscovery ]] || \
       [[ "$line" =~ ^[[:space:]]*$ ]] || \
       [[ "$line" =~ Current.*version ]] || \
       [[ "$line" =~ Loading.*provider ]] || \
       [[ "$line" =~ Enumerating.*subdomains ]] || \
       [[ "$line" =~ Found.*subdomains ]] || \
       [[ "$line" =~ seconds.*milliseconds ]]; then
      continue
    fi
    
    # Verificar se é um subdomínio válido do domínio alvo
    if [[ "$line" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*\.${d//./\\.}$ ]] || \
       [[ "$line" == *".$d" ]] && [[ ! "$line" =~ ^[[:space:]]*\[ ]]; then
      # Limpar espaços em branco
      line="${line//[[:space:]]/}"
      [[ -n "$line" ]] && subdomains+=("$line")
      ((subdomains_found++))
    fi
  done < <("${SUBFINDER_CMD:-subfinder}" -d "$d" 2>&1)
  
  # Mostrar resultados
  printf "\n"
  if [[ ${#subdomains[@]} -gt 0 ]]; then
    printf "%b" "${CLR_GREEN}[+] Found ${#subdomains[@]} subdomain(s):${CLR_RESET}\n"
    for subdomain in "${subdomains[@]}"; do
      printf "%b  • %s${CLR_RESET}\n" "${CLR_GREEN}" "$subdomain"
    done
    printf "\n"
  else
    printf "%b" "${CLR_YELLOW}[i] No subdomains found for $d${CLR_RESET}\n\n"
  fi
  
  printf "%b" "${CLR_GREEN}[+] subfinder finished${CLR_RESET}\n"
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

run_httpx() {
  if ! detect_httpx; then
    printf "%b" "${CLR_MAG}httpx not found. Skipping.${CLR_RESET}\n"
    return
  fi
  read -r -p "Enter target (URL, domain, or file with URLs): " target
  [[ -z "$target" ]] && {
    echo "Cancelled."
    return
  }
  echo "httpx modes: 1) Basic probe  2) Full scan (title, status, tech)  3) Custom flags"
  read -r -p "Choice [1]: " m
  m="${m:-1}"
  CMD=("${HTTPX_CMD:-httpx}")
  case $m in
  1)
    if [[ -f "$target" ]]; then
      CMD+=(-l "$target" -silent -status-code -content-length)
    else
      CMD+=(-u "$target" -silent -status-code -content-length)
    fi
    ;;
  2)
    if [[ -f "$target" ]]; then
      CMD+=(-l "$target" -title -status-code -tech-detect -content-length -follow-redirects)
    else
      CMD+=(-u "$target" -title -status-code -tech-detect -content-length -follow-redirects)
    fi
    ;;
  3)
    read -r -p "Enter custom flags (example: -u \"$target\" -title -status-code): " cf
    [[ -z "$cf" ]] && {
      echo "Cancelled."
      return
    }
    printf "%b" "${CLR_CYAN}[*] Running httpx custom: ${cf}${CLR_RESET}\n\n"
    sh -c "${HTTPX_CMD:-httpx} $cf"
    printf "%b\n" "${CLR_GREEN}[+] httpx (custom) finished${CLR_RESET}\n"
    return
    ;;
  *)
    if [[ -f "$target" ]]; then
      CMD+=(-l "$target" -silent -status-code -content-length)
    else
      CMD+=(-u "$target" -silent -status-code -content-length)
    fi
    ;;
  esac

  printf "%b" "${CLR_CYAN}[*] Running httpx: ${CMD[*]}${CLR_RESET}\n\n"
  "${CMD[@]}" 2>&1
  printf "%b\n" "${CLR_GREEN}[+] httpx finished${CLR_RESET}\n"
}

run_rustscan() {
  if ! detect_rustscan; then
    printf "%b" "${CLR_MAG}rustscan not found. Skipping.${CLR_RESET}\n"
    return
  fi
  read -r -p "Target (IP or hostname): " TGT
  [[ -z "$TGT" ]] && {
    echo "Cancelled."
    return
  }
  echo "RustScan modes: 1) Quick (top 1000 ports)  2) All ports  3) Custom ports  4) With nmap script"
  read -r -p "Choice [1]: " m
  m="${m:-1}"
  CMD=("${RUSTSCAN_CMD:-rustscan}")
  case $m in
  1)
    read -r -p "Threads (default 1000): " threads
    threads="${threads:-1000}"
    CMD+=(-a "$TGT" --ulimit 5000 -t "$threads")
    ;;
  2)
    read -r -p "Threads (default 1000): " threads
    threads="${threads:-1000}"
    CMD+=(-a "$TGT" --ulimit 5000 -t "$threads" -- -sV)
    ;;
  3)
    read -r -p "Ports (e.g. 80,443,8080 or 1-1000): " ports
    [[ -z "$ports" ]] && {
      echo "Cancelled."
      return
    }
    read -r -p "Threads (default 1000): " threads
    threads="${threads:-1000}"
    CMD+=(-a "$TGT" -p "$ports" --ulimit 5000 -t "$threads" -- -sV)
    ;;
  4)
    read -r -p "Nmap script (e.g. vuln,default): " script
    script="${script:-default}"
    read -r -p "Threads (default 1000): " threads
    threads="${threads:-1000}"
    CMD+=(-a "$TGT" --ulimit 5000 -t "$threads" -- -sC -sV --script "$script")
    ;;
  *)
    read -r -p "Threads (default 1000): " threads
    threads="${threads:-1000}"
    CMD+=(-a "$TGT" --ulimit 5000 -t "$threads")
    ;;
  esac

  printf "%b" "${CLR_CYAN}[*] Running rustscan: ${CMD[*]}${CLR_RESET}\n\n"
  "${CMD[@]}" 2>&1
  printf "%b\n" "${CLR_GREEN}[+] rustscan finished${CLR_RESET}\n"
}

run_sqlmap() {
  if ! detect_sqlmap; then
    printf "%b" "${CLR_MAG}sqlmap not found. Skipping.${CLR_RESET}\n"
    return
  fi
  read -r -p "Enter target URL (e.g. http://target.com/page?id=1): " url
  [[ -z "$url" ]] && {
    echo "Cancelled."
    return
  }
  echo "sqlmap modes: 1) Basic test  2) Full scan (dump)  3) Custom flags"
  read -r -p "Choice [1]: " m
  m="${m:-1}"
  
  if [[ "${SQLMAP_TYPE:-}" == "binary" ]]; then
    CMD=("${SQLMAP_CMD:-sqlmap}")
  else
    CMD=("${SQLMAP_CMD[@]}")
  fi
  
  case $m in
  1)
    CMD+=(-u "$url" --batch --crawl=2 --level=2 --risk=2)
    ;;
  2)
    read -r -p "Database name (or Enter to skip): " db
    if [[ -n "$db" ]]; then
      CMD+=(-u "$url" --batch --dbs -D "$db" --dump)
    else
      CMD+=(-u "$url" --batch --dbs --dump-all)
    fi
    ;;
  3)
    read -r -p "Enter custom flags (example: -u \"$url\" --batch --dbs): " cf
    [[ -z "$cf" ]] && {
      echo "Cancelled."
      return
    }
    printf "%b" "${CLR_CYAN}[*] Running sqlmap custom: ${cf}${CLR_RESET}\n\n"
    if [[ "${SQLMAP_TYPE:-}" == "binary" ]]; then
      sh -c "sqlmap $cf"
    else
      sh -c "${SQLMAP_CMD[*]} $cf"
    fi
    printf "%b\n" "${CLR_GREEN}[+] sqlmap (custom) finished${CLR_RESET}\n"
    return
    ;;
  *)
    CMD+=(-u "$url" --batch --crawl=2 --level=2 --risk=2)
    ;;
  esac

  printf "%b" "${CLR_CYAN}[*] Running sqlmap: ${CMD[*]}${CLR_RESET}\n\n"
  printf "%b" "${CLR_YELLOW}[!] Warning: sqlmap can be slow and resource-intensive${CLR_RESET}\n\n"
  "${CMD[@]}" 2>&1
  printf "%b\n" "${CLR_GREEN}[+] sqlmap finished${CLR_RESET}\n"
}

run_bloodhound() {
  if ! detect_bloodhound; then
    printf "%b" "${CLR_MAG}BloodHound not found. Skipping.${CLR_RESET}\n"
    return
  fi
  echo "BloodHound modes: 1) Ingest (collect data)  2) Custom command"
  read -r -p "Choice [1]: " m
  m="${m:-1}"
  
  case $m in
  1)
    read -r -p "Domain (e.g. example.local): " domain
    [[ -z "$domain" ]] && {
      echo "Cancelled."
      return
    }
    read -r -p "Username: " user
    [[ -z "$user" ]] && {
      echo "Cancelled."
      return
    }
    read -r -p "Password (or Enter for hash): " pass
    read -r -p "DC IP (or Enter to auto-detect): " dc_ip
    
    CMD=()
    if [[ "${BLOODHOUND_TYPE:-}" == "binary" ]]; then
      CMD=("${BLOODHOUND_CMD:-bloodhound-python}")
    else
      CMD=("${BLOODHOUND_CMD[@]}")
    fi
    
    CMD+=(-d "$domain" -u "$user")
    if [[ -n "$pass" ]]; then
      CMD+=(-p "$pass")
    else
      read -r -p "NTLM hash: " hash
      [[ -n "$hash" ]] && CMD+=(-hashes "$hash")
    fi
    [[ -n "$dc_ip" ]] && CMD+=(-dc-ip "$dc_ip" -ns "$dc_ip")
    CMD+=(-c all)
    
    printf "%b" "${CLR_CYAN}[*] Running BloodHound ingest: ${CMD[*]}${CLR_RESET}\n\n"
    printf "%b" "${CLR_YELLOW}[!] This may take a while...${CLR_RESET}\n\n"
    "${CMD[@]}" 2>&1
    printf "%b\n" "${CLR_GREEN}[+] BloodHound ingest finished${CLR_RESET}\n"
    printf "%b" "${CLR_CYAN}[i] Import the JSON files into BloodHound UI${CLR_RESET}\n"
    ;;
  2)
    read -r -p "Enter custom BloodHound command: " cf
    [[ -z "$cf" ]] && {
      echo "Cancelled."
      return
    }
    printf "%b" "${CLR_CYAN}[*] Running BloodHound custom: ${cf}${CLR_RESET}\n\n"
    if [[ "${BLOODHOUND_TYPE:-}" == "binary" ]]; then
      sh -c "${BLOODHOUND_CMD:-bloodhound-python} $cf"
    else
      sh -c "${BLOODHOUND_CMD[*]} $cf"
    fi
    printf "%b\n" "${CLR_GREEN}[+] BloodHound (custom) finished${CLR_RESET}\n"
    return
    ;;
  *)
    printf "%b" "${CLR_MAG}Invalid choice.${CLR_RESET}\n"
    return
    ;;
  esac
}

run_evilwinrm() {
  if ! detect_evilwinrm; then
    printf "%b" "${CLR_MAG}Evil-WinRM not found. Skipping.${CLR_RESET}\n"
    return
  fi
  read -r -p "Target IP or hostname: " target
  [[ -z "$target" ]] && {
    echo "Cancelled."
    return
  }
  echo "Authentication method: 1) Username/Password  2) Username/Hash  3) Kerberos  4) Custom"
  read -r -p "Choice [1]: " auth
  auth="${auth:-1}"
  
  CMD=()
  if [[ "${EVILWINRM_TYPE:-}" == "ruby" ]]; then
    CMD=("${EVILWINRM_CMD:-evil-winrm}")
  else
    CMD=("${EVILWINRM_CMD:-evil-winrm}")
  fi
  
  case $auth in
  1)
    read -r -p "Username: " user
    read -r -p "Password: " pass
    CMD+=(-i "$target" -u "$user" -p "$pass")
    ;;
  2)
    read -r -p "Username: " user
    read -r -p "NTLM hash: " hash
    CMD+=(-i "$target" -u "$user" -H "$hash")
    ;;
  3)
    read -r -p "Username: " user
    read -r -p "Kerberos ticket path: " ticket
    CMD+=(-i "$target" -u "$user" -k "$ticket")
    ;;
  4)
    read -r -p "Enter custom Evil-WinRM flags: " cf
    [[ -z "$cf" ]] && {
      echo "Cancelled."
      return
    }
    printf "%b" "${CLR_CYAN}[*] Running Evil-WinRM custom: ${cf}${CLR_RESET}\n\n"
    sh -c "${EVILWINRM_CMD:-evil-winrm} $cf"
    printf "%b\n" "${CLR_GREEN}[+] Evil-WinRM (custom) finished${CLR_RESET}\n"
    return
    ;;
  *)
    read -r -p "Username: " user
    read -r -p "Password: " pass
    CMD+=(-i "$target" -u "$user" -p "$pass")
    ;;
  esac
  
  read -r -p "Port (default 5985): " port
  port="${port:-5985}"
  CMD+=(-P "$port")
  
  printf "%b" "${CLR_CYAN}[*] Connecting via Evil-WinRM to $target:${port}${CLR_RESET}\n\n"
  printf "%b" "${CLR_YELLOW}[!] This will open an interactive WinRM session${CLR_RESET}\n\n"
  "${CMD[@]}" 2>&1
  printf "%b\n" "${CLR_GREEN}[+] Evil-WinRM session closed${CLR_RESET}\n"
}

run_impacket() {
  if ! detect_impacket; then
    printf "%b" "${CLR_MAG}Impacket not found. Skipping.${CLR_RESET}\n"
    return
  fi
  echo "Impacket tools:"
  echo "  1) secretsdump (dump credentials)"
  echo "  2) psexec (PsExec-like)"
  echo "  3) smbexec (SMB exec)"
  echo "  4) wmiexec (WMI exec)"
  echo "  5) GetNPUsers (AS-REP roasting)"
  echo "  6) Custom script"
  read -r -p "Choice [1]: " tool
  tool="${tool:-1}"
  
  local script_name=""
  case $tool in
  1) script_name="secretsdump.py" ;;
  2) script_name="psexec.py" ;;
  3) script_name="smbexec.py" ;;
  4) script_name="wmiexec.py" ;;
  5) script_name="GetNPUsers.py" ;;
  6)
    read -r -p "Script name (e.g. secretsdump.py): " script_name
    [[ -z "$script_name" ]] && {
      echo "Cancelled."
      return
    }
    ;;
  *)
    script_name="secretsdump.py"
    ;;
  esac
  
  # Construir caminho do script
  local script_path=""
  if [[ "${IMPK_TYPE:-}" == "wrappers" ]]; then
    # Usar wrapper binário
    CMD=("${script_name%.py}")
  elif [[ "${IMPK_TYPE:-}" == "docker_repo" ]] || [[ "${IMPK_TYPE:-}" == "local_repo" ]]; then
    script_path="${IMPK_DIR}/examples/${script_name}"
    if [[ -f "$script_path" ]]; then
      CMD=("${IMPK_CMD:-python3}" "$script_path")
    else
      printf "%b" "${CLR_MAG}Script not found: $script_path${CLR_RESET}\n"
      return
    fi
  elif [[ "${IMPK_TYPE:-}" == "python_module" ]]; then
    # Tentar encontrar via Python
    script_path="$("${IMPK_CMD:-python3}" -c "import impacket; import os; print(os.path.dirname(impacket.__file__))" 2>/dev/null)/examples/${script_name}"
    if [[ -f "$script_path" ]]; then
      CMD=("${IMPK_CMD:-python3}" "$script_path")
    else
      printf "%b" "${CLR_MAG}Script not found: $script_path${CLR_RESET}\n"
      return
    fi
  else
    printf "%b" "${CLR_MAG}Could not determine Impacket installation${CLR_RESET}\n"
    return
  fi
  
  read -r -p "Enter target and credentials (e.g. domain/user:pass@target): " target
  [[ -z "$target" ]] && {
    echo "Cancelled."
    return
  }
  
  printf "%b" "${CLR_CYAN}[*] Running Impacket ${script_name}: ${CMD[*]} $target${CLR_RESET}\n\n"
  printf "%b" "${CLR_YELLOW}[!] Warning: This may take time depending on the operation${CLR_RESET}\n\n"
  "${CMD[@]}" "$target" 2>&1
  printf "%b\n" "${CLR_GREEN}[+] Impacket ${script_name} finished${CLR_RESET}\n"
}

# -----------------------
# Run all available (in-order), showing live results
# -----------------------
run_all() {
  neon_header
  printf "%b" "${CLR_CYAN}[*] Running all available modules (live output)...${CLR_RESET}\n\n"
  if detect_subfinder; then
    run_subfinder
  else
    printf "%b" "${CLR_YELLOW}[i] subfinder not available, skipping.${CLR_RESET}\n"
  fi
  if detect_curl; then
    run_crtsh
  else
    printf "%b" "${CLR_YELLOW}[i] curl not available, skipping crt.sh.${CLR_RESET}\n"
  fi
  if detect_nmap; then
    run_nmap
  else
    printf "%b" "${CLR_YELLOW}[i] nmap not available, skipping.${CLR_RESET}\n"
  fi
  if [[ -f "$DIRSEARCH_PY" ]] && detect_python3; then
    run_dirsearch
  else
    printf "%b" "${CLR_YELLOW}[i] dirsearch or python3 not available, skipping.${CLR_RESET}\n"
  fi
  if detect_ffuf; then
    run_ffuf
  else
    printf "%b" "${CLR_YELLOW}[i] ffuf not available, skipping.${CLR_RESET}\n"
  fi
  if detect_xsstrike; then
    run_xsstrike
  else
    printf "%b" "${CLR_YELLOW}[i] XSStrike not available, skipping.${CLR_RESET}\n"
  fi
  if detect_httpx; then
    run_httpx
  else
    printf "%b" "${CLR_YELLOW}[i] httpx not available, skipping.${CLR_RESET}\n"
  fi
  if detect_rustscan; then
    run_rustscan
  else
    printf "%b" "${CLR_YELLOW}[i] rustscan not available, skipping.${CLR_RESET}\n"
  fi
  if detect_sqlmap; then
    run_sqlmap
  else
    printf "%b" "${CLR_YELLOW}[i] sqlmap not available, skipping.${CLR_RESET}\n"
  fi
  if detect_bloodhound; then
    run_bloodhound
  else
    printf "%b" "${CLR_YELLOW}[i] BloodHound not available, skipping.${CLR_RESET}\n"
  fi
  if detect_evilwinrm; then
    run_evilwinrm
  else
    printf "%b" "${CLR_YELLOW}[i] Evil-WinRM not available, skipping.${CLR_RESET}\n"
  fi
  if detect_impacket; then
    run_impacket
  else
    printf "%b" "${CLR_YELLOW}[i] Impacket not available, skipping.${CLR_RESET}\n"
  fi
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
    echo "  8) HTTPX (live)"
    echo "  9) RustScan (live)"
    echo " 10) SQLMap (live)"
    echo " 11) BloodHound (live)"
    echo " 12) Evil-WinRM (live)"
    echo " 13) Impacket (live)"
    echo " 14) Show banner"
    echo " 15) Clear screen"
    echo "  0) Exit"
    printf "%b\n" "${CLR_RESET}"
    read -r -p "Select option: " opt
    # Normalizar para lidar com CRLF (Git Bash/Windows)
    opt="${opt%$'\r'}"
    case "$opt" in
    1) run_all ;;
    2) run_nmap ;;
    3) run_crtsh ;;
    4) run_subfinder ;;
    5) run_dirsearch ;;
    6) run_ffuf ;;
    7) run_xsstrike ;;
    8) run_httpx ;;
    9) run_rustscan ;;
    10) run_sqlmap ;;
    11) run_bloodhound ;;
    12) run_evilwinrm ;;
    13) run_impacket ;;
    14) neon_header ;;
    15)
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
# Setup Python venv antes de iniciar
if command_exists python3; then
  setup_venv || printf "%b" "${CLR_YELLOW}[!] Warning: Python venv setup failed, using system Python${CLR_RESET}\n"
fi

if ! detect_jq; then printf "%b" "${CLR_YELLOW}[!] Note: jq not found. crt.sh output parsing will fallback to basic parsing.${CLR_RESET}\n"; fi
neon_header
main_loop
