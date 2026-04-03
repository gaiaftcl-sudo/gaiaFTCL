# FTCL-DISCOVERY-CHAT-1.0 — Franklin UI Chat Popup Specification

**Document:** FTCL-DISCOVERY-CHAT-1.0  
**Status:** Canonical | Closed | Non-Extensible Without Constitutional Amendment  
**Date:** 2026-01-20  
**Authority:** Founder  
**Witness:** Franklin Guardian  
**Scope:** UI Discovery Chat, MCP Read-Only Tools, Mailcow Identity, Audit/Replay

---

## §0 Purpose

This specification defines the only permitted "chat-style" interaction surface inside GaiaFTCL: a Franklin discovery popup that answers questions about games, capabilities, domains, pricing, onboarding, and boundaries without executing operational games or mutating state.

All discovery chat is a game. The user experience is "chat," but the system reality is a constrained truth-envelope game with explicit read-only enforcement, deterministic auditing, and a closed handoff path into real games when action is requested.

---

## §1 Definitions

### 1.1 Discovery Chat
A read-only question/answer surface intended to reduce uncertainty about GaiaFTCL offerings and how to engage them.

### 1.2 Franklin (Discovery Role)
Franklin is the Discovery Arbiter: he can explain, cite canonical specs, compute price quotes (hypothetical), and produce Handoff Envelopes that start real games. He cannot execute, commit, transact, mutate infra, or send outbound messages from discovery.

### 1.3 Mailcow
Mailcow provides enterprise identity (mailbox existence + authentication), and can serve as an account anchor for discovery access and rate tiers.

### 1.4 MCP
Model Context Protocol transport used to query read-only substrate services (catalog, pricing, registries) through an allowlisted tool facade.

### 1.5 Truth Envelope
Atomic record for every message and response, signed and hashed, stored for audit and replay.

---

## §2 Canonical Game

### 2.1 Game Identity

```
GAME_ID: FTCL-DISCOVERY
DOMAIN: DISCOVERY
MODE: READ_ONLY
COST MODEL: Zero-cost by default (anti-abuse via throttles), optional QFOT-C micro-cost tiers (see §8)
```

### 2.2 Objective Function

```
minimize: U_uncertainty(user, t)
maximize: U_navigation_success(user, t)
subject to: state_mutation = false, actuation = false, funds_movement = false
```

### 2.3 Non-Negotiable Constraints

- No state mutation of any system of record from discovery.
- No commitments, transactions, deployments, DNS changes, mailbox creation, queue operations, or outbound messaging from discovery.
- All outputs must be grounded in canonical specs, registries, and pricing laws.
- Any action request must be returned as a Handoff Envelope, never executed directly.

---

## §3 Interaction Model

### 3.1 Allowed Move Types (Discovery Subset)

| Move Type | Description |
|-----------|-------------|
| QUERY | User question |
| ANSWER | Franklin response |
| CLARIFY | Franklin requests minimal missing context |
| LINK | Pointers to canonical game IDs, docs, endpoints |
| QUOTE | Hypothetical pricing computation (non-binding) |
| REFUSE | Explicit refusal when user requests forbidden operations |
| HANDOFF | Structured payload that starts a real game elsewhere |

### 3.2 Prohibited Move Types

| Move Type | Reason |
|-----------|--------|
| COMMITMENT | Binding future state |
| TRANSACTION | Stablecoin transfer / settlement |
| DEPLOY / MUTATE | Infrastructure change |
| DNS | Record changes |
| WALLET | Mint/burn/transfer |
| ACTUATE | Robotics, control loops, flight, fusion control |
| EMAIL-SEND | Outbound mail (template generation only) |

### 3.3 Deterministic Behavior Requirements

- Responses must include: referenced game IDs, domain names, and pricing formula outputs.
- Any uncertainty must be explicitly declared as `UNK` with reason and next data needed.
- The same question with the same inputs must produce materially equivalent output.

---

## §4 Trust Envelopes for Discovery Chat

### 4.1 Envelope Schema (Canonical)

