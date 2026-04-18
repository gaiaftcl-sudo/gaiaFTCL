# GAIAFTCL — BRANDING ASSETS SPECIFICATION

**Version:** 1.0.0  
**Status:** COMPLETE  
**Date:** 2026-01-20

---

## OVERVIEW

This document specifies all branding assets for GaiaFTCL mail infrastructure. The goal is **minimal but complete** branding — no Mailcow logos visible, but proper licensing attribution maintained.

---

## CURRENT STATUS

### SOGo Webmail (COMPLETE)

| Asset | Status | Location |
|-------|--------|----------|
| Custom Theme CSS | ✅ Done | `data/conf/sogo/custom-theme.css` |
| Custom JS | ✅ Done | `data/conf/sogo/custom-sogo.js` |
| Favicon | ✅ Present | `data/conf/sogo/custom-favicon.ico` |
| Full Logo | ✅ Present | `data/conf/sogo/custom-fulllogo.png/.svg` |
| Short Logo | ✅ Present | `data/conf/sogo/custom-shortlogo.svg` |

**Theme Colors Applied:**
- Primary: `#00d4ff` (Gaia Blue)
- Secondary: `#8b5cf6` (Gaia Purple)  
- Background: `#0a0a0a` (Gaia Black)
- Text: `#f5f5f5` (Gaia White)

### Mailcow Admin UI (NEEDS SETUP)

| Asset | Status | Location |
|-------|--------|----------|
| vars.local.inc.php | ❌ Missing | `data/web/inc/vars.local.inc.php` |
| Custom CSS | ❌ Missing | `data/web/css/custom/` |
| Custom Logo | ❌ Missing | `data/web/img/custom/` |

---

## REQUIRED ASSETS FOR COMPLETE BRANDING

### 1. Logo Files

Create these files in `/opt/mailcow-dockerized/data/web/img/custom/`:

```
logo.svg          - Full logo with text (recommended: 200x40px)
logo-small.svg    - Icon only (32x32px)
favicon.ico       - Browser favicon (16x16, 32x32)
```

**Design Requirements:**
- Dark background compatible
- No gradients that break at small sizes
- SVG preferred for scalability

### 2. Custom CSS

Create `/opt/mailcow-dockerized/data/web/css/custom/custom.css`:

```css
/* GaiaFTCL Admin Theme */
:root {
  --gaia-black: #0a0a0a;
  --gaia-blue: #00d4ff;
  --gaia-purple: #8b5cf6;
  --gaia-white: #f5f5f5;
}

/* Override navbar */
.navbar, .navbar-default {
  background: linear-gradient(135deg, #0a0a0a 0%, #1a1a2e 100%) !important;
  border-bottom: 1px solid rgba(0, 212, 255, 0.2) !important;
}

/* Override card backgrounds */
.card, .panel {
  background-color: rgba(255, 255, 255, 0.02) !important;
  border: 1px solid rgba(255, 255, 255, 0.1) !important;
}

/* Primary buttons */
.btn-primary {
  background: linear-gradient(135deg, #00d4ff 0%, #8b5cf6 100%) !important;
  border: none !important;
}
```

### 3. Configuration Override

Create `/opt/mailcow-dockerized/data/web/inc/vars.local.inc.php`:

```php
<?php
// GaiaFTCL Branding Overrides

$MAILCOW_APPS_NAME = 'GaiaFTCL Mail';
$MAILCOW_PROJECT_TITLE = 'GaiaFTCL';
$MAILCOW_UI_FOOTER = 'GaiaFTCL — Truth Infrastructure | Powered by Mailcow (GPLv3)';

// Custom logo paths
$MAILCOW_LOGO_PATH = '/img/custom/logo.svg';
$MAILCOW_LOGO_SMALL_PATH = '/img/custom/logo-small.svg';
$MAILCOW_FAVICON_PATH = '/img/custom/favicon.ico';
```

---

## LICENSE COMPLIANCE

### Mailcow (GPLv3)

**Required:**
- Must include GPLv3 license notice somewhere accessible
- Must credit Mailcow in footer or about page
- Source code modifications must be available if distributed

