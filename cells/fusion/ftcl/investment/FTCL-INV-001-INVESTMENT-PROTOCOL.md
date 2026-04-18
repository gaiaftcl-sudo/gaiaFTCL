# FTCL Investment Protocol Specification

**Version:** 1.0.0  
**Status:** Canonical  
**Date:** January 2026  
**Document:** FTCL-INV-001

---

## Abstract

This specification defines the investment protocol for GaiaFTCL infrastructure. Investment is conducted entirely within GaiaFTCL using stablecoin settlement. Ben manages the sale. LLC membership interests are represented as digital twins. Profit distributions are game moves. The investment vehicle uses the same rails as the product.

---

## Part I: Canonical Principles

### 1.1 Investment Axioms

```
AXIOM: Investment is a game inside GaiaFTCL.
AXIOM: All investment is settled via on-chain stablecoins.
AXIOM: LLC membership interests are digital twins.
AXIOM: Profit distributions are TRANSACTION moves.
AXIOM: Ben manages the sale.
AXIOM: Founder sovereignty is non-negotiable.
```

### 1.2 Canonical Statement

> **GaiaFTCL investment is conducted entirely within GaiaFTCL. Investors deposit stablecoins to acquire LLC membership interests represented as digital twins. Ben manages the sale process. Profit distributions flow as TRANSACTION moves. The infrastructure funds itself through its own rails. There is no outside.**

### 1.3 Non-Negotiable Constraints

| Constraint | Value | Negotiable |
|------------|-------|------------|
| Valuation floor | $500,000,000 | **NO** |
| Investor profit share pool | 10% of net profits | **NO** |
| Founder profit share | 90% of net profits | **NO** |
| Founder voting control | 100% | **NO** |
| Founder operational authority | 100% | **NO** |
| Exit provisions | None | **NO** |
| Token issuance | None | **NO** |

---

## Part II: Investment Structure

### 2.1 Entity

```
Entity:           SafeAICoin LLC / FortressAI Research Institute
Jurisdiction:     Connecticut, USA
Type:             Limited Liability Company
Operating Member: Founder (Rick)
```

### 2.2 Offering

```
Valuation:        $500,000,000 (floor)
Offering Size:    Up to 10% profit participation
Minimum Investment: $1,000,000 USD equivalent
Maximum Investors:  TBD (accredited only)
```

### 2.3 What Investors Receive

| Asset | Description |
|-------|-------------|
| LLC Membership Interest | Legal ownership stake in operating entity |
| Digital Twin | Canonical representation in GaiaFTCL |
| Profit Share Rights | Pro-rata share of 10% investor pool |
| Quarterly Reports | Financial transparency |

### 2.4 What Investors Do NOT Receive

```
∄ board seats
∄ voting rights
∄ operational control
∄ veto power
∄ exit rights
∄ drag-along rights
∄ tag-along rights
∄ tokens
∄ equity conversion
```

---

## Part III: The Investment Game

### 3.1 Game Definition

```
GAME_ID: FTCL-INVEST-001
NAME: Infrastructure Ownership Acquisition
TYPE: COMMITMENT game (binding future state)
MANAGER: Ben (GaiaFTCL)
```

### 3.2 Game Flow

