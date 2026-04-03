#!/bin/bash
# deploy_mailcow_fleet.sh
# Master deployment script for GaiaFTCL Mailcow infrastructure
# Run from your local machine with SSH access to all cells

set -e

# Cell Configuration
declare -A CELLS=(
  ["nbg1-01"]="37.120.187.247:primary"
  ["hel1-01"]="77.42.85.60:backup"
  ["hel1-02"]="135.181.88.134:relay"
  ["hel1-03"]="77.42.32.156:relay"
  ["hel1-04"]="77.42.88.110:relay"
  ["hel1-05"]="37.27.7.9:relay"
  ["nbg1-02"]="152.53.91.220:relay"
  ["nbg1-03"]="152.53.88.141:relay"
  ["nbg1-04"]="37.120.187.174:relay"
)

SSH_USER="root"
SSH_KEY="~/.ssh/id_rsa"
DOMAIN="gaiaftcl.com"
PRIMARY_IP="37.120.187.247"
API_KEY=$(openssl rand -hex 32)
ARANGO_PASSWORD=$(openssl rand -hex 16)

echo "=============================================="
echo "GaiaFTCL Mailcow Fleet Deployment"
echo "=============================================="
echo ""
echo "Primary MX: nbg1-01 (${PRIMARY_IP})"
echo "Backup MX:  hel1-01 (77.42.85.60)"
echo "Relays:     7 cells"
echo ""
echo "API Key: ${API_KEY}"
echo "ArangoDB Password: ${ARANGO_PASSWORD}"
echo ""
echo "SAVE THESE CREDENTIALS SECURELY!"
echo ""
read -p "Press Enter to continue or Ctrl+C to abort..."

# ============================================
# Phase 1: Prerequisites on all cells
# ============================================

echo ""
echo "[Phase 1] Installing prerequisites on all cells..."

for cell in "${!CELLS[@]}"; do
  IFS=':' read -r ip role <<< "${CELLS[$cell]}"
  echo "  - ${cell} (${ip})..."
  
  ssh -i ${SSH_KEY} ${SSH_USER}@${ip} << 'PREREQ'
    apt update && apt upgrade -y
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    apt install -y docker-compose-plugin git curl wget jq
    
    # Firewall
    ufw allow 25/tcp
    ufw allow 465/tcp
    ufw allow 587/tcp
    ufw allow 143/tcp
    ufw allow 993/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
PREREQ
done

echo "[Phase 1] Complete"

# ============================================
# Phase 2: Primary MX (nbg1-01)
# ============================================

echo ""
echo "[Phase 2] Installing Mailcow Primary on nbg1-01..."

ssh -i ${SSH_KEY} ${SSH_USER}@${PRIMARY_IP} << MAILCOW_PRIMARY
  cd /opt
  rm -rf mailcow-dockerized
  git clone https://github.com/mailcow/mailcow-dockerized
  cd mailcow-dockerized
  
  # Generate config non-interactively
  MAILCOW_HOSTNAME=mail.${DOMAIN}
  MAILCOW_TZ=Europe/Berlin
  
  cat > mailcow.conf << EOF
MAILCOW_HOSTNAME=mail.${DOMAIN}
MAILCOW_PASS_SCHEME=ARGON2ID
DBNAME=mailcow
DBUSER=mailcow
DBPASS=$(openssl rand -hex 16)
DBROOT=$(openssl rand -hex 16)
HTTP_PORT=80
HTTP_BIND=0.0.0.0
HTTPS_PORT=443
HTTPS_BIND=0.0.0.0
SMTP_PORT=25
SMTPS_PORT=465
SUBMISSION_PORT=587
IMAP_PORT=143
IMAPS_PORT=993
POP_PORT=110
POPS_PORT=995
SIEVE_PORT=4190
DOVEADM_PORT=127.0.0.1:19991
SQL_PORT=127.0.0.1:13306
SOLR_PORT=127.0.0.1:18983
REDIS_PORT=127.0.0.1:7654
TZ=Europe/Berlin
COMPOSE_PROJECT_NAME=mailcowdockerized
SKIP_LETS_ENCRYPT=n
SKIP_SOGO=n
SKIP_CLAMD=n
SKIP_SOLR=y
ALLOW_ADMIN_EMAIL_LOGIN=y
ADDITIONAL_SAN=${DOMAIN},*.${DOMAIN}
API_KEY=${API_KEY}
API_KEY_READ_ONLY=${API_KEY}
API_ALLOW_FROM=0.0.0.0/0
ACL_ANYONE=disallow
EOF
  
  # Pull and start
  docker compose pull
  docker compose up -d
  
  echo "Waiting for services to start..."
  sleep 90
  
  # Create domain via API
  curl -s -X POST "http://localhost/api/v1/add/domain" \
    -H "X-API-Key: ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
      "domain": "${DOMAIN}",
      "description": "GaiaFTCL Primary",
      "aliases": 1000,
      "mailboxes": 10000,
      "maxquota": 10240,
      "quota": 1024000,
      "active": 1
    }'
  
  echo "Mailcow Primary installed"
