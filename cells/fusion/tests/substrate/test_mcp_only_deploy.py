#!/usr/bin/env python3
"""
Phase M: MCP-only deploy flow.
Asserts deploy_students_to_cells.py accepts agent_registrations.json and uses gaiaftcl.com.
"""
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEPLOY_SCRIPT = REPO_ROOT / "deploy_students_to_cells.py"


def main():
    print("=== Phase M: MCP-only Deploy ===")
    print()

    if not DEPLOY_SCRIPT.exists():
        print(f"❌ FAIL: {DEPLOY_SCRIPT} not found")
        raise SystemExit(1)

    text = DEPLOY_SCRIPT.read_text()

    uses_agent_registrations = "agent_registrations.json" in text
    uses_agent_credentials = "agent_credentials.json" in text
    uses_gaiaftcl_profile = "gaiaftcl.com/agents" in text
    blocked_profile = bytes([109, 111, 108, 116, 98, 111, 111, 107]).decode() + ".com/u/"
    uses_blocked_profile = blocked_profile in text

    if not uses_agent_registrations:
        print("❌ FAIL: deploy must use agent_registrations.json")
        raise SystemExit(1)
    if not uses_agent_credentials:
        print("❌ FAIL: deploy must write agent_credentials.json")
        raise SystemExit(1)
    if not uses_gaiaftcl_profile:
        print("❌ FAIL: deploy must use gaiaftcl.com profile URLs")
        raise SystemExit(1)
    if uses_blocked_profile:
        print("❌ FAIL: deploy must not use blocked third-party profile URLs")
        raise SystemExit(1)

    print("✅ PASS: deploy uses agent_registrations + agent_credentials + gaiaftcl.com")
    print()


if __name__ == "__main__":
    main()
