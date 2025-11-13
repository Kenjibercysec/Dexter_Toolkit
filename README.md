# Dexter Toolkit

![Version](https://img.shields.io/badge/Version-1.0-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey)

Dexter Toolkit orquestra, em um único painel interativo, várias etapas comuns de reconhecimento ofensivo. O `dexter.sh` detecta quais binários estão instalados, apresenta apenas opções viáveis e executa cada módulo em tempo real, sem gerar arquivos temporários.

## Principais módulos

- **Run all** — dispara, em sequência, todos os módulos disponíveis na máquina.
- **Nmap** — presets rápidos de varredura (`-sV`, `-A`, `-p-`, etc.) com ajuste de portas adicionais.
- **crt.sh** — enumeração de subdomínios via API pública com parsing opcional por `jq`.
- **Subfinder** — integração direta com o binário `subfinder`.
- **Dirsearch** — execução local do `dirsearch.py` clonado no repositório.
- **FFUF** — brute force de conteúdo com seleção de wordlists em `seclists/` ou `wordlists/`.
- **XSStrike** — detecção automática do binário local, módulo Python ou repositório clonado do XSStrike.
- **Banner & limpeza** — utilitários para refrescar a interface.

## Prerequisites

Before using Dexter Toolkit, make sure you have the following installed:

- **Bash 4+**
- **Git**
- **Python 3** (para `dirsearch` e XSStrike via repositório)
- **curl** e **jq**
- **nmap**, **ffuf**, **subfinder** (o `dexter.sh` ignora o que não estiver presente)
- **Go** (caso deseje instalar `ffuf`/`subfinder` via `go install`)
- **pip/pip3** (para dependências Python do XSStrike)

## Installation

### Instalação automatizada

Os scripts de instalação configuram dependências, clonam repositórios auxiliares (`dirsearch`, `XSStrike`, `SecLists`) e tentam instalar `ffuf`/`subfinder`. Execute o script adequado para o seu ambiente a partir da raiz do repositório:

- Debian, Ubuntu, Kali e derivados:

```bash
chmod +x install-apt.sh
sudo ./install-apt.sh
```

- Arch, Manjaro e derivados:

```bash
chmod +x install-arch.sh
sudo ./install-arch.sh
```

- Windows (PowerShell 7+):

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install-windows.ps1
```

Os scripts detectam gerenciadores (`apt`, `pacman`, `winget`, `choco`, `yay`, `paru`) e utilizam `git pull` quando os diretórios já existem. Ao final, confirme se o diretório de binários do Go (`$(go env GOPATH)/bin`) está no `PATH` quando `go install` for utilizado.

### Clonando e executando manualmente

```bash
git clone https://github.com/Kenjibercysec/Dexter_Toolkit.git
cd Dexter_Toolkit
chmod +x dexter.sh
./dexter.sh
```

### Manual setup

```bash
# Clone the repository
git clone https://github.com/Kenjibercysec/Dexter_Toolkit.git

# Navigate to the toolkit directory
cd Dexter_Toolkit

# Conceda permissão de execução ao painel principal
chmod +x dexter.sh

# Rode o painel interativo
./dexter.sh
```

## Wordlists Setup

O `dexter.sh` procura wordlists dentro de `seclists/` e `wordlists/`. Caso nenhum arquivo seja encontrado, o usuário pode fornecer o caminho completo manualmente. Os scripts de instalação já clonam o repositório `SecLists`; você também pode:

```bash
# Clonar SecLists manualmente
git clone --depth 1 https://github.com/danielmiessler/SecLists.git seclists

# Criar um diretório dedicado para listas próprias
mkdir -p wordlists
# Exemplo: adicionar rockyou.txt
wget -O wordlists/rockyou.txt https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt
```

## Usage

### Main interface

Rode o painel principal para acessar o menu interativo:

```bash
./dexter.sh
```

O menu apresenta as opções abaixo. Apenas as que tiverem binários detectados serão executadas; o restante é ignorado com mensagens informativas.

- `1) Run all available modules` — executa sequencialmente Subfinder, crt.sh, Nmap, Dirsearch, FFUF e XSStrike.
- `2) Nmap` — presets interativos com suporte a portas extras.
- `3) Subdomain enumeration (crt.sh)` — consulta direta à API crt.sh com formatação por `jq` quando disponível.
- `4) Subfinder` — chama `subfinder -d <domínio>`.
- `5) Dirsearch` — wrapper simples para `dirsearch.py`, permitindo ajustar extensões e threads.
- `6) FFUF` — executa `ffuf` com seleção de wordlist e filtros de código/tamanho.
- `7) XSStrike` — detecta a forma de execução (binário, módulo Python ou repositório local) e oferece presets comuns.
- `8) Show banner` — redesenha o cabeçalho neon.
- `9) Clear screen` — limpa o terminal e mostra o banner novamente.
- `0) Exit` — encerra o painel.

**Observação:** todo output é exibido ao vivo no terminal; nenhum arquivo é salvo por padrão. Utilize redirecionamento manual (`tee`, `>` etc.) caso deseje persistir resultados.

## Project structure

```
Dexter_Toolkit/
├── dexter.sh             # Painel interativo principal
├── install-apt.sh        # Instalação automatizada para Debian/Ubuntu/Kali
├── install-arch.sh       # Instalação automatizada para Arch/Manjaro
├── install-windows.ps1   # Instalação automatizada para Windows (PowerShell)
├── dirsearch/            # Clonado pelos scripts de instalação (opcional)
├── XSStrike/             # Clonado pelos scripts de instalação (opcional)
├── seclists/             # Coleção de wordlists (opcional, mas recomendado)
├── wordlists/            # Wordlists personalizadas (opcional)
└── README.md
```

## Contributing

Contributions, issue reports and feature requests are welcome. Please open an issue or submit a pull request on the repository.

## License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.

## Contact

For questions or collaboration, open an issue on the repository or contact the maintainer via the GitHub profile.
