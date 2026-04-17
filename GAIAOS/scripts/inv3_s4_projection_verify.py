#!/usr/bin/env python3
"""
INV3 AML — verify S4 lab projection vs substrate (mcp_claims via gateway POST /query).

Default: witness only. Lab correction: --apply with env INV3_VERIFY_APPLY=I_UNDERSTAND
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# Identifiers from runbook
FILTER_TERMS = (
    "aml-chem-001",
    "leuk-005",
    "9084",
    "inv(3)",
    "gata2",
    "mecom",
)

# Bound scan: TO_STRING on entire collection is O(n) and can hang the gateway; scan recent keys only.
AQL = """
LET recent = (
  FOR c IN mcp_claims
    SORT c._key DESC
    LIMIT @scan_cap
    RETURN c
)
FOR c IN recent
  LET s = LOWER(TO_STRING(c))
  FILTER """ + " OR ".join(f'CONTAINS(s, "{t}")' for t in FILTER_TERMS) + """
  LIMIT @lim
  RETURN c
"""


def norm_smiles(s: str | None) -> str | None:
    if not s:
        return None
    t = s.strip().replace(" ", "")
    return t if t else None


def norm_seq(s: str | None) -> str | None:
    if not s:
        return None
    lines = [ln.strip() for ln in s.splitlines() if ln.strip() and not ln.strip().startswith("#")]
    one = "".join(lines)
    return one.upper() if one else None


def extract_lab_smiles(lab_text: str) -> str | None:
    m = re.search(r"\*\*SMILES\*\*:\s*`([^`]+)`", lab_text)
    return m.group(1).strip() if m else None


def extract_lab_sequence(lab_text: str) -> str | None:
    m = re.search(
        r"\*\*Amino Acid Sequence\*\*:\s*```\s*([A-Za-z]+)\s*```",
        lab_text,
        re.DOTALL,
    )
    return m.group(1).strip() if m else None


def walk_strings(obj: Any, out: list[str]) -> None:
    if isinstance(obj, str):
        out.append(obj)
    elif isinstance(obj, dict):
        for v in obj.values():
            walk_strings(v, out)
    elif isinstance(obj, list):
        for v in obj:
            walk_strings(v, out)


def guess_smiles_from_claims(claims: list[dict[str, Any]]) -> tuple[str | None, str | None]:
    """Return (best_smiles, source_hint). Heuristic: look for SMILES= or "smiles": in JSON strings."""
    blob = json.dumps(claims)
    # JSON-style
    for pat in (
        r'"smiles"\s*:\s*"([^"]+)"',
        r"'smiles'\s*:\s*'([^']+)'",
        r"SMILES['\"]?\s*[:=]\s*['\"]([^'\"]+)['\"]",
    ):
        m = re.search(pat, blob, re.I)
        if m:
            return norm_smiles(m.group(1)), "claim_json_pattern"
    # long alphanumeric SMILES-like in strings
    strings: list[str] = []
    for c in claims:
        walk_strings(c, strings)
    for s in strings:
        if "AML-CHEM" in s.upper() or "9084" in s:
            inner = re.search(r"([A-Za-z0-9@+\-\[\]\(\)=#/\\]{12,})", s)
            if inner:
                return norm_smiles(inner.group(1)), "claim_string_heuristic"
    return None, None


def guess_sequence_from_claims(claims: list[dict[str, Any]]) -> tuple[str | None, str | None]:
    blob = json.dumps(claims)
    m = re.search(r'"sequence"\s*:\s*"([A-Za-z]{20,})"', blob, re.I)
    if m:
        return norm_seq(m.group(1)), "claim_json_sequence"
    strings: list[str] = []
    for c in claims:
        walk_strings(c, strings)
    for s in strings:
        if "LEUK-005" in s.upper() or "Harbinger" in s:
            m2 = re.search(r"\b([A-Z]{20,})\b", s.replace("\n", ""))
            if m2:
                return norm_seq(m2.group(1)), "claim_string_heuristic"
    return None, None


def post_query_raw(
    gateway: str, query: str, bind_vars: dict[str, Any], timeout: int = 90
) -> list[dict[str, Any]]:
    url = gateway.rstrip("/") + "/query"
    body = json.dumps({"query": query, "bind_vars": bind_vars}).encode()
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode()
    data = json.loads(raw)
    if isinstance(data, list):
        return data
    if isinstance(data, dict) and "result" in data:
        return data["result"]
    return []


def post_query(gateway: str, limit: int) -> list[dict[str, Any]]:
    scan_cap = min(max(limit * 40, 500), 5000)
    return post_query_raw(
        gateway,
        AQL,
        {"lim": limit, "scan_cap": scan_cap},
        timeout=90,
    )


def fetch_c4_aml_molecule(gateway: str) -> tuple[dict[str, Any] | None, str]:
    """Canonical C4 row for AML-CHEM-001 / 9084."""
    rows = post_query_raw(
        gateway,
        """
        FOR d IN discovered_molecules
          FILTER d._key == @key OR d.molecule_id == @mid OR d.name == @name
          LIMIT 1
          RETURN d
        """,
        {
            "key": "cancer_candidate_9084",
            "mid": "cancer_candidate_9084",
            "name": "AML-CHEM-001",
        },
    )
    if rows:
        return rows[0], "discovered_molecules/c4_primary"
    return None, "missing"


def fetch_c4_leuk_protein(gateway: str, lab_seq: str | None) -> tuple[dict[str, Any] | None, str]:
    if not lab_seq:
        return None, "no_lab_sequence"
    rows = post_query_raw(
        gateway,
        """
        FOR d IN discovered_proteins
          FILTER d.protein_id == @pid OR d.sequence == @seq
          LIMIT 1
          RETURN d
        """,
        {"pid": "LEUK-005", "seq": lab_seq.strip()},
    )
    if rows:
        return rows[0], "discovered_proteins/c4_primary"
    return None, "missing"


def rdkit_smiles_audit(smiles: str | None) -> str:
    if not smiles:
        return "n/a"
    try:
        from rdkit import Chem
        from rdkit.Chem import rdMolDescriptors

        m = Chem.MolFromSmiles(smiles.strip())
        if not m:
            return "RDKit: MolFromSmiles failed"
        return (
            f"RDKit formula `{rdMolDescriptors.CalcMolFormula(m)}` "
            f"(exact MW ~{rdMolDescriptors.CalcExactMolWt(m):.4f})"
        )
    except Exception as e:
        return f"RDKit unavailable or error: {e}"


def health_check(gateway: str) -> bool:
    url = gateway.rstrip("/") + "/health"
    try:
        with urllib.request.urlopen(url, timeout=15) as resp:
            return resp.status in (200, 201)
    except urllib.error.URLError:
        return False


def apply_smiles_fix(lab_path: Path, old: str, new: str) -> None:
    text = lab_path.read_text(encoding="utf-8")
    old_line = f"**SMILES**: `{old}`"
    new_line = f"**SMILES**: `{new}`"
    if old_line not in text:
        raise SystemExit(f"apply: expected lab line not found: {old_line!r}")
    text = text.replace(old_line, new_line, 1)
    lab_path.write_text(text, encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description="INV3 S4 projection vs substrate witness")
    ap.add_argument(
        "--gateway",
        default=os.environ.get("GAIAFTCL_GATEWAY", "http://127.0.0.1:8803"),
        help="MCP gateway base URL (POST /query, GET /health)",
    )
    ap.add_argument(
        "--lab",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "LAB_PROTOCOLS_INV3_LEUKEMIA_THERAPEUTICS.md",
    )
    ap.add_argument("--limit", type=int, default=500)
    ap.add_argument(
        "--apply",
        action="store_true",
        help="Write lab SMILES from substrate when mismatch (requires INV3_VERIFY_APPLY=I_UNDERSTAND)",
    )
    args = ap.parse_args()

    evdir = Path(__file__).resolve().parent.parent / "evidence" / "inv3_s4_projection"
    evdir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    if not health_check(args.gateway):
        print("BLOCKED: gateway /health unreachable:", args.gateway, file=sys.stderr)
        return 3

    try:
        c4_mol, c4_mol_src = fetch_c4_aml_molecule(args.gateway)
    except urllib.error.URLError as e:
        print("BLOCKED: /query failed (C4 molecule):", e, file=sys.stderr)
        return 3

    lab_text = args.lab.read_text(encoding="utf-8")
    lab_smiles = extract_lab_smiles(lab_text)
    lab_seq = extract_lab_sequence(lab_text)

    try:
        c4_prot, c4_prot_src = fetch_c4_leuk_protein(args.gateway, lab_seq)
    except urllib.error.URLError as e:
        print("BLOCKED: /query failed (C4 protein):", e, file=sys.stderr)
        return 3

    claims: list[dict[str, Any]] = []
    if os.environ.get("INV3_SCAN_MCP_CLAIMS", "").strip() in ("1", "true", "yes"):
        try:
            claims = post_query(args.gateway, args.limit)
        except urllib.error.URLError as e:
            print("BLOCKED: /query failed (mcp_claims scan):", e, file=sys.stderr)
            return 3

    snap_path = evdir / f"claims_snapshot_{ts}.json"
    snap_path.write_text(
        json.dumps(
            {
                "mcp_claims_hits": claims,
                "c4_aml_molecule": c4_mol,
                "c4_leuk_protein": c4_prot,
            },
            indent=2,
        ),
        encoding="utf-8",
    )

    sub_smiles = norm_smiles(c4_mol.get("smiles")) if c4_mol else None
    sm_src = c4_mol_src if sub_smiles else None
    if not sub_smiles:
        guess, gsrc = guess_smiles_from_claims(claims)
        sub_smiles, sm_src = guess, gsrc or "mcp_claims_fallback"

    sub_seq = norm_seq(c4_prot.get("sequence")) if c4_prot else None
    seq_src = c4_prot_src if sub_seq else None
    if lab_seq and not sub_seq:
        guess2, g2 = guess_sequence_from_claims(claims)
        sub_seq, seq_src = guess2, g2 or "mcp_claims_fallback"

    smiles_match = True
    smiles_mismatch_flag = False
    correction = "none"
    if lab_smiles and sub_smiles:
        smiles_match = norm_smiles(lab_smiles) == norm_smiles(sub_smiles)
        smiles_mismatch_flag = not smiles_match
    elif lab_smiles and not sub_smiles:
        smiles_match = False
        smiles_mismatch_flag = False  # UNKNOWN, not mismatch
        correction = "UNKNOWN — no C4 discovered_molecules row for AML-CHEM-001 / 9084"

    seq_match: bool | None = None
    seq_unknown = False
    c4_leuk_key = c4_prot.get("_key") if c4_prot else None
    if lab_seq:
        if sub_seq:
            seq_match = norm_seq(lab_seq) == norm_seq(sub_seq)
        else:
            seq_unknown = True
            correction = (
                "UNKNOWN — no discovered_proteins row for protein_id LEUK-005 or matching sequence; "
                "ingest C4 before treating lab sequence as verified projection"
            )

    chem_note = rdkit_smiles_audit(lab_smiles)
    lab_formula_line = (
        "see LAB doc Part 2 (C₁₅H₁₆F₃N₃O per canonical SMILES, MW ~311.12, HRMS [M+H]⁺ ~312.13 — confirm on instrument)"
    )

    lines = [
        "# INV3 M8 witness — S4 lab projection vs C4 substrate",
        "",
        "**Ontology:** M8 = S4 (manifest: markdown lab) × C4 (constraint: Arango `discovered_*`, `mcp_claims`). "
        "When S4 and C4 disagree on structure export, **C4 wins**. This note compares them.",
        "",
        f"- **generated_utc:** {ts}",
        f"- **gateway:** {args.gateway}",
        f"- **mcp_claims_hits:** {len(claims)}",
        f"- **c4_aml_key:** `{c4_mol.get('_key') if c4_mol else 'MISSING'}`",
        f"- **c4_leuk_key:** `{c4_leuk_key or 'MISSING'}`",
        f"- **snapshot:** `{snap_path.relative_to(evdir.parent.parent)}`",
        "",
        "## AML-CHEM-001 (small molecule)",
        "",
        f"| Field | Value |",
        f"|--------|--------|",
        f"| Lab SMILES (S4) | `{lab_smiles or 'N/A'}` |",
        f"| C4 SMILES (`discovered_molecules`) | `{sub_smiles or 'UNKNOWN'}` |",
        f"| C4 source | {sm_src or 'n/a'} |",
        f"| S4↔C4 projection mismatch | {str(smiles_mismatch_flag).lower()} |",
        f"| UNKNOWN (no C4 SMILES) | {str(not sub_smiles and bool(lab_smiles)).lower()} |",
        "",
        "### Chemistry cross-check (S4 text vs S4/C4 SMILES)",
        "",
        f"- Lab document claims: {lab_formula_line}",
        f"- Parsed SMILES (lab = C4): {chem_note}",
        "- If formula in the lab text does **not** match RDKit interpretation of the shared SMILES, **both** S4 and C4 may still carry the **same** wrong string (projection agreed but **structure inconsistent with IUPAC/MS**). "
        "Remedy: **update C4** `discovered_molecules/cancer_candidate_9084` with witnessed canonical SMILES/InChIKey, **then** re-export S4 (`--apply`).",
        "",
        "## LEUK-005 (protein)",
        "",
        f"| Field | Value |",
        f"|--------|--------|",
        f"| Lab sequence (S4) | `{lab_seq or 'N/A'}` |",
        f"| C4 sequence (`discovered_proteins`) | `{sub_seq or 'UNKNOWN'}` |",
        f"| C4 source | {seq_src or 'n/a'} |",
        f"| S4↔C4 match | {str(seq_match).lower() if seq_match is not None else 'n/a (no C4 sequence)'} |",
        f"| UNKNOWN (no C4 row) | {str(seq_unknown).lower()} |",
        "",
        "## Correction status",
        "",
        correction,
        "",
    ]

    if smiles_mismatch_flag and sub_smiles:
        lines.append("**Action:** Re-project lab SMILES from substrate canonical (translation artifact).")
        if args.apply:
            if os.environ.get("INV3_VERIFY_APPLY") != "I_UNDERSTAND":
                print("BLOCKED: set INV3_VERIFY_APPLY=I_UNDERSTAND to mutate lab file", file=sys.stderr)
                return 4
            apply_smiles_fix(args.lab, lab_smiles or "", sub_smiles)
            lines.append(f"**Applied:** lab SMILES replaced with substrate value ({ts}).")
            correction = "applied_smiles_from_substrate"

    wit_path = evdir / f"WITNESS_NOTE_{ts}.md"
    wit_path.write_text("\n".join(lines), encoding="utf-8")
    print(wit_path)

    if not sub_smiles and lab_smiles:
        return 2
    if smiles_mismatch_flag:
        return 1
    if seq_unknown:
        return 2
    if seq_match is False and sub_seq:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
