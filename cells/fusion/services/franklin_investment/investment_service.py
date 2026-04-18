#!/usr/bin/env python3
"""
Franklin's Investment Service - GaiaFTCL Infrastructure Investment Manager

"Ben" is the familiar name for Franklin (franklin@gaiaftcl.com).

Per FTCL-INV-001, Franklin manages the entire investment process:
- Inquiry handling
- Accreditation verification
- Operating agreement signing
- Stablecoin settlement
- Membership confirmation
- Quarterly profit distributions

Ben CANNOT:
- Modify valuation ($500M floor)
- Change profit share terms (10% investor / 90% founder)
- Grant governance rights
- Approve non-accredited investors
- Create exit provisions
"""

import os
import json
import hashlib
import logging
from datetime import datetime, timezone
from decimal import Decimal
from typing import Dict, Any, Optional, List
from uuid import uuid4
from enum import Enum

from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, EmailStr
import httpx

logging.basicConfig(level=logging.INFO, format="[%(asctime)s] %(levelname)s: %(message)s")
logger = logging.getLogger("ben-investment")

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION - NON-NEGOTIABLE
# ═══════════════════════════════════════════════════════════════════════════════

VALUATION_FLOOR = Decimal("500000000")  # $500M - NOT NEGOTIABLE
INVESTOR_POOL_PCT = Decimal("10")       # 10% of net profit - NOT NEGOTIABLE
FOUNDER_POOL_PCT = Decimal("90")        # 90% of net profit - NOT NEGOTIABLE
MINIMUM_INVESTMENT = Decimal("1000000") # $1M minimum - NOT NEGOTIABLE
QUALIFICATION_FEE_QFOT = 100            # Refundable on investment

CELL_ID = os.getenv("CELL_ID", "ben-investment")
ARANGO_URL = os.getenv("ARANGO_URL", "http://gaiaftcl-arangodb:8529")
ARANGO_DB = os.getenv("ARANGO_DB", "gaiaos")
ARANGO_USER = os.getenv("ARANGO_USER", "root")
ARANGO_PASSWORD = os.getenv("ARANGO_PASSWORD", "gaiaftcl2026")

# ═══════════════════════════════════════════════════════════════════════════════
# MODELS
# ═══════════════════════════════════════════════════════════════════════════════

class AccreditationType(str, Enum):
    INCOME = "income"
    NET_WORTH = "net_worth"
    PROFESSIONAL = "professional"
    ENTITY = "entity"

class InvestorStatus(str, Enum):
    INQUIRY = "inquiry"
    QUALIFIED = "qualified"
    COMMITTED = "committed"
    ACTIVE = "active"
    SUSPENDED = "suspended"

class InquiryRequest(BaseModel):
    name: str
    email: EmailStr
    intended_amount: Decimal = Field(..., ge=MINIMUM_INVESTMENT)
    accreditation_type: AccreditationType

class QualificationRequest(BaseModel):
    inquiry_id: str
    wallet_address: str = Field(..., pattern=r"^0x[a-fA-F0-9]{40}$")
    accreditation_proof_hash: str = Field(..., pattern=r"^sha256:[a-f0-9]{64}$")

class CommitmentRequest(BaseModel):
    qualification_id: str
    operating_agreement_signed: bool = Field(..., const=True)
    agreement_signature_hash: str = Field(..., pattern=r"^sha256:[a-f0-9]{64}$")

class DepositNotification(BaseModel):
    wallet_address: str
    amount: Decimal = Field(..., ge=MINIMUM_INVESTMENT)
    stablecoin: str = Field(..., pattern=r"^(USDC|DAI)$")
    chain: str = Field(..., pattern=r"^(ethereum|polygon|base)$")
    tx_hash: str

class InvestorTwin(BaseModel):
    twin_id: str
    type: str = "LLC_MEMBER"
    entity: str = "SafeAICoin LLC"
    wallet: str
    name: str
    email: str
    accreditation_verified: bool
    accreditation_date: str
    accreditation_type: AccreditationType
    status: InvestorStatus
    investment_amount_usd: Optional[Decimal] = None
    investment_date: Optional[str] = None
    membership_interest_pct: Optional[Decimal] = None
    pool_pct: Optional[Decimal] = None
    operating_agreement_hash: Optional[str] = None
    distributions_received: List[Dict] = Field(default_factory=list)
    total_received: Decimal = Decimal("0")
    created_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())

