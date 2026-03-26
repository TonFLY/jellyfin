#!/bin/bash
###############################################################################
# CRIAR SERVIÇO SYSTEMD PARA RCLONE
#
# Uso: chmod +x rclone-service.sh && sudo ./rclone-service.sh
#
# Este script cria um serviço systemd que monta automaticamente
# o Google Drive na inicialização do sistema.
###############################################################################

set -e

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Verificar root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Execute como root: sudo ./rclone-service.sh"
    exit 1
fi

echo -e "${YELLOW}Criando serviço systemd para Rclone...${NC}"

# Criar arquivo de serviço
cat > /etc/systemd/system/rclone-gdrive.service << 'EOF'
[Unit]
Description=Rclone Mount Google Drive para Jellyfin
Documentation=https://rclone.org/docs/
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
# Usuário que executa (ajuste se necessário)
User=root

# Comando de montagem otimizado para streaming
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

# Comando para desmontar
ExecStop=/bin/fusermount -u /opt/jellyfin/media

# Reiniciar em caso de falha
Restart=on-failure
RestartSec=10

# Timeout para montagem
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
EOF

# Recarregar systemd
systemctl daemon-reload

# Habilitar serviço para iniciar no boot
systemctl enable rclone-gdrive

echo -e "${GREEN}✓ Serviço criado: rclone-gdrive${NC}"
echo -e ""
echo -e "${YELLOW}Comandos úteis:${NC}"
echo -e "  Iniciar:    sudo systemctl start rclone-gdrive"
echo -e "  Parar:      sudo systemctl stop rclone-gdrive"
echo -e "  Status:     sudo systemctl status rclone-gdrive"
echo -e "  Logs:       sudo journalctl -u rclone-gdrive -f"
echo -e "  Logs file:  tail -f /var/log/rclone.log"
echo -e ""
echo -e "${YELLOW}Iniciar agora? (s/n)${NC}"
read -r resposta

if [[ "$resposta" =~ ^[Ss]$ ]]; then
    systemctl start rclone-gdrive
    sleep 3
    systemctl status rclone-gdrive
fi
