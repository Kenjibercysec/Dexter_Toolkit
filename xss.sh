#!/bin/bash
# Enhanced malwaricon script with per-command flag selection and wordlist chooser for ffuf
# Now includes rustscan in the toolkit
# Requirements: nmap, jq, ffuf, rustscan, python3, dirsearch, curl

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATH_TO_DIRSEARCH="$SCRIPT_DIR/dirsearch/dirsearch.py"

command_exists() { command -v "$1" >/dev/null 2>&1; }

if ! command_exists jq; then
  echo "[!] jq is required but not found. Install it and re-run."
  exit 1
fi

read -p "Enter domain or IP (e.g. example.com or 10.10.10.10): " TARGET
if [ -z "$TARGET" ]; then
  echo "[!] Target cannot be empty."
  exit 1
fi

OUTPUT_PREFIX="${TARGET}"

# --- Nmap ---
run_nmap() {
  echo
  echo "[*] Choose an Nmap preset (or Custom):"
  nmap_opts=("Quick (-sV)" "Aggressive (-A -sC -sV)" "All ports (-p-)" "OS & scripts (-O -sC)" "Custom")
  select opt in "${nmap_opts[@]}"; do
    case $REPLY in
    1)
      OPTS="-sV"
      break
      ;;
    2)
      OPTS="-A -sC -sV"
      break
      ;;
    3)
      OPTS="-p- -sV"
      break
      ;;
    4)
      OPTS="-O -sC -sV"
      break
      ;;
    5)
      read -p "Enter custom nmap flags: " OPTS
      break
      ;;
    *) echo "Invalid." ;;
    esac
  done

  read -p "Extra ports (comma-separated) or leave empty: " EXTRA_PORTS
  if [ -n "$EXTRA_PORTS" ]; then
    OPTS="$OPTS -p $EXTRA_PORTS"
  fi

  OUT_FILE="${OUTPUT_PREFIX}_nmap.txt"
  echo "[*] Running: nmap $OPTS -oN $OUT_FILE $TARGET"
  nmap $OPTS -oN "$OUT_FILE" "$TARGET"
  echo "[+] Saved to $OUT_FILE"
}

# --- Rustscan ---
run_rustscan() {
  if ! command_exists rustscan; then
    echo "[!] rustscan not found. Install rustscan or skip this step."
    return
  fi

  echo
  echo "[*] Rustscan presets:"
  rust_opts=("Top 1000 ports (fast)" "All ports (1-65535)" "Custom ports" "Rustscan -> Nmap (scan ports then run nmap with flags)")
  select opt in "${rust_opts[@]}"; do
    case $REPLY in
    1)
      PORTS="--ulimit 5000 --range 1-65535 --short" # we'll use top ports via rustscan's default behaviour by not specifying range; user-friendly fallback
      RS_CMD=(rustscan -a "$TARGET" --ulimit 5000)
      break
      ;;
    2)
      read -p "Enter port range (e.g. 1-65535): " RANGE
      [ -z "$RANGE" ] && RANGE="1-65535"
      RS_CMD=(rustscan -a "$TARGET" --range "$RANGE" --ulimit 5000)
      break
      ;;
    3)
      read -p "Enter custom ports (comma-separated, e.g. 22,80,443): " CUSTOM_PORTS
      RS_CMD=(rustscan -a "$TARGET" --ports "$CUSTOM_PORTS" --ulimit 5000)
      break
      ;;
    4)
      read -p "Enter nmap flags to run after rustscan (e.g. -A -sV): " NMAP_FLAGS
      [ -z "$NMAP_FLAGS" ] && NMAP_FLAGS="-sV"
      RS_CMD=(rustscan -a "$TARGET" --ulimit 5000 -- -sV)
      # We'll pass NMAP_FLAGS through when executing
      NMAP_AFTER="$NMAP_FLAGS"
      break
      ;;
    *) echo "Invalid." ;;
    esac
  done

  OUT_FILE="${OUTPUT_PREFIX}_rustscan.txt"

  if [ -n "$NMAP_AFTER" ]; then
    echo "[*] Running rustscan and then nmap with: $NMAP_AFTER"
    rustscan -a "$TARGET" --ulimit 5000 -- "--" $NMAP_AFTER | tee "$OUT_FILE"
    echo "[+] rustscan + nmap output saved to $OUT_FILE"
  else
    echo "[*] Running: ${RS_CMD[*]}"
    "${RS_CMD[@]}" | tee "$OUT_FILE"
    echo "[+] rustscan output saved to $OUT_FILE"
  fi
}

# --- Subdomain enumeration (crt.sh) ---
run_crtsh() {
  echo "[*] Enumerating subdomains from crt.sh..."
  OUT_FILE="${OUTPUT_PREFIX}_crt.txt"
  curl -s "https://crt.sh/?q=%25.$TARGET&output=json" | jq -r '.[].name_value' | sed 's/\*\.//g' | sort -u >"$OUT_FILE"
  echo "[+] Saved to $OUT_FILE"
}

