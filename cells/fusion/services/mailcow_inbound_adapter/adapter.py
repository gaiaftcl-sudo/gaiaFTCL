#!/usr/bin/env python3
"""
Mailcow inbound → MCP gateway POST /universal_ingest.

Intended for Postfix pipe(8): raw RFC822 on stdin.
Does not call /ask, LLMs, or Mailcow HTTP API.
"""

from __future__ import annotations

import importlib.util
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from email import policy
from email.header import decode_header, make_header
from email.message import EmailMessage
from email.parser import BytesParser
from email.utils import getaddresses, parsedate_to_datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# Load sibling queue.py without shadowing Python's stdlib `queue` module.
_qpath = Path(__file__).resolve().parent / "queue.py"
_spec = importlib.util.spec_from_file_location("gaiaftcl_inbound_queue", _qpath)
assert _spec and _spec.loader
_inbound_q = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_inbound_q)
enqueue_failure = _inbound_q.enqueue_failure

GAIAFTCL_GATEWAY = os.environ.get("GAIAFTCL_GATEWAY", "http://gaiaftcl-wallet-gate:8803").rstrip("/")
MAILCOW_DOMAIN = os.environ.get("MAILCOW_DOMAIN", "gaiaftcl.com").lower()
ADAPTER_CALLER_ID = os.environ.get("ADAPTER_CALLER_ID", "mailcow_inbound_adapter")
INTERNAL_SERVICE_KEY = os.environ.get("GAIAFTCL_INTERNAL_SERVICE_KEY", "").strip()

LOCAL_PART_TO_GAME_ROOM = {
    "research": "owl_protocol",
    "discovery": "discovery",
    "governance": "governance",
    "sovereign": "treasury",
    "ops": "sovereign_mesh",
    "receipts": "receipt_wall",
    "entropy": "open_loop_tracker",
}


def _log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def _decode_header_value(val: Optional[str]) -> str:
    if not val:
        return ""
    try:
        return str(make_header(decode_header(val)))
    except Exception:
        return val


def _first_address(header_val: Optional[str]) -> Tuple[str, str]:
    """Return (display_name, email) for first address in header."""
    if not header_val:
        return ("", "")
    pairs = getaddresses([header_val])
    if not pairs:
        return ("", "")
    name, addr = pairs[0]
    return (name.strip(), addr.strip().lower())


def _game_room_for_recipient(addr: str) -> str:
    if "@" not in addr:
        return "unclassified"
    local, _, domain = addr.partition("@")
    local = local.strip().lower()
    domain = domain.strip().lower()
    if domain != MAILCOW_DOMAIN:
        return "unclassified"
    return LOCAL_PART_TO_GAME_ROOM.get(local, "unclassified")


def _pick_game_room(to_header: str) -> str:
    """Use first To: address on our domain to select slice."""
    if not to_header:
        return "unclassified"
    for _, addr in getaddresses([to_header]):
        addr = addr.strip().lower()
        if not addr:
            continue
        gr = _game_room_for_recipient(addr)
        if gr != "unclassified":
            return gr
    # All recipients non-match — still classify first recipient bucket
    _, first = _first_address(to_header)
    if first:
        return _game_room_for_recipient(first)
    return "unclassified"


def _strip_html(text: str) -> str:
    text = re.sub(r"(?is)<script.*?>.*?</script>", "", text)
    text = re.sub(r"(?is)<style.*?>.*?</style>", "", text)
    text = re.sub(r"<[^>]+>", " ", text)
    return " ".join(text.split()).strip()


def _part_text(part: EmailMessage) -> str:
    try:
        return (part.get_content() or "").strip()
    except Exception:
        raw = part.get_payload(decode=True)
        if isinstance(raw, bytes):
            return raw.decode(part.get_content_charset() or "utf-8", errors="replace").strip()
        return str(raw or "").strip()


def _plain_body(msg: EmailMessage) -> str:
    if msg.is_multipart():
        html_fallback = ""
        for part in msg.walk():
            if part.get_content_maintype() == "multipart":
                continue
            ctype = part.get_content_type()
            if ctype == "text/plain":
                t = _part_text(part)
                if t:
                    return t
            elif ctype == "text/html" and not html_fallback:
                html_fallback = _strip_html(_part_text(part))
        if html_fallback:
            return html_fallback
    try:
        return (msg.get_content() or "").strip()
    except Exception:
        payload = msg.get_payload(decode=True)
        if isinstance(payload, bytes):
            return payload.decode("utf-8", errors="replace").strip()
        return str(payload or "").strip()


