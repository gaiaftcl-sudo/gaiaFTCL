# GaiaFTCL Enterprise Email System

**Version:** 1.0.0  
**Status:** Implementation Guide  
**Date:** January 2026  
**Document:** FTCL-MAIL-001

---

## Abstract

This specification defines the complete enterprise email infrastructure for GaiaFTCL using Mailcow as the core platform, extended with GaiaFTCL branding, truth envelope integration, wallet management, and treasury operations. Email becomes the unified coordination surface for all GaiaFTCL operations.

---

## Part I: Architecture Overview

### 1.1 The Email-Centric Model

```
┌─────────────────────────────────────────────────────────────┐
│                 GAIAFTCL EMAIL ARCHITECTURE                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   MAILCOW CORE                                              │
│   ├── Postfix (SMTP)                                        │
│   ├── Dovecot (IMAP)                                        │
│   ├── SOGo (Webmail) ──→ GaiaFTCL Branded                  │
│   ├── Rspamd (Spam)                                         │
│   ├── ClamAV (Virus)                                        │
│   ├── Redis (Cache)                                         │
│   ├── MariaDB (Store)                                       │
│   └── Admin UI ──→ Extended for GaiaFTCL                   │
│                                                             │
│   GAIAFTCL EXTENSIONS                                       │
│   ├── Truth Envelope Processor                              │
│   ├── Wallet Integration                                    │
│   ├── Treasury Dashboard                                    │
│   ├── Agent Mailboxes (Franklin, Gaia, Ben, etc.)          │
│   └── Game Move Detection                                   │
│                                                             │
│   DEPLOYMENT                                                │
│   ├── Primary: nbg1-01 (main mail server)                  │
│   ├── Backup MX: hel1-01                                   │
│   └── All cells: Local relay to primary                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Cell Roles

| Cell | Role | Function |
|------|------|----------|
| nbg1-01 | Primary MX | Main mail server, admin UI, treasury |
| hel1-01 | Backup MX | Failover, queue if primary down |
| All others | Relay | Send through primary, local agent delivery |

---

## Part II: Mailcow Installation

### 2.1 Prerequisites (All Cells)

```bash
#!/bin/bash
# prerequisites.sh - Run on each cell

# Update system
apt update && apt upgrade -y

# Install Docker (if not present)
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker

# Install Docker Compose
apt install -y docker-compose-plugin

# Install required packages
apt install -y git curl wget jq certbot

# Set hostname (adjust per cell)
hostnamectl set-hostname mail.gaiaftcl.com

# Configure firewall
ufw allow 25/tcp    # SMTP
ufw allow 465/tcp   # SMTPS
ufw allow 587/tcp   # Submission
ufw allow 143/tcp   # IMAP
ufw allow 993/tcp   # IMAPS
ufw allow 110/tcp   # POP3
ufw allow 995/tcp   # POP3S
ufw allow 80/tcp    # HTTP (certbot)
ufw allow 443/tcp   # HTTPS
ufw reload
```

### 2.2 Primary Mail Server (nbg1-01)

```bash
#!/bin/bash
# install_mailcow_primary.sh - Run on nbg1-01

set -e

# Variables
MAILCOW_HOSTNAME="mail.gaiaftcl.com"
MAILCOW_DIR="/opt/mailcow-dockerized"

# Clone Mailcow
cd /opt
git clone https://github.com/mailcow/mailcow-dockerized
cd mailcow-dockerized

# Generate configuration
./generate_config.sh <<EOF
${MAILCOW_HOSTNAME}
Europe/Berlin
EOF

# Customize mailcow.conf
cat >> mailcow.conf << 'CONF'
# GaiaFTCL Customizations
SKIP_LETS_ENCRYPT=n
SKIP_SOGO=n
SKIP_CLAMD=n
SKIP_SOLR=y
ALLOW_ADMIN_EMAIL_LOGIN=y
ADDITIONAL_SAN=gaiaftcl.com,*.gaiaftcl.com
API_KEY=GENERATE_SECURE_KEY_HERE
API_ALLOW_FROM=0.0.0.0/0
MAILCOW_PASS_SCHEME=ARGON2ID
CONF

# Pull and start
docker compose pull
docker compose up -d

# Wait for startup
echo "Waiting for Mailcow to start..."
sleep 60

# Get admin password
echo "Admin UI: https://${MAILCOW_HOSTNAME}"
echo "Default login: admin / moohoo"
echo "CHANGE THIS IMMEDIATELY!"

# Create initial domain
curl -X POST "http://localhost:8080/api/v1/add/domain" \
  -H "X-API-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "domain": "gaiaftcl.com",
    "description": "GaiaFTCL Primary Domain",
    "aliases": 400,
    "mailboxes": 1000,
    "maxquota": 10240,
    "quota": 102400,
    "active": 1
  }'

echo "Mailcow Primary installed on nbg1-01"
```

### 2.3 Backup MX Server (hel1-01)

```bash
#!/bin/bash
# install_mailcow_backup.sh - Run on hel1-01

set -e

MAILCOW_HOSTNAME="backup-mx.gaiaftcl.com"
MAILCOW_DIR="/opt/mailcow-dockerized"
PRIMARY_MX="mail.gaiaftcl.com"

cd /opt
git clone https://github.com/mailcow/mailcow-dockerized
cd mailcow-dockerized

./generate_config.sh <<EOF
${MAILCOW_HOSTNAME}
Europe/Helsinki
EOF

# Configure as backup MX
cat >> mailcow.conf << CONF
SKIP_LETS_ENCRYPT=n
SKIP_SOGO=y
SKIP_CLAMD=y
SKIP_SOLR=y
# Relay to primary
RELAYHOST=${PRIMARY_MX}
CONF

# Postfix relay configuration
mkdir -p data/conf/postfix
cat > data/conf/postfix/extra.cf << 'POSTFIX'
# Backup MX - relay all mail to primary
relay_domains = gaiaftcl.com
transport_maps = hash:/opt/postfix/conf/transport
POSTFIX

cat > data/conf/postfix/transport << 'TRANSPORT'
gaiaftcl.com smtp:[mail.gaiaftcl.com]:25
TRANSPORT

docker compose pull
docker compose up -d

echo "Backup MX installed on hel1-01"
```

### 2.4 Relay Configuration (Other Cells)

```bash
#!/bin/bash
# install_relay.sh - Run on all other cells

set -e

PRIMARY_MX="mail.gaiaftcl.com"
CELL_NAME=$(hostname -s)

