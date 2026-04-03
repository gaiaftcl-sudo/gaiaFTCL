#!/usr/bin/env python3
"""
Mailcow Bridge — internal ops only via docker exec (mysql, doveadm).
No Mailcow HTTP API. Called by MCP gateway only.
Constitutional: no direct Mailcow access from outside; gateway proxies here.
"""
import os
import hashlib
import base64
import secrets
from fastapi import FastAPI, HTTPException
import docker

app = FastAPI(title="Mailcow Bridge")
DOVECOT_CONTAINER = os.getenv("DOVECOT_CONTAINER", "mailcowdockerized-backup-dovecot-mailcow-1")
MYSQL_CONTAINER = os.getenv("MYSQL_CONTAINER", "mailcowdockerized-backup-mysql-mailcow-1")
POSTFIX_CONTAINER = os.getenv("POSTFIX_CONTAINER", "mailcowdockerized-backup-postfix-mailcow-1")
MYSQL_PASSWORD = os.getenv("MYSQL_PASSWORD", "a7f8c9d2e3b4f1a0987654321fedcba0")
DOMAIN = os.getenv("MAILCOW_DOMAIN", "gaiaftcl.com")

_docker_client = None

def _get_docker():
    global _docker_client
    if _docker_client is None:
        _docker_client = docker.from_env()
    return _docker_client


def _mysql_exec(query: str, silent: bool = False) -> str:
    """Run MySQL via docker exec (internal only)"""
    cmd = ["mysql", "-u", "mailcow", f"-p{MYSQL_PASSWORD}", "mailcow"]
    if silent:
        cmd.extend(["-s", "-N"])
    cmd.extend(["-e", query])
    container = _get_docker().containers.get(MYSQL_CONTAINER)
    exit_code, output = container.exec_run(cmd)
    return output.decode() if output else ""


def _hash_password(password: str) -> str:
    """SSHA256 hash for Mailcow."""
    salt = secrets.token_bytes(16)
    h = hashlib.sha256(password.encode() + salt).digest()
    return "{SSHA256}" + base64.b64encode(h + salt).decode()


@app.get("/health")
async def health():
    return {"status": "healthy", "service": "mailcow-bridge"}


def _esc(s: str) -> str:
    return s.replace("'", "''").replace("\\", "\\\\")


@app.post("/mailbox/create")
async def create_mailbox(request: dict):
    """Create mailbox via docker exec mysql. Requires caller_id."""
    if not request.get("caller_id"):
        raise HTTPException(status_code=400, detail="caller_id required")
    local_part = request.get("local_part") or (request.get("email", "").split("@")[0])
    name = request.get("name", local_part)
    password = request.get("password", "")
    if not local_part or not password:
        raise HTTPException(status_code=400, detail="local_part and password required")
    email = f"{local_part}@{DOMAIN}"
    # Get pass hash from franklin if exists, else hash provided password
    pass_hash = _mysql_exec("SELECT password FROM mailbox WHERE username='franklin@gaiaftcl.com'", silent=True).strip()
    if not pass_hash:
        pass_hash = _hash_password(password)
    sql = f"""
DELETE FROM mailbox WHERE username = '{_esc(email)}';
DELETE FROM alias WHERE address = '{_esc(email)}';
INSERT INTO mailbox (username, password, name, quota, local_part, domain, active, kind, mailbox_path_prefix, attributes, custom_attributes, multiple_bookings, authsource)
VALUES ('{_esc(email)}', '{_esc(pass_hash)}', '{_esc(name)}', 0, '{_esc(local_part)}', '{DOMAIN}', 1, '', '/var/vmail/', '{{\"mailbox_format\":\"maildir:\"}}', '{{}}', -1, 'mailcow');
INSERT INTO alias (address, goto, domain, active) VALUES ('{_esc(email)}', '{_esc(email)}', '{DOMAIN}', 1);
"""
    _mysql_exec(sql)
    # Reload postfix/dovecot
    try:
        _get_docker().containers.get(POSTFIX_CONTAINER).exec_run("postfix reload")
        _get_docker().containers.get(DOVECOT_CONTAINER).restart(timeout=30)
    except Exception:
        pass
    return {"status": "created", "email": email}


@app.get("/mailboxes")
async def list_mailboxes(caller_id: str = ""):
    """List mailboxes via docker exec mysql."""
    if not caller_id:
        raise HTTPException(status_code=400, detail="caller_id required")
    out = _mysql_exec("SELECT username FROM mailbox WHERE active=1", silent=True)
    mailboxes = [line.strip() for line in out.splitlines() if line.strip() and "@" in line]
    return {"mailboxes": mailboxes}


@app.post("/fetch_verification_email")
async def fetch_verification_email(request: dict):
    """Fetch verification email body via doveadm. Requires caller_id."""
    if not request.get("caller_id"):
        raise HTTPException(status_code=400, detail="caller_id required")
    email = request.get("email")
    subject_filter = request.get("subject_filter", "Verify your email")
    if not email:
        raise HTTPException(status_code=400, detail="email required")
    try:
        container = _get_docker().containers.get(DOVECOT_CONTAINER)
        exit_code, output = container.exec_run(
            ["doveadm", "fetch", "-u", email, "text", "SUBJECT", subject_filter]
        )
        body = output.decode() if output else ""
        link = None
        for line in body.splitlines():
            for prefix in ("https://gaiaftcl.com/verify/",):
                if prefix in line:
                    for word in line.split():
                        if word.startswith(prefix):
                            link = word.strip(".,;:)")
                            break
                    if link:
                        break
            if link:
                break
        return {"email": email, "body_preview": body[:500], "verification_link": link}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
