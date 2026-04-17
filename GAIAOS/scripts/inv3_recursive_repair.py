#!/usr/bin/env python3
"""
INV3 recursive invariant repair: LAB_PROTOCOLS_* (S4) vs C4 (discovered_* + claims).

Phases:
  1 — Discovery manifest (all LAB_PROTOCOLS_*.md under GAIAOS root + docs/)
  2 — Substrate sweep: GET /claims?filter= + POST /query C4 compare → ANCHORED | MISSING | MISMATCH | PENDING
  3 — universal_ingest for MISSING (structured payload); then UPSERT discovered_* via gateway /query when structure is known
  4 — Loop inv3_s4_projection_verify.py (max 5 iters); exit 1 → --apply once per iter if INV3_VERIFY_APPLY set
  5 — MASTER_WITNESS_NOTE under evidence/inv3_recursive_repair/

Mutations require INV3_VERIFY_APPLY=I_UNDERSTAND.
Default gateway: GAIAFTCL_GATEWAY or http://127.0.0.1:18803 (SSH tunnel).
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

# Reuse sweep logic (single source of truth for extraction + C4 fetch).
from lab_protocols_c4_s4_projection_sweep import (
    GAIA_ROOT,
    apply_alz_sequence_fix,
    apply_leuk_sequence_fix,
    apply_smiles_fix,
    build_s4_projection,
    entity_kind,
    fetch_c4_material,
    fetch_c4_molecule,
    fetch_c4_protein,
    health_check,
    norm_seq,
    norm_smiles,
    post_query_raw,
)

EVIDENCE = GAIA_ROOT / "evidence" / "inv3_recursive_repair"
VERIFY_SCRIPT = GAIA_ROOT / "scripts" / "inv3_s4_projection_verify.py"
INV3_LAB = GAIA_ROOT / "LAB_PROTOCOLS_INV3_LEUKEMIA_THERAPEUTICS.md"
ALZ_LAB = GAIA_ROOT / "LAB_PROTOCOLS_ALZHEIMER_BIOINVARIANT.md"


def discover_all_lab_files() -> list[Path]:
    """Operational lab protocols only (GAIAOS root), not docs/ methodology stubs."""
    return sorted(GAIA_ROOT.glob("LAB_PROTOCOLS_*.md"))


def discovery_type_label(eid: str) -> str:
    k = entity_kind(eid)
    if k == "molecule":
        return "small_molecule"
    if k == "protein":
        return "protein"
    return "material"


def get_claims_filtered(gateway: str, entity_id: str, limit: int = 5) -> tuple[list[dict[str, Any]], str | None]:
    q = urllib.parse.urlencode({"filter": entity_id, "limit": str(limit)})
    url = gateway.rstrip("/") + "/claims?" + q
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            raw = resp.read().decode()
    except urllib.error.URLError as e:
        return [], str(e)
    try:
        data = json.loads(raw)
        return (data if isinstance(data, list) else []), None
    except json.JSONDecodeError:
        return [], "invalid JSON from /claims"


def post_universal_ingest(gateway: str, body: dict[str, Any]) -> tuple[dict[str, Any] | None, str | None]:
    url = gateway.rstrip("/") + "/universal_ingest"
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode()
    except urllib.error.HTTPError as e:
        return None, e.read().decode()[:1200]
    except urllib.error.URLError as e:
        return None, str(e)
    try:
        return json.loads(raw), None
    except json.JSONDecodeError:
        return None, raw[:800]


def gateway_upsert_protein(
    gateway: str,
    dkey: str,
    protein_id: str,
    name: str,
    sequence: str,
    source_tag: str,
) -> tuple[bool, str]:
    aql = """
    UPSERT { protein_id: @pid }
    INSERT {
      _key: @dkey,
      protein_id: @pid,
      name: @name,
      sequence: @seq,
      source: @src,
      canonical_anchor_status: "canonical_anchor",
      inv3_recursive_repair: true
    }
    UPDATE {
      sequence: @seq,
      source: @src,
      canonical_anchor_status: "canonical_anchor",
      inv3_recursive_repair: true
    }
    IN discovered_proteins
    RETURN NEW
    """
    rows, err = post_query_raw(
        gateway,
        aql,
        {"pid": protein_id, "dkey": dkey, "name": name, "seq": sequence, "src": source_tag},
    )
    if err:
        return False, err
    return bool(rows), json.dumps(rows[0] if rows else {})


def classify_row(
    gateway: str,
    eid: str,
    s4_smiles: str | None,
    s4_seq: str | None,
) -> dict[str, Any]:
    kind = entity_kind(eid)
    claims, cerr = get_claims_filtered(gateway, eid, 5)
    out: dict[str, Any] = {
        "entity": eid,
        "discovery_type": discovery_type_label(eid),
        "claims_hits": len(claims),
        "claims_error": cerr,
    }
    c4_doc: dict[str, Any] | None = None
    coll = ""
    qerr: str | None = None

    if kind == "molecule":
        c4_doc, coll, qerr = fetch_c4_molecule(gateway, eid)
        c4_smiles = norm_smiles((c4_doc or {}).get("smiles") or (c4_doc or {}).get("canonical_smiles"))
        out.update(
            {
                "c4_collection": coll,
                "c4_key": c4_doc.get("_key") if c4_doc else None,
                "c4_smiles": c4_smiles,
                "s4_smiles": s4_smiles,
            }
        )
        if qerr:
            out["phase2_class"] = "BLOCKED"
            out["detail"] = qerr
            return out
        if not c4_doc:
            if s4_smiles:
                out["phase2_class"] = "MISSING"
                out["detail"] = "No C4 row; lab has SMILES"
            else:
                out["phase2_class"] = "PENDING"
                out["detail"] = "No SMILES in lab (TBD); C4 optional"
            return out
        if s4_smiles and c4_smiles and norm_smiles(s4_smiles) == c4_smiles:
            out["phase2_class"] = "ANCHORED"
        elif s4_smiles and c4_smiles:
            out["phase2_class"] = "MISMATCH"
            out["detail"] = "S4 SMILES != C4 SMILES"
        elif s4_smiles and not c4_smiles:
            out["phase2_class"] = "MISSING"
            out["detail"] = "C4 doc without smiles field"
        else:
            out["phase2_class"] = "PENDING"
            out["detail"] = "Hypothesis / no S4 SMILES"
        return out

    if kind == "protein":
        c4_doc, coll, qerr = fetch_c4_protein(gateway, eid, s4_seq)
        c4_seq = norm_seq((c4_doc or {}).get("sequence")) if c4_doc else None
        out.update(
            {
                "c4_collection": coll,
                "c4_key": c4_doc.get("_key") if c4_doc else None,
                "c4_sequence": c4_seq,
                "s4_sequence": s4_seq,
            }
        )
        if qerr:
            out["phase2_class"] = "BLOCKED"
            out["detail"] = qerr
            return out
        if not c4_doc:
            if s4_seq:
                out["phase2_class"] = "MISSING"
                out["detail"] = "No discovered_proteins row"
            else:
                out["phase2_class"] = "PENDING"
                out["detail"] = "No lab sequence (candidate/TBD)"
            return out
        if s4_seq and c4_seq and norm_seq(s4_seq) == c4_seq:
            out["phase2_class"] = "ANCHORED"
        elif s4_seq and c4_seq:
            out["phase2_class"] = "MISMATCH"
            out["detail"] = "S4 sequence != C4 sequence"
        elif s4_seq and not c4_seq:
            out["phase2_class"] = "MISSING"
            out["detail"] = "C4 protein missing sequence"
        else:
            out["phase2_class"] = "PENDING"
            out["detail"] = "No lab sequence to compare"
        return out

    c4_doc, coll, qerr = fetch_c4_material(gateway, eid)
    out.update({"c4_collection": coll, "c4_key": c4_doc.get("_key") if c4_doc else None})
    if qerr:
        out["phase2_class"] = "BLOCKED"
        out["detail"] = qerr
        return out
    out["phase2_class"] = "ANCHORED" if c4_doc else "PENDING"
    out["detail"] = "Material row" if c4_doc else "No C4 material"
    return out


def run_verifier(gateway: str, apply: bool) -> int:
    env = os.environ.copy()
    env["GAIAFTCL_GATEWAY"] = gateway
    cmd = [sys.executable, str(VERIFY_SCRIPT), "--gateway", gateway]
    if apply:
        cmd.append("--apply")
    r = subprocess.run(cmd, cwd=str(GAIA_ROOT), env=env, capture_output=True, text=True)
    if r.stdout.strip():
        print(r.stdout.strip())
    if r.stderr.strip():
        print(r.stderr, file=sys.stderr)
    return r.returncode


def main() -> int:
    ap = argparse.ArgumentParser(description="INV3 S4/C4 recursive repair + verifier loop")
    ap.add_argument(
        "--gateway",
        default=os.environ.get("GAIAFTCL_GATEWAY", "http://127.0.0.1:18803"),
    )
    ap.add_argument("--max-iterations", type=int, default=5)
    ap.add_argument(
        "--manifest-only",
        action="store_true",
        help="Phase 1 only: write manifest JSON and exit",
    )
    args = ap.parse_args()

    EVIDENCE.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    lab_files = discover_all_lab_files()
    if not lab_files:
        print("No LAB_PROTOCOLS_*.md found", file=sys.stderr)
        return 2

    s4 = build_s4_projection(lab_files)
    manifest_entities: list[dict[str, Any]] = []
    type_counts: dict[str, int] = {}
    for eid in sorted(s4.keys()):
        dt = discovery_type_label(eid)
        type_counts[dt] = type_counts.get(dt, 0) + 1
        ent = s4[eid]
        key_field = "compound_id" if dt == "small_molecule" else "peptide_id" if dt == "protein" else "material_id"
        manifest_entities.append(
            {
                "id": eid,
                "id_field": key_field,
                "type": dt,
                "smiles": ent.smiles,
                "sequence": ent.sequence,
                "composition": None,
                "sources": ent.sources,
            }
        )

    manifest_path = EVIDENCE / f"DISCOVERY_MANIFEST_{ts}.json"
    manifest_path.write_text(
        json.dumps(
            {
                "generated_utc": ts,
                "gateway": args.gateway,
                "lab_files": [str(p.relative_to(GAIA_ROOT)) for p in lab_files],
                "counts_by_type": type_counts,
                "total_entities": len(manifest_entities),
                "entities": manifest_entities,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(manifest_path)
    print(
        json.dumps({"PHASE_1": "manifest", "total": len(manifest_entities), "by_type": type_counts}),
        flush=True,
    )

    if args.manifest_only:
        return 0

    apply_ok = os.environ.get("INV3_VERIFY_APPLY") == "I_UNDERSTAND"
    gateway_ok = health_check(args.gateway)
    if not gateway_ok:
        _write_master_witness(
            ts,
            args.gateway,
            manifest_entities,
            type_counts,
            None,
            [],
            [],
            [],
            3,
            "INVARIANT_BREACH",
            [f"gateway /health unreachable: {args.gateway} (open SSH tunnel to 127.0.0.1:18803)"],
        )
        print("BLOCKED: gateway unreachable", file=sys.stderr)
        return 3

    # Initial Phase 2 snapshot (before repairs)
    before_rows = [_full_classify(args.gateway, s4, e["id"]) for e in manifest_entities]
    before_snap = _count_phase2(before_rows)

    claim_keys: list[str] = []
    corrections: list[str] = []
    c4_upserts: list[str] = []

    iteration = 0
    final_rc = 3
    while iteration < args.max_iterations:
        iteration += 1
        rows = [_full_classify(args.gateway, s4, e["id"]) for e in manifest_entities]

        for r in rows:
            eid = r["entity"]
            pc = r.get("phase2_class")
            if pc == "MISSING" and apply_ok:
                ent = s4[eid]
                dt = discovery_type_label(eid)
                payload = {
                    "entity_id": eid,
                    "discovery_type": dt,
                    "smiles": ent.smiles,
                    "sequence": ent.sequence,
                    "source": "inv3_recursive_repair",
                    "status": "canonical_anchor",
                    "caller_id": "recursive_invariant_repair",
                }
                ubody = {
                    "type": "protein" if dt == "protein" else "compound_anchor",
                    "payload": payload,
                    "from": "recursive_invariant_repair",
                }
                res, err = post_universal_ingest(args.gateway, ubody)
                if res and res.get("claim_key"):
                    claim_keys.append(str(res["claim_key"]))
                else:
                    claim_keys.append(f"INGEST_FAIL:{eid}:{err or 'unknown'}")

                if dt == "protein" and ent.sequence:
                    dkey = eid.lower().replace("-", "_") + "_canonical_anchor"
                    ok, info = gateway_upsert_protein(
                        args.gateway,
                        dkey,
                        eid,
                        f"{eid} (lab protocol anchor)",
                        ent.sequence.strip(),
                        "inv3_recursive_repair",
                    )
                    c4_upserts.append(f"{eid} discovered_proteins UPSERT ok={ok} {info[:240]}")

            if pc == "MISMATCH" and apply_ok:
                kind = entity_kind(eid)
                try:
                    if kind == "molecule" and eid == "AML-CHEM-001" and r.get("c4_smiles"):
                        old_s = s4[eid].smiles or ""
                        new_s = r["c4_smiles"]
                        apply_smiles_fix(INV3_LAB, old_s, new_s)
                        s4[eid].smiles = new_s
                        corrections.append(
                            f"PROJECTION_ERROR_CORRECTED AML-CHEM-001 SMILES → C4 in {INV3_LAB.name}"
                        )
                    elif kind == "protein" and r.get("c4_sequence") and s4[eid].sequence:
                        new_q = r["c4_sequence"]
                        lab_seq = s4[eid].sequence
                        if eid == "LEUK-005":
                            apply_leuk_sequence_fix(INV3_LAB, lab_seq, new_q)
                            s4[eid].sequence = new_q
                            corrections.append(
                                f"PROJECTION_ERROR_CORRECTED LEUK-005 sequence → C4 in {INV3_LAB.name}"
                            )
                        elif eid.startswith("ALZ-"):
                            apply_alz_sequence_fix(ALZ_LAB, eid, lab_seq, new_q)
                            s4[eid].sequence = new_q
                            corrections.append(
                                f"PROJECTION_ERROR_CORRECTED {eid} sequence → C4 in {ALZ_LAB.name}"
                            )
                except ValueError as ex:
                    corrections.append(f"PROJECTION_ERROR_APPLY_FAILED {eid}: {ex}")

        final_rc = run_verifier(args.gateway, apply=False)
        if final_rc == 0:
            break
        if final_rc == 1 and apply_ok:
            run_verifier(args.gateway, apply=True)
            final_rc = run_verifier(args.gateway, apply=False)
            if final_rc == 0:
                break
        if final_rc == 3:
            break

    after_rows = [_full_classify(args.gateway, s4, e["id"]) for e in manifest_entities]
    after_snap = _count_phase2(after_rows)

    breach = final_rc != 0
    gaps: list[str] = []
    if breach:
        if final_rc == 2:
            gaps.append("inv3_s4_projection_verify exit 2: missing C4 projection for INV3 lab entity")
        elif final_rc == 1:
            gaps.append("inv3_s4_projection_verify exit 1: SMILES or sequence mismatch persists")
        elif final_rc == 3:
            gaps.append("inv3_s4_projection_verify exit 3: gateway/query failure during verify")
        for r in after_rows:
            if r.get("phase2_class") in ("MISSING", "MISMATCH", "BLOCKED"):
                gaps.append(f"{r.get('entity')}: {r.get('phase2_class')} — {r.get('detail', '')}")

    statement = "ALL_INVARIANTS_CLOSED" if final_rc == 0 else "INVARIANT_BREACH"

    _write_master_witness(
        ts,
        args.gateway,
        manifest_entities,
        type_counts,
        before_snap,
        claim_keys,
        corrections,
        c4_upserts,
        final_rc,
        statement,
        gaps,
        after_snap=after_snap,
    )

    return final_rc if final_rc in (0, 1, 2, 3) else 3


def _full_classify(gateway: str, s4: dict, eid: str) -> dict[str, Any]:
    ent = s4[eid]
    return classify_row(gateway, eid, ent.smiles, ent.sequence)


def _count_phase2(rows: list[dict[str, Any]]) -> dict[str, int]:
    keys = ("ANCHORED", "MISSING", "MISMATCH", "PENDING", "BLOCKED")
    out = {k: 0 for k in keys}
    for r in rows:
        c = r.get("phase2_class") or "PENDING"
        if c in out:
            out[c] += 1
    return out


def _write_master_witness(
    ts: str,
    gateway: str,
    manifest_entities: list[dict[str, Any]],
    type_counts: dict[str, int],
    before_snap: dict[str, int] | None,
    claim_keys: list[str],
    corrections: list[str],
    c4_upserts: list[str],
    verify_rc: int,
    statement: str,
    gaps: list[str],
    after_snap: dict[str, int] | None = None,
) -> None:
    path = EVIDENCE / f"MASTER_WITNESS_NOTE_{ts}.md"
    lines = [
        "# MASTER_WITNESS_NOTE — INV3 recursive invariant repair",
        "",
        f"- **generated_utc:** `{ts}`",
        f"- **gateway:** `{gateway}`",
        f"- **total_discoveries_in_lab_docs:** {len(manifest_entities)}",
        f"- **counts_by_type (manifest):** `{json.dumps(type_counts)}`",
        "",
        "## Phase 2 — substrate classification",
        "",
    ]
    if before_snap:
        lines.append(f"- **before repair:** ANCHORED={before_snap['ANCHORED']}, MISSING={before_snap['MISSING']}, "
                     f"MISMATCH={before_snap['MISMATCH']}, PENDING={before_snap['PENDING']}, BLOCKED={before_snap['BLOCKED']}")
    if after_snap:
        lines.append(f"- **after repair:** ANCHORED={after_snap['ANCHORED']}, MISSING={after_snap['MISSING']}, "
                     f"MISMATCH={after_snap['MISMATCH']}, PENDING={after_snap['PENDING']}, BLOCKED={after_snap['BLOCKED']}")
    lines.extend(
        [
            "",
            "## Phase 3 — universal_ingest claim_key values",
            "",
        ]
    )
    if claim_keys:
        lines.extend(f"- `{k}`" for k in claim_keys)
    else:
        lines.append("- _(none)_")
    lines.extend(["", "## C4 UPSERT (discovered_proteins) via gateway /query", ""])
    if c4_upserts:
        lines.extend(f"- {u}" for u in c4_upserts)
    else:
        lines.append("- _(none)_")
    lines.extend(["", "## PROJECTION_ERROR_CORRECTED (lab doc patches)", ""])
    if corrections:
        lines.extend(f"- {c}" for c in corrections)
    else:
        lines.append("- _(none)_")
    lines.extend(
        [
            "",
            "## Phase 4 — inv3_s4_projection_verify.py",
            "",
            f"- **final_exit_code:** `{verify_rc}`",
            "",
            "## Terminal statement",
            "",
            f"**{statement}**",
            "",
        ]
    )
    if gaps:
        lines.append("### Remaining gaps")
        lines.extend(f"- {g}" for g in gaps)
    path.write_text("\n".join(lines), encoding="utf-8")
    print(path)


if __name__ == "__main__":
    raise SystemExit(main())