# Install lightweight Postfix relay
apt install -y postfix

# Configure as relay
cat > /etc/postfix/main.cf << POSTFIX
# GaiaFTCL Mail Relay - ${CELL_NAME}
myhostname = ${CELL_NAME}.gaiaftcl.com
mydomain = gaiaftcl.com
myorigin = \$mydomain
mydestination = 
relayhost = [${PRIMARY_MX}]:587
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_tls_security_level = encrypt
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt
POSTFIX

# Create credentials (will be set per-cell)
echo "[${PRIMARY_MX}]:587 relay@gaiaftcl.com:RELAY_PASSWORD" > /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd

systemctl restart postfix
systemctl enable postfix

echo "Relay configured on ${CELL_NAME}"
```

---

## Part III: DNS Configuration

### 3.1 MX Records

```dns
; GaiaFTCL Mail DNS Records
; Primary domain
gaiaftcl.com.           IN  MX  10 mail.gaiaftcl.com.
gaiaftcl.com.           IN  MX  20 backup-mx.gaiaftcl.com.

; Mail servers
mail.gaiaftcl.com.      IN  A   37.120.187.247    ; nbg1-01
backup-mx.gaiaftcl.com. IN  A   77.42.85.60       ; hel1-01

; SPF
gaiaftcl.com.           IN  TXT "v=spf1 mx ip4:37.120.187.247 ip4:77.42.85.60 ~all"

; DKIM (generated by Mailcow)
dkim._domainkey.gaiaftcl.com. IN TXT "v=DKIM1; k=rsa; p=..."

; DMARC
_dmarc.gaiaftcl.com.    IN  TXT "v=DMARC1; p=quarantine; rua=mailto:dmarc@gaiaftcl.com"

; Autodiscover
autodiscover.gaiaftcl.com.  IN  CNAME  mail.gaiaftcl.com.
autoconfig.gaiaftcl.com.    IN  CNAME  mail.gaiaftcl.com.

; SRV records for clients
_submission._tcp.gaiaftcl.com.  IN  SRV  0 1 587 mail.gaiaftcl.com.
_imap._tcp.gaiaftcl.com.        IN  SRV  0 1 143 mail.gaiaftcl.com.
_imaps._tcp.gaiaftcl.com.       IN  SRV  0 1 993 mail.gaiaftcl.com.
```

---

## Part IV: Migration from Maddy

### 4.1 Migration Script

```bash
#!/bin/bash
# migrate_maddy_to_mailcow.sh

set -e

MADDY_DIR="/var/lib/maddy"
MAILCOW_API="https://mail.gaiaftcl.com/api/v1"
API_KEY="YOUR_API_KEY"

echo "=== GaiaFTCL Mail Migration: Maddy → Mailcow ==="

# 1. Export Maddy users
echo "[1/5] Exporting Maddy users..."
maddy creds list > /tmp/maddy_users.txt

# 2. Export Maddy mailboxes (Maildir format)
echo "[2/5] Exporting mailboxes..."
MAILDIR_PATH="/var/lib/maddy/messages"

# 3. Create users in Mailcow
echo "[3/5] Creating Mailcow mailboxes..."
while read -r email; do
  if [[ -n "$email" ]]; then
    # Generate temporary password (user will reset)
    TEMP_PASS=$(openssl rand -base64 16)
    
    curl -s -X POST "${MAILCOW_API}/add/mailbox" \
      -H "X-API-Key: ${API_KEY}" \
      -H "Content-Type: application/json" \
      -d "{
        \"local_part\": \"${email%%@*}\",
        \"domain\": \"${email#*@}\",
        \"name\": \"${email%%@*}\",
        \"password\": \"${TEMP_PASS}\",
        \"password2\": \"${TEMP_PASS}\",
        \"quota\": 1024,
        \"active\": 1,
        \"force_pw_update\": 1
      }"
    
    echo "Created: ${email}"
  fi
done < /tmp/maddy_users.txt

# 4. Import mail via imapsync
echo "[4/5] Syncing mailboxes (this may take a while)..."
apt install -y imapsync

while read -r email; do
  if [[ -n "$email" ]]; then
    # Sync from Maddy to Mailcow
    imapsync \
      --host1 localhost --port1 993 --ssl1 \
      --user1 "${email}" --password1 "MADDY_PASS" \
      --host2 mail.gaiaftcl.com --port2 993 --ssl2 \
      --user2 "${email}" --password2 "TEMP_PASS" \
      --automap --nofoldersizes
  fi
done < /tmp/maddy_users.txt

# 5. Update DNS
echo "[5/5] Update DNS records to point to Mailcow"
echo "  MX: mail.gaiaftcl.com (37.120.187.247)"
echo "  Update SPF, DKIM, DMARC"

# 6. Disable Maddy
echo "Stopping Maddy..."
systemctl stop maddy
systemctl disable maddy

echo "=== Migration Complete ==="
echo "Users can login at: https://mail.gaiaftcl.com"
echo "All users must reset passwords on first login."
```

### 4.2 Migration Checklist

```markdown
## Pre-Migration
- [ ] Backup all Maddy data
- [ ] Document current users/aliases
- [ ] Test Mailcow in parallel
- [ ] Prepare DNS changes (low TTL)

## Migration
- [ ] Run migration script
- [ ] Verify all mailboxes created
- [ ] Sync mail content
- [ ] Test sending/receiving

## Cutover
- [ ] Update MX records
- [ ] Update SPF/DKIM/DMARC
- [ ] Disable Maddy
- [ ] Monitor for issues

## Post-Migration
- [ ] Notify users of new webmail URL
- [ ] Force password resets
- [ ] Apply GaiaFTCL branding
- [ ] Configure agent mailboxes
```

---

## Part V: GaiaFTCL Branding

### 5.1 SOGo Webmail Theme

```bash
#!/bin/bash
# install_sogo_theme.sh - Run on nbg1-01

SOGO_DIR="/opt/mailcow-dockerized/data/web/sogo"
THEME_DIR="${SOGO_DIR}/GaiaFTCL"

# Create theme directory
mkdir -p ${THEME_DIR}

# Create custom CSS
cat > ${THEME_DIR}/custom.css << 'CSS'
/* GaiaFTCL SOGo Theme */

