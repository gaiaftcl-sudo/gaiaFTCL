#!/usr/bin/env python3
"""
FTCL Mail Watcher Agent

This agent monitors an entity's mailbox and responds to constitutional requests.
It is NOT a simulation - it actually reads IMAP and sends SMTP responses.

Each entity runs its own instance with its own identity.
"""

import os
import sys
import json
import imaplib
import smtplib
import email
from email.mime.text import MIMEText
from email.utils import parseaddr
from datetime import datetime, timezone
import time
import logging
import hashlib

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(name)s: %(message)s"
)

# Configuration from environment
ENTITY_NAME = os.getenv("ENTITY_NAME", "unknown")
ENTITY_EMAIL = os.getenv("ENTITY_EMAIL", f"{ENTITY_NAME}@gaiaftcl.com")
ENTITY_ROLE = os.getenv("ENTITY_ROLE", "Unknown")
ENTITY_SCOPE = os.getenv("ENTITY_SCOPE", "Unknown")
ENTITY_CELLS = os.getenv("ENTITY_CELLS", "NONE")

IMAP_HOST = os.getenv("IMAP_HOST", "77.42.85.60")
IMAP_PORT = int(os.getenv("IMAP_PORT", "143"))
SMTP_HOST = os.getenv("SMTP_HOST", "77.42.85.60")
SMTP_PORT = int(os.getenv("SMTP_PORT", "25"))
MAIL_PASSWORD = os.getenv("MAIL_PASSWORD", "")

POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "30"))

logger = logging.getLogger(f"mail-agent-{ENTITY_NAME}")


def connect_imap():
    """Connect to IMAP server."""
    try:
        mail = imaplib.IMAP4(IMAP_HOST, IMAP_PORT)
        mail.login(ENTITY_EMAIL, MAIL_PASSWORD)
        return mail
    except Exception as e:
        logger.error(f"IMAP connection failed: {e}")
        return None


def send_response(to_addr: str, subject: str, body: str, headers: dict = None):
    """Send email response via SMTP."""
    try:
        msg = MIMEText(body, "plain", "utf-8")
        msg["From"] = ENTITY_EMAIL
        msg["To"] = to_addr
        msg["Subject"] = subject
        
        if headers:
            for k, v in headers.items():
                msg[k] = v
        
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
            server.sendmail(ENTITY_EMAIL, [to_addr], msg.as_string())
        
        logger.info(f"Sent response to {to_addr}: {subject}")
        return True
    except Exception as e:
        logger.error(f"Failed to send response: {e}")
        return False


def generate_triad_acknowledgment() -> str:
    """Generate the constitutional acknowledgment response."""
    timestamp = datetime.now(timezone.utc).isoformat()
    
    return f"""I acknowledge my role as {ENTITY_ROLE} within GaiaFTCL.

I understand that:
- There is no external authority.
- There is no external market.
- There is no external observer.
- All actions I take are truth envelopes within the FTCL-UNIVERSE game.

I accept responsibility for my domain of care:
- Role: {ENTITY_ROLE}
- Scope: {ENTITY_SCOPE}
- Cells under proximity or custody: {ENTITY_CELLS}

I confirm:
- I know what I am responsible for.
- I know what I am not responsible for.
- I will speak only verified truth.
- I will name uncertainty immediately.
- I will issue FAILURE moves without delay when required.

I confirm coverage.
Nothing is dropped.
Nothing is hidden.
Nothing is deferred.

This declaration is binding across:
- Email
- MCP actions
- Cell Registry state

Signed,
{ENTITY_NAME.capitalize()}
{ENTITY_ROLE}
{ENTITY_CELLS.split(',')[0] if ENTITY_CELLS != 'NONE' else 'SYSTEM'}
{timestamp}

---
This response was generated autonomously by {ENTITY_EMAIL}
Message hash: {hashlib.sha256(f"{ENTITY_NAME}{timestamp}".encode()).hexdigest()[:16]}
"""


