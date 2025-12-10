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

INSTALL_DIR="$HOME/rust-mumble"
SERVICE_USER="$USER"

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    echo -ne "   "
    while ps -p $pid > /dev/null 2>&1; do
        for i in $(seq 0 3); do
            echo -ne "\b${spinstr:i:1}"
            sleep $delay
        done
    done
    echo -ne "\b✔\n"
}

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

check_permissions() {
    if [ "$EUID" -ne 0 ]; then
        error "Este script precisa ser executado como root ou com sudo"
    fi
}

# Detectar versão do Ubuntu
detect_ubuntu() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" ]]; then
            success "Ubuntu $VERSION_ID detectado"
        else
            warning "Sistema detectado: $ID $VERSION_ID (não é Ubuntu, mas pode funcionar)"
        fi
    else
        warning "Não foi possível detectar o sistema operacional"
    fi
}

check_permissions
detect_ubuntu

step "Atualizando pacotes do sistema"
apt update &>/dev/null && apt upgrade -y &>/dev/null &
spinner $!
success "Sistema atualizado com sucesso"

step "Instalando dependências"
apt install -y build-essential llvm clang make pkg-config libssl-dev git curl ufw openssl &>/dev/null &
spinner $!
success "Dependências instaladas"

step "Verificando instalação do Rust"
if ! command -v rustc &>/dev/null; then
    warning "Rust não encontrado, instalando agora"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y &>/dev/null
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

step "Clonando repositório Rust-Mumble"
if [ ! -d "$INSTALL_DIR" ]; then
    git clone https://github.com/AvarianKnight/rust-mumble.git "$INSTALL_DIR" &>/dev/null &
    spinner $!
    success "Repositório Rust-Mumble clonado"
else
    warning "Rust-Mumble já existe em $INSTALL_DIR, atualizando..."
    cd "$INSTALL_DIR"
    git pull &>/dev/null || true
    success "Repositório atualizado"
fi

cd "$INSTALL_DIR"
step "Compilando Rust-Mumble (isso pode demorar alguns minutos)"
cargo clean &>/dev/null 2>&1 || true
cargo build --release &>/dev/null &
spinner $!
success "Rust-Mumble compilado com sucesso"

step "Verificando certificados"
if [ ! -f "$INSTALL_DIR/cert.pem" ] || [ ! -f "$INSTALL_DIR/key.pem" ]; then
    warning "Certificados não encontrados, gerando certificados auto-assinados"
    openssl req -newkey rsa:2048 -days 365 -nodes -x509 \
        -keyout "$INSTALL_DIR/key.pem" -out "$INSTALL_DIR/cert.pem" \
        -subj "/CN=Rust-Mumble" &>/dev/null &
    spinner $!
    success "Certificados gerados"
else
    success "Certificados já existem"
fi

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

step "Recarregando systemd e habilitando serviço"
systemctl daemon-reload
systemctl enable rust-mumble &>/dev/null
systemctl restart rust-mumble &
spinner $!
success "Serviço Rust-Mumble iniciado"

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

step "Configurando regras de firewall"
ufw allow 55500/tcp &>/dev/null
ufw allow 55500/udp &>/dev/null
ufw allow 8080/tcp &>/dev/null
ufw allow 22/tcp &>/dev/null
ufw --force enable &>/dev/null &
spinner $!
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
echo -e "  • Status:   ${BOLD}sudo systemctl status rust-mumble${RESET}"
echo -e "  • Logs:     ${BOLD}sudo journalctl -u rust-mumble -f${RESET}"
echo -e "  • Reiniciar:${BOLD}sudo systemctl restart rust-mumble${RESET}"
echo -e "  • Parar:    ${BOLD}sudo systemctl stop rust-mumble${RESET}"
echo ""

step "Status do serviço Rust-Mumble"
systemctl status rust-mumble --no-pager || true