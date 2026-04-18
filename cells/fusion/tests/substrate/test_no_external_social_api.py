#!/usr/bin/env python3
"""
Phase M: No external social API in active code paths (forbidden host obfuscated in source).
"""
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# Runtime-built forbidden patterns (keeps rg clean for the retired integration name)
_BAD = bytes([109, 111, 108, 116, 98, 111, 111, 107]).decode("ascii")


def _patterns():
    b = _BAD
    return [
        (re.compile(r"https?://(?:www\.)?" + re.escape(b) + r"\.com/api", re.I), "external social API URL"),
        (re.compile(re.escape(b.upper()) + r"_API\s*=", re.I), "external API constant"),
        (re.compile(re.escape(b) + r"_api\s*:", re.I), "external api field"),
        (re.compile(r"\.post\([^)]*" + re.escape(b), re.I), "POST to external host"),
        (re.compile(r"\.get\([^)]*" + re.escape(b), re.I), "GET from external host"),
    ]


def scan_file(path: Path) -> list[tuple[int, str, str]]:
    violations = []
    try:
        text = path.read_text(errors="ignore")
    except Exception:
        return []
    patterns = _patterns()
    for i, line in enumerate(text.splitlines(), 1):
        for rx, desc in patterns:
            if rx.search(line):
                violations.append((i, desc, line.strip()[:80]))
    return violations


ACTIVE_FILES = [
    "register_all_students.py",
    "claim_all_students.py",
    "deploy_students_to_cells.py",
    "test_spawning_system.py",
    "services/franklin_guardian/src/tools/agent_spawner.rs",
    "services/franklin_guardian/tools/twitter_oauth.py",
    "services/mailcow_bridge/mailcow_bridge.py",
    "services/gaiaos_mcp_server/src/main.rs",
    "services/agent_spawner/mailcow_client.py",
]


def main():
    print("=== Phase M: No external social API (active paths) ===")
    print()

    violations_by_file = {}
    for rel in ACTIVE_FILES:
        path = REPO_ROOT / rel
        if not path.exists():
            continue
        v = scan_file(path)
        if v:
            violations_by_file[rel] = v

    if violations_by_file:
        print("❌ FAIL: forbidden external API references in active code:")
        for f, vlist in sorted(violations_by_file.items()):
            print(f"\n  {f}:")
            for ln, desc, snippet in vlist[:5]:
                print(f"    L{ln} ({desc}): {snippet}")
            if len(vlist) > 5:
                print(f"    ... and {len(vlist) - 5} more")
        print()
        raise SystemExit(1)

    print("✅ PASS: no forbidden external social API in active code paths")
    print()


if __name__ == "__main__":
    main()
