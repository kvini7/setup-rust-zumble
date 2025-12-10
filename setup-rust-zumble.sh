#!/bin/bash

set -e  # Exit on error
set -o pipefail
set -u

# ANSI color codes
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

step() {
    echo -e "${CYAN}${BOLD}➜ $1...${RESET}"
}

success() {
    echo -e "${GREEN}✔ $1${RESET}"
}

warning() {
    echo -e "${YELLOW}⚠ $1${RESET}"
}

error() {
    echo -e "${RED}✖ $1${RESET}"
    exit 1
}

# Diretório de instalação
INSTALL_DIR="/root/rust-mumble"

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then
    error "Este script precisa ser executado como root ou com sudo"
fi

# Detectar versão do Ubuntu/Debian
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" == "ubuntu" ]] || [[ "$ID" == "debian" ]]; then
        success "$ID $VERSION_ID detectado"
    else
        warning "Sistema detectado: $ID $VERSION_ID (não é Ubuntu/Debian, mas pode funcionar)"
    fi
else
    warning "Não foi possível detectar o sistema operacional"
fi

# Update system packages
step "Atualizando pacotes do sistema"
apt update && apt upgrade -y
success "Sistema atualizado com sucesso"

# Install dependencies
step "Instalando dependências"
apt install -y build-essential llvm clang make pkg-config libssl-dev git curl ufw openssl
success "Dependências instaladas"

# Check if Rust is installed
step "Verificando instalação do Rust"
if ! command -v rustc &>/dev/null; then
    warning "Rust não encontrado, instalando agora"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    # Carregar ambiente do Rust
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    elif [ -f "/root/.cargo/env" ]; then
        source "/root/.cargo/env"
    fi
    export PATH="$HOME/.cargo/bin:$PATH"
    success "Rust instalado com sucesso"
else
    success "Rust já está instalado ($(rustc --version))"
fi

# Clone Rust-Mumble
step "Clonando repositório Rust-Mumble"
if [ ! -d "$INSTALL_DIR" ]; then
    git clone https://github.com/AvarianKnight/rust-mumble.git "$INSTALL_DIR"
    success "Repositório Rust-Mumble clonado"
else
    warning "Rust-Mumble já existe em $INSTALL_DIR, atualizando..."
    cd "$INSTALL_DIR"
    git pull || true
    success "Repositório atualizado"
fi

# Build Rust-Mumble
cd "$INSTALL_DIR"
step "Compilando Rust-Mumble (isso pode demorar alguns minutos)"
cargo clean 2>/dev/null || true
cargo build --release
success "Rust-Mumble compilado com sucesso"

# Check for certificates
step "Verificando certificados"
if [ ! -f "$INSTALL_DIR/cert.pem" ] || [ ! -f "$INSTALL_DIR/key.pem" ]; then
    warning "Certificados não encontrados, gerando certificados auto-assinados"
    openssl req -newkey rsa:2048 -days 365 -nodes -x509 \
        -keyout "$INSTALL_DIR/key.pem" -out "$INSTALL_DIR/cert.pem" \
        -subj "/CN=Rust-Mumble"
    success "Certificados gerados"
else
    success "Certificados já existem"
fi

# Create systemd service
step "Criando serviço systemd"
cat <<EOF > /etc/systemd/system/rust-mumble.service
[Unit]
Description=Rust-Mumble Voice Server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/target/release/rust-mumble --cert $INSTALL_DIR/cert.pem --key $INSTALL_DIR/key.pem --listen 0.0.0.0:55500 --http-listen 0.0.0.0:8080 --http-password dummy
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
success "Serviço systemd criado"

# Reload systemd
step "Recarregando systemd e habilitando serviço"
systemctl daemon-reload
systemctl enable rust-mumble
systemctl restart rust-mumble
success "Serviço Rust-Mumble iniciado"

# Configure file descriptor limits
step "Configurando limites de file descriptors"
if ! grep -q "soft nofile 1048576" /etc/security/limits.conf 2>/dev/null; then
    cat <<EOF >> /etc/security/limits.conf
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
fi
success "Limites de file descriptors configurados"

step "Configurando PAM para aplicar limites"
if ! grep -q "pam_limits.so" /etc/pam.d/common-session 2>/dev/null; then
    echo "session required pam_limits.so" >> /etc/pam.d/common-session
fi
if ! grep -q "pam_limits.so" /etc/pam.d/common-session-noninteractive 2>/dev/null; then
    echo "session required pam_limits.so" >> /etc/pam.d/common-session-noninteractive
fi
success "Limites PAM aplicados"

step "Configurando limites do systemd"
sed -i 's/^#DefaultLimitNOFILE=.*/DefaultLimitNOFILE=1048576/' /etc/systemd/system.conf 2>/dev/null || true
sed -i 's/^#DefaultLimitNOFILE=.*/DefaultLimitNOFILE=1048576/' /etc/systemd/user.conf 2>/dev/null || true
success "Limites do systemd configurados"

# Configure firewall
step "Configurando regras de firewall"
ufw allow 55500/tcp
ufw allow 55500/udp
ufw allow 8080/tcp
ufw allow 22/tcp  # Manter SSH aberto
success "Regras de firewall aplicadas"

echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  ✔ Instalação concluída com sucesso!${RESET}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "${CYAN}Informações do servidor:${RESET}"
echo -e "  • Porta Voice: ${BOLD}55500${RESET} (TCP/UDP)"
echo -e "  • Porta HTTP:  ${BOLD}8080${RESET} (TCP)"
echo -e "  • Diretório:   ${BOLD}$INSTALL_DIR${RESET}"
echo ""
echo -e "${CYAN}Comandos úteis:${RESET}"
echo -e "  • Status:    ${BOLD}sudo systemctl status rust-mumble${RESET}"
echo -e "  • Logs:      ${BOLD}sudo journalctl -u rust-mumble -f${RESET}"
echo -e "  • Reiniciar: ${BOLD}sudo systemctl restart rust-mumble${RESET}"
echo -e "  • Parar:     ${BOLD}sudo systemctl stop rust-mumble${RESET}"
echo ""

# Display Rust-Mumble Service Status
step "Status do serviço Rust-Mumble"
systemctl status rust-mumble --no-pager || true