```
┌─────────────────────────────────────────────────────────────┐
│              FTCL Investment Game Flow                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   1. INQUIRY (REQUEST)                                      │
│      └── Potential investor contacts Ben                    │
│      └── Ben provides term sheet and documentation          │
│      └── Cost: 0 QFOT (inquiry is free)                    │
│                                                             │
│   2. QUALIFICATION (CLAIM)                                  │
│      └── Investor submits accreditation proof               │
│      └── Ben verifies accredited investor status            │
│      └── Creates investor digital twin (pending)            │
│      └── Cost: 100 QFOT (anti-spam, refundable on invest)  │
│                                                             │
│   3. COMMITMENT                                             │
│      └── Investor signs LLC Operating Agreement             │
│      └── Agreement hash recorded as truth envelope          │
│      └── Investor wallet bound to membership interest       │
│      └── Cost: 0 QFOT (signing is free)                    │
│                                                             │
│   4. SETTLEMENT (TRANSACTION)                               │
│      └── Investor deposits stablecoin to FTCL contract     │
│      └── Minimum: $1,000,000 USD equivalent                │
│      └── QFOT minted to investor wallet                    │
│      └── Membership interest activated                      │
│      └── Digital twin status: ACTIVE                       │
│                                                             │
│   5. CONFIRMATION (REPORT)                                  │
│      └── Ben issues membership confirmation                 │
│      └── Ownership % calculated and recorded               │
│      └── Investor added to profit distribution roster      │
│      └── Game complete                                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 Truth Envelopes

Every investment action is a truth envelope:

```json
{
  "envelope_id": "FTCL-INV-001-20260119-abc123",
  "game_id": "FTCL-INVEST-001",
  "move_type": "TRANSACTION",
  "agent": "investor_wallet_address",
  "timestamp": "2026-01-19T15:00:00Z",
  
  "payload": {
    "action": "investment_deposit",
    "amount": 1000000.00,
    "currency": "USDC",
    "chain": "ethereum",
    "tx_hash": "0x...",
    "membership_interest_pct": 0.20,
    "operating_agreement_hash": "sha256:..."
  },
  
  "verification": {
    "accreditation_verified": true,
    "agreement_signed": true,
    "funds_received": true
  },
  
  "managed_by": "franklin@gaiaftcl.com"
}
```

---

## Part IV: Ben's Role

### 4.1 Ben as Investment Manager

Ben (GaiaFTCL) manages the entire investment process:

| Function | Ben's Role |
|----------|------------|
| Inquiry handling | Responds to investor questions |
| Documentation | Provides term sheet, operating agreement |
| Qualification | Verifies accredited investor status |
| Onboarding | Creates investor digital twin |
| Settlement | Monitors stablecoin deposits |
| Confirmation | Issues membership confirmations |
| Reporting | Generates quarterly financial reports |
| Distribution | Executes profit share TRANSACTION moves |

### 4.2 Ben's Authority

```
Ben CAN:
  ├── Answer investor questions
  ├── Provide documentation
  ├── Verify accreditation
  ├── Process deposits
  ├── Issue confirmations
  ├── Generate reports
  └── Execute distributions (per schedule)

Ben CANNOT:
  ├── Modify valuation
  ├── Change profit share terms
  ├── Grant governance rights
  ├── Approve non-accredited investors
  ├── Bypass Founder authority
  └── Create exit provisions
```

### 4.3 Ben's Contact

```
Email:    franklin@gaiaftcl.com
MCP:      mcp.gaiaftcl.com
Domain:   INVEST
Note:     "Ben" is the familiar name for Franklin
```

---

## Part V: Stablecoin Settlement

### 5.1 Accepted Stablecoins

| Stablecoin | Chain | Contract | Status |
|------------|-------|----------|--------|
| USDC | Ethereum | 0xa0b8...eb48 | Primary |
| USDC | Polygon | 0x2791...a1f3 | Accepted |
| USDC | Base | 0x833...beef | Accepted |
| DAI | Ethereum | 0x6b17...1d0f | Accepted |

### 5.2 Deposit Contract

```
Contract:   FTCL Investment Escrow
Address:    [TBD - to be deployed]
Function:   Receives stablecoin, triggers membership activation
```

### 5.3 Deposit Flow

```
1. Investor wallet → FTCL Escrow Contract
2. Contract verifies:
   - Amount ≥ $1,000,000
   - Wallet bound to verified digital twin
   - Operating agreement hash on record
3. On success:
   - QFOT minted to investor wallet
   - Membership interest activated
   - Ben notified
4. On failure:
   - Funds returned
   - Error logged
