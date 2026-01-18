#!/usr/bin/env bash
# Script para construir e gerenciar o container Docker do Dexter Toolkit

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="dexter-toolkit"
CONTAINER_NAME="dexter-toolkit"

info() { printf "\033[1;36m[i]\033[0m %s\n" "$*"; }
ok() { printf "\033[1;32m[+]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[-]\033[0m %s\n" "$*"; }

usage() {
    cat <<EOF
Uso: $0 [comando]

Comandos:
  build       - Construir a imagem Docker
  run         - Executar o container (interativo)
  start       - Iniciar container em background
  stop        - Parar o container
  restart     - Reiniciar o container
  shell       - Abrir shell no container
  logs        - Ver logs do container
  clean       - Remover container e imagem
  update      - Reconstruir imagem (pull latest)
  help        - Mostrar esta ajuda

Exemplos:
  $0 build && $0 run
  $0 shell
EOF
}

build_image() {
    info "Construindo imagem Docker..."
    cd "$SCRIPT_DIR"
    docker build -t "$IMAGE_NAME:latest" .
    ok "Imagem construída com sucesso!"
}

run_container() {
    info "Executando container (modo interativo)..."
    docker run -it --rm \
        --name "$CONTAINER_NAME" \
        --network host \
        --cap-add=NET_RAW \
        --cap-add=NET_ADMIN \
        -v "$SCRIPT_DIR/wordlists:/opt/dexter/wordlists" \
        -v "$SCRIPT_DIR/seclists:/opt/tools/seclists" \
        -v "$SCRIPT_DIR/results:/opt/dexter/results" \
        "$IMAGE_NAME:latest"
}

start_container() {
    info "Iniciando container em background..."
    docker-compose up -d
    ok "Container iniciado!"
}

stop_container() {
    info "Parando container..."
    docker-compose down || docker stop "$CONTAINER_NAME" 2>/dev/null || true
    ok "Container parado!"
}

restart_container() {
    stop_container
    sleep 2
    start_container
}

shell_container() {
    info "Abrindo shell no container..."
    if docker ps | grep -q "$CONTAINER_NAME"; then
        docker exec -it "$CONTAINER_NAME" /bin/bash
    else
        docker run -it --rm \
            --name "${CONTAINER_NAME}-shell" \
            --network host \
            --cap-add=NET_RAW \
            --cap-add=NET_ADMIN \
            -v "$SCRIPT_DIR/wordlists:/opt/dexter/wordlists" \
            -v "$SCRIPT_DIR/seclists:/opt/tools/seclists" \
            -v "$SCRIPT_DIR/results:/opt/dexter/results" \
            "$IMAGE_NAME:latest" /bin/bash
    fi
}

show_logs() {
    info "Mostrando logs do container..."
    docker-compose logs -f || docker logs -f "$CONTAINER_NAME" 2>/dev/null || warn "Container não está rodando"
}

clean_all() {
    warn "Isso irá remover o container e a imagem. Continuar? (s/N)"
    read -r response
    if [[ "$response" =~ ^[Ss]$ ]]; then
        docker-compose down -v 2>/dev/null || true
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
        docker rmi "$IMAGE_NAME:latest" 2>/dev/null || true
        ok "Limpeza concluída!"
    else
        info "Operação cancelada."
    fi
}

update_image() {
    info "Atualizando imagem (reconstruindo)..."
    build_image
    ok "Imagem atualizada!"
}

# Criar diretórios necessários
mkdir -p "$SCRIPT_DIR/wordlists"
mkdir -p "$SCRIPT_DIR/results"

# Processar comando
case "${1:-help}" in
    build)
        build_image
        ;;
    run)
        run_container
        ;;
    start)
        start_container
        ;;
    stop)
        stop_container
        ;;
    restart)
        restart_container
        ;;
    shell)
        shell_container
        ;;
    logs)
        show_logs
        ;;
    clean)
        clean_all
        ;;
    update)
        update_image
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        err "Comando desconhecido: $1"
        usage
        exit 1
        ;;
esac
