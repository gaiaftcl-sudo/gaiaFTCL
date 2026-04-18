# REAL OAuth Implementation for GaiaOS

## Architecture

```
User Browser → GaiaOS UI (78.46.149.125:3000) → OAuth Provider (Google/Microsoft/GitHub)
                           ↑                                    ↓
                           └──────── Callback URL ─────────────┘
```

## Required Components

### 1. OAuth Configuration (Environment Variables)
```bash
# Google OAuth
GOOGLE_CLIENT_ID=<real_client_id>
GOOGLE_CLIENT_SECRET=<real_secret>

# Microsoft OAuth
MICROSOFT_CLIENT_ID=<real_client_id>
MICROSOFT_CLIENT_SECRET=<real_secret>

# GitHub OAuth
GITHUB_CLIENT_ID=<real_client_id>
GITHUB_CLIENT_SECRET=<real_secret>

# Callback base URL
OAUTH_CALLBACK_BASE=http://78.46.149.125:3000
```

### 2. Callback Routes
```
GET  /auth/callback/google     - Google OAuth callback
GET  /auth/callback/microsoft  - Microsoft OAuth callback
GET  /auth/callback/github     - GitHub OAuth callback
POST /api/auth/oauth/:provider/url      - Generate OAuth URL
GET  /api/auth/oauth/:provider/callback - Handle OAuth callback
```

### 3. OAuth Flow

**Step 1: User clicks "Login with Google"**
```
Frontend → GET /api/auth/oauth/google/url
Response: {
  "auth_url": "https://accounts.google.com/o/oauth2/v2/auth?client_id=REAL_ID&redirect_uri=...",
  "state": "random_csrf_token"
}
```

**Step 2: User redirected to Google**
- Google shows login screen
- User authenticates
- User approves permissions

**Step 3: Google redirects back to our callback**
```
Google → GET /auth/callback/google?code=AUTH_CODE&state=CSRF_TOKEN
```

**Step 4: Exchange code for tokens**
```
Backend → POST https://oauth2.googleapis.com/token
Request: { code, client_id, client_secret, redirect_uri }
Response: { access_token, refresh_token, id_token }
```

**Step 5: Get user info**
```
Backend → GET https://www.googleapis.com/oauth2/v1/userinfo
Headers: Authorization: Bearer ACCESS_TOKEN
Response: { email, name, picture }
```

**Step 6: Create session**
```
- Generate session token (JWT)
- Generate 8D QSig from user data
- Store session in memory/Redis
- Return session token to frontend
```

**Step 7: Frontend stores session**
```
- Save session token in localStorage
- Redirect to main app
- User is now logged in
```