:root {
  --gaia-black: #0a0a0a;
  --gaia-darker: #050505;
  --gaia-white: #f5f5f5;
  --gaia-blue: #00d4ff;
  --gaia-purple: #8b5cf6;
  --gaia-green: #10b981;
  --gaia-red: #ef4444;
  --gaia-gray: #374151;
  --gaia-gray-light: #6b7280;
}

/* Background */
body, .bg-primary {
  background-color: var(--gaia-black) !important;
}

/* Toolbar */
md-toolbar, .md-toolbar-tools {
  background: linear-gradient(135deg, #0a0a0a 0%, #1a1a2e 100%) !important;
  border-bottom: 1px solid rgba(0, 212, 255, 0.2) !important;
}

/* Sidebar */
.sg-folder-list, md-sidenav {
  background-color: var(--gaia-darker) !important;
}

/* Cards */
md-card, .md-whiteframe-1dp {
  background-color: rgba(255, 255, 255, 0.02) !important;
  border: 1px solid rgba(255, 255, 255, 0.1) !important;
}

/* Text */
body, p, span, div, .md-subhead {
  color: var(--gaia-white) !important;
}

/* Accent color */
.md-primary, a, .sg-active {
  color: var(--gaia-blue) !important;
}

/* Buttons */
.md-button.md-primary {
  background: linear-gradient(135deg, #00d4ff 0%, #8b5cf6 100%) !important;
  color: var(--gaia-black) !important;
}

.md-button.md-primary:hover {
  box-shadow: 0 4px 20px rgba(0, 212, 255, 0.3) !important;
}

/* Input fields */
md-input-container input, md-input-container textarea {
  color: var(--gaia-white) !important;
  border-color: var(--gaia-gray) !important;
}

md-input-container.md-input-focused input {
  border-color: var(--gaia-blue) !important;
}

/* Mail list */
.sg-mail-list md-list-item {
  border-bottom: 1px solid rgba(255, 255, 255, 0.05) !important;
}

.sg-mail-list md-list-item:hover {
  background-color: rgba(0, 212, 255, 0.05) !important;
}

.sg-mail-list md-list-item.sg-active {
  background-color: rgba(0, 212, 255, 0.1) !important;
  border-left: 3px solid var(--gaia-blue) !important;
}

/* Unread indicator */
.sg-mail-unread {
  font-weight: 700 !important;
  color: var(--gaia-blue) !important;
}

/* Compose button */
.sg-compose-fab {
  background: linear-gradient(135deg, #00d4ff 0%, #8b5cf6 100%) !important;
}

/* Scrollbars */
::-webkit-scrollbar {
  width: 8px;
  background: var(--gaia-black);
}

::-webkit-scrollbar-thumb {
  background: var(--gaia-gray);
  border-radius: 4px;
}

::-webkit-scrollbar-thumb:hover {
  background: var(--gaia-blue);
}

/* Login page */
.md-dialog-container, md-dialog {
  background: var(--gaia-black) !important;
  border: 1px solid rgba(0, 212, 255, 0.2) !important;
}

/* Logo */
.sg-logo, #logo {
  content: url('/images/gaiaftcl-logo.svg') !important;
  max-height: 40px !important;
}

/* Footer */
.sg-footer {
  background: var(--gaia-darker) !important;
  border-top: 1px solid rgba(255, 255, 255, 0.05) !important;
  color: var(--gaia-gray-light) !important;
}

/* Calendar colors */
.sg-event, .sg-calendar-event {
  border-left: 3px solid var(--gaia-purple) !important;
}

/* Contacts */
.sg-contact-avatar {
  background: linear-gradient(135deg, #00d4ff 0%, #8b5cf6 100%) !important;
}

/* Notifications */
.md-toast-success {
  background: var(--gaia-green) !important;
}

.md-toast-error {
  background: var(--gaia-red) !important;
}

/* Truth Envelope indicator (custom) */
.gaia-envelope-badge {
  background: var(--gaia-purple);
  color: white;
  font-size: 10px;
  padding: 2px 6px;
  border-radius: 4px;
  margin-left: 8px;
}

/* QFOT balance indicator (custom) */
.gaia-balance-indicator {
  font-family: 'JetBrains Mono', monospace;
  font-size: 12px;
  color: var(--gaia-blue);
  padding: 4px 8px;
  background: rgba(0, 212, 255, 0.1);
  border-radius: 4px;
}
CSS

# Create logo SVG
cat > ${SOGO_DIR}/images/gaiaftcl-logo.svg << 'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 40">
  <defs>
    <linearGradient id="gradient" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" style="stop-color:#00d4ff"/>
      <stop offset="100%" style="stop-color:#8b5cf6"/>
    </linearGradient>
  </defs>
  <text x="0" y="32" font-family="Space Grotesk, sans-serif" font-size="28" font-weight="700" fill="#f5f5f5">
    GAIA
  </text>
  <text x="75" y="32" font-family="Space Grotesk, sans-serif" font-size="28" font-weight="700" fill="url(#gradient)">
    FT
  </text>
  <text x="115" y="32" font-family="Space Grotesk, sans-serif" font-size="28" font-weight="700" fill="#f5f5f5">
    CL
  </text>
</svg>
SVG

# Apply theme to Mailcow
echo "Applying theme..."
docker compose exec -T sogo-mailcow bash -c "cp -r /custom-theme/* /usr/lib/GNUstep/SOGo/WebServerResources/"

docker compose restart sogo-mailcow

echo "SOGo theme installed"
```

### 5.2 Admin UI Branding

```bash
#!/bin/bash
# brand_admin_ui.sh

MAILCOW_DIR="/opt/mailcow-dockerized"

# Custom admin CSS
cat > ${MAILCOW_DIR}/data/web/css/gaiaftcl-admin.css << 'CSS'
/* GaiaFTCL Mailcow Admin Theme */

:root {
  --primary: #00d4ff;
  --secondary: #8b5cf6;
  --dark: #0a0a0a;
  --light: #f5f5f5;
}

body {
  background: var(--dark) !important;
  color: var(--light) !important;
}

.navbar {
  background: linear-gradient(135deg, #0a0a0a 0%, #1a1a2e 100%) !important;
  border-bottom: 1px solid rgba(0, 212, 255, 0.2) !important;
}

.navbar-brand {
  font-family: 'Space Grotesk', sans-serif !important;
  font-weight: 700 !important;
  letter-spacing: 0.1em !important;
}

.card {
  background: rgba(255, 255, 255, 0.02) !important;
  border: 1px solid rgba(255, 255, 255, 0.1) !important;
}

.btn-primary {
  background: linear-gradient(135deg, #00d4ff 0%, #8b5cf6 100%) !important;
  border: none !important;
}

.btn-primary:hover {
  box-shadow: 0 4px 20px rgba(0, 212, 255, 0.3) !important;
}

.table {
  color: var(--light) !important;
}

.table-striped tbody tr:nth-of-type(odd) {
  background-color: rgba(255, 255, 255, 0.02) !important;
}

/* Sidebar */
.sidebar {
  background: #050505 !important;
}

.sidebar .nav-link {
  color: #6b7280 !important;
}

.sidebar .nav-link:hover, .sidebar .nav-link.active {
  color: #00d4ff !important;
  background: rgba(0, 212, 255, 0.1) !important;
}

/* Forms */
.form-control {
  background: var(--dark) !important;
  border-color: #374151 !important;
  color: var(--light) !important;
}

.form-control:focus {
  border-color: var(--primary) !important;
  box-shadow: 0 0 0 3px rgba(0, 212, 255, 0.1) !important;
}

/* Stats cards */
.card-counter {
  background: linear-gradient(135deg, rgba(0, 212, 255, 0.1) 0%, rgba(139, 92, 246, 0.1) 100%) !important;
  border: 1px solid rgba(0, 212, 255, 0.2) !important;
}

.card-counter .count-numbers {
  color: var(--primary) !important;
  font-family: 'Space Grotesk', sans-serif !important;
}
CSS

# Inject into admin UI
cat >> ${MAILCOW_DIR}/data/web/inc/header.inc.php << 'PHP'
<link href="/css/gaiaftcl-admin.css" rel="stylesheet">
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@500;700&display=swap" rel="stylesheet">
PHP

docker compose restart nginx-mailcow

echo "Admin UI branded"
```

### 5.3 Login Page Customization

```html
<!-- data/web/templates/login.tpl - Custom login page -->
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>GaiaFTCL Mail</title>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=Space+Grotesk:wght@700&display=swap" rel="stylesheet">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    
    body {
      background: #0a0a0a;
      color: #f5f5f5;
      font-family: 'Inter', sans-serif;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    
    .login-container {
      width: 100%;
      max-width: 400px;
      padding: 24px;
    }
    
    .logo {
      text-align: center;
      margin-bottom: 48px;
      font-family: 'Space Grotesk', sans-serif;
      font-size: 32px;
      font-weight: 700;
      letter-spacing: 0.1em;
    }
    
    .logo .ft {
      background: linear-gradient(135deg, #00d4ff 0%, #8b5cf6 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    
    .login-card {
      background: rgba(255, 255, 255, 0.02);
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 16px;
      padding: 40px;
    }
    
    .login-card h2 {
      font-family: 'Space Grotesk', sans-serif;
      font-size: 24px;
      margin-bottom: 8px;
      text-align: center;
    }
    
    .login-card .subtitle {
      color: #6b7280;
      text-align: center;
      margin-bottom: 32px;
      font-size: 14px;
    }
    
    .form-group {
      margin-bottom: 20px;
    }
    
    .form-group label {
      display: block;
      font-size: 14px;
      color: #6b7280;
      margin-bottom: 8px;
    }
    
    .form-group input {
      width: 100%;
      padding: 14px 16px;
      background: #0a0a0a;
      border: 1px solid #374151;
      border-radius: 8px;
      color: #f5f5f5;
      font-size: 16px;
      transition: all 0.2s;
    }
    
    .form-group input:focus {
      outline: none;
      border-color: #00d4ff;
      box-shadow: 0 0 0 3px rgba(0, 212, 255, 0.1);
    }
    
    .btn-login {
      width: 100%;
      padding: 16px;
      background: linear-gradient(135deg, #00d4ff 0%, #8b5cf6 100%);
      border: none;
      border-radius: 8px;
      color: #0a0a0a;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s;
    }
    
    .btn-login:hover {
      transform: translateY(-2px);
      box-shadow: 0 10px 40px rgba(0, 212, 255, 0.3);
    }
    
    .footer {
      text-align: center;
      margin-top: 32px;
      color: #6b7280;
      font-size: 14px;
    }
    
    .footer a {
      color: #00d4ff;
      text-decoration: none;
    }
  </style>
</head>
<body>
  <div class="login-container">
    <div class="logo">GAIA<span class="ft">FT</span>CL</div>
    
    <div class="login-card">
      <h2>Welcome back</h2>
      <p class="subtitle">Sign in to your account</p>
      
      <form method="post" action="/login">
        <div class="form-group">
          <label for="email">Email</label>
          <input type="email" id="email" name="email" placeholder="you@gaiaftcl.com" required>
        </div>
        
        <div class="form-group">
          <label for="password">Password</label>
          <input type="password" id="password" name="password" placeholder="••••••••••••" required>
        </div>
        
        <button type="submit" class="btn-login">Sign In</button>
      </form>
    </div>
    
    <div class="footer">
      <a href="https://gaiaftcl.com">← Back to GaiaFTCL</a>
    </div>
  </div>
</body>
</html>
```

---

## Part VI: GaiaFTCL Extensions

### 6.1 Truth Envelope Processor

```python
#!/usr/bin/env python3
"""
truth_envelope_processor.py
Hooks into Mailcow to process emails as truth envelopes
"""

import imaplib
import email
import json
import hashlib
import requests
from datetime import datetime
from email.utils import parseaddr

IMAP_HOST = "mail.gaiaftcl.com"
IMAP_PORT = 993
API_URL = "http://localhost:8080/api/v1"
NATS_URL = "nats://localhost:4222"

# Move type detection patterns
MOVE_PATTERNS = {
    "CLAIM": ["i claim", "i assert", "i state", "this is true", "fact:"],
    "REQUEST": ["please", "can you", "could you", "i request", "i need", "i ask"],
    "COMMITMENT": ["i will", "i commit", "i promise", "i pledge", "i guarantee"],
    "REPORT": ["report:", "update:", "status:", "fyi:", "informing"],
    "TRANSACTION": ["transfer", "payment", "send qfot", "pay", "invoice"],
    "FAILURE": ["i failed", "error", "mistake", "i was wrong", "correction"]
}

def detect_move_type(subject: str, body: str) -> str:
    """Detect game move type from email content"""
    text = (subject + " " + body).lower()
    
    for move_type, patterns in MOVE_PATTERNS.items():
        for pattern in patterns:
            if pattern in text:
                return move_type
    
    return "REPORT"  # Default

def create_truth_envelope(msg: email.message.Message) -> dict:
    """Convert email to truth envelope"""
    
    # Extract email metadata
    from_addr = parseaddr(msg["From"])[1]
    to_addrs = [parseaddr(addr)[1] for addr in msg["To"].split(",")]
    subject = msg["Subject"] or ""
    date = msg["Date"]
    message_id = msg["Message-ID"]
    
    # Get body
    body = ""
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == "text/plain":
                body = part.get_payload(decode=True).decode()
                break
    else:
        body = msg.get_payload(decode=True).decode()
    
    # Detect move type
    move_type = detect_move_type(subject, body)
    
    # Create envelope
    envelope = {
        "envelope_id": hashlib.sha256(message_id.encode()).hexdigest()[:16],
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "game_id": "FTCL-EMAIL",
        "move_type": move_type,
        
        "agent": from_addr,
        "recipients": to_addrs,
        
        "content": {
            "subject": subject,
            "body_preview": body[:500],
            "message_id": message_id,
            "headers_hash": hashlib.sha256(str(msg.items()).encode()).hexdigest()
        },
        
        "verification": {
            "dkim": msg.get("DKIM-Signature") is not None,
            "spf": "pass" in msg.get("Received-SPF", ""),
            "envelope_hash": hashlib.sha256(body.encode()).hexdigest()
        },
        
        "cost": calculate_cost(move_type, len(body)),
        "processed": datetime.utcnow().isoformat() + "Z"
    }
    
    return envelope

def calculate_cost(move_type: str, body_length: int) -> dict:
    """Calculate QFOT cost for move"""
    base_costs = {
        "CLAIM": 25.0,
        "REQUEST": 10.0,
        "COMMITMENT": 50.0,
        "REPORT": 5.0,
        "TRANSACTION": 25.0,
        "FAILURE": 0.0
    }
    
    base = base_costs.get(move_type, 5.0)
    size_factor = 1.0 + (body_length / 10000)  # Larger emails cost more
    
    return {
        "base": base,
        "size_factor": size_factor,
        "total": round(base * size_factor, 2),
        "currency": "QFOT"
    }

def process_mailbox(username: str, password: str):
    """Process unread emails in mailbox"""
    
    mail = imaplib.IMAP4_SSL(IMAP_HOST, IMAP_PORT)
    mail.login(username, password)
    mail.select("INBOX")
    
    # Search for unprocessed emails (custom flag)
    _, message_ids = mail.search(None, "NOT", "KEYWORD", "FTCL_PROCESSED")
    
    for msg_id in message_ids[0].split():
        _, msg_data = mail.fetch(msg_id, "(RFC822)")
        msg = email.message_from_bytes(msg_data[0][1])
        
        # Create truth envelope
        envelope = create_truth_envelope(msg)
        
        # Store in ArangoDB
        store_envelope(envelope)
        
        # Publish to NATS
        publish_envelope(envelope)
        
        # Deduct QFOT if applicable
        if envelope["cost"]["total"] > 0:
            deduct_qfot(envelope["agent"], envelope["cost"]["total"])
        
        # Mark as processed
        mail.store(msg_id, "+FLAGS", "FTCL_PROCESSED")
        
        print(f"Processed: {envelope['envelope_id']} ({envelope['move_type']})")
    
    mail.close()
    mail.logout()

def store_envelope(envelope: dict):
    """Store envelope in ArangoDB"""
    # Implementation: POST to ArangoDB API
    pass

def publish_envelope(envelope: dict):
    """Publish envelope to NATS"""
    # Implementation: Publish to ftcl.envelopes subject
    pass

def deduct_qfot(wallet: str, amount: float):
    """Deduct QFOT from wallet"""
    # Implementation: Update wallet balance
    pass

if __name__ == "__main__":
    # Run as daemon or cron
    import sys
    if len(sys.argv) > 2:
        process_mailbox(sys.argv[1], sys.argv[2])
```

### 6.2 Wallet Integration Service

```python
#!/usr/bin/env python3
"""
wallet_service.py
Manage QFOT wallets tied to email addresses
"""

from flask import Flask, jsonify, request
from arango import ArangoClient
import os

app = Flask(__name__)

# ArangoDB connection
client = ArangoClient()
db = client.db('gaiaftcl', username='root', password=os.environ['ARANGO_PASSWORD'])
wallets = db.collection('wallets')

@app.route('/api/v1/wallet/<email>')
def get_wallet(email: str):
    """Get wallet balance"""
    wallet = wallets.get(email.replace('@', '_').replace('.', '_'))
    if not wallet:
        return jsonify({"error": "Wallet not found"}), 404
    
    return jsonify({
        "email": email,
        "qfot": wallet.get("qfot", 0.0),
        "qfot_c": wallet.get("qfot_c", 0.0),
        "qfot_c_expires": wallet.get("qfot_c_expires"),
        "created": wallet.get("created")
    })

@app.route('/api/v1/wallet/<email>/deduct', methods=['POST'])
def deduct(email: str):
    """Deduct QFOT from wallet"""
    data = request.json
    amount = data.get("amount", 0)
    reason = data.get("reason", "game_move")
    
    wallet_key = email.replace('@', '_').replace('.', '_')
    wallet = wallets.get(wallet_key)
    
    if not wallet:
        return jsonify({"error": "Wallet not found"}), 404
    
    # Try QFOT-C first, then QFOT
    qfot_c = wallet.get("qfot_c", 0.0)
    qfot = wallet.get("qfot", 0.0)
    
    if qfot_c >= amount:
        wallets.update({
            "_key": wallet_key,
            "qfot_c": qfot_c - amount
        })
        source = "qfot_c"
    elif qfot >= amount:
        wallets.update({
            "_key": wallet_key,
            "qfot": qfot - amount
        })
        source = "qfot"
    else:
        return jsonify({"error": "Insufficient balance"}), 400
    
    # Log transaction
    db.collection('transactions').insert({
        "wallet": email,
        "amount": -amount,
        "source": source,
        "reason": reason,
        "timestamp": datetime.utcnow().isoformat()
    })
    
    return jsonify({"success": True, "deducted": amount, "source": source})

@app.route('/api/v1/wallet/<email>/deposit', methods=['POST'])
def deposit(email: str):
    """Deposit QFOT to wallet (after stablecoin confirmation)"""
    data = request.json
    amount = data.get("amount", 0)
    tx_hash = data.get("tx_hash")
    
    wallet_key = email.replace('@', '_').replace('.', '_')
    wallet = wallets.get(wallet_key)
    
    if not wallet:
        # Create wallet if doesn't exist
        wallets.insert({
            "_key": wallet_key,
            "email": email,
            "qfot": amount,
            "qfot_c": 0,
            "created": datetime.utcnow().isoformat()
        })
    else:
        wallets.update({
            "_key": wallet_key,
            "qfot": wallet.get("qfot", 0) + amount
        })
    
    # Log transaction
    db.collection('transactions').insert({
        "wallet": email,
        "amount": amount,
        "source": "deposit",
        "tx_hash": tx_hash,
        "timestamp": datetime.utcnow().isoformat()
    })
    
    return jsonify({"success": True, "deposited": amount})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8081)
```

### 6.3 Treasury Dashboard Extension

```python
#!/usr/bin/env python3
"""
treasury_dashboard.py
Admin dashboard extension for treasury management
"""

from flask import Flask, render_template, jsonify, request
from arango import ArangoClient
import os

app = Flask(__name__)

# Database
client = ArangoClient()
db = client.db('gaiaftcl', username='root', password=os.environ['ARANGO_PASSWORD'])

@app.route('/admin/treasury')
def treasury_dashboard():
    """Main treasury dashboard"""
    
    # Get aggregates
    wallets = db.collection('wallets')
    transactions = db.collection('transactions')
    
    total_qfot = sum(w['qfot'] for w in wallets.all())
    total_qfot_c = sum(w['qfot_c'] for w in wallets.all())
    total_wallets = wallets.count()
    
    # Recent transactions
    recent_txs = list(transactions.find({}, limit=50, sort='timestamp DESC'))
    
    # Daily stats
    daily_stats = db.aql.execute('''
        FOR t IN transactions
        COLLECT date = DATE_FORMAT(t.timestamp, "%Y-%m-%d")
        AGGREGATE 
            deposits = SUM(t.amount > 0 ? t.amount : 0),
            spending = SUM(t.amount < 0 ? ABS(t.amount) : 0),
            count = COUNT(1)
        SORT date DESC
        LIMIT 30
        RETURN { date, deposits, spending, count }
    ''').batch()
    
    return render_template('treasury.html',
        total_qfot=total_qfot,
        total_qfot_c=total_qfot_c,
        total_wallets=total_wallets,
        recent_txs=recent_txs,
        daily_stats=daily_stats
    )

@app.route('/admin/treasury/wallets')
def list_wallets():
    """List all wallets with balances"""
    wallets = list(db.collection('wallets').all())
    return render_template('wallets.html', wallets=wallets)

@app.route('/admin/treasury/mint', methods=['POST'])
def mint_qfot():
    """Mint QFOT (requires stablecoin proof)"""
    data = request.json
    email = data.get('email')
    amount = data.get('amount')
    tx_hash = data.get('tx_hash')
    
    # Verify stablecoin transaction
    # TODO: Implement blockchain verification
    
    # Mint QFOT
    wallet_key = email.replace('@', '_').replace('.', '_')
    wallet = db.collection('wallets').get(wallet_key)
    
    if wallet:
        db.collection('wallets').update({
            "_key": wallet_key,
            "qfot": wallet['qfot'] + amount
        })
    else:
        db.collection('wallets').insert({
            "_key": wallet_key,
            "email": email,
            "qfot": amount,
            "qfot_c": 0
        })
    
    # Log mint
    db.collection('treasury_log').insert({
        "action": "mint",
        "email": email,
        "amount": amount,
        "tx_hash": tx_hash,
        "timestamp": datetime.utcnow().isoformat()
    })
    
    return jsonify({"success": True})

@app.route('/admin/treasury/burn', methods=['POST'])
def burn_qfot():
    """Burn QFOT (payout)"""
    data = request.json
    email = data.get('email')
    amount = data.get('amount')
    reason = data.get('reason')
    
    wallet_key = email.replace('@', '_').replace('.', '_')
    wallet = db.collection('wallets').get(wallet_key)
    
    if not wallet or wallet['qfot'] < amount:
        return jsonify({"error": "Insufficient balance"}), 400
    
    db.collection('wallets').update({
        "_key": wallet_key,
        "qfot": wallet['qfot'] - amount
    })
    
    # Log burn
    db.collection('treasury_log').insert({
        "action": "burn",
        "email": email,
        "amount": amount,
        "reason": reason,
        "timestamp": datetime.utcnow().isoformat()
    })
    
    return jsonify({"success": True})

@app.route('/admin/treasury/grant-credits', methods=['POST'])
def grant_credits():
    """Grant QFOT-C credits"""
    data = request.json
    email = data.get('email')
    amount = data.get('amount')
    expires_days = data.get('expires_days', 90)
    reason = data.get('reason')
    
    wallet_key = email.replace('@', '_').replace('.', '_')
    wallet = db.collection('wallets').get(wallet_key)
    
    expiry = (datetime.utcnow() + timedelta(days=expires_days)).isoformat()
    
    if wallet:
        db.collection('wallets').update({
            "_key": wallet_key,
            "qfot_c": wallet.get('qfot_c', 0) + amount,
            "qfot_c_expires": expiry
        })
    else:
        db.collection('wallets').insert({
            "_key": wallet_key,
            "email": email,
            "qfot": 0,
            "qfot_c": amount,
            "qfot_c_expires": expiry
        })
    
    return jsonify({"success": True})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8082)
```

### 6.4 Treasury Dashboard Template

```html
<!-- templates/treasury.html -->
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Treasury — GaiaFTCL Admin</title>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Space+Grotesk:wght@700&family=JetBrains+Mono&display=swap" rel="stylesheet">
  <style>
    :root {
      --gaia-black: #0a0a0a;
      --gaia-white: #f5f5f5;
      --gaia-blue: #00d4ff;
      --gaia-purple: #8b5cf6;
      --gaia-green: #10b981;
      --gaia-red: #ef4444;
      --gaia-gray: #374151;
    }
    
    * { margin: 0; padding: 0; box-sizing: border-box; }
    
    body {
      background: var(--gaia-black);
      color: var(--gaia-white);
      font-family: 'Inter', sans-serif;
      padding: 24px;
    }
    
    h1, h2, h3 { font-family: 'Space Grotesk', sans-serif; }
    code, .mono { font-family: 'JetBrains Mono', monospace; }
    
    .header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 32px;
      padding-bottom: 16px;
      border-bottom: 1px solid rgba(255,255,255,0.1);
    }
    
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 24px;
      margin-bottom: 32px;
    }
    
    .stat-card {
      background: rgba(255,255,255,0.02);
      border: 1px solid rgba(255,255,255,0.1);
      border-radius: 12px;
      padding: 24px;
    }
    
    .stat-value {
      font-family: 'Space Grotesk', sans-serif;
      font-size: 36px;
      font-weight: 700;
      background: linear-gradient(135deg, #00d4ff, #8b5cf6);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    
    .stat-label {
      color: #6b7280;
      font-size: 14px;
      margin-top: 4px;
    }
    
    .section {
      background: rgba(255,255,255,0.02);
      border: 1px solid rgba(255,255,255,0.1);
      border-radius: 12px;
      padding: 24px;
      margin-bottom: 24px;
    }
    
    .section h3 {
      margin-bottom: 16px;
      font-size: 18px;
    }
    
    table {
      width: 100%;
      border-collapse: collapse;
    }
    
    th, td {
      text-align: left;
      padding: 12px;
      border-bottom: 1px solid rgba(255,255,255,0.05);
    }
    
    th {
      color: #6b7280;
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.05em;
    }
    
    .amount-positive { color: var(--gaia-green); }
    .amount-negative { color: var(--gaia-red); }
    
    .btn {
      padding: 10px 20px;
      background: linear-gradient(135deg, #00d4ff, #8b5cf6);
      border: none;
      border-radius: 8px;
      color: var(--gaia-black);
      font-weight: 600;
      cursor: pointer;
    }
    
    .btn:hover {
      box-shadow: 0 4px 20px rgba(0,212,255,0.3);
    }
    
    .action-buttons {
      display: flex;
      gap: 12px;
      margin-bottom: 24px;
    }
  </style>
</head>
<body>
  <div class="header">
    <h1>Treasury Dashboard</h1>
    <div class="action-buttons">
      <button class="btn" onclick="showMintModal()">Mint QFOT</button>
      <button class="btn" onclick="showGrantModal()">Grant Credits</button>
      <button class="btn" onclick="exportData()">Export</button>
    </div>
  </div>
  
  <div class="stats-grid">
    <div class="stat-card">
      <div class="stat-value">{{ "{:,.2f}".format(total_qfot) }}</div>
      <div class="stat-label">Total QFOT (Circulation)</div>
    </div>
    <div class="stat-card">
      <div class="stat-value">{{ "{:,.2f}".format(total_qfot_c) }}</div>
      <div class="stat-label">Total QFOT-C (Credits)</div>
    </div>
    <div class="stat-card">
      <div class="stat-value">{{ total_wallets }}</div>
      <div class="stat-label">Active Wallets</div>
    </div>
    <div class="stat-card">
      <div class="stat-value">${{ "{:,.2f}".format(total_qfot) }}</div>
      <div class="stat-label">USD Reserve Required</div>
    </div>
  </div>
  
  <div class="section">
    <h3>Recent Transactions</h3>
    <table>
      <thead>
        <tr>
          <th>Time</th>
          <th>Wallet</th>
          <th>Type</th>
          <th>Amount</th>
          <th>Reason</th>
        </tr>
      </thead>
      <tbody>
        {% for tx in recent_txs %}
        <tr>
          <td class="mono">{{ tx.timestamp[:19] }}</td>
          <td class="mono">{{ tx.wallet }}</td>
          <td>{{ tx.source }}</td>
          <td class="{{ 'amount-positive' if tx.amount > 0 else 'amount-negative' }}">
            {{ "{:+,.2f}".format(tx.amount) }} QFOT
          </td>
          <td>{{ tx.reason or '-' }}</td>
        </tr>
        {% endfor %}
      </tbody>
    </table>
  </div>
  
  <div class="section">
    <h3>Daily Activity (Last 30 Days)</h3>
    <table>
      <thead>
        <tr>
          <th>Date</th>
          <th>Deposits</th>
          <th>Spending</th>
          <th>Net</th>
          <th>Transactions</th>
        </tr>
      </thead>
      <tbody>
        {% for day in daily_stats %}
        <tr>
          <td class="mono">{{ day.date }}</td>
          <td class="amount-positive">+{{ "{:,.2f}".format(day.deposits) }}</td>
          <td class="amount-negative">-{{ "{:,.2f}".format(day.spending) }}</td>
          <td class="{{ 'amount-positive' if (day.deposits - day.spending) >= 0 else 'amount-negative' }}">
            {{ "{:+,.2f}".format(day.deposits - day.spending) }}
          </td>
          <td>{{ day.count }}</td>
        </tr>
        {% endfor %}
      </tbody>
    </table>
  </div>
</body>
</html>
```

---

## Part VII: Agent Mailboxes

### 7.1 System Agents Setup

```bash
#!/bin/bash
# setup_agent_mailboxes.sh

API_URL="https://mail.gaiaftcl.com/api/v1"
API_KEY="YOUR_API_KEY"

# Agent mailboxes to create
AGENTS=(
  "franklin:Constitutional Guardian:franklin_guardian_password"
  "gaia:Planetary Coordinator:gaia_coordinator_password"
  "fara:Field-Aware Reasoning Agent:fara_agent_password"
  "qstate:Quantum State Manager:qstate_manager_password"
  "validator:Truth Validator:validator_agent_password"
  "witness:Audit Witness:witness_agent_password"
  "oracle:Data Oracle:oracle_agent_password"
  "gamerunner:Game Executor:gamerunner_agent_password"
  "virtue:Ethics Engine:virtue_engine_password"
  "ben:Investment Manager:ben_manager_password"
  "treasury:Treasury System:treasury_system_password"
  "support:Support System:support_system_password"
  "noreply:No Reply:noreply_system_password"
)

for agent_data in "${AGENTS[@]}"; do
  IFS=':' read -r username description password <<< "$agent_data"
  
  echo "Creating agent mailbox: ${username}@gaiaftcl.com"
  
  curl -s -X POST "${API_URL}/add/mailbox" \
    -H "X-API-Key: ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
      \"local_part\": \"${username}\",
      \"domain\": \"gaiaftcl.com\",
      \"name\": \"${description}\",
      \"password\": \"${password}\",
      \"password2\": \"${password}\",
      \"quota\": 10240,
      \"active\": 1,
      \"force_pw_update\": 0
    }"
  
  echo ""
done

# Create aliases
ALIASES=(
  "admin:founder@gaiaftcl.com"
  "postmaster:founder@gaiaftcl.com"
  "abuse:founder@gaiaftcl.com"
  "security:founder@gaiaftcl.com"
  "dmarc:founder@gaiaftcl.com"
)

for alias_data in "${ALIASES[@]}"; do
  IFS=':' read -r alias_name target <<< "$alias_data"
  
  echo "Creating alias: ${alias_name}@gaiaftcl.com -> ${target}"
  
  curl -s -X POST "${API_URL}/add/alias" \
    -H "X-API-Key: ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
      \"address\": \"${alias_name}@gaiaftcl.com\",
      \"goto\": \"${target}\",
      \"active\": 1
    }"
  
  echo ""
done

echo "Agent mailboxes created"
```

---

## Part VIII: Docker Compose Override

### 8.1 Full Stack with Extensions

```yaml
# docker-compose.gaiaftcl.yml
# Run with: docker compose -f docker-compose.yml -f docker-compose.gaiaftcl.yml up -d

version: '3.8'

services:
  # GaiaFTCL Extensions
  gaiaftcl-wallet:
    build: ./extensions/wallet
    container_name: gaiaftcl-wallet
    restart: always
    environment:
      - ARANGO_PASSWORD=${ARANGO_PASSWORD}
      - ARANGO_HOST=arangodb
    ports:
      - "8081:8081"
    networks:
      - mailcow-network
    depends_on:
      - arangodb

  gaiaftcl-treasury:
    build: ./extensions/treasury
    container_name: gaiaftcl-treasury
    restart: always
    environment:
      - ARANGO_PASSWORD=${ARANGO_PASSWORD}
      - ARANGO_HOST=arangodb
    ports:
      - "8082:8082"
    networks:
      - mailcow-network
    depends_on:
      - arangodb

  gaiaftcl-envelope:
    build: ./extensions/envelope
    container_name: gaiaftcl-envelope
    restart: always
    environment:
      - IMAP_HOST=dovecot-mailcow
      - ARANGO_PASSWORD=${ARANGO_PASSWORD}
      - NATS_URL=nats://nats:4222
    networks:
      - mailcow-network
    depends_on:
      - dovecot-mailcow
      - arangodb
      - nats

  # ArangoDB for wallets/twins/envelopes
  arangodb:
    image: arangodb:3.11
    container_name: gaiaftcl-arangodb
    restart: always
    environment:
      - ARANGO_ROOT_PASSWORD=${ARANGO_PASSWORD}
    volumes:
      - arangodb_data:/var/lib/arangodb3
    ports:
      - "8529:8529"
    networks:
      - mailcow-network

  # NATS for event streaming
  nats:
    image: nats:2.10-alpine
    container_name: gaiaftcl-nats
    restart: always
    command: ["--jetstream", "--store_dir=/data"]
    volumes:
      - nats_data:/data
    ports:
      - "4222:4222"
      - "8222:8222"
    networks:
      - mailcow-network

volumes:
  arangodb_data:
  nats_data:

networks:
  mailcow-network:
    external: true
    name: mailcowdockerized_mailcow-network
```

---

## Part IX: Deployment Checklist

### 9.1 Full Deployment Steps

```markdown
## Phase 1: Primary Server (nbg1-01)

- [ ] Run prerequisites.sh
- [ ] Run install_mailcow_primary.sh
- [ ] Access admin UI, change password
- [ ] Create gaiaftcl.com domain
- [ ] Generate DKIM keys
- [ ] Apply SOGo theme (install_sogo_theme.sh)
- [ ] Apply admin theme (brand_admin_ui.sh)
- [ ] Deploy custom login page

## Phase 2: DNS

- [ ] Update MX records
- [ ] Add SPF record
- [ ] Add DKIM record (from Mailcow)
- [ ] Add DMARC record
- [ ] Add autodiscover/autoconfig CNAME
- [ ] Lower TTL before cutover

## Phase 3: Backup MX (hel1-01)

- [ ] Run prerequisites.sh
- [ ] Run install_mailcow_backup.sh
- [ ] Configure relay to primary
- [ ] Test failover

## Phase 4: Relays (Other Cells)

- [ ] Run install_relay.sh on each cell
- [ ] Configure SASL credentials
- [ ] Test sending through primary

## Phase 5: Migration

- [ ] Run migrate_maddy_to_mailcow.sh
- [ ] Verify all users migrated
- [ ] Sync mailboxes with imapsync
- [ ] Update DNS MX records
- [ ] Disable Maddy

## Phase 6: Extensions

- [ ] Deploy ArangoDB
- [ ] Deploy NATS
- [ ] Deploy wallet service
- [ ] Deploy treasury dashboard
- [ ] Deploy envelope processor
- [ ] Run setup_agent_mailboxes.sh

## Phase 7: Testing

- [ ] Test webmail login
- [ ] Test IMAP/SMTP clients
- [ ] Test sending/receiving
- [ ] Test admin functions
- [ ] Test wallet integration
- [ ] Test treasury dashboard
- [ ] Test envelope processing

## Phase 8: Production

- [ ] Increase DNS TTL
- [ ] Enable monitoring
- [ ] Configure backups
- [ ] Document procedures
```

---

## Appendix A: Quick Reference

### Mailcow URLs

| Service | URL |
|---------|-----|
| Admin UI | https://mail.gaiaftcl.com |
| Webmail (SOGo) | https://mail.gaiaftcl.com/SOGo |
| API Docs | https://mail.gaiaftcl.com/api |
| Rspamd | https://mail.gaiaftcl.com/rspamd |

### Ports

| Port | Service |
|------|---------|
| 25 | SMTP |
| 465 | SMTPS |
| 587 | Submission |
| 143 | IMAP |
| 993 | IMAPS |
| 443 | HTTPS |
| 8529 | ArangoDB |
| 4222 | NATS |

### API Endpoints (Custom)

| Endpoint | Function |
|----------|----------|
| GET /api/v1/wallet/{email} | Get wallet balance |
| POST /api/v1/wallet/{email}/deduct | Deduct QFOT |
| POST /api/v1/wallet/{email}/deposit | Deposit QFOT |
| GET /admin/treasury | Treasury dashboard |
| POST /admin/treasury/mint | Mint QFOT |
| POST /admin/treasury/grant-credits | Grant QFOT-C |

---

*This specification is the canonical reference for GaiaFTCL enterprise email infrastructure.*
