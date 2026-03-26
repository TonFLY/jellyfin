#!/bin/bash
###############################################################################
# CONFIGURAR JELLYFIN COM NGINX EXISTENTE
# Execute: sudo bash configure-nginx.sh
###############################################################################

set -e

echo "Parando Caddy do docker-compose..."
cd /opt/jellyfin
docker compose down

echo ""
echo "Editando docker-compose para remover Caddy..."
echo "Deixando apenas o Jellyfin e expondo porta 8096..."

# Backup do original
cp docker-compose.yml docker-compose.yml.backup

# Criar novo docker-compose sem Caddy
cat > docker-compose.yml << 'EOF'
version: "3.9"

services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: unless-stopped
    ports:
      - "127.0.0.1:8096:8096"
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/Sao_Paulo
    volumes:
      - ./config:/config
      - ./cache:/cache
      - /opt/jellyfin/media:/media:ro
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8096/health"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

echo "Subindo Jellyfin..."
docker compose up -d

sleep 5

echo ""
echo "Criando configuração do Nginx..."

# Criar arquivo de config do Nginx
sudo tee /etc/nginx/sites-available/jellyfin > /dev/null << 'NGINX'
server {
    listen 80;
    listen [::]:80;
    server_name jellyfin.tonfly.cloud;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name jellyfin.tonfly.cloud;

    # Certificados SSL (adapt conforme sua config)
    ssl_certificate /etc/letsencrypt/live/tonfly.cloud/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/tonfly.cloud/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8096;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX

echo "Ativando site..."
sudo ln -sf /etc/nginx/sites-available/jellyfin /etc/nginx/sites-enabled/

echo "Testando configuração do Nginx..."
sudo nginx -t

echo "Recarregando Nginx..."
sudo systemctl reload nginx

echo ""
echo "✅ Pronto! Acesse: https://jellyfin.tonfly.cloud"
