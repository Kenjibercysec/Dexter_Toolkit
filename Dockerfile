# Dexter Toolkit - Docker Image Unificada
# Base image com suporte para múltiplas linguagens
FROM ubuntu:22.04

# Evitar prompts interativos durante instalação
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Variáveis de ambiente
ENV GOPATH=/root/go
ENV PATH=$GOPATH/bin:/usr/local/go/bin:$PATH
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo
ENV PATH=$CARGO_HOME/bin:$PATH

# Instalar dependências base
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    python3 \
    python3-pip \
    python3-venv \
    nmap \
    jq \
    build-essential \
    libssl-dev \
    libffi-dev \
    pkg-config \
    ca-certificates \
    ruby-full \
    ruby-dev \
    libkrb5-dev \
    krb5-user \
    libreadline-dev \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Instalar Go (versão mais recente)
RUN wget -q https://go.dev/dl/go1.21.5.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz && \
    rm go1.21.5.linux-amd64.tar.gz

# Instalar Rust e Cargo
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable && \
    chmod -R a+w $RUSTUP_HOME $CARGO_HOME

# Criar diretórios de trabalho
WORKDIR /opt/dexter

# Clonar e instalar ferramentas Go
RUN mkdir -p /opt/tools && \
    cd /opt/tools && \
    # httpx
    go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest && \
    # ffuf
    go install -v github.com/ffuf/ffuf@latest && \
    # subfinder
    go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest && \
    # nuclei (ferramenta útil adicional)
    go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest || true

# Instalar RustScan
RUN cd /opt/tools && \
    (git clone --depth 1 https://github.com/RustScan/RustScan.git rustscan-src && \
     cd rustscan-src && \
     cargo build --release && \
     cp target/release/rustscan /usr/local/bin/rustscan && \
     chmod +x /usr/local/bin/rustscan && \
     cd /opt/tools && \
     rm -rf rustscan-src) || \
    (wget -q https://github.com/RustScan/RustScan/releases/latest/download/rustscan_2.1.1_amd64.deb -O /tmp/rustscan.deb 2>/dev/null && \
     dpkg -i /tmp/rustscan.deb 2>/dev/null || apt-get install -yf 2>/dev/null || true) && \
    rm -f /tmp/rustscan.deb 2>/dev/null || true

# Clonar repositórios Python
RUN cd /opt/tools && \
    # dirsearch
    git clone --depth 1 https://github.com/maurosoria/dirsearch.git dirsearch && \
    cd dirsearch && \
    pip3 install -q -r requirements.txt && \
    cd /opt/tools && \
    # XSStrike
    git clone --depth 1 https://github.com/s0md3v/XSStrike.git XSStrike && \
    cd XSStrike && \
    pip3 install -q -r requirements.txt && \
    cd /opt/tools && \
    # sqlmap
    git clone --depth 1 https://github.com/sqlmapproject/sqlmap.git sqlmap && \
    cd /opt/tools && \
    # Impacket
    git clone --depth 1 https://github.com/fortra/impacket.git impacket && \
    cd impacket && \
    pip3 install -q . && \
    cd /opt/tools

# Clonar SecLists
RUN cd /opt/tools && \
    git clone --depth 1 https://github.com/danielmiessler/SecLists.git seclists || true

# Copiar arquivos do projeto
COPY dexter.sh /opt/dexter/dexter.sh
COPY scan.lib /opt/dexter/scan.lib 2>/dev/null || true
RUN chmod +x /opt/dexter/dexter.sh

# Instalar ferramentas Python via pip
RUN pip3 install -q bloodhound-ce evil-winrm-py[kerberos] || true

# Instalar Evil-WinRM Ruby
RUN gem install evil-winrm || true

# Criar links simbólicos para facilitar acesso
RUN ln -sf /opt/tools/dirsearch/dirsearch.py /usr/local/bin/dirsearch && \
    ln -sf /opt/tools/XSStrike/xsstrike.py /usr/local/bin/xsstrike && \
    ln -sf /opt/tools/sqlmap/sqlmap.py /usr/local/bin/sqlmap

# Criar scripts wrapper para Impacket (principais ferramentas)
RUN echo '#!/bin/bash\npython3 /opt/tools/impacket/examples/secretsdump.py "$@"' > /usr/local/bin/secretsdump && \
    echo '#!/bin/bash\npython3 /opt/tools/impacket/examples/psexec.py "$@"' > /usr/local/bin/psexec && \
    echo '#!/bin/bash\npython3 /opt/tools/impacket/examples/smbexec.py "$@"' > /usr/local/bin/smbexec && \
    echo '#!/bin/bash\npython3 /opt/tools/impacket/examples/wmiexec.py "$@"' > /usr/local/bin/wmiexec && \
    echo '#!/bin/bash\npython3 /opt/tools/impacket/examples/GetNPUsers.py "$@"' > /usr/local/bin/GetNPUsers && \
    chmod +x /usr/local/bin/secretsdump /usr/local/bin/psexec /usr/local/bin/smbexec /usr/local/bin/wmiexec /usr/local/bin/GetNPUsers

# Configurar Python venv para o projeto
RUN python3 -m venv /opt/dexter/.venv && \
    /opt/dexter/.venv/bin/pip install --upgrade pip && \
    /opt/dexter/.venv/bin/pip install -q bloodhound-ce evil-winrm-py[kerberos] || true

# Criar diretório para wordlists personalizadas
RUN mkdir -p /opt/dexter/wordlists

# Definir diretório de trabalho
WORKDIR /opt/dexter

# Expor volumes para persistência
VOLUME ["/opt/dexter/wordlists", "/opt/dexter/results"]

# Script de entrada
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["./dexter.sh"]