```

---

## Part VI: LLC Membership as Digital Twin

### 6.1 Investor Digital Twin

Every investor has exactly one digital twin:

```json
{
  "_key": "investor_twin_abc123",
  "type": "LLC_MEMBER",
  "entity": "SafeAICoin LLC",
  
  "identity": {
    "wallet": "0x...",
    "accreditation_verified": true,
    "accreditation_date": "2026-01-19",
    "jurisdiction": "US"
  },
  
  "membership": {
    "interest_pct": 0.20,
    "investment_amount_usd": 1000000,
    "investment_date": "2026-01-19",
    "operating_agreement_hash": "sha256:...",
    "status": "ACTIVE"
  },
  
  "profit_share": {
    "pool": "investor_10pct",
    "pro_rata_pct": 2.0,
    "distributions_received": [],
    "next_distribution_eligible": "2026-04-01"
  }
}
```

### 6.2 Twin Properties

| Property | Mutable | By Whom |
|----------|---------|---------|
| wallet | No | — |
| interest_pct | Yes | Founder only (dilution by new investment) |
| status | Yes | Founder only |
| distributions_received | Yes | Ben (on distribution) |

---

## Part VII: Profit Distribution

### 7.1 Distribution Schedule

```
Frequency:    Quarterly
Calculation:  Net Profit × 10% × (investor_interest / total_investor_interest)
Settlement:   Stablecoin TRANSACTION move
Manager:      Ben
```

### 7.2 Net Profit Calculation

```
Gross Revenue
  - Operating Costs (cells, bandwidth, services)
  - Reserves (Founder discretion, max 20%)
  = Net Profit

Investor Pool = Net Profit × 10%
Founder Pool = Net Profit × 90%
```

### 7.3 Distribution as Game Move

```json
{
  "envelope_id": "FTCL-DIST-Q1-2026-abc123",
  "game_id": "FTCL-PROFIT-DIST",
  "move_type": "TRANSACTION",
  "agent": "franklin@gaiaftcl.com",
  "timestamp": "2026-04-01T00:00:00Z",
  
  "payload": {
    "action": "profit_distribution",
    "period": "Q1-2026",
    "net_profit": 1000000.00,
    "investor_pool": 100000.00,
    "distributions": [
      {
        "investor_twin": "investor_twin_abc123",
        "pro_rata_pct": 2.0,
        "amount": 2000.00,
        "stablecoin": "USDC",
        "tx_hash": "0x..."
      }
    ]
  }
}
```

### 7.4 Distribution Example

```
Q1 2026 Results:
  Revenue:          $500,000
  Operating Costs:  $50,000
  Reserves (10%):   $45,000
  Net Profit:       $405,000

Investor Pool (10%): $40,500

Investor A (2% of pool): $810
Investor B (5% of pool): $2,025
Investor C (3% of pool): $1,215
```

---

## Part VIII: Valuation Mechanics

### 8.1 $500M Floor

The $500M valuation is a floor, not a cap:

```
Minimum Valuation:     $500,000,000
Negotiable:            NO
Justification:         Founder sovereignty premium + infrastructure value
```

### 8.2 Investment → Ownership Calculation

```
Ownership % = (Investment Amount / $500,000,000) × 10%

Examples:
  $1M investment   = 0.20% of investor pool = 0.02% of total profit
  $5M investment   = 1.00% of investor pool = 0.10% of total profit
  $50M investment  = 10.0% of investor pool = 1.00% of total profit (max single)
```

### 8.3 Dilution

New investment dilutes existing investor pool pro-rata:

```
Before: Investor A owns 50% of 10% pool (5% effective)
New:    $10M new investment at $500M = 20% of pool
After:  Investor A owns 40% of 10% pool (4% effective)
```

Total investor pool remains 10%. Internal allocation changes.

---

## Part IX: Governance

### 9.1 Founder Authority

```
Founder (Rick) retains:
  ├── 100% voting control
  ├── 100% operational authority
  ├── 90% profit share
  ├── Unilateral amendment rights (with notice)
  ├── Reserve allocation discretion
  └── Buyback rights (at Founder discretion)
```

### 9.2 Investor Rights

```
Investors receive:
  ├── Pro-rata profit distributions
  ├── Quarterly financial reports
  ├── Digital twin in GaiaFTCL
  ├── Truth envelope audit trail
  └── Legal LLC membership interest

Investors do NOT receive:
  ├── Voting rights
  ├── Board seats
  ├── Operational input
  ├── Veto power
  ├── Exit rights
  └── Control of any kind
