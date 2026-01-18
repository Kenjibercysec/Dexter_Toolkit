# Adicionando Novas Ferramentas ao Dexter Toolkit

Este documento explica como adicionar novas ferramentas ao Dexter Toolkit, tanto para uso nativo quanto via Docker.

## Estrutura Geral

Para adicionar uma nova ferramenta, você precisa:

1. **Instalar a ferramenta** (Dockerfile ou scripts de instalação)
2. **Criar função de detecção** no `dexter.sh`
3. **Criar função de execução** no `dexter.sh`
4. **Adicionar ao menu** principal
5. **Adicionar ao `run_all()`** (opcional)

## Exemplo: Adicionar uma ferramenta Go

### 1. Dockerfile

Adicione a instalação no Dockerfile:

```dockerfile
# No bloco de ferramentas Go
RUN go install -v github.com/usuario/ferramenta/cmd/ferramenta@latest
```

### 2. dexter.sh - Função de Detecção

```bash
detect_ferramenta() {
  if command_exists ferramenta; then
    FERRAMENTA_CMD="ferramenta"
    return 0
  fi
  # Tentar encontrar no Go bin configurado
  if [[ -n "${GOBIN:-}" ]] && [[ -f "$GOBIN/ferramenta" ]]; then
    FERRAMENTA_CMD="$GOBIN/ferramenta"
    return 0
  fi
  # Tentar GOPATH padrão
  if [[ -z "${GOBIN:-}" ]]; then
    DEFAULT_GOPATH="${HOME}/go/bin"
    if [[ -f "$DEFAULT_GOPATH/ferramenta" ]]; then
      FERRAMENTA_CMD="$DEFAULT_GOPATH/ferramenta"
      return 0
    fi
  fi
  return 1
}
```

### 3. dexter.sh - Função de Execução

```bash
run_ferramenta() {
  if ! detect_ferramenta; then
    printf "%b" "${CLR_MAG}ferramenta not found. Skipping.${CLR_RESET}\n"
    return
  fi
  read -r -p "Enter target: " target
  [[ -z "$target" ]] && {
    echo "Cancelled."
    return
  }
  echo "Modes: 1) Quick  2) Full  3) Custom"
  read -r -p "Choice [1]: " m
  m="${m:-1}"
  CMD=("${FERRAMENTA_CMD:-ferramenta}")
  case $m in
  1) CMD+=(-u "$target" -quick) ;;
  2) CMD+=(-u "$target" -full) ;;
  3)
    read -r -p "Enter custom flags: " cf
    [[ -z "$cf" ]] && return
    printf "%b" "${CLR_CYAN}[*] Running custom: ${cf}${CLR_RESET}\n\n"
    sh -c "${FERRAMENTA_CMD:-ferramenta} $cf"
    printf "%b\n" "${CLR_GREEN}[+] Finished${CLR_RESET}\n"
    return
    ;;
  *) CMD+=(-u "$target" -quick) ;;
  esac

  printf "%b" "${CLR_CYAN}[*] Running: ${CMD[*]}${CLR_RESET}\n\n"
  "${CMD[@]}" 2>&1
  printf "%b\n" "${CLR_GREEN}[+] Finished${CLR_RESET}\n"
}
```

### 4. Adicionar ao Menu

No `main_loop()`, adicione a opção:

```bash
echo "  X) Ferramenta (live)"
```

E no `case`:

```bash
X) run_ferramenta ;;
```

### 5. Adicionar ao run_all() (Opcional)

```bash
if detect_ferramenta; then
  run_ferramenta
else
  printf "%b" "${CLR_YELLOW}[i] ferramenta not available, skipping.${CLR_RESET}\n"
fi
```

## Exemplo: Adicionar Ferramenta Python

### 1. Dockerfile

```dockerfile
# Clonar repositório
RUN cd /opt/tools && \
    git clone --depth 1 https://github.com/usuario/ferramenta.git ferramenta && \
    cd ferramenta && \
    pip3 install -q -r requirements.txt

# Criar link simbólico
RUN ln -sf /opt/tools/ferramenta/ferramenta.py /usr/local/bin/ferramenta
```

### 2. Detecção (similar ao XSStrike)

```bash
detect_ferramenta() {
  if command_exists ferramenta; then
    FERRAMENTA_CMD=(ferramenta)
    FERRAMENTA_TYPE="binary"
    return 0
  fi
  local py_cmd="${PYTHON_CMD:-python3}"
  if [[ -f "$SCRIPT_DIR/ferramenta/ferramenta.py" ]]; then
    FERRAMENTA_CMD=("$py_cmd" "$SCRIPT_DIR/ferramenta/ferramenta.py")
    FERRAMENTA_TYPE="local_repo"
    return 0
  fi
  if [[ -f "/opt/tools/ferramenta/ferramenta.py" ]]; then
    FERRAMENTA_CMD=("$py_cmd" "/opt/tools/ferramenta/ferramenta.py")
    FERRAMENTA_TYPE="docker_repo"
    return 0
  fi
  return 1
}
```

## Ferramentas Adicionais Sugeridas

Se você quiser adicionar outras ferramentas populares:

- **nuclei** - Já incluído no Dockerfile, pode adicionar ao menu
- **gobuster** - Fuzzer web em Go
- **wfuzz** - Web application fuzzer em Python
- **nikto** - Web server scanner
- **masscan** - Scanner de portas massivo
- **amass** - Enumeração de subdomínios avançada

## Notas

- Sempre teste a detecção e execução antes de commitar
- Mantenha consistência com o padrão de cores e mensagens
- Adicione documentação no README quando adicionar ferramentas principais
- Considere adicionar ao `run_all()` apenas se fizer sentido no fluxo de trabalho
