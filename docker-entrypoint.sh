#!/bin/bash
# Entrypoint para o container Docker

set -e

# Garantir que o PATH inclui os binários Go
export PATH=$GOPATH/bin:/usr/local/go/bin:$PATH
export PATH=$CARGO_HOME/bin:$PATH

# Ativar venv Python se existir
if [ -f /opt/dexter/.venv/bin/activate ]; then
    source /opt/dexter/.venv/bin/activate
fi

# Criar diretórios necessários
mkdir -p /opt/dexter/wordlists
mkdir -p /opt/dexter/results

# Verificar se ferramentas estão disponíveis
echo "[*] Verificando ferramentas instaladas..."
command -v httpx >/dev/null 2>&1 && echo "[+] httpx: OK" || echo "[-] httpx: não encontrado"
command -v rustscan >/dev/null 2>&1 && echo "[+] rustscan: OK" || echo "[-] rustscan: não encontrado"
command -v sqlmap >/dev/null 2>&1 && echo "[+] sqlmap: OK" || echo "[-] sqlmap: não encontrado"
command -v ffuf >/dev/null 2>&1 && echo "[+] ffuf: OK" || echo "[-] ffuf: não encontrado"
command -v subfinder >/dev/null 2>&1 && echo "[+] subfinder: OK" || echo "[-] subfinder: não encontrado"
command -v nmap >/dev/null 2>&1 && echo "[+] nmap: OK" || echo "[-] nmap: não encontrado"
command -v dirsearch >/dev/null 2>&1 && echo "[+] dirsearch: OK" || echo "[-] dirsearch: não encontrado"
command -v xsstrike >/dev/null 2>&1 && echo "[+] xsstrike: OK" || echo "[-] xsstrike: não encontrado"
command -v bloodhound-python >/dev/null 2>&1 && echo "[+] bloodhound-python: OK" || command -v bloodhound-ce >/dev/null 2>&1 && echo "[+] bloodhound-ce: OK" || echo "[-] bloodhound: não encontrado"
command -v evil-winrm >/dev/null 2>&1 && echo "[+] evil-winrm: OK" || command -v evil_winrm >/dev/null 2>&1 && echo "[+] evil-winrm (ruby): OK" || echo "[-] evil-winrm: não encontrado"
command -v secretsdump >/dev/null 2>&1 && echo "[+] impacket: OK" || [ -f /opt/tools/impacket/examples/secretsdump.py ] && echo "[+] impacket: OK" || echo "[-] impacket: não encontrado"

echo ""

# Executar comando passado ou script padrão
if [ $# -eq 0 ]; then
    exec /opt/dexter/dexter.sh
else
    exec "$@"
fi
