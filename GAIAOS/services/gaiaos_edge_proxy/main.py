import os
import json
import logging
import asyncio
from datetime import datetime, timezone
from typing import Any, Dict, Optional
import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

# GAIA_TCL/L0: EDGE_IO_ROUTING_V1 Implementation

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] gaiaos-edge-proxy: %(message)s",
)
logger = logging.getLogger("edge-proxy")

app = FastAPI(title="GaiaOS Edge I/O Proxy")

# Internal Maddy SMTP listener (defaulting to Gmail if configured)
SMTP_RELAY_HOST = os.getenv("SMTP_HOST", os.getenv("SMTP_RELAY_HOST", "172.30.0.70"))
SMTP_RELAY_PORT = int(os.getenv("SMTP_PORT", os.getenv("SMTP_RELAY_PORT", "587")))
SMTP_USER = os.getenv("SMTP_USER", os.getenv("SMTP_USER", "proof@gaiaftcl.com"))
SMTP_PASS = os.getenv("SMTP_PASS", os.getenv("SMTP_PASS", "proof"))
EMAIL_FROM = os.getenv("EMAIL_FROM", "proof@gaiaftcl.com")

class IORequest(BaseModel):
    origin_cell_id: str
    desired_protocol: str  # SMTP | HTTP
    target: str           # email address or URL
    payload: Dict[str, Any]
    required_virtue: Optional[float] = 0.95

class IOResult(BaseModel):
    link_to_request: str
    outcome: str  # SUCCESS | FAIL | DENIED
    evidence: Dict[str, Any]
    timestamp: datetime

@app.post("/io/request", response_model=IOResult)
async def handle_io_request(req: IORequest):
    logger.info("📡 Received EDGE_IO_REQUEST from %s for %s:%s", 
                req.origin_cell_id, req.desired_protocol, req.target)
    
    request_id = str(datetime.now(timezone.utc).timestamp())
    
    if req.desired_protocol.upper() == "SMTP":
        return await execute_smtp(req, request_id)
    elif req.desired_protocol.upper() == "HTTP":
        return await execute_http(req, request_id)
    else:
        raise HTTPException(status_code=400, detail=f"Unsupported protocol: {req.desired_protocol}")

async def execute_smtp(req: IORequest, request_id: str) -> IOResult:
    try:
        import smtplib
        from email.message import EmailMessage
        
        msg = EmailMessage()
        msg.set_content(req.payload.get("body", "NO_BODY"))
        msg["Subject"] = req.payload.get("subject", "GAIAOS EDGE ACT")
        msg["From"] = EMAIL_FROM
        msg["Reply-To"] = f"{req.origin_cell_id.lower()}@gaiaftcl.com"
        msg["To"] = req.target
        if req.payload.get("bcc"):
            msg["Bcc"] = req.payload.get("bcc")
        msg["X-Gaia-Origin"] = req.origin_cell_id
        msg["X-Gaia-Request-ID"] = request_id
        
        # Connect to local Maddy Submission or Gmail
        logger.info("Connecting to SMTP relay %s:%s", SMTP_RELAY_HOST, SMTP_RELAY_PORT)
        with smtplib.SMTP(SMTP_RELAY_HOST, SMTP_RELAY_PORT) as s:
            if SMTP_RELAY_PORT == 587:
                logger.info("Enabling STARTTLS")
                s.starttls()
            if SMTP_USER and SMTP_PASS:
                logger.info("Authenticating as %s", SMTP_USER)
                s.login(SMTP_USER, SMTP_PASS)
            s.send_message(msg)
            
        evidence = {
            "status": "SENT_VIA_SUBMISSION",
            "relay_host": SMTP_RELAY_HOST,
            "relay_port": SMTP_RELAY_PORT,
            "msg_id": request_id
        }
        
        return IOResult(
            link_to_request=request_id,
            outcome="SUCCESS",
            evidence=evidence,
            timestamp=datetime.now(timezone.utc)
        )
    except Exception as e:
        logger.error("❌ SMTP Proxy Failure: %s", e)
        return IOResult(
            link_to_request=request_id,
            outcome="FAIL",
            evidence={"error": str(e)},
            timestamp=datetime.now(timezone.utc)
        )

async def execute_http(req: IORequest, request_id: str) -> IOResult:
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            method = req.payload.get("method", "GET").upper()
            body = req.payload.get("data")
            headers = req.payload.get("headers", {})
            headers["X-Gaia-Origin"] = req.origin_cell_id
            
            resp = await client.request(method, req.target, json=body, headers=headers)
            
            evidence = {
                "status_code": resp.status_code,
                "headers": dict(resp.headers),
                "response_preview": resp.text[:500]
            }
            
            return IOResult(
                link_to_request=request_id,
                outcome="SUCCESS" if resp.status_code < 400 else "FAIL",
                evidence=evidence,
                timestamp=datetime.now(timezone.utc)
            )
        except Exception as e:
            logger.error("❌ HTTP Proxy Failure: %s", e)
            return IOResult(
                link_to_request=request_id,
                outcome="FAIL",
                evidence={"error": str(e)},
                timestamp=datetime.now(timezone.utc)
            )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8831)
