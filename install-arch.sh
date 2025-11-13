#!/usr/bin/env bash
# install-arch.sh — instala dependências em Arch/Manjaro (pacman + optional AUR via yay)
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECLISTS_DIR="$SCRIPT_DIR/seclists"
WORDLISTS_DIR="$SCRIPT_DIR/wordlists"
DIRSEARCH_DIR="$SCRIPT_DIR/dirsearch"
XS_DIR="$SCRIPT_DIR/XSStrike"

info(){ printf "\033[1;36m[i]\033[0m %s\n" "$*"; }
ok(){ printf "\033[1;32m[+]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err(){ printf "\033[1;31m[-]\033[0m %s\n" "$*"; }

# Pacotes pacman
PKGS=(git python python-pip nmap jq go curl base-devel)

info "Atualizando repositórios e instalando pacotes: ${PKGS[*]}"
pacman -Syu --noconfirm
pacman -S --noconfirm "${PKGS[@]}" || { warn "Falha ao instalar alguns pacotes via pacman. Verifique manualmente."; }

# AUR helper detection (yay/paru)
AUR_HELPER=""
if command -v yay >/dev/null 2>&1; then AUR_HELPER=yay
elif command -v paru >/dev/null 2>&1; then AUR_HELPER=paru
fi

if [[ -n "$AUR_HELPER" ]]; then
  ok "AUR helper detectado: $AUR_HELPER"
  info "Instalando ffuf (AUR) e outras ferramentas possíveis via AUR"
  $AUR_HELPER -S --noconfirm ffuf || warn "ffuf AUR install falhou (pode já existir via go)."
else
  warn "Nenhum AUR helper encontrado. ffuf/subfinder serão instalados via go install (se go presente). Se preferir, instale yay/paru."
fi

# go install ffuf/subfinder
if command -v go >/dev/null 2>&1; then
  info "Instalando ffuf e subfinder via go install"
  go install github.com/ffuf/ffuf@latest || warn "go install ffuf falhou"
  go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest || warn "go install subfinder falhou"
else
  warn "go não encontrado — pulei go install. Instale go para usar go install."
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
  info "Clonando SecLists (pode ser grande)..."
  git clone --depth 1 https://github.com/danielmiessler/SecLists.git "$SECLISTS_DIR" || warn "clone SecLists falhou"
fi

# python deps for XSStrike
if command -v pip >/dev/null 2>&1 && [[ -f "$XS_DIR/requirements.txt" ]]; then
  info "Instalando requirements do XSStrike..."
  pip install -r "$XS_DIR/requirements.txt" || warn "pip install requirements falhou"
fi

ok "Instalação concluída."
printf "Resumo:\n - dirsearch: %s\n - XSStrike: %s\n - SecLists: %s\n - wordlists: %s\n" "$DIRSEARCH_DIR" "$XS_DIR" "$SECLISTS_DIR" "$WORDLISTS_DIR"
warn "Se ffuf/subfinder não estiverem no PATH, adicione $(go env GOPATH)/bin ou $(go env GOBIN) ao PATH."