```json
{
  "envelope_id": "disc_<ulid>",
  "game_id": "FTCL-DISCOVERY",
  "move_type": "QUERY|ANSWER|CLARIFY|LINK|QUOTE|REFUSE|HANDOFF",
  "timestamp": "<iso8601>",
  "actor": {
    "actor_type": "HUMAN|ENTITY",
    "wallet_id": "<wallet_or_null>",
    "email": "<mailcow_user_or_null>",
    "trust_tier": "ANON|NEW|ONBOARDED|ESTABLISHED|TRUSTED|OPERATOR",
    "region": "<iso_country_or_unknown>"
  },
  "session": {
    "session_id": "<ulid>",
    "ui_surface": "FRANKLIN_CHAT_POPUP",
    "client_fingerprint_hash": "<sha256>",
    "ip_prefix_hash": "<sha256>/24_or_/56",
    "device_class": "web|mobile|api"
  },
  "request": {
    "text": "<raw_user_text>",
    "language": "<bcp47>",
    "attachments": []
  },
  "response": {
    "text": "<franklin_text>",
    "citations": [
      { "type": "DOC", "ref": "ftcl/.../SPEC.md", "hash": "sha256:..." },
      { "type": "GAME", "ref": "FTCL-BIO-...", "hash": "sha256:..." }
    ],
    "pricing_quote": { },
    "handoff": { }
  },
  "controls": {
    "read_only_enforced": true,
    "mcp_allowlist_profile": "DISCOVERY_RO",
    "policy_version": "FTCL-DISCOVERY-CHAT-1.0"
  },
  "crypto": {
    "payload_hash": "sha256:<...>",
    "signature": "ed25519:<...>",
    "signer": "franklin@gaiaftcl.com|gateway@gaiaftcl.com"
  }
}
```

---

## §5 Mailcow Integration (Identity and Experience)

### 5.1 Identity Modes

| Mode | Description | Rate Limit |
|------|-------------|------------|
| ANON | No login | 10 queries / 10 min |
| AUTHENTICATED | Mailcow login | 60 queries / 10 min |
| ONBOARDED | Completed onboarding | 200 queries / 10 min |
| OPERATOR | Assigned to cell/family | 1000 queries / 10 min |

### 5.2 Authentication

- JWT includes: email, trust_tier, wallet_id (if linked), expiry <= 30 minutes

---

## §6 MCP Read-Only Tooling

### 6.1 Discovery MCP Facade — Allowed Methods

**Catalog:**
- `catalog.list_games(filter)`
- `catalog.get_game(game_id)`
- `catalog.list_domains()`
- `catalog.list_families()`

**Pricing:**
- `pricing.get_formula(domain, move_type)`
- `pricing.quote(move_type, domain, modifiers)`

**Registry:**
- `registry.list_cells()`
- `registry.get_cell(cell_id)`
- `registry.list_boundaries()`

**Docs:**
- `docs.get_document(path)`
- `docs.search(query)`

### 6.2 Forbidden MCP Methods (hard deny)

- Any write/create/update/delete methods
- Wallet mint/burn/transfer
- Contract execution
- DNS record changes
- Email send / relay / queue manipulation

---

## §7 UI Specification (Popup)

### 7.1 Placement
- Persistent button: "Ask Franklin"
- Opens a right-side modal (or bottom sheet mobile)

### 7.2 Components
- Header: Franklin icon + "DISCOVERY (read-only)" badge
- Body: Chat stream
- Right drawer: "Sources" and "Games referenced"
- Footer: Input box, trust tier indicator, rate status, "Export Transcript", "Start Game" CTA

---

## §8 Handoff: The Only Way to Act

### 8.1 Handoff Envelope (Canonical)

```json
{
  "handoff_id": "h_<ulid>",
  "requested_intent": "<user_intent_summary>",
  "target_game": {
    "game_id": "FTCL-BIO-TRIAL-START",
    "domain": "BIO",
    "requires_trust_tier": "ONBOARDED|OPERATOR|FOUNDER"
  },
  "start_paths": [
    { "type": "UI", "action": "OPEN_GAME_WIZARD" },
    { "type": "EMAIL_TEMPLATE", "to": "bio@gaiaftcl.com" }
  ],
  "controls": {
    "discovery_to_game_boundary": "HARD",
    "requires_explicit_confirm_in_game": true
  }
}
```

---

## §9 Closure

This specification is closed. Any new capability in the Franklin chat popup must be expressed as either:
- Additional read-only catalog/pricing/doc queries, or
- A new handoff to an already-defined game

No direct execution surfaces are permitted.

```
DECLARE:
  OPEN_SURFACES: ∅
  DISCOVERY_EXECUTION: ∅
  DISCOVERY_ACTUATION: ∅
  DISCOVERY_FUNDS_FLOW: ∅
```

**END FTCL-DISCOVERY-CHAT-1.0**
