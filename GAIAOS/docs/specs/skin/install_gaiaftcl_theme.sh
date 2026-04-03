#!/bin/bash
# install_gaiaftcl_theme.sh
# Install GaiaFTCL branding on Mailcow
# Run on nbg1-01 (primary mail server)

set -e

MAILCOW_DIR="/opt/mailcow-dockerized"
cd ${MAILCOW_DIR}

echo "Installing GaiaFTCL Theme..."

# ============================================
# 1. SOGo Custom CSS
# ============================================

mkdir -p data/conf/sogo

cat > data/conf/sogo/custom-theme.css << 'CSS'
/* ============================================
   GaiaFTCL SOGo Theme
   ============================================ */

:root {
  --gaia-black: #0a0a0a;
  --gaia-darker: #050505;
  --gaia-white: #f5f5f5;
  --gaia-blue: #00d4ff;
  --gaia-purple: #8b5cf6;
  --gaia-green: #10b981;
  --gaia-red: #ef4444;
  --gaia-yellow: #f59e0b;
  --gaia-gray: #374151;
  --gaia-gray-light: #6b7280;
}

/* === Global === */
body {
  background-color: var(--gaia-black) !important;
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif !important;
}

/* === Toolbar === */
md-toolbar,
.md-toolbar-tools,
.sg-toolbar {
  background: linear-gradient(135deg, #0a0a0a 0%, #1a1a2e 100%) !important;
  border-bottom: 1px solid rgba(0, 212, 255, 0.2) !important;
}

.md-toolbar-tools .md-button {
  color: var(--gaia-white) !important;
}

/* === Sidebar === */
md-sidenav,
.sg-sidenav,
.md-sidenav-left {
  background-color: var(--gaia-darker) !important;
  border-right: 1px solid rgba(255, 255, 255, 0.1) !important;
}

.sg-folder-list md-list-item {
  color: var(--gaia-gray-light) !important;
}

.sg-folder-list md-list-item:hover,
.sg-folder-list md-list-item.sg-active {
  background-color: rgba(0, 212, 255, 0.1) !important;
  color: var(--gaia-blue) !important;
}

.sg-folder-list md-list-item.sg-active {
  border-left: 3px solid var(--gaia-blue) !important;
}

/* === Cards === */
md-card,
.md-whiteframe-1dp,
.md-whiteframe-2dp,
.md-whiteframe-3dp {
  background-color: rgba(255, 255, 255, 0.02) !important;
  border: 1px solid rgba(255, 255, 255, 0.1) !important;
  border-radius: 8px !important;
}

/* === Text === */
body,
p,
span,
div,
.md-subhead,
.md-body-1,
.md-body-2,
md-list-item {
  color: var(--gaia-white) !important;
}

.md-caption,
.md-hint,
label {
  color: var(--gaia-gray-light) !important;
}

/* === Accent Colors === */
.md-primary,
a:not(.md-button),
.sg-active,
.md-focused {
  color: var(--gaia-blue) !important;
}

/* === Buttons === */
.md-button.md-raised.md-primary,
.md-button.md-fab.md-primary {
  background: linear-gradient(135deg, #00d4ff 0%, #8b5cf6 100%) !important;
  color: var(--gaia-black) !important;
}

.md-button.md-raised.md-primary:hover,
.md-button.md-fab.md-primary:hover {
  box-shadow: 0 4px 20px rgba(0, 212, 255, 0.4) !important;
}

.md-button:not(.md-raised):not(.md-fab) {
  color: var(--gaia-white) !important;
}

/* === Input Fields === */
md-input-container input,
md-input-container textarea,
.md-input {
  color: var(--gaia-white) !important;
  border-color: var(--gaia-gray) !important;
}

md-input-container.md-input-focused input,
md-input-container.md-input-focused textarea {
  border-color: var(--gaia-blue) !important;
}

md-input-container.md-input-focused label {
  color: var(--gaia-blue) !important;
}

/* === Mail List === */
.sg-mail-list md-list-item {
  border-bottom: 1px solid rgba(255, 255, 255, 0.05) !important;
}

.sg-mail-list md-list-item:hover {
  background-color: rgba(0, 212, 255, 0.05) !important;
}

.sg-mail-list md-list-item.sg-active,
.sg-mail-list md-list-item[selected] {
  background-color: rgba(0, 212, 255, 0.1) !important;
  border-left: 3px solid var(--gaia-blue) !important;
}

/* Unread */
.sg-mail-unread .sg-tile-content,
.sg-mail-unread .sg-md-subhead {
  font-weight: 600 !important;
  color: var(--gaia-blue) !important;
}

/* === Compose FAB === */
.sg-compose-fab,
.md-fab {
  background: linear-gradient(135deg, #00d4ff 0%, #8b5cf6 100%) !important;
}

/* === Dialogs === */
md-dialog,
.md-dialog-container {
  background-color: var(--gaia-black) !important;
  border: 1px solid rgba(0, 212, 255, 0.2) !important;
  border-radius: 12px !important;
}

md-dialog-content {
  background-color: var(--gaia-black) !important;
}

md-dialog-actions {
  background-color: var(--gaia-darker) !important;
  border-top: 1px solid rgba(255, 255, 255, 0.1) !important;
}

/* === Checkboxes & Radio === */
md-checkbox .md-icon,
md-radio-button .md-off {
  border-color: var(--gaia-gray) !important;
}

md-checkbox.md-checked .md-icon {
  background-color: var(--gaia-blue) !important;
}

/* === Progress/Loading === */
md-progress-circular path,
md-progress-linear .md-bar {
  stroke: var(--gaia-blue) !important;
  background-color: var(--gaia-blue) !important;
}

/* === Scrollbars === */
::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}

::-webkit-scrollbar-track {
  background: var(--gaia-black);
}

::-webkit-scrollbar-thumb {
  background: var(--gaia-gray);
  border-radius: 4px;
}

::-webkit-scrollbar-thumb:hover {
  background: var(--gaia-blue);
}

/* === Calendar === */
.sg-calendar-day.sg-active,
.sg-event {
  background-color: rgba(139, 92, 246, 0.2) !important;
  border-left: 3px solid var(--gaia-purple) !important;
}

/* === Contacts === */
.sg-contact-avatar,
.sg-avatar {
  background: linear-gradient(135deg, #00d4ff 0%, #8b5cf6 100%) !important;
}

/* === Notifications/Toast === */
md-toast {
  background-color: var(--gaia-gray) !important;
}

md-toast.md-success-toast-theme {
  background-color: var(--gaia-green) !important;
}

md-toast.md-warn-toast-theme {
  background-color: var(--gaia-red) !important;
}

/* === Menu === */
md-menu-content {
  background-color: var(--gaia-darker) !important;
  border: 1px solid rgba(255, 255, 255, 0.1) !important;
}

md-menu-item {
  color: var(--gaia-white) !important;
}

md-menu-item:hover {
  background-color: rgba(0, 212, 255, 0.1) !important;
}

/* === Chips/Tags === */
md-chip,
.md-chip {
  background-color: rgba(0, 212, 255, 0.1) !important;
  color: var(--gaia-blue) !important;
  border: 1px solid rgba(0, 212, 255, 0.3) !important;
}

/* === Tabs === */
md-tabs-wrapper {
  background-color: var(--gaia-darker) !important;
}

md-tab-item {
  color: var(--gaia-gray-light) !important;
}

md-tab-item.md-active {
  color: var(--gaia-blue) !important;
}

md-ink-bar {
  background-color: var(--gaia-blue) !important;
}

/* === Footer === */
.sg-footer {
  background-color: var(--gaia-darker) !important;
  border-top: 1px solid rgba(255, 255, 255, 0.1) !important;
  color: var(--gaia-gray-light) !important;
}

/* === Select/Dropdown === */
md-select-value,
md-option {
  color: var(--gaia-white) !important;
}

md-select-menu md-content {
  background-color: var(--gaia-darker) !important;
}

md-option:hover,
md-option[selected] {
  background-color: rgba(0, 212, 255, 0.1) !important;
}

/* === Empty State === */
.sg-empty-state {
  color: var(--gaia-gray-light) !important;
}

/* === Loading Overlay === */
.sg-loading {
  background-color: rgba(10, 10, 10, 0.9) !important;
}
CSS

echo "  [✓] SOGo CSS created"

# ============================================
# 2. Logo SVG
# ============================================

mkdir -p data/web/img

cat > data/web/img/gaiaftcl-logo.svg << 'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 48">
  <defs>
    <linearGradient id="gaia-gradient" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" style="stop-color:#00d4ff"/>
      <stop offset="100%" style="stop-color:#8b5cf6"/>
    </linearGradient>
  </defs>
  <text x="0" y="36" font-family="Space Grotesk, sans-serif" font-size="32" font-weight="700" fill="#f5f5f5" letter-spacing="0.05em">
    GAIA
  </text>
  <text x="90" y="36" font-family="Space Grotesk, sans-serif" font-size="32" font-weight="700" fill="url(#gaia-gradient)" letter-spacing="0.05em">
    FT
  </text>
  <text x="142" y="36" font-family="Space Grotesk, sans-serif" font-size="32" font-weight="700" fill="#f5f5f5" letter-spacing="0.05em">
    CL
  </text>
</svg>
SVG

echo "  [✓] Logo SVG created"

# ============================================
# 3. Favicon
# ============================================

# Create a simple favicon using base64 encoded PNG
# This is a 32x32 PNG with the GaiaFTCL colors
cat > data/web/img/favicon.ico << 'FAVICON'
AAABAAEAICAAAAEAIACoEAAAFgAAACgAAAAgAAAAQAAAAAEAIAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABQ0NlECgorMQECgv/AAAAAAAA
FAVICON

echo "  [✓] Favicon created (placeholder)"

# ============================================
# 4. Mailcow Admin CSS Override
# ============================================

mkdir -p data/web/css

cat > data/web/css/gaiaftcl-admin.css << 'ADMINCSS'
/* GaiaFTCL Mailcow Admin Theme */

@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Space+Grotesk:wght@500;700&family=JetBrains+Mono:wght@400;500&display=swap');

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

body {
  background: var(--gaia-black) !important;
  color: var(--gaia-white) !important;
  font-family: 'Inter', sans-serif !important;
}

/* Navbar */
.navbar,
.navbar-default,
.navbar-dark {
  background: linear-gradient(135deg, #0a0a0a 0%, #1a1a2e 100%) !important;
  border-bottom: 1px solid rgba(0, 212, 255, 0.2) !important;
}

.navbar-brand {
  font-family: 'Space Grotesk', sans-serif !important;
  font-weight: 700 !important;
  font-size: 20px !important;
  letter-spacing: 0.1em !important;
  color: var(--gaia-white) !important;
}

.nav-link {
  color: var(--gaia-gray-light) !important;
}

.nav-link:hover,
.nav-link.active {
  color: var(--gaia-blue) !important;
}

/* Cards */
.card {
  background: rgba(255, 255, 255, 0.02) !important;
  border: 1px solid rgba(255, 255, 255, 0.1) !important;
  border-radius: 12px !important;
}

.card-header {
  background: rgba(255, 255, 255, 0.02) !important;
  border-bottom: 1px solid rgba(255, 255, 255, 0.1) !important;
  color: var(--gaia-white) !important;
}

.card-body {
  color: var(--gaia-white) !important;
}

/* Tables */
.table {
  color: var(--gaia-white) !important;
}

.table th {
  color: var(--gaia-gray-light) !important;
  border-color: rgba(255, 255, 255, 0.1) !important;
  font-size: 12px !important;
  text-transform: uppercase !important;
  letter-spacing: 0.05em !important;
}

.table td {
  border-color: rgba(255, 255, 255, 0.05) !important;
}

.table-striped tbody tr:nth-of-type(odd) {
  background-color: rgba(255, 255, 255, 0.02) !important;
}

.table-hover tbody tr:hover {
  background-color: rgba(0, 212, 255, 0.05) !important;
}

/* Buttons */
.btn-primary {
  background: linear-gradient(135deg, #00d4ff 0%, #8b5cf6 100%) !important;
  border: none !important;
  color: var(--gaia-black) !important;
  font-weight: 600 !important;
}

.btn-primary:hover {
  box-shadow: 0 4px 20px rgba(0, 212, 255, 0.3) !important;
  transform: translateY(-1px);
}

.btn-secondary,
.btn-default {
  background: var(--gaia-gray) !important;
  border: none !important;
  color: var(--gaia-white) !important;
}

.btn-success {
  background: var(--gaia-green) !important;
  border: none !important;
}

.btn-danger {
  background: var(--gaia-red) !important;
  border: none !important;
}

/* Forms */
.form-control {
  background: var(--gaia-black) !important;
  border: 1px solid var(--gaia-gray) !important;
  color: var(--gaia-white) !important;
  border-radius: 8px !important;
}

.form-control:focus {
  border-color: var(--gaia-blue) !important;
  box-shadow: 0 0 0 3px rgba(0, 212, 255, 0.1) !important;
}

.form-control::placeholder {
  color: var(--gaia-gray-light) !important;
}

label {
  color: var(--gaia-gray-light) !important;
}

/* Sidebar */
.sidebar,
.nav-sidebar {
  background: var(--gaia-darker) !important;
}

.sidebar .nav-link {
  color: var(--gaia-gray-light) !important;
  border-radius: 8px !important;
  margin: 2px 8px !important;
}

.sidebar .nav-link:hover,
.sidebar .nav-link.active {
  background: rgba(0, 212, 255, 0.1) !important;
  color: var(--gaia-blue) !important;
}

/* Alerts */
.alert-success {
  background: rgba(16, 185, 129, 0.1) !important;
  border: 1px solid var(--gaia-green) !important;
  color: var(--gaia-green) !important;
}

.alert-danger {
  background: rgba(239, 68, 68, 0.1) !important;
  border: 1px solid var(--gaia-red) !important;
  color: var(--gaia-red) !important;
}

.alert-warning {
  background: rgba(245, 158, 11, 0.1) !important;
  border: 1px solid var(--gaia-yellow) !important;
  color: var(--gaia-yellow) !important;
}

.alert-info {
  background: rgba(0, 212, 255, 0.1) !important;
  border: 1px solid var(--gaia-blue) !important;
  color: var(--gaia-blue) !important;
}

/* Badges */
.badge-primary {
  background: var(--gaia-blue) !important;
  color: var(--gaia-black) !important;
}

.badge-success {
  background: var(--gaia-green) !important;
}

.badge-danger {
  background: var(--gaia-red) !important;
}

/* Modals */
.modal-content {
  background: var(--gaia-black) !important;
  border: 1px solid rgba(0, 212, 255, 0.2) !important;
  border-radius: 12px !important;
}

.modal-header {
  border-bottom: 1px solid rgba(255, 255, 255, 0.1) !important;
}

.modal-footer {
  border-top: 1px solid rgba(255, 255, 255, 0.1) !important;
}

/* Dropdown */
.dropdown-menu {
  background: var(--gaia-darker) !important;
  border: 1px solid rgba(255, 255, 255, 0.1) !important;
}

.dropdown-item {
  color: var(--gaia-white) !important;
}

.dropdown-item:hover {
  background: rgba(0, 212, 255, 0.1) !important;
  color: var(--gaia-blue) !important;
}

/* Stats/Counters */
.card-counter {
  background: linear-gradient(135deg, rgba(0, 212, 255, 0.1) 0%, rgba(139, 92, 246, 0.1) 100%) !important;
  border: 1px solid rgba(0, 212, 255, 0.2) !important;
  border-radius: 12px !important;
}

.card-counter .count-numbers {
  color: var(--gaia-blue) !important;
  font-family: 'Space Grotesk', sans-serif !important;
  font-size: 32px !important;
  font-weight: 700 !important;
}

.card-counter .count-name {
  color: var(--gaia-gray-light) !important;
}

/* Pagination */
.page-link {
  background: var(--gaia-black) !important;
  border-color: var(--gaia-gray) !important;
  color: var(--gaia-white) !important;
}

.page-link:hover {
  background: rgba(0, 212, 255, 0.1) !important;
  border-color: var(--gaia-blue) !important;
  color: var(--gaia-blue) !important;
}

.page-item.active .page-link {
  background: var(--gaia-blue) !important;
  border-color: var(--gaia-blue) !important;
  color: var(--gaia-black) !important;
}

/* Progress */
.progress {
  background: var(--gaia-gray) !important;
  border-radius: 8px !important;
}

.progress-bar {
  background: linear-gradient(135deg, #00d4ff 0%, #8b5cf6 100%) !important;
}

/* Code */
code {
  font-family: 'JetBrains Mono', monospace !important;
  background: rgba(0, 212, 255, 0.1) !important;
  color: var(--gaia-blue) !important;
  padding: 2px 6px !important;
  border-radius: 4px !important;
}

pre {
  background: var(--gaia-darker) !important;
  border: 1px solid rgba(255, 255, 255, 0.1) !important;
  border-radius: 8px !important;
  color: var(--gaia-white) !important;
}

/* Scrollbars */
::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}

::-webkit-scrollbar-track {
  background: var(--gaia-black);
}

::-webkit-scrollbar-thumb {
  background: var(--gaia-gray);
  border-radius: 4px;
}

::-webkit-scrollbar-thumb:hover {
  background: var(--gaia-blue);
}
ADMINCSS

echo "  [✓] Admin CSS created"

# ============================================
# 5. Apply Theme
# ============================================

echo ""
echo "Applying theme to containers..."

# Copy SOGo CSS into container
docker cp data/conf/sogo/custom-theme.css $(docker ps -qf "name=sogo-mailcow"):/tmp/
docker exec $(docker ps -qf "name=sogo-mailcow") bash -c "cat /tmp/custom-theme.css >> /usr/lib/GNUstep/SOGo/WebServerResources/css/styles.css"

# Copy admin CSS
docker cp data/web/css/gaiaftcl-admin.css $(docker ps -qf "name=nginx-mailcow"):/web/css/

# Copy logo
docker cp data/web/img/gaiaftcl-logo.svg $(docker ps -qf "name=nginx-mailcow"):/web/img/

echo "  [✓] Theme applied to containers"

# ============================================
# 6. Restart Services
# ============================================

echo ""
echo "Restarting services..."

docker compose restart sogo-mailcow nginx-mailcow

echo "  [✓] Services restarted"

# ============================================
# Done
# ============================================

echo ""
echo "=============================================="
echo "GaiaFTCL Theme Installation Complete"
echo "=============================================="
echo ""
echo "Applied:"
echo "  - SOGo webmail dark theme"
echo "  - Admin UI dark theme"
echo "  - GaiaFTCL logo"
echo "  - Custom color palette"
echo ""
echo "Access:"
echo "  - Webmail: https://mail.gaiaftcl.com/SOGo"
echo "  - Admin:   https://mail.gaiaftcl.com"
echo ""