MAILCOW_PRIMARY

echo "[Phase 2] Complete"

# ============================================
# Phase 3: Backup MX (hel1-01)
# ============================================

echo ""
echo "[Phase 3] Installing Mailcow Backup on hel1-01..."

BACKUP_IP="77.42.85.60"

ssh -i ${SSH_KEY} ${SSH_USER}@${BACKUP_IP} << MAILCOW_BACKUP
  cd /opt
  rm -rf mailcow-dockerized
  git clone https://github.com/mailcow/mailcow-dockerized
  cd mailcow-dockerized
  
  cat > mailcow.conf << EOF
MAILCOW_HOSTNAME=backup-mx.${DOMAIN}
MAILCOW_PASS_SCHEME=ARGON2ID
DBNAME=mailcow
DBUSER=mailcow
DBPASS=$(openssl rand -hex 16)
DBROOT=$(openssl rand -hex 16)
HTTP_PORT=80
HTTP_BIND=0.0.0.0
HTTPS_PORT=443
HTTPS_BIND=0.0.0.0
SMTP_PORT=25
SMTPS_PORT=465
SUBMISSION_PORT=587
IMAP_PORT=143
IMAPS_PORT=993
TZ=Europe/Helsinki
COMPOSE_PROJECT_NAME=mailcowdockerized
SKIP_LETS_ENCRYPT=n
SKIP_SOGO=y
SKIP_CLAMD=y
SKIP_SOLR=y
ACL_ANYONE=disallow
EOF
  
  # Configure as relay
  mkdir -p data/conf/postfix
  cat > data/conf/postfix/extra.cf << POSTFIX
relay_domains = ${DOMAIN}
transport_maps = hash:/opt/postfix/conf/transport
POSTFIX
  
  mkdir -p data/conf/postfix
  echo "${DOMAIN} smtp:[mail.${DOMAIN}]:25" > data/conf/postfix/transport
  
  # Constitutional mesh: join gaiaftcl_cell, use MCP only (see mailcow-mesh-override.yml)
  # If cell stack runs on this host, copy override and use it:
  #   cp /opt/gaia/GAIAOS/docs/specs/skin/mailcow-mesh-override.yml .
  #   docker compose -f docker-compose.yml -f mailcow-mesh-override.yml up -d
  docker compose pull
  docker compose up -d
  
  echo "Mailcow Backup installed"
MAILCOW_BACKUP

echo "[Phase 3] Complete"

# ============================================
# Phase 4: Relay Configuration (Other Cells)
# ============================================

echo ""
echo "[Phase 4] Configuring relay on other cells..."

for cell in "${!CELLS[@]}"; do
  IFS=':' read -r ip role <<< "${CELLS[$cell]}"
  
  if [ "$role" = "relay" ]; then
    echo "  - ${cell} (${ip})..."
    
    ssh -i ${SSH_KEY} ${SSH_USER}@${ip} << RELAY
      # Install Postfix as relay
      DEBIAN_FRONTEND=noninteractive apt install -y postfix
      
      cat > /etc/postfix/main.cf << POSTFIX