def _iso_date(msg: EmailMessage) -> str:
    ds = msg.get("Date")
    if not ds:
        from datetime import datetime, timezone

        return datetime.now(timezone.utc).isoformat()
    try:
        dt = parsedate_to_datetime(ds)
        if dt.tzinfo is None:
            from datetime import timezone

            dt = dt.replace(tzinfo=timezone.utc)
        return dt.isoformat()
    except Exception:
        from datetime import datetime, timezone

        return datetime.now(timezone.utc).isoformat()


def parse_mail(raw: bytes) -> Dict[str, Any]:
    msg = BytesParser(policy=policy.default).parsebytes(raw)
    assert isinstance(msg, EmailMessage)

    subj = _decode_header_value(msg.get("Subject"))
    to_raw = msg.get("To") or ""
    from_name, from_addr = _first_address(msg.get("From"))
    _, to_addr = _first_address(to_raw)
    reply_to = _decode_header_value(msg.get("Reply-To")) or ""
    mid = (msg.get("Message-ID") or "").strip()
    game_room = _pick_game_room(to_raw)
    body = _plain_body(msg)
    ts = _iso_date(msg)

    return {
        "game_room": game_room,
        "from": from_addr or from_name or "unknown",
        "from_display": from_name,
        "to": to_addr or _decode_header_value(to_raw),
        "to_raw": to_raw,
        "subject": subj,
        "body": body,
        "message_id": mid,
        "timestamp": ts,
        "reply_to": reply_to,
    }


def build_universal_ingest_body(parsed: Dict[str, Any]) -> Dict[str, Any]:
    payload = {
        "game_room": parsed["game_room"],
        "from": parsed["from"],
        "to": parsed["to"],
        "subject": parsed["subject"],
        "body": parsed["body"],
        "message_id": parsed["message_id"],
        "timestamp": parsed["timestamp"],
        "caller_id": ADAPTER_CALLER_ID,
        "status": "unresolved",
        "reply_to": parsed.get("reply_to") or "",
        "to_raw": parsed.get("to_raw") or "",
    }
    return {
        "type": "MAIL",
        "from": parsed["from"],
        "payload": payload,
    }


def post_universal_ingest(body: Dict[str, Any]) -> Tuple[bool, Dict[str, Any] | str]:
    url = f"{GAIAFTCL_GATEWAY}/universal_ingest"
    data = json.dumps(body).encode("utf-8")
    last_err = ""

    for attempt in range(3):
        try:
            headers = {"Content-Type": "application/json"}
            if INTERNAL_SERVICE_KEY:
                headers["X-Gaiaftcl-Internal-Key"] = INTERNAL_SERVICE_KEY
            req = urllib.request.Request(
                url,
                data=data,
                method="POST",
                headers=headers,
            )
            with urllib.request.urlopen(req, timeout=45) as resp:
                raw = resp.read().decode("utf-8")
                out = json.loads(raw) if raw.strip() else {}
                return True, out
        except urllib.error.HTTPError as e:
            last_err = f"HTTP {e.code}: {e.read().decode('utf-8', errors='replace')[:500]}"
        except urllib.error.URLError as e:
            last_err = f"URLError: {e.reason}"
        except Exception as e:
            last_err = str(e)

        _log(f"BLOCKED attempt {attempt + 1}/3: {last_err}")
        if attempt < 2:
            time.sleep(1.0 * (attempt + 1))

    return False, last_err


def main(argv: List[str]) -> int:
    if len(argv) > 1 and argv[1] in ("-h", "--help"):
        _log("Usage: adapter.py [path-to-.eml]  (default: read RFC822 from stdin)")
        return 0

    if len(argv) > 1:
        with open(argv[1], "rb") as f:
            raw = f.read()
    else:
        raw = sys.stdin.buffer.read()

    if not raw.strip():
        _log("BLOCKED: empty stdin / file")
        return 1

    try:
        parsed = parse_mail(raw)
    except Exception as e:
        _log(f"BLOCKED: parse error: {e}")
        return 1

    body = build_universal_ingest_body(parsed)
    ok, result = post_universal_ingest(body)

    if ok and isinstance(result, dict):
        key = result.get("claim_key") or result.get("claim_id")
        if result.get("accepted") is False:
            _log(f"BLOCKED: gateway rejected: {result}")
            path = enqueue_failure(
                claim_body=body,
                error=json.dumps(result),
                raw_meta={"message_id": parsed.get("message_id")},
            )
            _log(f"queued: {path}")
            return 1
        _log(f"receipt claim_key={key} outcome={result.get('outcome')}")
        return 0

    err = result if isinstance(result, str) else json.dumps(result)
    _log(f"BLOCKED: {err}")
    path = enqueue_failure(
        claim_body=body,
        error=err,
        raw_meta={"message_id": parsed.get("message_id")},
    )
    _log(f"queued: {path}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
