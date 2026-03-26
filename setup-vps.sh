#!/bin/bash
###############################################################################
# SCRIPT DE INSTALAÇÃO AUTOMÁTICA - JELLYFIN + CADDY + RCLONE
#
# Uso: curl -sSL URL_DO_SCRIPT | bash
# Ou:  chmod +x setup-vps.sh && ./setup-vps.sh
#
# ANTES DE EXECUTAR:
# 1. Configure o DNS (registro A para jellyfin.tonfly.cloud)
# 2. Valide com: nslookup jellyfin.tonfly.cloud
###############################################################################

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   JELLYFIN + CADDY + RCLONE - INSTALAÇÃO AUTOMÁTICA           ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Execute como root: sudo ./setup-vps.sh${NC}"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
# 1. ATUALIZAR SISTEMA
# ═══════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}[1/7] Atualizando sistema...${NC}"
apt update && apt upgrade -y
apt install -y curl wget unzip fuse3

# ═══════════════════════════════════════════════════════════════
# 2. INSTALAR DOCKER
# ═══════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}[2/7] Instalando Docker...${NC}"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    echo -e "${GREEN}✓ Docker instalado${NC}"
else
    echo -e "${GREEN}✓ Docker já instalado${NC}"
fi
docker --version

# ═══════════════════════════════════════════════════════════════
# 3. INSTALAR RCLONE
# ═══════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}[3/7] Instalando Rclone...${NC}"
if ! command -v rclone &> /dev/null; then
    curl https://rclone.org/install.sh | bash
    echo -e "${GREEN}✓ Rclone instalado${NC}"
else
    echo -e "${GREEN}✓ Rclone já instalado${NC}"
fi
rclone --version

# ═══════════════════════════════════════════════════════════════
# 4. CRIAR ESTRUTURA DE PASTAS
# ═══════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}[4/7] Criando estrutura de pastas...${NC}"
mkdir -p /opt/jellyfin/{config,cache,media,caddy_data,caddy_config}
echo -e "${GREEN}✓ Pastas criadas em /opt/jellyfin/${NC}"
ls -la /opt/jellyfin/

# ═══════════════════════════════════════════════════════════════
# 5. CRIAR DOCKER-COMPOSE.YML
# ═══════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}[5/7] Criando docker-compose.yml...${NC}"
cat > /opt/jellyfin/docker-compose.yml << 'DOCKER_COMPOSE'
version: "3.9"

services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: unless-stopped
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/Sao_Paulo
    volumes:
      - ./config:/config
      - ./cache:/cache
      - /opt/jellyfin/media:/media:ro
    networks:
      - jellyfin_network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8096/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./caddy_data:/data
      - ./caddy_config:/config
    networks:
      - jellyfin_network
    depends_on:
      - jellyfin

networks:
  jellyfin_network:
    driver: bridge
    name: jellyfin_network
DOCKER_COMPOSE
echo -e "${GREEN}✓ docker-compose.yml criado${NC}"

# ═══════════════════════════════════════════════════════════════
# 6. CRIAR CADDYFILE
# ═══════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}[6/7] Criando Caddyfile...${NC}"

# Solicitar email para SSL
read -p "Digite seu email para certificado SSL: " EMAIL_SSL

cat > /opt/jellyfin/Caddyfile << CADDYFILE
{
    email ${EMAIL_SSL}
}

jellyfin.tonfly.cloud {
    reverse_proxy jellyfin:8096 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
        flush_interval -1
    }
    
    header {
        X-Frame-Options "SAMEORIGIN"
        X-Content-Type-Options "nosniff"
        -Server
    }
    
    encode gzip zstd
}
CADDYFILE
echo -e "${GREEN}✓ Caddyfile criado com email: ${EMAIL_SSL}${NC}"

# ═══════════════════════════════════════════════════════════════
# 7. CONFIGURAR FIREWALL
# ═══════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}[7/7] Configurando firewall (UFW)...${NC}"
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
echo "y" | ufw enable
echo -e "${GREEN}✓ Firewall configurado${NC}"
ufw status

# ═══════════════════════════════════════════════════════════════
# INSTRUÇÕES FINAIS
# ═══════════════════════════════════════════════════════════════
echo -e "\n${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   ✅ INSTALAÇÃO BASE CONCLUÍDA!                               ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"

echo -e "\n${YELLOW}PRÓXIMOS PASSOS:${NC}"
echo -e ""
echo -e "1. ${YELLOW}Configurar Rclone (Google Drive):${NC}"
echo -e "   rclone config"
echo -e ""
echo -e "2. ${YELLOW}Montar Google Drive:${NC}"
echo -e "   rclone mount gdrive: /opt/jellyfin/media \\"
echo -e "       --vfs-cache-mode full \\"
echo -e "       --vfs-cache-max-size 10G \\"
echo -e "       --buffer-size 100M \\"
echo -e "       --dir-cache-time 72h \\"
echo -e "       --poll-interval 15s \\"
echo -e "       --allow-other \\"
echo -e "       --daemon"
echo -e ""
echo -e "3. ${YELLOW}Verificar se /media tem arquivos:${NC}"
echo -e "   ls /opt/jellyfin/media/"
echo -e ""
echo -e "4. ${YELLOW}Subir containers:${NC}"
echo -e "   cd /opt/jellyfin && docker compose up -d"
echo -e ""
echo -e "5. ${YELLOW}Acessar:${NC}"
echo -e "   https://jellyfin.tonfly.cloud"
echo -e ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