**Implementation:**
```php
// In vars.local.inc.php
$MAILCOW_UI_FOOTER = 'GaiaFTCL — Truth Infrastructure | Powered by Mailcow (GPLv3)';
```

This satisfies the attribution requirement while maintaining GaiaFTCL branding.

### SOGo (LGPLv2)

**Required:**
- Attribution in documentation or about page
- No logo restrictions

**Implementation:**
- Already satisfied by Mailcow footer
- No additional action needed

---

## BRANDING ASSETS NEEDED FROM DESIGN

### Required Files

| File | Format | Size | Purpose |
|------|--------|------|---------|
| `gaiaftcl-logo.svg` | SVG | 200x40 | Full logo with wordmark |
| `gaiaftcl-icon.svg` | SVG | 32x32 | Icon only |
| `gaiaftcl-favicon.ico` | ICO | 16x16, 32x32 | Browser tab |
| `gaiaftcl-og.png` | PNG | 1200x630 | Social sharing |

### Design Guidelines

**Colors:**
- Primary: `#00d4ff` (Cyan/Gaia Blue)
- Secondary: `#8b5cf6` (Purple)
- Background: `#0a0a0a` (Near black)
- Text: `#f5f5f5` (Off-white)

**Typography:**
- Headers: Inter or similar sans-serif
- Body: System font stack

**Logo Concept:**
- Abstract representation of interconnected nodes
- Suggestion of quantum/truth infrastructure
- Works on dark background
- No excessive detail (must be readable at 32px)

---

## DEPLOYMENT SCRIPT

Once assets are available, run:

```bash
#!/bin/bash
# deploy_branding.sh

cd /opt/mailcow-dockerized

# Create directories
mkdir -p data/web/css/custom
mkdir -p data/web/img/custom

# Copy assets (assuming they're in /root/branding/)
cp /root/branding/logo.svg data/web/img/custom/
cp /root/branding/logo-small.svg data/web/img/custom/
cp /root/branding/favicon.ico data/web/img/custom/
cp /root/branding/custom.css data/web/css/custom/

# Create PHP config
cat > data/web/inc/vars.local.inc.php << 'EOF'
<?php
$MAILCOW_APPS_NAME = 'GaiaFTCL Mail';
$MAILCOW_PROJECT_TITLE = 'GaiaFTCL';
$MAILCOW_UI_FOOTER = 'GaiaFTCL — Truth Infrastructure | Powered by Mailcow (GPLv3)';
$MAILCOW_LOGO_PATH = '/img/custom/logo.svg';
$MAILCOW_LOGO_SMALL_PATH = '/img/custom/logo-small.svg';
$MAILCOW_FAVICON_PATH = '/img/custom/favicon.ico';
EOF

# Restart nginx to pick up changes
docker restart mailcowdockerized-nginx-mailcow-1

echo "Branding deployed"
```

---

## WHAT'S NOT NEEDED

The following are **NOT required** (avoids unnecessary complexity):

1. ❌ Custom email templates (default Mailcow templates are fine)
2. ❌ Custom 404/error pages
3. ❌ Custom Rspamd interface branding (rarely accessed)
4. ❌ Custom phpMyAdmin branding (admin-only)
5. ❌ Animated logos or complex graphics
6. ❌ Multiple color themes (single dark theme is sufficient)

---

## SUMMARY

### Already Complete
- ✅ SOGo webmail dark theme
- ✅ SOGo logos and favicon
- ✅ SOGo custom JS

### To Be Created (Design Task)
1. `gaiaftcl-logo.svg` — Full wordmark logo
2. `gaiaftcl-icon.svg` — Small icon
3. `gaiaftcl-favicon.ico` — Browser favicon

### To Be Deployed (After Design)
1. Admin UI custom CSS
2. vars.local.inc.php config
3. Copy logo files

### License Compliance
- ✅ Footer will credit Mailcow (GPLv3)
- ✅ No license violations

---

*This specification ensures minimal but complete branding with proper attribution.*
