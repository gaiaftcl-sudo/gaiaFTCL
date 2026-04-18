# GaiaFTCL Brand & Onboarding System

**Version:** 1.0.0  
**Status:** Canonical  
**Date:** January 2026  
**Document:** FTCL-BRAND-001

---

## Part I: Core Identity Principle

### 1.1 The Axiom

```
Email = Wallet = Identity
```

- **No names**
- **No personal information**
- **No KYC** (except for investment tier)
- **Email address is the only identifier**
- **Wallet is the economic surface**

### 1.2 What We Collect

```
COLLECT:
  ├── Chosen username (becomes email prefix)
  ├── Password (hashed, for email/wallet access)
  └── Nothing else

DO NOT COLLECT:
  ├── Real name
  ├── Phone number
  ├── Physical address
  ├── Government ID
  ├── Payment method (stablecoin is pseudonymous)
  └── Any PII whatsoever
```

### 1.3 Identity Structure

```
username@gaiaftcl.com
    │
    ├── Email inbox (Roundcube)
    ├── Wallet (QFOT balance)
    ├── Digital twin (game state)
    └── MCP endpoint (agent access)
```

---

## Part II: Brand Identity

### 2.1 Name

```
Primary:    GaiaFTCL
Expanded:   Gaia Field-Truth Coordination Layer
Short:      FTCL
Domain:     gaiaftcl.com
```

### 2.2 Tagline Options

```
Primary:    "There is only the game."
Secondary:  "Truth-preserving infrastructure for civilization."
Technical:  "AI coordination substrate."
```

### 2.3 Color Palette

```css
/* Primary */
--gaia-black:       #0a0a0a;    /* Deep space black */
--gaia-white:       #f5f5f5;    /* Off-white */

/* Accent */
--gaia-blue:        #00d4ff;    /* Quantum cyan */
--gaia-purple:      #8b5cf6;    /* Emergence violet */
--gaia-green:       #10b981;    /* Truth green */

/* Functional */
--gaia-red:         #ef4444;    /* Failure red */
--gaia-yellow:      #f59e0b;    /* Warning amber */
--gaia-gray:        #374151;    /* Interface gray */

/* Gradients */
--gaia-gradient:    linear-gradient(135deg, #00d4ff 0%, #8b5cf6 100%);
```

### 2.4 Typography

```css
/* Headings */
font-family: 'Space Grotesk', 'Inter', sans-serif;
font-weight: 700;

/* Body */
font-family: 'Inter', -apple-system, sans-serif;
font-weight: 400;

/* Code/Technical */
font-family: 'JetBrains Mono', 'Fira Code', monospace;
```

### 2.5 Logo Concept

```
Symbol: Klein bottle (recursive topology)
        - Represents "no inside, no outside"
        - Single continuous surface
        - Self-referential

Text:   GAIAFTCL in Space Grotesk
        - All caps
        - Letter-spaced
        - Quantum cyan accent on "FT" (Field-Truth)
```

### 2.6 Visual Language

```
Aesthetic:
  ├── Dark mode default (space black background)
  ├── Minimal, clean interfaces
  ├── Geometric precision
  ├── Subtle glow effects (cyan/purple)
  ├── Monospace for data/code
  └── No decorative elements (form follows function)

Iconography:
  ├── Line icons only
  ├── 2px stroke weight
  ├── Rounded caps
  └── Consistent 24px grid
```

---

## Part III: Onboarding Flow

### 3.1 Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    ONBOARDING FLOW                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   1. LANDING                                                │
│      └── gaiaftcl.com                                       │
│      └── "There is only the game."                          │
│      └── [Enter the Game] button                            │
│                                                             │
│   2. USERNAME SELECTION                                     │
│      └── "Choose your identity"                             │
│      └── Input: username (alphanumeric, 3-20 chars)         │
│      └── Preview: username@gaiaftcl.com                     │
│      └── Check availability in real-time                    │
│                                                             │
│   3. PASSWORD                                               │
│      └── "Secure your wallet"                               │
│      └── Password (min 12 chars)                            │
│      └── Confirm password                                   │
│      └── No recovery without password (sovereign identity)  │
│                                                             │
│   4. CREATION                                               │
│      └── Create email account (Maddy)                       │
│      └── Create wallet (internal ledger)                    │
│      └── Create digital twin (ArangoDB)                     │
│      └── Mint 10 QFOT-C bootstrap grant                     │
│      └── Send welcome email                                 │
│                                                             │
│   5. DASHBOARD                                              │
│      └── Redirect to dashboard.gaiaftcl.com                 │
│      └── Show wallet balance (10 QFOT-C)                    │
│      └── Show onboarding game progress                      │
│      └── "Complete 6 moves to earn 25 QFOT-C"              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 What Gets Created

