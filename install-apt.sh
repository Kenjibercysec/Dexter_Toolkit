#!/usr/bin/env bash
# install-apt.sh — instala dependências via apt (Debian/Ubuntu)
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECLISTS_DIR="$SCRIPT_DIR/seclists"
WORDLISTS_DIR="$SCRIPT_DIR/wordlists"
DIRSEARCH_DIR="$SCRIPT_DIR/dirsearch"
XS_DIR="$SCRIPT_DIR/XSStrike"

info(){ printf "\033[1;36m[i]\033[0m %s\n" "$*"; }
ok(){ printf "\033[1;32m[+]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[!]\033[0m %s\n" "$*"; }

# Update & install packages
info "Atualizando apt e instalando pacotes básicos..."
apt update -y
DEBIAN_FRONTEND=noninteractive apt install -y git curl python3 python3-pip python3-venv nmap jq gcc make golang || {
  warn "Alguns pacotes falharam ao instalar. Verifique sua conexão / repositórios."
}

# Try to install ffuf from apt (if available); otherwise rely on go install
if apt-cache show ffuf >/dev/null 2>&1; then
  info "Instalando ffuf via apt"
  apt install -y ffuf || warn "ffuf via apt falhou"
else
  warn "ffuf não disponível no repositório apt; será tentado via 'go install' se go presente."
fi

# go install ffuf/subfinder if go present
if command -v go >/dev/null 2>&1; then
  info "Instalando ffuf e subfinder via go install..."
  go install github.com/ffuf/ffuf@latest || warn "go install ffuf falhou"
  go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest || warn "go install subfinder falhou"
else
  warn "go não encontrado. Instale 'golang' e re-run para go install."
fi

# Clone repos
if [[ -d "$DIRSEARCH_DIR/.git" ]]; then
  info "Atualizando dirsearch..."
  git -C "$DIRSEARCH_DIR" pull --ff-only || warn "git pull dirsearch falhou"
else
  info "Clonando dirsearch..."
  git clone --depth 1 https://github.com/maurosoria/dirsearch.git "$DIRSEARCH_DIR" || warn "clone dirsearch falhou"
fi

if [[ -d "$XS_DIR/.git" ]]; then
  info "Atualizando XSStrike..."
  git -C "$XS_DIR" pull --ff-only || warn "git pull xsstrike falhou"
else
  info "Clonando XSStrike..."
  git clone --depth 1 https://github.com/s0md3v/XSStrike.git "$XS_DIR" || warn "clone XSStrike falhou"
fi

if [[ -d "$SECLISTS_DIR/.git" ]]; then
  info "Atualizando SecLists..."
  git -C "$SECLISTS_DIR" pull --ff-only || warn "git pull seclists falhou"
else
  info "Clonando SecLists (pode demorar)..."
  git clone --depth 1 https://github.com/danielmiessler/SecLists.git "$SECLISTS_DIR" || warn "clone SecLists falhou"
fi

# pip requirements for XSStrike
if command -v pip3 >/dev/null 2>&1 && [[ -f "$XS_DIR/requirements.txt" ]]; then
  info "Instalando dependências Python do XSStrike via pip3..."
  pip3 install -r "$XS_DIR/requirements.txt" || warn "pip3 install requirements falhou"
fi

ok "Instalação APT finalizada."
printf "Resumo:\n - dirsearch: %s\n - XSStrike: %s\n - SecLists: %s\n - wordlists: %s\n" "$DIRSEARCH_DIR" "$XS_DIR" "$SECLISTS_DIR" "$WORDLISTS_DIR"
warn "Se instalou via go, verifique se $(go env GOPATH)/bin (ou $(go env GOBIN)) está no PATH."


