#!/bin/bash
###############################################################################
# 🚀 INSTALADOR COMPLETO - JELLYFIN + CADDY + RCLONE
#
# USO:
#   git clone https://github.com/tonfly/jellyfin-vps.git
#   cd jellyfin-vps
#   chmod +x install.sh
#   sudo ./install.sh
#
# Este script instala e configura TUDO automaticamente!
###############################################################################

set -e

# ═══════════════════════════════════════════════════════════════
# CORES E FUNÇÕES AUXILIARES
# ═══════════════════════════════════════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_banner() {
    echo -e "${BLUE}"
    echo "═══════════════════════════════════════════════════════════════"
    echo "   🎬 JELLYFIN + CADDY + RCLONE - INSTALADOR AUTOMÁTICO"
    echo "   📍 Domínio: jellyfin.tonfly.cloud"
    echo "═══════════════════════════════════════════════════════════════"
    echo -e "${NC}"
}

print_step() {
    echo -e "\n${YELLOW}[$1/$TOTAL_STEPS] $2${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# ═══════════════════════════════════════════════════════════════
# VERIFICAÇÕES INICIAIS
# ═══════════════════════════════════════════════════════════════
TOTAL_STEPS=9

print_banner

# Verificar root
if [ "$EUID" -ne 0 ]; then
    print_error "Execute como root: sudo ./install.sh"
    exit 1
fi

# Verificar se está no diretório correto
if [ ! -f "docker-compose.yml" ]; then
    print_error "Execute este script na pasta do projeto (onde está docker-compose.yml)"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
# COLETAR INFORMAÇÕES
# ═══════════════════════════════════════════════════════════════
echo -e "\n${BLUE}📝 CONFIGURAÇÃO INICIAL${NC}\n"

read -p "Digite seu email para certificado SSL: " SSL_EMAIL
if [ -z "$SSL_EMAIL" ]; then
    print_error "Email é obrigatório para o certificado SSL"
    exit 1
fi

echo ""
print_info "Verificando DNS de jellyfin.tonfly.cloud..."
DNS_CHECK=$(nslookup jellyfin.tonfly.cloud 2>/dev/null | grep -c "Address" || echo "0")

if [ "$DNS_CHECK" -lt 2 ]; then
    echo -e "${YELLOW}"
    echo "⚠️  ATENÇÃO: O DNS pode não estar configurado ainda!"
    echo ""
    echo "Configure no painel do seu domínio:"
    echo "  Tipo: A"
    echo "  Host: jellyfin"
    echo "  Valor: $(curl -s ifconfig.me 2>/dev/null || echo 'SEU_IP')"
    echo ""
    echo "O certificado SSL só será gerado após o DNS propagar."
    echo -e "${NC}"
    read -p "Continuar mesmo assim? (s/n): " CONTINUAR
    if [[ ! "$CONTINUAR" =~ ^[Ss]$ ]]; then
        echo "Configure o DNS e execute novamente."
        exit 0
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 1. ATUALIZAR SISTEMA
# ═══════════════════════════════════════════════════════════════
print_step 1 "Atualizando sistema..."

apt update && apt upgrade -y
apt install -y curl wget unzip fuse3 ufw

print_success "Sistema atualizado"

# ═══════════════════════════════════════════════════════════════
# 2. INSTALAR DOCKER
# ═══════════════════════════════════════════════════════════════
print_step 2 "Instalando Docker..."

if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    print_success "Docker instalado"
else
    print_success "Docker já instalado"
fi

docker --version

# ═══════════════════════════════════════════════════════════════
# 3. INSTALAR RCLONE
# ═══════════════════════════════════════════════════════════════
print_step 3 "Instalando Rclone..."

if ! command -v rclone &> /dev/null; then
    curl https://rclone.org/install.sh | bash
    print_success "Rclone instalado"
else
    print_success "Rclone já instalado"
fi

rclone --version | head -1

# ═══════════════════════════════════════════════════════════════
# 4. CRIAR ESTRUTURA DE PASTAS
# ═══════════════════════════════════════════════════════════════
print_step 4 "Criando estrutura de pastas..."

INSTALL_DIR="/opt/jellyfin"
mkdir -p ${INSTALL_DIR}/{config,cache,media,caddy_data,caddy_config}

print_success "Pastas criadas em ${INSTALL_DIR}"

# ═══════════════════════════════════════════════════════════════
# 5. COPIAR ARQUIVOS DE CONFIGURAÇÃO
# ═══════════════════════════════════════════════════════════════
print_step 5 "Copiando arquivos de configuração..."

# Copiar docker-compose.yml
cp docker-compose.yml ${INSTALL_DIR}/

# Copiar e configurar Caddyfile (substituir email)
sed "s/EMAIL_SSL/${SSL_EMAIL}/g" Caddyfile > ${INSTALL_DIR}/Caddyfile

# Copiar scripts auxiliares
cp comandos.sh ${INSTALL_DIR}/ 2>/dev/null || true
chmod +x ${INSTALL_DIR}/comandos.sh 2>/dev/null || true

print_success "Arquivos copiados para ${INSTALL_DIR}"

# ═══════════════════════════════════════════════════════════════
# 6. CONFIGURAR RCLONE (GOOGLE DRIVE)
# ═══════════════════════════════════════════════════════════════
print_step 6 "Configurando Rclone (Google Drive)..."

if [ -f ~/.config/rclone/rclone.conf ] && grep -q "gdrive" ~/.config/rclone/rclone.conf 2>/dev/null; then
    print_success "Rclone já configurado com 'gdrive'"
else
    echo -e "${YELLOW}"
    echo "═══════════════════════════════════════════════════════════════"
    echo "  CONFIGURAÇÃO DO GOOGLE DRIVE"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Siga os passos:"
    echo "  1. Digite: n (new remote)"
    echo "  2. Name: gdrive"
    echo "  3. Storage: drive (ou número do Google Drive)"
    echo "  4. client_id: [ENTER]"
    echo "  5. client_secret: [ENTER]"
    echo "  6. scope: 1"
    echo "  7. root_folder_id: [ENTER]"
    echo "  8. service_account_file: [ENTER]"
    echo "  9. Edit advanced config: n"
    echo "  10. Use auto config: n"
    echo "  11. Copie o link, abra no navegador, autorize, cole o código"
    echo "  12. Configure as team drive: n"
    echo "  13. y (confirmar)"
    echo "  14. q (sair)"
    echo ""
    echo -e "${NC}"
    
    read -p "Pressione ENTER para iniciar a configuração do Rclone..."
    rclone config
fi

# Verificar se foi configurado
if ! rclone listremotes | grep -q "gdrive"; then
    print_error "Remote 'gdrive' não encontrado. Execute 'rclone config' manualmente."
else
    print_success "Rclone configurado"
fi

# ═══════════════════════════════════════════════════════════════
# 7. CRIAR SERVIÇO SYSTEMD PARA RCLONE
# ═══════════════════════════════════════════════════════════════
print_step 7 "Criando serviço Rclone..."

cat > /etc/systemd/system/rclone-gdrive.service << 'EOF'
[Unit]
Description=Rclone Mount Google Drive para Jellyfin
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/rclone mount gdrive: /opt/jellyfin/media \
    --vfs-cache-mode full \
    --vfs-cache-max-size 10G \
    --vfs-cache-max-age 72h \
    --buffer-size 100M \
    --dir-cache-time 72h \
    --poll-interval 15s \
    --allow-other \
    --log-level INFO \
    --log-file /var/log/rclone.log \
    --config /root/.config/rclone/rclone.conf
ExecStop=/bin/fusermount -u /opt/jellyfin/media
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Habilitar allow_other no FUSE
if ! grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
    echo "user_allow_other" >> /etc/fuse.conf
fi

systemctl daemon-reload
systemctl enable rclone-gdrive
systemctl start rclone-gdrive

sleep 3

if systemctl is-active --quiet rclone-gdrive; then
    print_success "Serviço Rclone ativo"
else
    print_error "Serviço Rclone falhou. Verifique: journalctl -u rclone-gdrive"
fi

# ═══════════════════════════════════════════════════════════════
# 8. CONFIGURAR FIREWALL
# ═══════════════════════════════════════════════════════════════
print_step 8 "Configurando firewall..."

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp   # SSH
ufw allow 80/tcp   # HTTP
ufw allow 443/tcp  # HTTPS
echo "y" | ufw enable

print_success "Firewall configurado (SSH, HTTP, HTTPS)"

# ═══════════════════════════════════════════════════════════════
# 9. SUBIR DOCKER COMPOSE
# ═══════════════════════════════════════════════════════════════
print_step 9 "Iniciando containers Docker..."

cd ${INSTALL_DIR}
docker compose pull
docker compose up -d

sleep 5

if docker compose ps | grep -q "running"; then
    print_success "Containers rodando"
else
    print_error "Problemas com containers. Verifique: docker compose logs"
fi

# ═══════════════════════════════════════════════════════════════
# RESUMO FINAL
# ═══════════════════════════════════════════════════════════════
echo -e "\n${GREEN}"
echo "═══════════════════════════════════════════════════════════════"
echo "   ✅ INSTALAÇÃO CONCLUÍDA!"
echo "═══════════════════════════════════════════════════════════════"
echo -e "${NC}"

echo -e "${BLUE}📊 STATUS:${NC}"
echo ""
docker compose ps
echo ""

echo -e "${BLUE}📁 Arquivos em /media:${NC}"
ls ${INSTALL_DIR}/media/ 2>/dev/null | head -5 || echo "  (vazio ou aguardando montagem)"
echo ""

echo -e "${BLUE}🌐 ACESSO:${NC}"
echo "  https://jellyfin.tonfly.cloud"
echo ""

echo -e "${BLUE}📝 PRÓXIMOS PASSOS:${NC}"
echo "  1. Acesse https://jellyfin.tonfly.cloud"
echo "  2. Configure usuário administrador (use senha FORTE!)"
echo "  3. Adicione biblioteca: /media"
echo ""

echo -e "${BLUE}🔧 COMANDOS ÚTEIS:${NC}"
echo "  cd /opt/jellyfin"
echo "  docker compose logs -f       # Ver logs"
echo "  docker compose restart       # Reiniciar"
echo "  systemctl status rclone-gdrive  # Status do mount"
echo ""

echo -e "${YELLOW}⚠️  Se o certificado SSL não funcionar, aguarde o DNS propagar e reinicie:${NC}"
echo "  docker compose restart caddy"
echo ""