| Asset | Location | Purpose |
|-------|----------|---------|
| Email | username@gaiaftcl.com | Communication, identity |
| Wallet | QFOT ledger | Economic participation |
| Digital Twin | ArangoDB | Game state, history |
| MCP Token | JWT | API/agent access |
| Bootstrap Grant | 10 QFOT-C | Initial play credits |

### 3.3 Username Rules

```
ALLOWED:
  ├── Lowercase letters (a-z)
  ├── Numbers (0-9)
  ├── Underscores (_)
  ├── Hyphens (-)
  └── Length: 3-20 characters

NOT ALLOWED:
  ├── Uppercase (auto-lowercased)
  ├── Spaces
  ├── Special characters
  ├── Starting with number
  └── Reserved words (admin, root, system, gaia, franklin, etc.)

RESERVED USERNAMES:
  admin, administrator, root, system, support, help,
  gaia, franklin, fara, qstate, validator, witness,
  oracle, gamerunner, virtue, ben, rick, founder,
  postmaster, webmaster, mail, www, ftp, api
```

### 3.4 No Recovery Warning

```
⚠️ IMPORTANT

Your password is the ONLY way to access your identity.

GaiaFTCL does not collect personal information.
We cannot verify who you are.
We cannot reset your password.
We cannot recover your account.

If you lose your password, your identity is lost forever.
Your QFOT balance will be unrecoverable.

This is the price of sovereignty.

[ ] I understand and accept this responsibility.
```

---

## Part IV: Site Structure

### 4.1 Domains

```
gaiaftcl.com              # Landing page
├── /enter                # Onboarding flow
├── /docs                 # Protocol documentation
├── /status               # Infrastructure status
└── /invest               # Investment information

dashboard.gaiaftcl.com    # User dashboard (authenticated)
├── /wallet               # Balance, transactions
├── /games                # Active games, history
├── /mail                 # Email (Roundcube embed/redirect)
└── /settings             # Password change only

mail.gaiaftcl.com         # Roundcube (direct access)

api.gaiaftcl.com          # API endpoints
mcp.gaiaftcl.com          # MCP gateway
```

### 4.2 Page Specifications

#### Landing Page (gaiaftcl.com)

```
SECTIONS:
  1. Hero
     - "There is only the game."
     - Animated Klein bottle
     - [Enter the Game] CTA

  2. What is GaiaFTCL
     - "Truth-preserving infrastructure for AI coordination"
     - 3 key points (Email=Identity, No PII, Sovereign)

  3. The Game
     - "Every action is a move. Every move has cost."
     - 6 move types visual
     - "Complete the onboarding game to earn 25 QFOT-C"

  4. Infrastructure
     - "11 cells. 9 agents. 5 protocols."
     - Live status indicators
     - Map visualization

  5. Investment
     - "Own a piece of the infrastructure."
     - "10% profit share. Stablecoin settlement."
     - [Contact Ben] CTA

  6. Footer
     - Docs, Status, API
     - "© GaiaFTCL. There is no outside."
```

#### Dashboard (dashboard.gaiaftcl.com)

