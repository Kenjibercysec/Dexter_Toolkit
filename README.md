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
- **HTTPX** — sondagem HTTP/HTTPS rápida com detecção de tecnologias, títulos e status codes.
- **RustScan** — scanner de portas ultrarrápido com integração ao Nmap.
- **SQLMap** — detecção e exploração automatizada de vulnerabilidades de injeção SQL.
- **BloodHound** — coletor de dados do Active Directory para análise de relações e caminhos de ataque.
- **Evil-WinRM** — shell interativo WinRM para acesso remoto a sistemas Windows.
- **Impacket** — conjunto de ferramentas Python para protocolos de rede (SMB, Kerberos, etc).
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

### 🐳 Instalação via Docker (Recomendado)

A forma mais simples e unificada de usar o Dexter Toolkit é através do Docker. Isso elimina a necessidade de instalar dependências manualmente em diferentes sistemas operacionais.

#### Pré-requisitos Docker

- **Docker** instalado e em execução
- **Docker Compose** (opcional, mas recomendado)

#### Construir e executar

```bash
# Tornar o script de build executável
chmod +x build-docker.sh

# Construir a imagem Docker
./build-docker.sh build

# Executar o container (modo interativo)
./build-docker.sh run
```

Ou usando Docker Compose:

```bash
# Construir e iniciar
docker-compose up --build

# Executar em modo interativo
docker-compose run --rm dexter

# Parar o container
docker-compose down
```

#### Comandos úteis do build-docker.sh

```bash
./build-docker.sh build      # Construir a imagem
./build-docker.sh run        # Executar interativo
./build-docker.sh start       # Iniciar em background
./build-docker.sh stop        # Parar container
./build-docker.sh shell       # Abrir shell no container
./build-docker.sh logs        # Ver logs
./build-docker.sh clean       # Remover tudo
./build-docker.sh update      # Reconstruir imagem
```

#### Estrutura de volumes Docker

O Docker monta automaticamente os seguintes diretórios:
- `./wordlists` → `/opt/dexter/wordlists` (wordlists personalizadas)
- `./seclists` → `/opt/tools/seclists` (SecLists)
- `./results` → `/opt/dexter/results` (resultados de scans)

### Instalação nativa (alternativa ao Docker)

Se preferir não usar Docker, você pode instalar as ferramentas manualmente seguindo as instruções de cada repositório oficial. O `dexter.sh` detectará automaticamente quais ferramentas estão disponíveis no sistema.

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

- `1) Run all available modules` — executa sequencialmente todos os módulos disponíveis.
- `2) Nmap` — presets interativos com suporte a portas extras.
- `3) Subdomain enumeration (crt.sh)` — consulta direta à API crt.sh com formatação por `jq` quando disponível.
- `4) Subfinder` — chama `subfinder -d <domínio>`.
- `5) Dirsearch` — wrapper simples para `dirsearch.py`, permitindo ajustar extensões e threads.
- `6) FFUF` — executa `ffuf` com seleção de wordlist e filtros de código/tamanho.
- `7) XSStrike` — detecta a forma de execução (binário, módulo Python ou repositório local) e oferece presets comuns.
- `8) HTTPX` — sondagem HTTP/HTTPS com detecção de tecnologias, títulos e status codes.
- `9) RustScan` — scanner de portas ultrarrápido com integração ao Nmap.
- `10) SQLMap` — detecção e exploração de vulnerabilidades de injeção SQL.
- `11) BloodHound` — coleta dados do Active Directory para análise.
- `12) Evil-WinRM` — shell interativo WinRM para acesso remoto Windows.
- `13) Impacket` — ferramentas para protocolos de rede (SMB, Kerberos, etc).
- `14) Show banner` — redesenha o cabeçalho neon.
- `15) Clear screen` — limpa o terminal e mostra o banner novamente.
- `0) Exit` — encerra o painel.

**Observação:** todo output é exibido ao vivo no terminal; nenhum arquivo é salvo por padrão. Utilize redirecionamento manual (`tee`, `>` etc.) caso deseje persistir resultados.

## Project structure

```
Dexter_Toolkit/
├── dexter.sh             # Painel interativo principal
├── Dockerfile            # Imagem Docker unificada
├── docker-compose.yml    # Configuração Docker Compose
├── docker-entrypoint.sh  # Script de entrada do container
├── build-docker.sh       # Script de gerenciamento Docker
├── ADDING_TOOLS.md       # Guia para adicionar novas ferramentas
├── dirsearch/            # Clonado pelo Dockerfile (opcional)
├── XSStrike/             # Clonado pelo Dockerfile (opcional)
├── sqlmap/               # Clonado pelo Dockerfile (opcional)
├── impacket/             # Clonado pelo Dockerfile (opcional)
├── seclists/             # Coleção de wordlists (opcional, mas recomendado)
├── wordlists/            # Wordlists personalizadas (opcional)
└── README.md
```

## Ferramentas incluídas

O Dexter Toolkit inclui as seguintes ferramentas de segurança:

| Ferramenta | Tipo | Descrição |
|------------|------|-----------|
| **nmap** | Binário | Scanner de portas e serviços |
| **subfinder** | Go | Enumeração de subdomínios |
| **ffuf** | Go | Web fuzzer rápido |
| **httpx** | Go | Sondagem HTTP/HTTPS |
| **rustscan** | Rust | Scanner de portas ultrarrápido |
| **dirsearch** | Python | Scanner de diretórios web |
| **XSStrike** | Python | Detector de vulnerabilidades XSS |
| **sqlmap** | Python | Exploração de injeção SQL |
| **bloodhound-ce** | Python | Coletor de dados do Active Directory |
| **evil-winrm** | Ruby/Python | Shell interativo WinRM |
| **impacket** | Python | Ferramentas para protocolos de rede |
| **curl/jq** | Binários | Utilitários para APIs e parsing JSON |

## Contributing

Contributions, issue reports and feature requests are welcome. Please open an issue or submit a pull request on the repository.

## License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.

## Contact

For questions or collaboration, open an issue on the repository or contact the maintainer via the GitHub profile.