# --- Dirsearch ---
run_dirsearch() {
  if [ ! -f "$PATH_TO_DIRSEARCH" ]; then
    echo "[!] dirsearch not found at $PATH_TO_DIRSEARCH. Skipping."
    return
  fi

  echo
  read -p "Enter base URL (e.g. http://$TARGET or https://$TARGET): " BASE_URL
  [ -z "$BASE_URL" ] && BASE_URL="http://$TARGET"

  echo "Select extensions to search (comma separated, e.g. php,html,js,txt). Leave blank for default:"
  read -p "Exts: " EXTS
  [ -z "$EXTS" ] && EXTS="php,html,js,txt"

  read -p "Threads (e.g. 10): " THREADS
  [ -z "$THREADS" ] && THREADS=10

  OUT_FILE="${OUTPUT_PREFIX}_dirsearch.txt"
  echo "[*] Running dirsearch against $BASE_URL (-e $EXTS -t $THREADS)"
  python3 "$PATH_TO_DIRSEARCH" -u "$BASE_URL" -e "$EXTS" -t "$THREADS" -o "$OUT_FILE"
  echo "[+] Saved to $OUT_FILE"
}

# --- FFUF ---
list_wordlists() {
  # search in ./seclists and ./wordlists
  WL_DIRS=("$SCRIPT_DIR/seclists" "$SCRIPT_DIR/wordlists")
  files=()
  for d in "${WL_DIRS[@]}"; do
    [ -d "$d" ] || continue
    while IFS= read -r -d $'' f; do files+=("$f"); done < <(find "$d" -type f -maxdepth 6 -print0)
  done
}

run_ffuf() {
  if ! command_exists ffuf; then
    echo "[!] ffuf not found. Install ffuf or skip this step."
    return
  fi

  echo
  read -p "Enter the target URL (use FUZZ placeholder, e.g. http://$TARGET/FUZZ or http://$TARGET/sub/FUZZ): " TARGET_URL
  if [[ "$TARGET_URL" != *FUZZ* ]]; then
    # try to append /FUZZ if user entered base
    if [[ "$TARGET_URL" =~ \/$ ]]; then
      TARGET_URL+="FUZZ"
    else
      TARGET_URL+="/FUZZ"
    fi
    echo "[i] Target URL changed to: $TARGET_URL"
  fi

  read -p "Enter Host header if needed (leave empty to skip): " HOST_HEADER

  # choose wordlist
  echo "[*] Scanning available wordlists (this may take a second)..."
  list_wordlists
  if [ ${#files[@]} -eq 0 ]; then
    echo "[!] No wordlists found in seclists/ or wordlists/. You can enter a custom path."
  else
    echo "Select a wordlist from the list (or choose 'Custom path')"
    PS3="Choose wordlist: "
    choices=("Custom path")
    for f in "${files[@]}"; do choices+=("$f"); done
    select choice in "${choices[@]}"; do
      if [ "$REPLY" -eq 1 ]; then
        read -p "Enter full path to wordlist: " FULL_WL_PATH
      else
        idx=$((REPLY - 2))
        if [ $idx -ge 0 ] && [ $idx -lt ${#files[@]} ]; then
          FULL_WL_PATH="${files[$idx]}"
        else
          echo "Invalid."
          continue
        fi
      fi
      break
    done
  fi

  if [ -z "$FULL_WL_PATH" ] || [ ! -f "$FULL_WL_PATH" ]; then
    echo "[!] Wordlist not found or not provided. Aborting ffuf."
    return
  fi

  read -p "Status codes to include (comma-separated, default 200,301,403,401): " STATUS_CODES
  [ -z "$STATUS_CODES" ] && STATUS_CODES="200,301,403,401"

  read -p "Filter by response size (e.g. -fs 6109) leave blank to skip: " FILTER_SIZE
  FS_FLAG=""
  if [ -n "$FILTER_SIZE" ]; then FS_FLAG="-fs $FILTER_SIZE"; fi

  read -p "Number of threads (-t) [default 40]: " FF_THREADS
  [ -z "$FF_THREADS" ] && FF_THREADS=40

  OUT_JSON="${OUTPUT_PREFIX}_ffuf.json"

  CMD=(ffuf -w "$FULL_WL_PATH" -u "$TARGET_URL" -mc "$STATUS_CODES" $FS_FLAG -t "$FF_THREADS" -o "$OUT_JSON" -of json -recursion=false -ac)

  if [ -n "$HOST_HEADER" ]; then
    CMD+=(-H "Host: $HOST_HEADER")
  fi

  echo "[*] Running ffuf: ${CMD[*]}"
  eval "${CMD[*]}"
  echo "[+] Saved to $OUT_JSON"
}

# --- Main menu ---
PS3="Select reconnaissance mode: "
options=("Run all" "Nmap" "Rustscan" "Subdomain enumeration (crt.sh)" "Dirsearch" "FFUF (Fuzzing)" "Exit")
select opt in "${options[@]}"; do
  case $REPLY in
  1)
    run_nmap
    run_rustscan
    run_crtsh
    run_dirsearch
    run_ffuf
    break
    ;;
  2)
    run_nmap
    break
    ;;
  3)
    run_rustscan
    break
    ;;
  4)
    run_crtsh
    break
    ;;
  5)
    run_dirsearch
    break
    ;;
  6)
    run_ffuf
    break
    ;;
  7)
    echo "Exiting."
    exit 0
    ;;
  *) echo "Invalid option." ;;
  esac
done

echo "[*] Recon completed for $TARGET"