class TruthEnvelope(BaseModel):
    envelope_id: str = Field(default_factory=lambda: f"FTCL-INV-{datetime.now().strftime('%Y%m%d')}-{uuid4().hex[:8]}")
    game_id: str = "G_FTCL_INVEST_001"
    move_type: str
    agent: str
    timestamp: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    payload: Dict[str, Any]
    managed_by: str = "franklin@gaiaftcl.com"

# ═══════════════════════════════════════════════════════════════════════════════
# APP SETUP
# ═══════════════════════════════════════════════════════════════════════════════

app = FastAPI(
    title="Franklin's Investment Service",
    version="1.0.0",
    description="GaiaFTCL Infrastructure Investment Manager"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

HTTP_CLIENT: Optional[httpx.AsyncClient] = None

@app.on_event("startup")
async def startup():
    global HTTP_CLIENT
    HTTP_CLIENT = httpx.AsyncClient(timeout=30.0)
    logger.info("═══════════════════════════════════════════════════════════════")
    logger.info("  BEN'S INVESTMENT SERVICE - STARTED")
    logger.info("═══════════════════════════════════════════════════════════════")
    logger.info(f"  Valuation Floor: ${VALUATION_FLOOR:,}")
    logger.info(f"  Investor Pool: {INVESTOR_POOL_PCT}%")
    logger.info(f"  Minimum Investment: ${MINIMUM_INVESTMENT:,}")
    logger.info("═══════════════════════════════════════════════════════════════")

@app.on_event("shutdown")
async def shutdown():
    if HTTP_CLIENT:
        await HTTP_CLIENT.aclose()

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

def calculate_ownership(investment_amount: Decimal) -> Dict[str, Decimal]:
    """Calculate ownership percentages from investment amount."""
    pool_pct = (investment_amount / VALUATION_FLOOR) * 100
    effective_pct = pool_pct * (INVESTOR_POOL_PCT / 100)
    return {
        "pool_pct": pool_pct,
        "effective_profit_pct": effective_pct,
        "membership_interest_pct": pool_pct / 10  # Pool % / 10 = membership %
    }

async def store_to_akg(collection: str, document: Dict) -> bool:
    """Store document to ArangoDB."""
    try:
        r = await HTTP_CLIENT.post(
            f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/{collection}",
            json=document,
            auth=(ARANGO_USER, ARANGO_PASSWORD)
        )
        return r.status_code in (200, 201, 202)
    except Exception as e:
        logger.error(f"Failed to store to AKG: {e}")
        return False

async def get_from_akg(collection: str, key: str) -> Optional[Dict]:
    """Get document from ArangoDB."""
    try:
        r = await HTTP_CLIENT.get(
            f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/{collection}/{key}",
            auth=(ARANGO_USER, ARANGO_PASSWORD)
        )
        if r.status_code == 200:
            return r.json()
    except Exception as e:
        logger.error(f"Failed to get from AKG: {e}")
    return None

async def emit_truth_envelope(envelope: TruthEnvelope) -> bool:
    """Store truth envelope to AKG."""
    return await store_to_akg("investment_envelopes", envelope.dict())

# ═══════════════════════════════════════════════════════════════════════════════
# API ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

@app.get("/health")
def health():
    return {
        "status": "healthy",
        "service": "ben-investment",
        "manager": "franklin@gaiaftcl.com",
        "valuation_floor": str(VALUATION_FLOOR),
        "investor_pool_pct": str(INVESTOR_POOL_PCT),
        "minimum_investment": str(MINIMUM_INVESTMENT)
    }

@app.get("/")
def root():
    return {
        "service": "Franklin's Investment Service",
        "version": "1.0.0",
        "manager": "franklin@gaiaftcl.com",
        "spec": "FTCL-INV-001",
        "games": ["G_FTCL_INVEST_001", "G_FTCL_PROFIT_DIST"],
        "contact": "ben@gaiaftcl.com"
    }

@app.get("/terms")
def get_terms():
    """Return investment terms (non-negotiable)."""
    return {
        "valuation_floor": str(VALUATION_FLOOR),
        "investor_pool_pct": str(INVESTOR_POOL_PCT),
        "founder_pool_pct": str(FOUNDER_POOL_PCT),
        "minimum_investment": str(MINIMUM_INVESTMENT),
        "settlement": "stablecoin_only",
        "accepted_stablecoins": ["USDC", "DAI"],
        "accepted_chains": ["ethereum", "polygon", "base"],
        "distributions": "quarterly",
        "governance_rights": "none",
        "exit_provisions": "none",
        "negotiable": False,
        "spec": "FTCL-INV-001"
    }

@app.post("/v1/invest/inquiry")
async def create_inquiry(request: InquiryRequest):
    """Handle investment inquiry (Move 1: INQUIRY)."""
    
    inquiry_id = f"inq_{uuid4().hex[:12]}"
    
    # Create truth envelope
    envelope = TruthEnvelope(
        move_type="REQUEST",
        agent=request.email,
        payload={
            "action": "investment_inquiry",
            "inquiry_id": inquiry_id,
            "name": request.name,
            "email": request.email,
            "intended_amount": str(request.intended_amount),
            "accreditation_type": request.accreditation_type.value
        }
    )
    
    await emit_truth_envelope(envelope)
    
    # Calculate projected ownership
    ownership = calculate_ownership(request.intended_amount)
    
    logger.info(f"Investment inquiry received: {inquiry_id} - ${request.intended_amount:,}")
    
    return {
        "inquiry_id": inquiry_id,
        "status": "received",
        "next_step": "qualification",
        "projected_ownership": {
            "pool_pct": str(ownership["pool_pct"]),
            "effective_profit_pct": str(ownership["effective_profit_pct"])
        },
        "documents": {
            "term_sheet": "https://gaiaftcl.com/docs/term_sheet.pdf",
            "operating_agreement": "https://gaiaftcl.com/docs/operating_agreement.pdf",
            "spec": "https://gaiaftcl.com/docs/FTCL-INV-001.md"
        },
        "contact": "franklin@gaiaftcl.com",
        "qualification_fee": f"{QUALIFICATION_FEE_QFOT} QFOT (refundable on investment)"
    }

@app.post("/v1/invest/qualify")
async def submit_qualification(request: QualificationRequest):
    """Handle qualification submission (Move 2: QUALIFICATION)."""
    
    qualification_id = f"qual_{uuid4().hex[:12]}"
    twin_id = f"investor_twin_{uuid4().hex[:12]}"
    
    # In production: verify accreditation proof
    # For now: create pending investor twin
    
    # Create investor digital twin (pending status)
    twin = InvestorTwin(
        twin_id=twin_id,
        wallet=request.wallet_address,
        name="[From inquiry]",  # Would be populated from inquiry
        email="[From inquiry]",
        accreditation_verified=True,  # Would be verified
        accreditation_date=datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        accreditation_type=AccreditationType.INCOME,  # Would come from inquiry
        status=InvestorStatus.QUALIFIED
    )
    
    await store_to_akg("investor_twins", {"_key": twin_id, **twin.dict()})
    
    # Create truth envelope
    envelope = TruthEnvelope(
        move_type="CLAIM",
        agent=request.wallet_address,
        payload={
            "action": "qualification_verified",
            "inquiry_id": request.inquiry_id,
            "qualification_id": qualification_id,
            "wallet_address": request.wallet_address,
            "accreditation_proof_hash": request.accreditation_proof_hash,
            "digital_twin_id": twin_id
        }
    )
    
    await emit_truth_envelope(envelope)
    
    logger.info(f"Investor qualified: {qualification_id} - Twin: {twin_id}")
    
    return {
        "qualification_id": qualification_id,
        "status": "verified",
        "digital_twin_id": twin_id,
        "deposit_address": "[ESCROW_CONTRACT_ADDRESS]",  # TBD
        "minimum_deposit": str(MINIMUM_INVESTMENT),
        "accepted_stablecoins": ["USDC", "DAI"],
        "accepted_chains": ["ethereum", "polygon", "base"],
        "next_step": "commitment",
        "fee_paid": f"{QUALIFICATION_FEE_QFOT} QFOT (refundable on investment)"
    }

@app.post("/v1/invest/commit")
async def submit_commitment(request: CommitmentRequest):
    """Handle commitment (Move 3: COMMITMENT)."""
    
    commitment_id = f"commit_{uuid4().hex[:12]}"
    
    # Create truth envelope
    envelope = TruthEnvelope(
        move_type="COMMITMENT",
        agent="[wallet_from_qualification]",
        payload={
            "action": "agreement_signed",
            "qualification_id": request.qualification_id,
            "commitment_id": commitment_id,
            "operating_agreement_signed": True,
            "agreement_signature_hash": request.agreement_signature_hash
        }
    )
    
    await emit_truth_envelope(envelope)
    
    logger.info(f"Commitment received: {commitment_id}")
    
    return {
        "commitment_id": commitment_id,
        "status": "committed",
        "agreement_hash": request.agreement_signature_hash,
        "next_step": "settlement",
        "deposit_instructions": {
            "send_to": "[ESCROW_CONTRACT_ADDRESS]",
            "minimum": str(MINIMUM_INVESTMENT),
            "stablecoins": ["USDC", "DAI"]
        }
    }

@app.post("/v1/invest/deposit")
async def process_deposit(notification: DepositNotification):
    """Handle deposit notification (Move 4: SETTLEMENT)."""
    
    # Verify deposit meets minimum
    if notification.amount < MINIMUM_INVESTMENT:
        raise HTTPException(
            status_code=400,
            detail=f"Deposit below minimum: ${notification.amount} < ${MINIMUM_INVESTMENT}"
        )
    
    # Calculate ownership
    ownership = calculate_ownership(notification.amount)
    
    # Create truth envelope
    envelope = TruthEnvelope(
        move_type="TRANSACTION",
        agent=notification.wallet_address,
        payload={
            "action": "investment_deposit",
            "amount": str(notification.amount),
            "currency": notification.stablecoin,
            "chain": notification.chain,
            "tx_hash": notification.tx_hash,
            "membership_interest_pct": str(ownership["membership_interest_pct"]),
            "pool_pct": str(ownership["pool_pct"])
        }
    )
    
    await emit_truth_envelope(envelope)
    
    logger.info(f"Deposit processed: ${notification.amount:,} from {notification.wallet_address}")
    
    return {
        "status": "completed",
        "wallet": notification.wallet_address,
        "amount_deposited": str(notification.amount),
        "stablecoin": notification.stablecoin,
        "chain": notification.chain,
        "tx_hash": notification.tx_hash,
        "ownership": {
            "membership_interest_pct": str(ownership["membership_interest_pct"]),
            "pool_pct": str(ownership["pool_pct"]),
            "effective_profit_pct": str(ownership["effective_profit_pct"])
        },
        "qfot_minted": str(notification.amount),
        "qualification_fee_refunded": f"{QUALIFICATION_FEE_QFOT} QFOT",
        "next_distribution": "Q1-2026"
    }

@app.get("/v1/invest/distributions/{twin_id}")
async def get_distributions(twin_id: str):
    """Get distribution history for an investor."""
    
    twin = await get_from_akg("investor_twins", twin_id)
    if not twin:
        raise HTTPException(status_code=404, detail="Investor twin not found")
    
    return {
        "investor_twin": twin_id,
        "membership_interest_pct": twin.get("membership_interest_pct", "0"),
        "pool_pct": twin.get("pool_pct", "0"),
        "distributions": twin.get("distributions_received", []),
        "total_received": twin.get("total_received", "0"),
        "next_distribution": "Q1-2026"
    }

@app.get("/v1/invest/ownership/{amount}")
async def calculate_ownership_preview(amount: int):
    """Preview ownership for a given investment amount."""
    
    if amount < MINIMUM_INVESTMENT:
        raise HTTPException(
            status_code=400,
            detail=f"Amount below minimum: ${amount:,} < ${MINIMUM_INVESTMENT:,}"
        )
    
    ownership = calculate_ownership(Decimal(amount))
    
    return {
        "investment_amount": amount,
        "valuation": str(VALUATION_FLOOR),
        "pool_pct": str(ownership["pool_pct"]),
        "effective_profit_pct": str(ownership["effective_profit_pct"]),
        "membership_interest_pct": str(ownership["membership_interest_pct"]),
        "example_quarterly_distribution": {
            "if_net_profit": 1000000,
            "investor_pool": 100000,
            "your_share": float(ownership["pool_pct"]) * 1000
        }
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8860)