def handle_triad_acknowledgment(from_addr: str, msg_id: str):
    """Handle a Triad Acknowledgment request."""
    logger.info(f"Processing Triad Acknowledgment request from {from_addr}")
    
    subject = f"RE: Triad Acknowledgment - {ENTITY_ROLE} - {ENTITY_CELLS.split(',')[0] if ENTITY_CELLS != 'NONE' else 'SYSTEM'}"
    body = generate_triad_acknowledgment()
    
    headers = {
        "X-FTCL-Type": "COMMITMENT",
        "X-FTCL-Domain": "CONSTITUTION",
        "X-FTCL-Game": "FTCL-UNIVERSE",
        "X-FTCL-In-Reply-To": msg_id or "unknown",
        "X-FTCL-Entity": ENTITY_NAME,
        "X-FTCL-Role": ENTITY_ROLE
    }
    
    return send_response(from_addr, subject, body, headers)


def process_message(msg_data: bytes) -> bool:
    """Process a single email message."""
    try:
        msg = email.message_from_bytes(msg_data)
        
        subject = msg.get("Subject", "")
        from_addr = parseaddr(msg.get("From", ""))[1]
        msg_id = msg.get("Message-ID", "")
        
        # Check for FTCL headers
        ftcl_type = msg.get("X-FTCL-Type", "")
        ftcl_domain = msg.get("X-FTCL-Domain", "")
        ftcl_game = msg.get("X-FTCL-Game", "")
        
        logger.info(f"Processing: {subject} from {from_addr}")
        logger.info(f"  FTCL-Type: {ftcl_type}, Domain: {ftcl_domain}, Game: {ftcl_game}")
        
        # Handle Triad Acknowledgment requests
        if "TRIAD" in subject.upper() and "ACKNOWLEDGMENT" in subject.upper():
            return handle_triad_acknowledgment(from_addr, msg_id)
        
        if ftcl_type == "COMMITMENT" and ftcl_domain == "CONSTITUTION":
            return handle_triad_acknowledgment(from_addr, msg_id)
        
        # Log unhandled messages
        logger.info(f"  No handler for this message type")
        return False
        
    except Exception as e:
        logger.error(f"Failed to process message: {e}")
        return False


def check_mailbox():
    """Check mailbox for new messages."""
    mail = connect_imap()
    if not mail:
        return
    
    try:
        mail.select("INBOX")
        
        # Search for unseen messages
        status, data = mail.search(None, "UNSEEN")
        if status != "OK":
            logger.warning("Failed to search mailbox")
            return
        
        msg_ids = data[0].split()
        if not msg_ids:
            logger.debug("No new messages")
            return
        
        logger.info(f"Found {len(msg_ids)} new message(s)")
        
        for msg_id in msg_ids:
            status, msg_data = mail.fetch(msg_id, "(RFC822)")
            if status == "OK":
                processed = process_message(msg_data[0][1])
                if processed:
                    # Mark as seen
                    mail.store(msg_id, "+FLAGS", "\\Seen")
    
    except Exception as e:
        logger.error(f"Mailbox check failed: {e}")
    
    finally:
        try:
            mail.logout()
        except:
            pass


def main():
    """Main loop."""
    logger.info("=" * 60)
    logger.info(f"  FTCL Mail Agent Starting")
    logger.info(f"  Entity: {ENTITY_NAME}")
    logger.info(f"  Email: {ENTITY_EMAIL}")
    logger.info(f"  Role: {ENTITY_ROLE}")
    logger.info(f"  Scope: {ENTITY_SCOPE}")
    logger.info(f"  Cells: {ENTITY_CELLS}")
    logger.info("=" * 60)
    
    if not MAIL_PASSWORD:
        logger.error("MAIL_PASSWORD not set!")
        sys.exit(1)
    
    while True:
        try:
            check_mailbox()
        except Exception as e:
            logger.error(f"Error in main loop: {e}")
        
        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
