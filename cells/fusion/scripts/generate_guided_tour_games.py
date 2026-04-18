#!/usr/bin/env python3
"""
Emit spec/guided_tour/02_domains_mesh_generated.json from game_room_registry.json.
Deep intent trees: every branch ends in user_intent_closed + c4_witness (or explicit REFUSED).

S4 only — QFOT balances are policy placeholders until C4 ledger gates them.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REG = ROOT / "services" / "discord_frontier" / "game_room_registry.json"
OUT = ROOT / "spec" / "guided_tour" / "02_domains_mesh_generated.json"


def origin_fusion_spine() -> dict:
    """
    Canonical Fusion path: issued from membrane/mother (origin), not as a direct edge from
    domain web (ATC dashboard, etc.) or as an implied hop inside a domain room tour.
    """
    return {
        "routing_rule": "domain_room → origin (membrane/mother) → Fusion moves → return to origin",
        "fusion_surfaces_s4": [
            "Local Mac: full cell via GaiaFusion DMG (signed URL after moor).",
            "Global: sovereign UI / mesh digest (fleet + Mac spine) — not hosted as a node inside per-domain HTTP dashboards.",
        ],
        "intent_tree": {
            "node_id": "origin.fusion.root",
            "depth": 0,
            "user_language": "I am in the membrane or mother channel (origin) and want Fusion / Mac fleet visibility",
            "terminal_user_intent": False,
            "children": [
                {
                    "node_id": "origin.fusion.s1",
                    "depth": 1,
                    "user_language": "I want the Fusion fleet digest (global operator view)",
                    "gaia_moves": [{"type": "slash", "command": "/fusion_fleet", "surface": "membrane_or_mother"}],
                    "c4_witness": "HTTP 200 body excerpt or REFUSED with reason",
                    "terminal_user_intent": True,
                    "requires": {"moored": False},
                    "children": [
                        {
                            "node_id": "origin.fusion.s2",
                            "depth": 2,
                            "user_language": "I want the Mac mesh operator spine and my moor status",
                            "gaia_moves": [{"type": "slash", "command": "/mesh_status", "surface": "membrane_or_mother"}],
                            "c4_witness": "GET /api/fusion/mesh-operator-spine + moor PASS/FAIL line",
                            "terminal_user_intent": True,
                            "requires": {"moored": False},
                            "children": [
                                {
                                    "node_id": "origin.fusion.s3",
                                    "depth": 3,
                                    "user_language": "I want the GaiaFusion DMG with signed URL (local Mac full cell)",
                                    "gaia_moves": [{"type": "slash", "command": "/getmaccellfusion", "surface": "membrane_or_mother"}],
                                    "c4_witness": "signed URL + Range probe status; REFUSED if not moored",
                                    "terminal_user_intent": True,
                                    "requires": {"moored": True},
                                    "refused_if": ["not_moored", "bad_download_probe"],
                                    "children": [],
                                }
                            ],
                        }
                    ],
                }
            ],
        },
    }


def crystal_spine_children(domain_id: str, mesh_mb: str | None) -> list[dict]:
    """Domain room: crystal + dashboard/status + mailbox. Fusion chain lives under origin_fusion_spine only."""
    return [
        {
            "node_id": f"{domain_id}.s1",
            "depth": 1,
            "user_language": "I want to see my crystal and earth feed health in this room",
            "gaia_moves": [{"type": "slash", "command": "/cell", "surface": "crystal"}],
            "c4_witness": "ephemeral: cell_id, earth_mooring (k/n), earth_torsion_hint",
            "terminal_user_intent": True,
            "requires": {"moored": False},
            "children": [],
        },
        {
            "node_id": f"{domain_id}.s0",
            "depth": 1,
            "user_language": "I want Fusion fleet, Mac mesh spine, or DMG after working in this domain",
            "gaia_moves": [
                {
                    "type": "human",
                    "note": "No direct domain-web or ATC→Fusion edge: switch to membrane/mother (origin), run /fusion_fleet → /mesh_status → /getmaccellfusion there, then return to origin/center before other domain work.",
                }
            ],
            "c4_witness": "slash receipts from origin channel; see origin_fusion_spine in this JSON",
            "terminal_user_intent": True,
            "requires": {"moored": False},
            "children": [],
        },
        {
            "node_id": f"{domain_id}.d1",
            "depth": 1,
            "user_language": "I want the domain dashboard (HTTP link from /dashboard)",
            "gaia_moves": [{"type": "slash", "command": "/dashboard", "surface": "crystal"}],
            "c4_witness": "Link button to CELL_BASE_URL:port?discord_id=",
            "terminal_user_intent": True,
            "requires": {"moored": False},
            "children": [
                {
                    "node_id": f"{domain_id}.d2",
                    "depth": 2,
                    "user_language": "I want operational status before I commit time",
                    "gaia_moves": [{"type": "slash", "command": "/status", "surface": "crystal"}],
                    "c4_witness": "embed OPERATIONAL + port",
                    "terminal_user_intent": True,
                    "requires": {"moored": False},
                    "children": [],
                }
            ],
        },
        {
            "node_id": f"{domain_id}.m1",
            "depth": 1,
            "user_language": f"I want mesh mailbox {mesh_mb or 'N/A'} alignment for this domain pillar",
            "gaia_moves": [{"type": "substrate", "note": "game_room on claims; optional NATS"}],
            "c4_witness": "optional: claim with payload.game_room matching registry",
            "terminal_user_intent": True,
            "s4_open": "Full live twin — requires gateway + ingest path; not closed in Discord alone",
            "children": [],
        },
    ]


def codex_extra_children(domain_id: str) -> list[dict]:
    return [
        {
            "node_id": f"{domain_id}.c1",
            "depth": 1,
            "user_language": "I want the codex adjunct surface (no mesh mailbox row)",
            "gaia_moves": [{"type": "slash", "command": "/dashboard"}, {"type": "slash", "command": "/status"}],
            "c4_witness": "same as mesh domain bots",
            "terminal_user_intent": True,
            "children": [
                {
                    "node_id": f"{domain_id}.c2",
                    "depth": 2,
                    "user_language": "I want cross-link to related mesh pillar (e.g. Bio↔chem)",
                    "gaia_moves": [{"type": "human", "note": "Navigate to sibling channel per registry notes"}],
                    "c4_witness": "human documented path; optional Playwright multi-channel",
                    "terminal_user_intent": True,
                    "s4_open": "Automated cross-room tour not in single-bot code",
                    "children": [],
                }
            ],
        }
    ]


def main() -> int:
    reg = json.loads(REG.read_text(encoding="utf-8"))
    entries = [e for e in reg.get("entries", []) if e.get("kind") == "game_room" and e.get("enabled", True)]
    out_domains: list[dict] = []
    for e in entries:
        did = str(e.get("id") or "")
        mb = e.get("mesh_mailbox")
        ch = str(e.get("discord_channel_slug") or "")
        dk = str(e.get("domain_key") or "")
        children = crystal_spine_children(did, mb)
        if mb is None:
            children.extend(codex_extra_children(did))
        out_domains.append(
            {
                "domain_id": did,
                "domain_key": dk,
                "mesh_mailbox": mb,
                "discord_channel_slug": ch,
                "bot_entry": e.get("bot_entry"),
                "ultimate_user_intent_closed": f"User exercised domain {did} with at least one terminal witness (dashboard/status/spine/mailbox story).",
                "s4_open_opportunities": [
                    "Rich dashboard data (domain HTTP surface — C4 = host responds)",
                    "Per-domain NATS / claims volume",
                    "Multi-step QFOT-gated premium moves when ledger live",
                ],
                "qfot": {
                    "min_balance_to_enter": 0,
                    "policy": "S4 placeholder — navy blue gap: wire C4 QFOT ledger to gate moves",
                },
                "intent_tree": {
                    "node_id": f"{did}.root",
                    "depth": 0,
                    "user_language": f"I want to work in domain {did} ({dk})",
                    "terminal_user_intent": False,
                    "children": children,
                },
            }
        )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "generated": True,
        "source_registry": str(REG),
        "origin_fusion_spine": origin_fusion_spine(),
        "domains": out_domains,
    }
    OUT.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {OUT} ({len(out_domains)} domains)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