```
LAYOUT:
  ┌─────────────────────────────────────────────────────────┐
  │  GAIAFTCL                    username@gaiaftcl.com  [≡] │
  ├─────────────────────────────────────────────────────────┤
  │                                                         │
  │  WALLET                                                 │
  │  ┌─────────────┐  ┌─────────────┐                      │
  │  │    0.00     │  │   10.00     │                      │
  │  │    QFOT     │  │   QFOT-C    │                      │
  │  │  [Deposit]  │  │  Expires:   │                      │
  │  └─────────────┘  │  89 days    │                      │
  │                   └─────────────┘                      │
  │                                                         │
  │  ONBOARDING GAME                     Progress: 0/6     │
  │  ┌─────────────────────────────────────────────────┐   │
  │  │  ○ CLAIM      Make a truth assertion            │   │
  │  │  ○ REQUEST    Ask for something                 │   │
  │  │  ○ COMMITMENT Promise future action             │   │
  │  │  ○ REPORT     Share information                 │   │
  │  │  ○ TRANSACTION Transfer value                   │   │
  │  │  ○ FAILURE    Admit an error                    │   │
  │  └─────────────────────────────────────────────────┘   │
  │  Complete all 6 to earn 25 QFOT-C                      │
  │                                                         │
  │  RECENT ACTIVITY                                        │
  │  ┌─────────────────────────────────────────────────┐   │
  │  │  (no activity yet)                              │   │
  │  └─────────────────────────────────────────────────┘   │
  │                                                         │
  └─────────────────────────────────────────────────────────┘
```

---

## Part V: Technical Implementation

### 5.1 Account Creation Flow

```python
# POST /api/v1/onboard/create
{
  "username": "alice",
  "password": "secure_password_here"
}

# Backend Flow:
1. Validate username (rules, availability)
2. Hash password (argon2id)
3. Create Maddy email account
4. Create wallet entry in ledger
5. Create digital twin in ArangoDB
6. Mint 10 QFOT-C bootstrap grant
7. Generate JWT for session
8. Send welcome email
9. Return success + redirect to dashboard
```

### 5.2 Maddy Account Creation

```bash
# Create email account via Maddy CLI
maddy creds create "username@gaiaftcl.com" "hashed_password"

# Or via API if configured
POST /admin/accounts
{
  "email": "username@gaiaftcl.com",
  "password_hash": "argon2id$..."
}
```

### 5.3 Wallet Creation

```json
// ArangoDB: wallets collection
{
  "_key": "username_gaiaftcl_com",
  "email": "username@gaiaftcl.com",
  "qfot": 0.0,
  "qfot_c": 10.0,
  "qfot_c_grants": [
    {
      "id": "bootstrap_20260120",
      "amount": 10.0,
      "expires": "2026-04-20T00:00:00Z",
      "source": "onboarding_bootstrap"
    }
  ],
  "created": "2026-01-20T12:00:00Z",
  "status": "active"
}
```

### 5.4 Digital Twin Creation

```json
// ArangoDB: twins collection
{
  "_key": "username_gaiaftcl_com",
  "email": "username@gaiaftcl.com",
  "type": "PARTICIPANT",
  "wallet": "username_gaiaftcl_com",
  
  "onboarding": {
    "game_id": "FTCL-TRAIN-ONBOARD",
    "started": "2026-01-20T12:00:00Z",
    "moves_completed": [],
    "status": "in_progress"
  },
  
  "virtue_score": {
    "HON": 0.5,
    "FOR": 0.5,
    "JUS": 0.5,
    "TEM": 0.5,
    "PRU": 0.5,
    "COU": 0.5,
    "HUM": 0.5
  },
  
  "created": "2026-01-20T12:00:00Z"
}
```

### 5.5 Welcome Email

```
From: welcome@gaiaftcl.com
To: username@gaiaftcl.com
Subject: Welcome to GaiaFTCL

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Welcome to GaiaFTCL, username.

Your identity: username@gaiaftcl.com
Your wallet: 10.00 QFOT-C (expires in 90 days)

There is only the game.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

COMPLETE THE ONBOARDING GAME

You have 10 QFOT-C to make your first moves.
Complete all 6 move types to earn 25 QFOT-C:

  ○ CLAIM       - Assert a truth
  ○ REQUEST     - Ask for something
  ○ COMMITMENT  - Promise future action
  ○ REPORT      - Share information
  ○ TRANSACTION - Transfer value (min 1 QFOT)
  ○ FAILURE     - Admit an error

Dashboard: https://dashboard.gaiaftcl.com

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

IMPORTANT

Your password is the ONLY way to access your identity.
We do not collect personal information.
We cannot reset your password.
If you lose it, your identity is lost forever.

This is the price of sovereignty.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

There is no inside. There is no outside.
There is only the game.

—GaiaFTCL

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Part VI: Roundcube Customization

### 6.1 Branding Files

```
/var/www/roundcube/skins/gaiaftcl/
├── meta.json           # Skin metadata
├── styles.css          # Custom CSS
├── images/
│   ├── logo.svg        # GaiaFTCL logo
│   └── favicon.ico     # Favicon
└── templates/
    └── login.html      # Custom login page
