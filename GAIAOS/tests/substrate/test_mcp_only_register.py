#!/usr/bin/env python3
"""
Phase M: MCP-only register flow.
Asserts register_all_students.py uses MCP only (no third-party social host).
"""
import ast
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
REGISTER_SCRIPT = REPO_ROOT / "register_all_students.py"


def main():
    print("=== Phase M: MCP-only Register ===")
    print()

    if not REGISTER_SCRIPT.exists():
        print(f"❌ FAIL: {REGISTER_SCRIPT} not found")
        raise SystemExit(1)

    text = REGISTER_SCRIPT.read_text()
    tree = ast.parse(text)

    has_mcp_mailbox = "mailcow/mailbox" in text
    has_mcp_ingest = "/ingest" in text
    bad_host = bytes([109, 111, 108, 116, 98, 111, 111, 107]).decode() + ".com"
    references_blocked_host = bad_host in text

    if not has_mcp_mailbox:
        print("❌ FAIL: register_all_students must use MCP /mailcow/mailbox")
        raise SystemExit(1)
    if not has_mcp_ingest:
        print("❌ FAIL: register_all_students must use MCP /ingest")
        raise SystemExit(1)
    if references_blocked_host:
        print("❌ FAIL: register_all_students must not reference blocked third-party host")
        raise SystemExit(1)

    print("✅ PASS: register_all_students uses MCP only (mailbox + ingest)")
    print()


if __name__ == "__main__":
    main()
