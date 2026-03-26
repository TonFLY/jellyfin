# 🎬 Jellyfin no VPS com Docker + Google Drive

## Guia Completo de Instalação e Configuração

**Domínio:** `jellyfin.tonfly.cloud`  
**Arquitetura:** Jellyfin + Caddy (HTTPS) + Rclone (Google Drive)

---

## 📋 Índice

1. [Visão Geral da Arquitetura](#1-visão-geral-da-arquitetura)
2. [Configuração do DNS](#2-configuração-do-dns)
3. [Preparação do VPS](#3-preparação-do-vps)
4. [Instalação do Docker](#4-instalação-do-docker)
5. [Instalação e Configuração do Rclone](#5-instalação-e-configuração-do-rclone)
6. [Estrutura de Pastas](#6-estrutura-de-pastas)
7. [Arquivos de Configuração](#7-arquivos-de-configuração)
8. [Subindo o Ambiente](#8-subindo-o-ambiente)
9. [Configuração do Firewall](#9-configuração-do-firewall)
10. [Segurança](#10-segurança)
11. [Troubleshooting](#11-troubleshooting)
12. [Comandos Úteis](#12-comandos-úteis)

---

## 1. Visão Geral da Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                         INTERNET                                │
│                            │                                    │
│                     jellyfin.tonfly.cloud                       │
│                            │                                    │
│                      ┌─────▼─────┐                              │
│                      │  Caddy    │ ← HTTPS (Let's Encrypt)      │
│                      │  :443     │                              │
│                      └─────┬─────┘                              │
│                            │ (rede interna Docker)              │
│                      ┌─────▼─────┐                              │
│                      │ Jellyfin  │ ← Servidor de Mídia          │
│                      │  :8096    │   (porta NÃO exposta)        │
│                      └─────┬─────┘                              │
│                            │                                    │
│                      ┌─────▼─────┐                              │
│                      │  /media   │ ← Rclone mount               │
│                      │           │   (Google Drive)             │
│                      └───────────┘                              │
└─────────────────────────────────────────────────────────────────┘
```

### Por que essa arquitetura?

| Componente | Função |
|------------|--------|
| **Caddy** | Reverse proxy com HTTPS automático. Única porta exposta (443) |
| **Jellyfin** | Servidor de mídia. Roda internamente sem expor porta |
| **Rclone** | Monta Google Drive como pasta local em `/media` |

---

## 2. Configuração do DNS

### ⚠️ FAÇA ISSO PRIMEIRO!

O HTTPS só funcionará após o DNS estar propagado corretamente.

### 2.1 Criar Registro DNS

Acesse o painel do seu provedor de domínio (onde você comprou `tonfly.cloud`) e crie:

| Campo | Valor |
|-------|-------|
| **Tipo** | `A` |
| **Host/Name** | `jellyfin` |
| **Valor/Target** | `170.80.38.25` |
| **TTL** | Padrão (ou 3600) |

> **Nota:** O registro `A` aponta um subdomínio para um IP.
> `jellyfin` + `tonfly.cloud` = `jellyfin.tonfly.cloud`

### 2.2 Validar DNS

Aguarde a propagação (pode levar de 5 minutos a 48 horas) e teste:

```bash
# Verificar se o DNS resolve para o IP correto
nslookup jellyfin.tonfly.cloud

# Deve retornar:
# Name:    jellyfin.tonfly.cloud
# Address: 170.80.38.25

# Testar conectividade
ping jellyfin.tonfly.cloud

# Verificar propagação global (opcional)
# Acesse: https://dnschecker.org/#A/jellyfin.tonfly.cloud
```

### 2.3 Tempo de Propagação

- **Mínimo:** 5-15 minutos
- **Típico:** 1-2 horas  
- **Máximo:** 24-48 horas

> **IMPORTANTE:** NÃO inicie o Caddy antes do DNS estar propagado!
> O Let's Encrypt precisa validar o domínio para gerar o certificado.

---

## 3. Preparação do VPS

### 3.1 Conectar ao VPS

```bash
ssh root@170.80.38.25
```

### 3.2 Atualizar Sistema

```bash
apt update && apt upgrade -y
```

### 3.3 Instalar Dependências

```bash
apt install -y curl wget unzip fuse3
```

---

## 4. Instalação do Docker

### 4.1 Instalar Docker

```bash
# Instalar Docker via script oficial
curl -fsSL https://get.docker.com | sh

# Verificar instalação
docker --version
```

### 4.2 Instalar Docker Compose

```bash
# Docker Compose já vem com Docker moderno
# Verificar:
docker compose version

# Se não funcionar, instalar manualmente:
apt install docker-compose-plugin -y
```

### 4.3 Iniciar Docker

```bash
# Habilitar Docker no boot
systemctl enable docker

# Iniciar Docker
systemctl start docker

# Verificar status
systemctl status docker
```

---

## 5. Instalação e Configuração do Rclone

### 5.1 Instalar Rclone

```bash
# Instalar via script oficial
curl https://rclone.org/install.sh | bash

# Verificar instalação
rclone --version
```

### 5.2 Configurar Google Drive

```bash
# Iniciar configuração interativa
rclone config
```

**Siga os passos:**

```
n) New remote
name> gdrive
Storage> drive                    # ou número do Google Drive
client_id> [ENTER para padrão]
client_secret> [ENTER para padrão]
scope> 1                          # Full access
root_folder_id> [ENTER]
service_account_file> [ENTER]
Edit advanced config> n
Use auto config> n                # IMPORTANTE para VPS sem GUI

# Você receberá um link para autorizar no navegador
# Copie o link, abra no seu PC, autorize, copie o código
# Cole o código no terminal

Configure as team drive> n
y) Yes this is OK
q) Quit config
```

### 5.3 Verificar Configuração

```bash
# Arquivo de configuração fica em:
cat ~/.config/rclone/rclone.conf

# Testar listando arquivos do Drive
rclone ls gdrive: --max-depth 1
```

### 5.4 Montar Google Drive

```bash
# Criar diretório de mídia
mkdir -p /opt/jellyfin/media

# Montar Google Drive (comando completo otimizado para streaming)
rclone mount gdrive: /opt/jellyfin/media \
    --vfs-cache-mode full \
    --vfs-cache-max-size 10G \
    --buffer-size 100M \
    --dir-cache-time 72h \
    --poll-interval 15s \
    --allow-other \
    --daemon
```

**Explicação dos parâmetros:**

| Parâmetro | Descrição |
|-----------|-----------|
| `--vfs-cache-mode full` | Cache completo para melhor streaming |
| `--vfs-cache-max-size 10G` | Limite de 10GB para cache |
| `--buffer-size 100M` | Buffer de 100MB por arquivo |
| `--dir-cache-time 72h` | Cache de diretórios por 72 horas |
| `--poll-interval 15s` | Verifica mudanças a cada 15 segundos |
| `--allow-other` | Permite acesso por outros usuários (Docker) |
| `--daemon` | Roda em background |

### 5.5 Verificar Montagem

```bash
# Verificar se está montado
df -h | grep media

# Listar arquivos
ls -la /opt/jellyfin/media/
```

### 5.6 Montar Automaticamente no Boot

Crie um serviço systemd:

```bash
cat > /etc/systemd/system/rclone-gdrive.service << 'EOF'
[Unit]
Description=Rclone Mount Google Drive
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/rclone mount gdrive: /opt/jellyfin/media \
    --vfs-cache-mode full \
    --vfs-cache-max-size 10G \
    --buffer-size 100M \
    --dir-cache-time 72h \
    --poll-interval 15s \
    --allow-other \
    --config /root/.config/rclone/rclone.conf
ExecStop=/bin/fusermount -u /opt/jellyfin/media
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Habilitar serviço
systemctl daemon-reload
systemctl enable rclone-gdrive
systemctl start rclone-gdrive

# Verificar status
systemctl status rclone-gdrive
```

### 5.7 Limitações do Rclone com Google Drive

⚠️ **Importante saber:**

| Limitação | Descrição |
|-----------|-----------|
| **Latência** | Há delay para iniciar vídeos (2-5 segundos) |
| **Buffering** | Pode ocorrer em conexões lentas |
| **Quota diária** | Google Drive tem limite de ~10TB de download/dia |
| **Conexões** | Limite de conexões simultâneas |

**Dicas:**
- Use transcodificação no Jellyfin para arquivos muito grandes
- Prefira arquivos de até 10GB para melhor experiência
- O cache local ajuda muito na performance

---

## 6. Estrutura de Pastas

```bash
# Criar estrutura completa
mkdir -p /opt/jellyfin/{config,cache,media,caddy_data,caddy_config}

# Verificar estrutura
tree /opt/jellyfin/
# ou
ls -la /opt/jellyfin/
```

**Estrutura final:**

```
/opt/jellyfin/
├── docker-compose.yml    # Configuração dos containers
├── Caddyfile             # Configuração do reverse proxy
├── config/               # Configurações do Jellyfin
├── cache/                # Cache de transcodificação
├── media/                # Google Drive montado (rclone)
├── caddy_data/           # Certificados SSL (IMPORTANTE!)
└── caddy_config/         # Configurações do Caddy
```

---

## 7. Arquivos de Configuração

### 7.1 docker-compose.yml

Crie o arquivo:

```bash
nano /opt/jellyfin/docker-compose.yml
```

Cole o conteúdo (ver arquivo docker-compose.yml fornecido).

### 7.2 Caddyfile

```bash
nano /opt/jellyfin/Caddyfile
```

Cole o conteúdo (ver arquivo Caddyfile fornecido).

**⚠️ IMPORTANTE:** Substitua `EMAIL_SSL` pelo seu email real!

---

## 8. Subindo o Ambiente

### 8.1 Verificações Pré-Deploy

```bash
# 1. Verificar DNS
nslookup jellyfin.tonfly.cloud
# Deve retornar 170.80.38.25

# 2. Verificar Rclone montado
ls /opt/jellyfin/media/
# Deve mostrar seus arquivos do Drive

# 3. Verificar Docker rodando
docker ps
```

### 8.2 Subir Containers

```bash
cd /opt/jellyfin

# Subir em modo detached (background)
docker compose up -d

# Ver logs em tempo real
docker compose logs -f

# Verificar containers rodando
docker ps
```

### 8.3 Verificar Certificado SSL

O Caddy gera o certificado automaticamente. Aguarde ~1 minuto e teste:

```bash
# Ver logs do Caddy
docker logs caddy

# Deve mostrar algo como:
# "certificate obtained successfully"
```

### 8.4 Acessar Jellyfin

Abra no navegador:

```
https://jellyfin.tonfly.cloud
```

**Configuração inicial do Jellyfin:**
1. Escolha idioma (Português)
2. Crie usuário administrador (use senha FORTE!)
3. Adicione biblioteca de mídia → Pasta: `/media`
4. Configure metadados
5. Finalize

---

## 9. Configuração do Firewall

### 9.1 Configurar UFW

```bash
# Instalar UFW se não tiver
apt install ufw -y

# Reset para garantir
ufw reset

# Política padrão: bloquear tudo
ufw default deny incoming
ufw default allow outgoing

# Liberar SSH (IMPORTANTE! Senão perde acesso)
ufw allow 22/tcp

# Liberar HTTP e HTTPS (Caddy)
ufw allow 80/tcp
ufw allow 443/tcp

# NÃO liberar 8096! (Jellyfin só via Caddy)

# Ativar UFW
ufw enable

# Verificar regras
ufw status verbose
```

### 9.2 Resultado Esperado

```
Status: active

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW       Anywhere
80/tcp                     ALLOW       Anywhere
443/tcp                    ALLOW       Anywhere
```

> **Nota:** A porta 8096 do Jellyfin NÃO aparece porque está protegida.
> Acesso apenas via `https://jellyfin.tonfly.cloud`

---

## 10. Segurança

### 10.1 Por que NÃO expor a porta 8096?

| Risco | Descrição |
|-------|-----------|
| **Sem HTTPS** | Dados trafegam sem criptografia |
| **Senhas expostas** | Login pode ser interceptado |
| **Ataques diretos** | Serviço vulnerável a exploits |
| **Força bruta** | Sem proteção contra tentativas de login |

### 10.2 Benefícios do Caddy

- ✅ HTTPS automático com Let's Encrypt
- ✅ Renovação automática de certificados
- ✅ Headers de segurança
- ✅ Compressão de dados
- ✅ Única porta exposta

### 10.3 Boas Práticas

```
1. ✅ Senha forte no Jellyfin (mínimo 12 caracteres)
2. ✅ Desabilitar acesso anônimo (padrão)
3. ✅ Não usar usuário "admin" ou "root"
4. ✅ Manter Docker e Jellyfin atualizados
5. ✅ Fazer backup do /opt/jellyfin/config/
```

### 10.4 Configurações no Jellyfin

Acesse: **Painel de Controle → Usuários**

- Desmarcar "Permitir acesso remoto" para usuários sensíveis
- Limitar taxa de login (proteção força bruta)
- Configurar controle parental se necessário

---

## 11. Troubleshooting

### ❌ DNS não resolve

```bash
# Verificar
nslookup jellyfin.tonfly.cloud

# Se não resolver:
# 1. Aguarde propagação (até 48h)
# 2. Verifique registro no painel do domínio
# 3. Teste em https://dnschecker.org
```

### ❌ Certificado não gerado

```bash
# Ver logs do Caddy
docker logs caddy

# Erros comuns:
# - DNS não propagado (aguarde)
# - Porta 80 bloqueada (ufw allow 80)
# - Email inválido no Caddyfile

# Forçar renovação:
docker compose restart caddy
```

### ❌ Jellyfin não carrega

```bash
# Verificar container
docker ps -a

# Ver logs
docker logs jellyfin

# Reiniciar
docker compose restart jellyfin

# Verificar /media
ls /opt/jellyfin/media/
```

### ❌ Rclone não monta

```bash
# Verificar serviço
systemctl status rclone-gdrive

# Ver logs
journalctl -u rclone-gdrive -f

# Testar manualmente
rclone ls gdrive: --max-depth 1

# Remontar
fusermount -u /opt/jellyfin/media
systemctl restart rclone-gdrive
```

### ❌ Vídeo travando (buffering)

```bash
# Verificar velocidade do VPS
speedtest-cli

# Aumentar buffer no rclone
# Edite /etc/systemd/system/rclone-gdrive.service
--buffer-size 200M

# Ou habilite transcodificação no Jellyfin
# Painel → Reprodução → Transcodificação
```

### ❌ Porta 80/443 bloqueada

```bash
# Verificar UFW
ufw status

# Verificar se portas estão em uso
netstat -tlnp | grep -E '80|443'

# Verificar firewall do provedor (painel da VPS)
# Alguns provedores têm firewall adicional
```

---

## 12. Comandos Úteis

### Gerenciamento

```bash
# Acessar pasta do projeto
cd /opt/jellyfin

# Iniciar ambiente
docker compose up -d

# Parar ambiente
docker compose down

# Reiniciar
docker compose restart

# Ver status
docker compose ps

# Ver logs (todos)
docker compose logs -f

# Ver logs específico
docker logs jellyfin -f
docker logs caddy -f

# Atualizar imagens
docker compose pull
docker compose up -d
```

### Rclone

```bash
# Status do mount
systemctl status rclone-gdrive

# Reiniciar mount
systemctl restart rclone-gdrive

# Desmontar
fusermount -u /opt/jellyfin/media

# Ver uso do cache
du -sh /var/cache/rclone/
```

### Manutenção

```bash
# Backup configuração Jellyfin
tar -czvf jellyfin-backup.tar.gz /opt/jellyfin/config/

# Limpar cache do Docker
docker system prune -a

# Ver uso de disco
df -h

# Ver logs do sistema
journalctl -xe
```

---

## 🎯 Passo a Passo Final (Resumo)

```bash
# ═══════════════════════════════════════════════════════════════
# 1. CONFIGURAR DNS (no painel do domínio)
# ═══════════════════════════════════════════════════════════════
# Tipo: A
# Host: jellyfin
# Valor: 170.80.38.25

# ═══════════════════════════════════════════════════════════════
# 2. VALIDAR DNS (aguarde propagação!)
# ═══════════════════════════════════════════════════════════════
nslookup jellyfin.tonfly.cloud

# ═══════════════════════════════════════════════════════════════
# 3. PREPARAR VPS
# ═══════════════════════════════════════════════════════════════
ssh root@170.80.38.25
apt update && apt upgrade -y
apt install -y curl wget unzip fuse3

# ═══════════════════════════════════════════════════════════════
# 4. INSTALAR DOCKER
# ═══════════════════════════════════════════════════════════════
curl -fsSL https://get.docker.com | sh
systemctl enable docker && systemctl start docker

# ═══════════════════════════════════════════════════════════════
# 5. INSTALAR E CONFIGURAR RCLONE
# ═══════════════════════════════════════════════════════════════
curl https://rclone.org/install.sh | bash
rclone config
# (siga os passos para configurar gdrive)

# ═══════════════════════════════════════════════════════════════
# 6. CRIAR ESTRUTURA
# ═══════════════════════════════════════════════════════════════
mkdir -p /opt/jellyfin/{config,cache,media,caddy_data,caddy_config}

# ═══════════════════════════════════════════════════════════════
# 7. MONTAR GOOGLE DRIVE
# ═══════════════════════════════════════════════════════════════
rclone mount gdrive: /opt/jellyfin/media \
    --vfs-cache-mode full \
    --vfs-cache-max-size 10G \
    --buffer-size 100M \
    --dir-cache-time 72h \
    --poll-interval 15s \
    --allow-other \
    --daemon

# ═══════════════════════════════════════════════════════════════
# 8. CRIAR ARQUIVOS (docker-compose.yml e Caddyfile)
# ═══════════════════════════════════════════════════════════════
cd /opt/jellyfin
nano docker-compose.yml   # Cole o conteúdo
nano Caddyfile            # Cole o conteúdo (MUDE O EMAIL!)

# ═══════════════════════════════════════════════════════════════
# 9. CONFIGURAR FIREWALL
# ═══════════════════════════════════════════════════════════════
ufw allow 22 && ufw allow 80 && ufw allow 443
ufw enable

# ═══════════════════════════════════════════════════════════════
# 10. SUBIR DOCKER COMPOSE
# ═══════════════════════════════════════════════════════════════
docker compose up -d

# ═══════════════════════════════════════════════════════════════
# 11. ACESSAR
# ═══════════════════════════════════════════════════════════════
# Abra: https://jellyfin.tonfly.cloud
# Configure o Jellyfin (usuário, biblioteca em /media)
```

---

## 📱 Acesso via Smart TV

Após configurar:

1. Na Smart TV, abra a loja de apps
2. Procure por "Jellyfin" e instale
3. Abra o app e configure:
   - **Servidor:** `https://jellyfin.tonfly.cloud`
   - **Usuário:** seu usuário
   - **Senha:** sua senha
4. Pronto! 🎬

---

**Dúvidas?** Verifique a seção de Troubleshooting ou os logs dos containers.

```bash
docker compose logs -f
```

---

## 13. CI/CD com GitHub Actions

### 13.1 Configuração do Repositório

O projeto inclui um workflow de CI/CD que faz deploy automático quando você faz push para `main` ou `master`.

### 13.2 Estrutura do Repositório

```
jellyfin/
├── .github/
│   └── workflows/
│       └── deploy.yml      # Workflow de deploy automático
├── docker-compose.yml
├── Caddyfile
└── ...
```

### 13.3 Secrets Necessários no GitHub

Vá em **Settings → Secrets and variables → Actions** e adicione:

| Secret | Descrição | Exemplo |
|--------|-----------|---------|
| `SSH_PRIVATE_KEY` | Chave privada SSH para acessar o VPS | Conteúdo do `~/.ssh/id_rsa` |
| `VPS_HOST` | IP ou hostname do VPS | `170.80.38.25` |
| `VPS_USER` | Usuário SSH | `root` |
| `SSL_EMAIL` | Email para certificado Let's Encrypt | `seu@email.com` |

### 13.4 Gerar Chave SSH

```bash
# No seu computador local
ssh-keygen -t ed25519 -C "github-actions"

# Copiar chave pública para o VPS
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@170.80.38.25

# Copiar chave privada para o secret SSH_PRIVATE_KEY
cat ~/.ssh/id_ed25519
```

### 13.5 Preparar VPS para Primeiro Deploy

Antes do primeiro deploy automático, execute no VPS:

```bash
# Criar estrutura base
mkdir -p /opt/jellyfin/{config,cache,media,caddy_data,caddy_config}

# Instalar Docker (se ainda não tiver)
curl -fsSL https://get.docker.com | sh
systemctl enable docker && systemctl start docker

# Configurar Rclone (manual - uma única vez)
curl https://rclone.org/install.sh | bash
rclone config
# ... configure gdrive ...

# Criar serviço Rclone
# (copie o conteúdo de rclone-service.sh e execute)

# Iniciar montagem
systemctl start rclone-gdrive
```

### 13.6 Fluxo de Deploy

```
┌─────────────────┐
│  git push main  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ GitHub Actions  │
│   Checkout      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   SCP arquivos  │
│  para o VPS     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  SSH no VPS     │
│  docker compose │
│  pull && up -d  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  ✅ Deploy OK!  │
└─────────────────┘
```

### 13.7 Como Usar

1. **Faça alterações** no `docker-compose.yml` ou `Caddyfile`
2. **Commit e push**:
   ```bash
   git add .
   git commit -m "Atualizar configuração"
   git push origin main
   ```
3. **Acompanhe** o deploy em **Actions** no GitHub
4. O deploy é feito automaticamente! 🚀
