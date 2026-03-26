#!/bin/bash
###############################################################################
# COMANDOS RÁPIDOS - JELLYFIN + CADDY + RCLONE
#
# Uso: ./comandos.sh [comando]
#
# Comandos disponíveis:
#   start     - Inicia todos os serviços
#   stop      - Para todos os serviços
#   restart   - Reinicia todos os serviços
#   status    - Mostra status de todos os serviços
#   logs      - Mostra logs em tempo real
#   update    - Atualiza imagens Docker
#   backup    - Faz backup das configurações
###############################################################################

cd /opt/jellyfin || exit 1

case "$1" in
    start)
        echo "🚀 Iniciando serviços..."
        systemctl start rclone-gdrive
        sleep 3
        docker compose up -d
        echo "✅ Serviços iniciados"
        docker compose ps
        ;;
    
    stop)
        echo "🛑 Parando serviços..."
        docker compose down
        systemctl stop rclone-gdrive
        fusermount -u /opt/jellyfin/media 2>/dev/null || true
        echo "✅ Serviços parados"
        ;;
    
    restart)
        echo "🔄 Reiniciando serviços..."
        docker compose restart
        systemctl restart rclone-gdrive
        echo "✅ Serviços reiniciados"
        ;;
    
    status)
        echo "═══════════════════════════════════════════"
        echo "📊 STATUS DOS SERVIÇOS"
        echo "═══════════════════════════════════════════"
        echo ""
        echo "🐳 Docker Containers:"
        docker compose ps
        echo ""
        echo "📁 Rclone Mount:"
        systemctl status rclone-gdrive --no-pager | head -10
        echo ""
        echo "💾 Espaço em disco:"
        df -h /opt/jellyfin/
        echo ""
        echo "📂 Arquivos em /media:"
        ls /opt/jellyfin/media/ 2>/dev/null | head -10 || echo "⚠️  /media não montado ou vazio"
        ;;
    
    logs)
        echo "📋 Logs em tempo real (Ctrl+C para sair)..."
        docker compose logs -f
        ;;
    
    logs-caddy)
        docker logs caddy -f
        ;;
    
    logs-jellyfin)
        docker logs jellyfin -f
        ;;
    
    logs-rclone)
        journalctl -u rclone-gdrive -f
        ;;
    
    update)
        echo "🔄 Atualizando imagens Docker..."
        docker compose pull
        docker compose up -d
        docker image prune -f
        echo "✅ Imagens atualizadas"
        ;;
    
    backup)
        DATA=$(date +%Y%m%d_%H%M%S)
        ARQUIVO="jellyfin-backup-${DATA}.tar.gz"
        echo "💾 Criando backup: ${ARQUIVO}"
        tar -czvf "/root/${ARQUIVO}" \
            /opt/jellyfin/config \
            /opt/jellyfin/Caddyfile \
            /opt/jellyfin/docker-compose.yml \
            /root/.config/rclone/rclone.conf
        echo "✅ Backup salvo em: /root/${ARQUIVO}"
        ls -lh "/root/${ARQUIVO}"
        ;;
    
    test-dns)
        echo "🌐 Testando DNS..."
        nslookup jellyfin.tonfly.cloud
        ;;
    
    test-ssl)
        echo "🔒 Testando SSL..."
        curl -I https://jellyfin.tonfly.cloud 2>/dev/null | head -5
        ;;
    
    *)
        echo "═══════════════════════════════════════════"
        echo "🎬 COMANDOS RÁPIDOS - JELLYFIN"
        echo "═══════════════════════════════════════════"
        echo ""
        echo "Uso: $0 [comando]"
        echo ""
        echo "Comandos disponíveis:"
        echo "  start         Inicia todos os serviços"
        echo "  stop          Para todos os serviços"
        echo "  restart       Reinicia todos os serviços"
        echo "  status        Mostra status de todos"
        echo "  logs          Logs Docker (tempo real)"
        echo "  logs-caddy    Logs só do Caddy"
        echo "  logs-jellyfin Logs só do Jellyfin"
        echo "  logs-rclone   Logs do Rclone mount"
        echo "  update        Atualiza imagens Docker"
        echo "  backup        Backup das configurações"
        echo "  test-dns      Testa resolução DNS"
        echo "  test-ssl      Testa certificado SSL"
        echo ""
        ;;
esac