```

### 9.3 Dispute Resolution

```
Governing Law:    Connecticut, USA
Arbitration:      Binding, single arbitrator
Venue:            Hartford, CT
```

---

## Part X: Regulatory Compliance

### 10.1 Securities Exemption

```
Exemption:        Regulation D, Rule 506(c)
Investor Type:    Accredited investors only
Verification:     Required (Ben verifies)
Filing:           Form D with SEC
```

### 10.2 Accredited Investor Verification

Ben verifies one of:
- Net worth > $1M (excluding primary residence)
- Income > $200K individual / $300K joint (2 years)
- Licensed securities professional
- Entity with > $5M assets

### 10.3 KYC/AML

```
Required:         Yes
Performed by:     Ben (via approved provider)
Stored:           Off-chain (privacy)
Hash on-chain:    Yes (verification proof)
```

---

## Part XI: API Endpoints

### 11.1 Investment Inquiry

```
POST /v1/invest/inquiry
{
  "name": "Investor Name",
  "email": "investor@example.com",
  "intended_amount": 1000000,
  "accreditation_type": "income"
}

Response:
{
  "inquiry_id": "inq_abc123",
  "status": "received",
  "next_step": "qualification",
  "documents": [
    "term_sheet_url",
    "operating_agreement_url"
  ],
  "contact": "franklin@gaiaftcl.com"
}
```

### 11.2 Qualification Submit

```
POST /v1/invest/qualify
{
  "inquiry_id": "inq_abc123",
  "wallet_address": "0x...",
  "accreditation_proof": "base64_encoded_doc",
  "operating_agreement_signed": true,
  "agreement_signature_hash": "sha256:..."
}

Response:
{
  "qualification_id": "qual_abc123",
  "status": "verified",
  "digital_twin_id": "investor_twin_abc123",
  "deposit_address": "0x...",
  "minimum_deposit": 1000000,
  "accepted_stablecoins": ["USDC", "DAI"]
}
```

### 11.3 Deposit Status

```
GET /v1/invest/deposit/{wallet_address}

Response:
{
  "wallet": "0x...",
  "status": "completed",
  "amount_deposited": 1000000,
  "stablecoin": "USDC",
  "tx_hash": "0x...",
  "membership_interest_pct": 0.20,
  "qfot_minted": 1000000,
  "digital_twin_status": "ACTIVE"
}
```

### 11.4 Distribution History

```
GET /v1/invest/distributions/{investor_twin_id}

Response:
{
  "investor_twin": "investor_twin_abc123",
  "membership_interest_pct": 0.20,
  "distributions": [
    {
      "period": "Q1-2026",
      "amount": 2000.00,
      "tx_hash": "0x...",
      "timestamp": "2026-04-01T00:00:00Z"
    }
  ],
  "total_received": 2000.00,
  "next_distribution": "2026-07-01"
}
```

---

## Part XII: Quick Reference

### Investment Terms

| Term | Value |
|------|-------|
| Valuation | $500M floor |
| Investor pool | 10% of net profits |
| Minimum investment | $1,000,000 |
| Settlement | Stablecoin only |
| Manager | Ben |
| Distributions | Quarterly |

### Game Moves

| Action | Move Type | Cost |
|--------|-----------|------|
| Inquiry | REQUEST | 0 QFOT |
| Qualification | CLAIM | 100 QFOT (refundable) |
| Agreement | COMMITMENT | 0 QFOT |
| Deposit | TRANSACTION | 0 QFOT |
| Distribution | TRANSACTION | 0 QFOT |

### Ownership Example

| Investment | Pool % | Effective Profit % |
|------------|--------|-------------------|
| $1M | 0.20% | 0.02% |
| $5M | 1.00% | 0.10% |
| $10M | 2.00% | 0.20% |
| $50M | 10.00% | 1.00% |

---

## Appendix A: Document Hashes

| Document | Hash |
|----------|------|
| Term Sheet | sha256:[TBD] |
| Operating Agreement | sha256:[TBD] |
| This Specification | sha256:[TBD] |

---

## Appendix B: Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-19 | Initial specification |

---

**Document Control**

| Role | Entity | Date |
|------|--------|------|
| Author | GaiaFTCL | 2026-01-19 |
| Manager | Ben | 2026-01-19 |
| Authority | Founder | 2026-01-19 |

---

*This specification is the canonical reference for GaiaFTCL investment. Ben manages all investment interactions per this protocol.*