```

### 6.2 Custom CSS

```css
/* GaiaFTCL Roundcube Theme */

:root {
  --gaia-black: #0a0a0a;
  --gaia-white: #f5f5f5;
  --gaia-blue: #00d4ff;
  --gaia-purple: #8b5cf6;
  --gaia-gray: #374151;
}

body {
  background: var(--gaia-black);
  color: var(--gaia-white);
  font-family: 'Inter', sans-serif;
}

#login-form {
  background: var(--gaia-gray);
  border: 1px solid var(--gaia-blue);
  border-radius: 8px;
}

.button.mainaction {
  background: linear-gradient(135deg, #00d4ff 0%, #8b5cf6 100%);
  border: none;
  color: white;
}

#logo {
  content: url('/images/logo.svg');
}
```

---

## Part VII: API Endpoints

### 7.1 Onboarding

```
POST /api/v1/onboard/check-username
  → Check if username is available

POST /api/v1/onboard/create
  → Create account (email + wallet + twin)

POST /api/v1/auth/login
  → Authenticate, return JWT

POST /api/v1/auth/logout
  → Invalidate session
```

### 7.2 Wallet

```
GET /api/v1/wallet
  → Get balances (QFOT, QFOT-C)

GET /api/v1/wallet/transactions
  → Transaction history

POST /api/v1/wallet/deposit
  → Initiate stablecoin deposit
```

### 7.3 Games

```
GET /api/v1/games/onboarding
  → Get onboarding progress

POST /api/v1/games/move
  → Submit a game move

GET /api/v1/games/history
  → Move history
```

---

## Part VIII: Security Model

### 8.1 Authentication

```
Method:     Password-based (email + password)
Hashing:    Argon2id
Sessions:   JWT (24 hour expiry)
MFA:        Not implemented (password is sovereign)
Recovery:   NONE (by design)
```

### 8.2 Authorization

```
All access requires:
  ├── Valid JWT token
  └── Token matches requested resource owner

No admin access to user data:
  ├── Cannot read emails
  ├── Cannot see passwords
  ├── Cannot modify wallets
  └── Cannot impersonate users
```

### 8.3 Data Minimization

```
We store:
  ├── Username (email prefix)
  ├── Password hash
  ├── Wallet balances
  ├── Game state
  └── Email content

We DO NOT store:
  ├── Real names
  ├── Physical addresses
  ├── Phone numbers
  ├── IP addresses (beyond session)
  ├── Device fingerprints
  └── Any PII
```

---

## Part IX: Deployment

### 9.1 Services Required

| Service | Purpose | Cell |
|---------|---------|------|
| Caddy | Reverse proxy, HTTPS | nbg1-01 |
| Web App | Landing, onboarding, dashboard | nbg1-01 |
| Maddy | Email (create accounts) | All cells |
| Roundcube | Webmail | All cells |
| ArangoDB | Wallets, twins, games | All cells |
| API | Backend services | nbg1-01 |

### 9.2 DNS

```
gaiaftcl.com            → nbg1-01 (Caddy)
dashboard.gaiaftcl.com  → nbg1-01 (Caddy)
mail.gaiaftcl.com       → Round-robin all cells
api.gaiaftcl.com        → nbg1-01 (Caddy)
```

---

## Appendix A: Reserved Usernames

```
admin, administrator, root, system, support, help, info,
gaia, franklin, fara, qstate, validator, witness, oracle,
gamerunner, virtue, ben, rick, founder, owner,
postmaster, webmaster, hostmaster, abuse, security,
mail, www, ftp, api, cdn, static, assets,
noreply, no-reply, donotreply, mailer-daemon,
test, demo, example, sample
```

---

## Appendix B: Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-20 | Initial specification |

---

*This specification is the canonical reference for GaiaFTCL branding and user onboarding.*