myhostname = ${cell}.${DOMAIN}
mydomain = ${DOMAIN}
myorigin = \$mydomain
mydestination = 
relayhost = [mail.${DOMAIN}]:587
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_tls_security_level = encrypt
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt
inet_interfaces = all
inet_protocols = ipv4
POSTFIX
      
      # Create relay credentials
      echo "[mail.${DOMAIN}]:587 relay@${DOMAIN}:RELAY_PASSWORD_HERE" > /etc/postfix/sasl_passwd
      chmod 600 /etc/postfix/sasl_passwd
      postmap /etc/postfix/sasl_passwd
      
      systemctl restart postfix
      systemctl enable postfix
      
      echo "Relay configured on ${cell}"
RELAY
  fi
done

echo "[Phase 4] Complete"

# ============================================
# Phase 5: Mailcow MCP-only (Constitutional)
# ============================================
#
# Mailcow must NOT have direct ArangoDB or NATS. All substrate access via MCP.
# Join mesh network, set MCP_URL. No gaiaftcl-arangodb, no gaiaftcl-nats on mailcow-network.
#
# If primary needs substrate: join gaiaftcl_cell (or mesh) and use MCP_URL only.
# See docs/specs/skin/mailcow-mesh-override.yml for the override pattern.

echo ""
echo "[Phase 5] Mailcow uses MCP only (no direct ArangoDB/NATS)"
echo "  - Apply mailcow-mesh-override.yml when cell stack runs on same host"
echo "  - MCP_URL=http://gaiaftcl-mcp-gateway:8803"
echo "[Phase 5] Complete"

# ============================================
# Phase 6: Agent Mailboxes
# ============================================

echo ""
echo "[Phase 6] Creating agent mailboxes..."

# Wait for API to be ready
sleep 30

# Create agent mailboxes
AGENTS=(
  "franklin:Constitutional Guardian"
  "gaia:Planetary Coordinator"
  "fara:Field-Aware Reasoning Agent"
  "qstate:Quantum State Manager"
  "validator:Truth Validator"
  "witness:Audit Witness"
  "oracle:Data Oracle"
  "gamerunner:Game Executor"
  "virtue:Ethics Engine"
  "ben:Investment Manager"
  "treasury:Treasury System"
  "support:User Support"
  "founder:Founder"
  "welcome:Welcome System"
  "noreply:No Reply"
)

for agent in "${AGENTS[@]}"; do
  IFS=':' read -r name desc <<< "$agent"
  password=$(openssl rand -hex 16)
  
  echo "  - Creating ${name}@${DOMAIN}..."
  
  curl -s -X POST "https://mail.${DOMAIN}/api/v1/add/mailbox" \
    -H "X-API-Key: ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
      \"local_part\": \"${name}\",
      \"domain\": \"${DOMAIN}\",
      \"name\": \"${desc}\",
      \"password\": \"${password}\",
      \"password2\": \"${password}\",
      \"quota\": 10240,
      \"active\": 1,
      \"force_pw_update\": 0
    }" > /dev/null
  
  echo "    Password: ${password}"
done

echo "[Phase 6] Complete"

# ============================================
# Summary
# ============================================

echo ""
echo "=============================================="
echo "DEPLOYMENT COMPLETE"
echo "=============================================="
echo ""
echo "Services:"
echo "  Admin UI:    https://mail.${DOMAIN}"
echo "  Webmail:     https://mail.${DOMAIN}/SOGo"
echo "  MCP Gateway: http://77.42.85.60:8803 (substrate access via MCP only)"
echo ""
echo "Credentials (SAVE THESE!):"
echo "  Admin:       admin / moohoo (CHANGE IMMEDIATELY)"
echo "  API Key:     ${API_KEY}"
echo ""
echo "DNS Records to add:"
echo "  MX 10  mail.${DOMAIN}      -> ${PRIMARY_IP}"
echo "  MX 20  backup-mx.${DOMAIN} -> 77.42.85.60"
echo "  TXT    v=spf1 mx ip4:${PRIMARY_IP} ip4:77.42.85.60 ~all"
echo "  TXT    _dmarc  v=DMARC1; p=quarantine; rua=mailto:dmarc@${DOMAIN}"
echo ""
echo "Next steps:"
echo "  1. Change admin password immediately"
echo "  2. Configure DNS records"
echo "  3. Get DKIM key from admin UI and add to DNS"
echo "  4. Apply GaiaFTCL branding"
echo "  5. Test email flow"
echo ""
