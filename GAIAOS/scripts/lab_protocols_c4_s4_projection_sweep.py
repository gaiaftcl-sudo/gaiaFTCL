#!/usr/bin/env python3
"""
Unified sweep: all GAIAOS LAB_PROTOCOLS_*.md (S4) vs C4 (discovered_* via gateway POST /query).

Steps 1–4, 6 automated; Step 5 emits a review list (naming vs chemistry is not fully automatable).

Apply gate: INV3_VERIFY_APPLY=I_UNDERSTAND
Optional ingest: --ingest-self-heal (caller_id + substantive content)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

GAIA_ROOT = Path(__file__).resolve().parent.parent
EVIDENCE = GAIA_ROOT / "evidence" / "lab_protocols_c4_s4_sweep"

ENTITY_ID_RE = re.compile(
    r"\b(MENING-PROT-\d{3}|MEN-CHEM-\d{3}|AML-CHEM-\d{3}|LEUK-\d{3}|ALZ-\d{3}|ALZ-CHEM)\b",
    re.I,
)


def norm_smiles(s: str | None) -> str | None:
    if not s:
        return None
    t = s.strip().replace(" ", "")
    return t if t else None


def norm_seq(s: str | None) -> str | None:
    if not s:
        return None
    one = "".join(s.split()).upper()
    return one if one else None


def post_query_raw(
    gateway: str, query: str, bind_vars: dict[str, Any], timeout: int = 90
) -> tuple[list[dict[str, Any]], str | None]:
    url = gateway.rstrip("/") + "/query"
    body = json.dumps({"query": query, "bind_vars": bind_vars}).encode()
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode()
    except urllib.error.URLError as e:
        return [], f"BLOCKED: {e}"
    data = json.loads(raw)
    if isinstance(data, list):
        return data, None
    if isinstance(data, dict) and "result" in data:
        return data["result"], None
    return [], "BLOCKED: unexpected /query response shape"


def health_check(gateway: str) -> bool:
    url = gateway.rstrip("/") + "/health"
    try:
        with urllib.request.urlopen(url, timeout=15) as resp:
            return resp.status in (200, 201)
    except urllib.error.URLError:
        return False


def post_ingest_self_heal(gateway: str, content: str) -> tuple[bool, str]:
    url = gateway.rstrip("/") + "/ingest"
    payload = {
        "caller_id": "lab_protocols_c4_s4_sweep",
        "type": "SELF_HEAL",
        "content": content,
    }
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            return True, resp.read().decode()[:800]
    except urllib.error.HTTPError as e:
        return False, e.read().decode()[:800]
    except urllib.error.URLError as e:
        return False, str(e)


def discover_lab_files() -> list[Path]:
    return sorted(GAIA_ROOT.glob("LAB_PROTOCOLS_*.md"))


def extract_entity_ids(text: str) -> list[str]:
    found = {m.group(1).upper() for m in ENTITY_ID_RE.finditer(text)}
    return sorted(found)


def extract_leuk_sequence(text: str) -> str | None:
    m = re.search(
        r"\*\*Amino Acid Sequence\*\*:\s*```\s*([A-Za-z]+)\s*```",
        text,
        re.DOTALL,
    )
    return m.group(1).strip() if m else None


def extract_aml_smiles(text: str) -> tuple[str | None, str | None]:
    m = re.search(
        r"\*\*Chemical Name\*\*:\s*(AML-CHEM-\d+).*?\*\*SMILES\*\*:\s*`([^`]+)`",
        text,
        re.DOTALL | re.IGNORECASE,
    )
    if m:
        return m.group(1).upper(), m.group(2).strip()
    m2 = re.search(r"\*\*SMILES\*\*:\s*`([^`]+)`", text)
    if m2 and "AML-CHEM" in text.upper():
        return "AML-CHEM-001", m2.group(1).strip()
    return None, None


def extract_alz_sequences(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for m in re.finditer(
        r"###\s*(ALZ-\d{3}).*?\*\*Sequence\*\*:\s*([A-Za-z]+)",
        text,
        re.DOTALL,
    ):
        out[m.group(1).upper()] = m.group(2).strip()
    return out


@dataclass
class EntityS4:
    smiles: str | None = None
    sequence: str | None = None
    sources: list[str] = field(default_factory=list)


def build_s4_projection(lab_paths: list[Path]) -> dict[str, EntityS4]:
    proj: dict[str, EntityS4] = {}
    for path in lab_paths:
        text = path.read_text(encoding="utf-8")
        rel = str(path.relative_to(GAIA_ROOT))
        for eid in extract_entity_ids(text):
            proj.setdefault(eid, EntityS4()).sources.append(rel)
        seq = extract_leuk_sequence(text)
        if seq and "LEUK-005" in text.upper():
            p = proj.setdefault("LEUK-005", EntityS4())
            p.sequence = seq
            if rel not in p.sources:
                p.sources.append(rel)
        chem_id, smi = extract_aml_smiles(text)
        if chem_id and smi:
            p = proj.setdefault(chem_id, EntityS4())
            p.smiles = smi
            if rel not in p.sources:
                p.sources.append(rel)
        for aid, aseq in extract_alz_sequences(text).items():
            p = proj.setdefault(aid, EntityS4())
            p.sequence = aseq
            if rel not in p.sources:
                p.sources.append(rel)
    return proj


def entity_kind(eid: str) -> str:
    u = eid.upper()
    if "CHEM" in u:
        return "molecule"
    if u.startswith("LEUK") or u.startswith("MENING-PROT") or u.startswith("ALZ-"):
        return "protein"
    return "unknown"


def fetch_c4_molecule(gateway: str, eid: str) -> tuple[dict[str, Any] | None, str, str | None]:
    keys: list[str] = []
    if eid.upper() == "AML-CHEM-001":
        keys.append("cancer_candidate_9084")
    q = """
    FOR d IN discovered_molecules
      FILTER d.name == @id OR d.molecule_id == @id OR d._key IN @keys
      LIMIT 1
      RETURN d
    """
    rows, err = post_query_raw(gateway, q, {"id": eid, "keys": keys})
    if err:
        return None, "discovered_molecules", err
    if rows:
        return rows[0], "discovered_molecules", None
    q2 = """
    FOR d IN discovered_compounds
      FILTER d.compound_id == @id OR d.name == @id
      LIMIT 1
      RETURN d
    """
    rows2, err2 = post_query_raw(gateway, q2, {"id": eid})
    if err2:
        return None, "discovered_compounds", err2
    if rows2:
        return rows2[0], "discovered_compounds", None
    return None, "discovered_molecules", None


def fetch_c4_protein(
    gateway: str, eid: str, lab_seq: str | None
) -> tuple[dict[str, Any] | None, str, str | None]:
    q = """
    FOR d IN discovered_proteins
      FILTER d.protein_id == @id
         OR (IS_STRING(d.name) AND UPPER(d.name) == UPPER(@id))
      LIMIT 1
      RETURN d
    """
    rows, err = post_query_raw(gateway, q, {"id": eid})
    if err:
        return None, "discovered_proteins", err
    if rows:
        return rows[0], "discovered_proteins", None
    if lab_seq:
        q2 = """
        FOR d IN discovered_proteins
          FILTER d.sequence == @seq
          LIMIT 1
          RETURN d
        """
        rows2, err2 = post_query_raw(gateway, q2, {"seq": lab_seq.strip()})
        if err2:
            return None, "discovered_proteins", err2
        if rows2:
            return rows2[0], "discovered_proteins", None
    return None, "discovered_proteins", None


def fetch_c4_material(gateway: str, eid: str) -> tuple[dict[str, Any] | None, str, str | None]:
    q = """
    FOR d IN discovered_materials
      FILTER d.name == @id
      LIMIT 1
      RETURN d
    """
    rows, err = post_query_raw(gateway, q, {"id": eid})
    if err:
        return None, "discovered_materials", err
    return (rows[0], "discovered_materials", None) if rows else (None, "discovered_materials", None)


def apply_smiles_fix(lab_path: Path, old: str, new: str) -> None:
    text = lab_path.read_text(encoding="utf-8")
    old_line = f"**SMILES**: `{old}`"
    new_line = f"**SMILES**: `{new}`"
    if old_line not in text:
        raise ValueError(f"apply_smiles_fix: line not found in {lab_path.name}")
    text = text.replace(old_line, new_line, 1)
    lab_path.write_text(text, encoding="utf-8")


def apply_leuk_sequence_fix(lab_path: Path, old: str, new: str) -> None:
    text = lab_path.read_text(encoding="utf-8")
    old_block = f"```\n{old}\n```"
    new_block = f"```\n{new}\n```"
    if old_block not in text:
        raise ValueError(f"apply_leuk_sequence_fix: block not found in {lab_path.name}")
    text = text.replace(old_block, new_block, 1)
    lab_path.write_text(text, encoding="utf-8")


def apply_alz_sequence_fix(lab_path: Path, eid: str, old: str, new: str) -> None:
    text = lab_path.read_text(encoding="utf-8")
    pat = rf"(###\s*{re.escape(eid)}\b[^\n]*\n\n\*\*Sequence\*\*:\s*){re.escape(old)}(\s)"
    ntext, n = re.subn(pat, rf"\g<1>{new}\2", text, count=1, flags=re.DOTALL)
    if n != 1:
        raise ValueError(f"apply_alz_sequence_fix: no single match for {eid} in {lab_path.name}")
    lab_path.write_text(ntext, encoding="utf-8")


def synthesis_step_index(lab_paths: list[Path]) -> list[dict[str, Any]]:
    """Step 5 helper: numbered / titled steps for human review (not chemistry NLP)."""
    rows: list[dict[str, Any]] = []
    step_re = re.compile(
        r"^(#{3,4})\s+(.+)$|^(\d+)\.\s+\*\*(.+?)\*\*",
        re.MULTILINE,
    )
    for path in lab_paths:
        text = path.read_text(encoding="utf-8")
        for ln, line in enumerate(text.splitlines(), 1):
            if re.match(r"^\d+\.\s+", line) and len(line) < 200:
                rows.append(
                    {
                        "file": path.name,
                        "line": ln,
                        "step_line": line.strip(),
                    }
                )
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description="LAB_PROTOCOLS_* S4 vs C4 unified sweep")
    ap.add_argument(
        "--gateway",
        default=os.environ.get("GAIAFTCL_GATEWAY", "http://127.0.0.1:8803"),
    )
    ap.add_argument("--manifest-only", action="store_true", help="Step 1 only; no /query")
    ap.add_argument("--audit", action="store_true", help="Steps 2–3 (+5 index); no file writes")
    ap.add_argument(
        "--apply",
        action="store_true",
        help="Step 4: patch S4 from C4 when mismatch (requires INV3_VERIFY_APPLY=I_UNDERSTAND)",
    )
    ap.add_argument(
        "--ingest-self-heal",
        action="store_true",
        help="After each successful file patch, POST /ingest SELF_HEAL (needs reachable gateway)",
    )
    args = ap.parse_args()

    EVIDENCE.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    lab_files = discover_lab_files()
    if not lab_files:
        print("No LAB_PROTOCOLS_*.md under", GAIA_ROOT, file=sys.stderr)
        return 2

    s4 = build_s4_projection(lab_files)
    manifest = {
        "generated_utc": ts,
        "lab_files": [str(p.relative_to(GAIA_ROOT)) for p in lab_files],
        "entities": {
            eid: {
                "smiles": s4[eid].smiles,
                "sequence": s4[eid].sequence,
                "sources": s4[eid].sources,
            }
            for eid in sorted(s4.keys())
        },
    }
    man_path = EVIDENCE / f"DISCOVERY_MANIFEST_{ts}.json"
    man_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(man_path)

    if args.manifest_only:
        return 0

    if not args.audit and not args.apply:
        print("Specify --audit and/or --apply (or --manifest-only alone).", file=sys.stderr)
        return 2

    gateway_ok = health_check(args.gateway)
    audit_rows: list[dict[str, Any]] = []
    corrections: list[str] = []
    ingest_log: list[dict[str, Any]] = []

    if not gateway_ok:
        for eid in sorted(s4.keys()):
            audit_rows.append(
                {
                    "entity": eid,
                    "status": "BLOCKED",
                    "detail": f"gateway /health unreachable: {args.gateway}",
                    "c4_collection": None,
                    "c4_key": None,
                }
            )
    else:
        for eid in sorted(s4.keys()):
            kind = entity_kind(eid)
            row: dict[str, Any] = {
                "entity": eid,
                "kind": kind,
                "s4_smiles": s4[eid].smiles,
                "s4_sequence": s4[eid].sequence,
            }
            c4_doc: dict[str, Any] | None = None
            coll = ""
            qerr: str | None = None

            if kind == "molecule":
                c4_doc, coll, qerr = fetch_c4_molecule(args.gateway, eid)
                c4_smiles = None
                if c4_doc:
                    c4_smiles = norm_smiles(
                        c4_doc.get("smiles") or c4_doc.get("canonical_smiles")
                    )
                row["c4_collection"] = coll
                row["c4_key"] = c4_doc.get("_key") if c4_doc else None
                row["c4_smiles"] = c4_smiles
                if qerr:
                    row["status"] = "BLOCKED"
                    row["detail"] = qerr
                elif not c4_doc:
                    if s4[eid].smiles:
                        row["status"] = "UNKNOWN"
                        row["detail"] = "No C4 molecule/compound row; flag for ingest"
                    else:
                        row["status"] = "NO_S4_STRUCTURE"
                        row["detail"] = "No SMILES in lab (TBD); no C4 row"
                elif s4[eid].smiles and c4_smiles:
                    if norm_smiles(s4[eid].smiles) == c4_smiles:
                        row["status"] = "MATCH"
                    else:
                        row["status"] = "MISMATCH"
                        row["detail"] = "S4 SMILES != C4 SMILES (projection error)"
                elif s4[eid].smiles and not c4_smiles:
                    row["status"] = "UNKNOWN"
                    row["detail"] = "S4 has SMILES; C4 doc has no smiles field"
                else:
                    row["status"] = "NO_S4_STRUCTURE"
                    row["detail"] = "Hypothesis / TBD in lab — nothing to compare"

            elif kind == "protein":
                lab_seq = s4[eid].sequence
                c4_doc, coll, qerr = fetch_c4_protein(args.gateway, eid, lab_seq)
                c4_seq = norm_seq(c4_doc.get("sequence")) if c4_doc else None
                row["c4_collection"] = coll
                row["c4_key"] = c4_doc.get("_key") if c4_doc else None
                row["c4_sequence"] = c4_seq
                if qerr:
                    row["status"] = "BLOCKED"
                    row["detail"] = qerr
                elif not c4_doc:
                    if lab_seq:
                        row["status"] = "UNKNOWN"
                        row["detail"] = (
                            "No C4 protein row; ingest or align protein_id before SETTLED projection"
                        )
                    else:
                        row["status"] = "NO_S4_STRUCTURE"
                        row["detail"] = "No lab sequence export (TBD/candidate); no C4 row"
                elif lab_seq and c4_seq:
                    if norm_seq(lab_seq) == c4_seq:
                        row["status"] = "MATCH"
                    else:
                        row["status"] = "MISMATCH"
                        row["detail"] = "S4 sequence != C4 sequence"
                elif lab_seq and not c4_seq:
                    row["status"] = "UNKNOWN"
                    row["detail"] = "Lab sequence but C4 has empty sequence"
                else:
                    row["status"] = "NO_S4_STRUCTURE"
                    row["detail"] = "No sequence in lab for this id (TBD/candidates)"

            else:
                c4_doc, coll, qerr = fetch_c4_material(args.gateway, eid)
                row["c4_collection"] = coll
                row["c4_key"] = c4_doc.get("_key") if c4_doc else None
                row["status"] = "UNKNOWN" if not c4_doc else "NO_S4_STRUCTURE"
                row["detail"] = qerr or "Unclassified entity kind"

            audit_rows.append(row)

            if args.apply and row.get("status") == "MISMATCH":
                if os.environ.get("INV3_VERIFY_APPLY") != "I_UNDERSTAND":
                    print(
                        "BLOCKED: --apply requires INV3_VERIFY_APPLY=I_UNDERSTAND",
                        file=sys.stderr,
                    )
                    return 3
                inv3_lab = GAIA_ROOT / "LAB_PROTOCOLS_INV3_LEUKEMIA_THERAPEUTICS.md"
                alz_lab = GAIA_ROOT / "LAB_PROTOCOLS_ALZHEIMER_BIOINVARIANT.md"
                try:
                    if kind == "molecule" and eid == "AML-CHEM-001" and row.get("c4_smiles"):
                        old_s = s4[eid].smiles or ""
                        new_s = row["c4_smiles"]
                        apply_smiles_fix(inv3_lab, old_s, new_s)
                        msg = (
                            f"SELF_HEAL lab projection: entity {eid} SMILES aligned to C4 "
                            f"key {row.get('c4_key')} in {inv3_lab.name}."
                        )
                        corrections.append(msg)
                        if args.ingest_self_heal:
                            ok, info = post_ingest_self_heal(args.gateway, msg + " Witness sweep timestamp " + ts)
                            ingest_log.append({"entity": eid, "ok": ok, "info": info})
                    elif kind == "protein" and row.get("c4_sequence") and lab_seq:
                        new_q = row["c4_sequence"]
                        if eid == "LEUK-005" and lab_seq:
                            apply_leuk_sequence_fix(inv3_lab, lab_seq, new_q)
                            msg = (
                                f"SELF_HEAL lab projection: {eid} sequence aligned to C4 "
                                f"key {row.get('c4_key')} in {inv3_lab.name}."
                            )
                            corrections.append(msg)
                            if args.ingest_self_heal:
                                ok, info = post_ingest_self_heal(
                                    args.gateway, msg + " Witness sweep timestamp " + ts
                                )
                                ingest_log.append({"entity": eid, "ok": ok, "info": info})
                        elif eid.startswith("ALZ-"):
                            apply_alz_sequence_fix(alz_lab, eid, lab_seq, new_q)
                            msg = (
                                f"SELF_HEAL lab projection: {eid} sequence aligned to C4 "
                                f"key {row.get('c4_key')} in {alz_lab.name}."
                            )
                            corrections.append(msg)
                            if args.ingest_self_heal:
                                ok, info = post_ingest_self_heal(
                                    args.gateway, msg + " Witness sweep timestamp " + ts
                                )
                                ingest_log.append({"entity": eid, "ok": ok, "info": info})
                except ValueError as ex:
                    corrections.append(f"APPLY_FAILED {eid}: {ex}")

    audit_path = EVIDENCE / f"PROJECTION_AUDIT_{ts}.json"
    audit_path.write_text(
        json.dumps(
            {
                "gateway": args.gateway,
                "gateway_ok": gateway_ok,
                "rows": audit_rows,
                "corrections": corrections,
                "ingest_self_heal": ingest_log,
            },
            indent=2,
        ),
        encoding="utf-8",
    )

    step5_path = EVIDENCE / f"SYNTHESIS_STEP_INDEX_{ts}.json"
    step5_path.write_text(
        json.dumps(synthesis_step_index(lab_files), indent=2),
        encoding="utf-8",
    )

    mismatch = sum(1 for r in audit_rows if r.get("status") == "MISMATCH")
    unknown = sum(1 for r in audit_rows if r.get("status") == "UNKNOWN")
    blocked = sum(1 for r in audit_rows if r.get("status") == "BLOCKED")
    matched = sum(1 for r in audit_rows if r.get("status") == "MATCH")
    no_s4 = sum(1 for r in audit_rows if r.get("status") == "NO_S4_STRUCTURE")

    master_lines = [
        "# MASTER_WITNESS_NOTE — LAB_PROTOCOLS S4 × C4 unified sweep",
        "",
        f"- **generated_utc:** {ts}",
        f"- **gateway:** `{args.gateway}`",
        f"- **gateway_ok:** {str(gateway_ok).lower()}",
        f"- **lab_files:** {len(lab_files)}",
        "",
        "## Counts",
        "",
        f"| MATCH | MISMATCH | UNKNOWN | BLOCKED | NO_S4_STRUCTURE |",
        f"|-------|----------|---------|---------|-------------------|",
        f"| {matched} | {mismatch} | {unknown} | {blocked} | {no_s4} |",
        "",
        "## Terminal state (mission criterion)",
        "",
        "Zero **MISMATCH** requires every entity with both S4 structure export and C4 canonical "
        "to agree. **UNKNOWN** means substrate row or field missing — ingest C4, then re-run. "
        "**BLOCKED** is per-entity or whole-gateway I/O failure.",
        "",
        f"- **mismatch_count:** {mismatch}",
        f"- **unknown_count:** {unknown}",
        f"- **blocked_count:** {blocked}",
        f"- **clean_projection_achieved:** "
        f"{str(mismatch == 0 and blocked == 0 and unknown == 0).lower()} "
        f"(strict: no UNKNOWN)",
        "",
        "## Entities",
        "",
        "| entity | status | c4_collection | c4_key | detail |",
        "|--------|--------|-----------------|--------|--------|",
    ]
    for r in audit_rows:
        master_lines.append(
            f"| {r.get('entity')} | {r.get('status')} | "
            f"{r.get('c4_collection') or ''} | `{r.get('c4_key') or ''}` | "
            f"{(r.get('detail') or '').replace('|', '/')} |"
        )
    if corrections:
        master_lines.extend(["", "## Corrections applied (this run)", ""])
        master_lines.extend(f"- {c}" for c in corrections)

    master_path = EVIDENCE / f"MASTER_WITNESS_NOTE_{ts}.md"
    master_path.write_text("\n".join(master_lines), encoding="utf-8")
    print(audit_path)
    print(step5_path)
    print(master_path)

    if not gateway_ok:
        return 3
    if mismatch > 0:
        return 1
    if unknown > 0 or blocked > 0:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
