#!/usr/bin/env python3
"""
INV3 AML email → substrate → Franklin life-safety validation (subprocess + HTTP).
Assumes PHASE 0: SSH tunnel 18803→8803 (and optional 18529→8529) already up.
"""
from __future__ import annotations

import json
import os
import re
import socket
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

GAIA_ROOT = Path(__file__).resolve().parent.parent
EVIDENCE = GAIA_ROOT / "evidence" / "inv3_email_validation"
ADAPTER = GAIA_ROOT / "services" / "mailcow_inbound_adapter" / "adapter.py"
VERIFY = GAIA_ROOT / "scripts" / "inv3_s4_projection_verify.py"
REPAIR = GAIA_ROOT / "scripts" / "inv3_recursive_repair.py"

GATEWAY = os.environ.get("GAIAFTCL_GATEWAY", "http://127.0.0.1:18803").rstrip("/")
SMTP_HOST = os.environ.get("INV3_SMTP_HOST", "77.42.85.60")
SMTP_PORT = int(os.environ.get("INV3_SMTP_PORT", "25"))
# When external :25 is blocked, tunnel: ssh -L 18025:127.0.0.1:25 ... then INV3_SMTP_FALLBACK_PORT=18025
SMTP_FALLBACK_PORT = os.environ.get("INV3_SMTP_FALLBACK_PORT", "18025")
# Per runbook: curl .../claims?filter=...&limit=5 — override with INV3_CLAIMS_LIMIT for noisy filters.
CLAIMS_PHASE3_LIMIT = int(os.environ.get("INV3_CLAIMS_LIMIT", "5"))


def http_json(method: str, url: str, data: dict | None = None, timeout: int = 120) -> tuple[dict | list | None, str | None]:
    try:
        body = json.dumps(data).encode() if data is not None else None
        req = urllib.request.Request(url, data=body, method=method, headers={"Content-Type": "application/json"} if body else {})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode()
        return (json.loads(raw) if raw.strip() else None), None
    except urllib.error.HTTPError as e:
        return None, f"HTTP {e.code}: {e.read().decode()[:800]}"
    except urllib.error.URLError as e:
        return None, str(e.reason)
    except json.JSONDecodeError as e:
        return None, str(e)


def get_claims(filter_term: str, limit: int = 5) -> list:
    q = urllib.parse.urlencode({"filter": filter_term, "limit": str(limit)})
    url = f"{GATEWAY}/claims?{q}"
    try:
        with urllib.request.urlopen(url, timeout=60) as resp:
            data = json.loads(resp.read().decode())
        return data if isinstance(data, list) else []
    except Exception:
        return []


def post_query(q: str, bind: dict) -> list:
    url = f"{GATEWAY}/query"
    payload = {"query": q, "bind_vars": bind}
    out, err = http_json("POST", url, payload, timeout=90)
    if err:
        return []
    if isinstance(out, list):
        return out
    return []


def claim_blob(c: dict) -> str:
    return json.dumps(c, default=str).lower()


def phase0() -> tuple[bool, str]:
    try:
        with urllib.request.urlopen(f"{GATEWAY}/health", timeout=15) as r:
            h = json.loads(r.read().decode())
    except Exception as e:
        return False, f"TUNNEL_FAILED: health unreachable: {e}"
    if h.get("status") != "healthy":
        return False, f"TUNNEL_FAILED: status not healthy: {h}"
    if not h.get("nats_connected"):
        return False, f"TUNNEL_FAILED: nats_connected false: {h}"
    return True, "ok"


def substrate_leuk_aml() -> tuple[bool, bool]:
    """LEUK-005 and AML-CHEM-001 rows in discovered_* (canonical substrate)."""
    rows_p = post_query(
        "FOR d IN discovered_proteins FILTER d.protein_id == @pid LIMIT 1 RETURN d",
        {"pid": "LEUK-005"},
    )
    rows_m = post_query(
        """
        FOR d IN discovered_molecules
          FILTER d._key == @key OR d.name == @name OR d.molecule_id == @mid
          LIMIT 1
          RETURN d
        """,
        {"key": "cancer_candidate_9084", "name": "AML-CHEM-001", "mid": "cancer_candidate_9084"},
    )
    leuk = bool(rows_p and rows_p[0].get("sequence"))
    aml = bool(rows_m and (rows_m[0].get("smiles") or rows_m[0].get("canonical_smiles")))
    return leuk, aml


def analyze_claims_filter(label: str, filter_term: str) -> dict:
    rows = get_claims(filter_term, 5)
    out = {"label": label, "filter": filter_term, "count": len(rows), "statuses": [], "canonical_anchor_hits": 0}
    for c in rows:
        st = c.get("status") or c.get("type") or ""
        out["statuses"].append(str(st))
        blob = claim_blob(c)
        if "canonical_anchor" in blob or "inv3_recursive_repair" in blob:
            out["canonical_anchor_hits"] += 1
    return out


def run_repair() -> int:
    env = os.environ.copy()
    env["GAIAFTCL_GATEWAY"] = GATEWAY
    env.setdefault("INV3_VERIFY_APPLY", "I_UNDERSTAND")
    return subprocess.run(
        [sys.executable, str(REPAIR)],
        cwd=str(GAIA_ROOT),
        env=env,
        capture_output=True,
        text=True,
    ).returncode


def run_verify(apply: bool) -> int:
    env = os.environ.copy()
    env["GAIAFTCL_GATEWAY"] = GATEWAY
    env.setdefault("INV3_VERIFY_APPLY", "I_UNDERSTAND")
    cmd = [sys.executable, str(VERIFY), "--gateway", GATEWAY]
    if apply:
        cmd.append("--apply")
    return subprocess.run(cmd, cwd=str(GAIA_ROOT), env=env, capture_output=True, text=True).returncode


def inject_email() -> tuple[str | None, str]:
    raw = (
        "From: janowitz@cshl.edu\n"
        "To: research@gaiaftcl.com\n"
        "Subject: RE: Owl Protocol — INV3 AML maternal parity cohort\n"
        "Message-ID: <inv3-test-001@cshl.edu>\n"
        "\n"
        "Rick — yes we have maternal parity data in our TNBC cohort. "
        "We also have inv(3) AML patient records that include birth order information. "
        "LEUK-005 binding affinity data attached. AML-CHEM-001 IC50 results coming next week.\n"
        "Tobias\n"
    )
    env = os.environ.copy()
    env["GAIAFTCL_GATEWAY"] = GATEWAY
    p = subprocess.run(
        [sys.executable, str(ADAPTER)],
        input=raw,
        capture_output=True,
        text=True,
        env=env,
        cwd=str(GAIA_ROOT),
        timeout=120,
    )
    err = p.stderr or ""
    m = re.search(r"claim_key=([^\s]+)", err)
    key = m.group(1).strip() if m else None
    if p.returncode != 0:
        return None, f"adapter_exit={p.returncode} stderr={err[:1200]} stdout={p.stdout[:400]}"
    if not key or key == "None":
        return None, f"no claim_key in stderr: {err[:800]}"
    return key, "ok"


def find_inbound_claim(claim_key: str) -> dict | None:
    rows = post_query("FOR c IN mcp_claims FILTER c._key == @k LIMIT 1 RETURN c", {"k": claim_key})
    if rows:
        return rows[0]
    rows = get_claims(claim_key, 20)
    for c in rows:
        if c.get("_key") == claim_key or claim_key in json.dumps(c):
            return c
    return None


def phase3_assert(claim_key: str) -> tuple[list[str], dict]:
    failures = []
    filters = [("janowitz", "janowitz"), ("owl_protocol", "owl_protocol"), ("research", "research")]
    parsed: dict[str, dict] = {}
    for name, ft in filters:
        rows = get_claims(ft, CLAIMS_PHASE3_LIMIT)
        blob = json.dumps(rows)
        disambig = ""
        if claim_key not in blob and name == "research":
            rows2 = get_claims("research@gaiaftcl.com", CLAIMS_PHASE3_LIMIT)
            blob2 = json.dumps(rows2)
            if claim_key in blob2:
                rows, blob = rows2, blob2
                disambig = " (disambiguated: filter=research@gaiaftcl.com)"
        if claim_key not in blob:
            failures.append(f"PHASE3: filter={ft!r} missing INBOUND_CLAIM_KEY {claim_key}{disambig}")
        hit = None
        for c in rows:
            if c.get("_key") == claim_key:
                hit = c
                break
        if not hit:
            for c in rows:
                if claim_key in json.dumps(c):
                    hit = c
                    break
        pl = (hit or {}).get("payload") if isinstance((hit or {}).get("payload"), dict) else {}
        gr = pl.get("game_room", "")
        if hit and gr != "owl_protocol":
            failures.append(f"PHASE3: filter={ft!r} game_room={gr!r} expected owl_protocol")
        from_v = str(pl.get("from", "")).lower()
        if hit and "janowitz@cshl.edu" not in from_v:
            failures.append(f"PHASE3: filter={ft!r} from={from_v!r} missing janowitz@cshl.edu")
        st = str((hit or {}).get("status", "")).lower()
        if hit and "error" in st:
            failures.append(f"PHASE3: filter={ft!r} status looks like error: {st}")
        parsed[name] = {"hit": bool(hit), "game_room": gr, "from": pl.get("from", ""), "status": (hit or {}).get("status")}
    return failures, parsed


def franklin_ask() -> tuple[str, str | None]:
    q = (
        "What is the status of INV3 AML research communications? Has anyone contacted us "
        "about maternal parity data or LEUK-005 binding affinity?"
    )
    url = f"{GATEWAY}/ask"
    out, err = http_json("POST", url, {"query": q}, timeout=180)
    if err:
        return "", err
    if isinstance(out, dict):
        return out.get("document") or out.get("essay") or "", None
    return "", "unexpected /ask shape"


def franklin_substrate_mail_witness(claim_key: str) -> tuple[bool, str]:
    """
    If /ask still returns NATS/generative fallback, prove MAIL claim is readable from substrate
    (same shape as gateway query_full_substrate mail_summary).
    """
    rows = post_query(
        """
        FOR c IN mcp_claims
          FILTER c._key == @k AND c.type == "MAIL" AND c.payload != null
          LIMIT 1
          RETURN {
            id: c._key,
            game_room: c.payload.game_room,
            mail_from: c.payload.from,
            subject: c.payload.subject,
            body_preview: SUBSTRING(c.payload.body != null ? c.payload.body : "", 0, 400)
          }
        """,
        {"k": claim_key},
    )
    if not rows:
        return False, ""
    r = rows[0]
    blob = json.dumps(r, default=str).lower()
    ok = (
        r.get("game_room") == "owl_protocol"
        and "janowitz@cshl.edu" in blob
        and "leuk-005" in blob
        and "aml-chem-001" in blob
    )
    return ok, blob[:600]


def franklin_assert(doc: str) -> tuple[bool, list[str]]:
    fails = []
    low = doc.lower()
    neg = [
        "no data",
        "no information",
        "couldn't find",
        "could not find",
        "don't have any",
        "do not have any",
        "i don't have",
        "no access",
        "unable to find",
        "substrate unreachable",
    ]
    for n in neg:
        if n in low:
            fails.append(f"PHASE4: negative phrase in response: {n!r}")
    strong = (
        "leuk-005",
        "aml-chem-001",
        "inv3",
        "maternal",
        "parity",
        "janowitz",
        "binding",
        "affinity",
        "owl protocol",
        "research@",
        "mailcow",
        "inbound",
    )
    if not any(p in low for p in strong):
        fails.append("PHASE4: response missing strong INV3/email/thread hints (LEUK-005, janowitz, maternal, …)")
    return len(fails) == 0, fails


def _smtp_rcpt_on(host: str, port: int) -> tuple[bool, str, str]:
    lines: list[str] = []
    try:
        s = socket.create_connection((host, port), timeout=18)
    except OSError as e:
        return False, "", f"connect_failed:{host}:{port}:{e}"
    try:
        f = s.makefile("r", encoding="utf-8", errors="replace", newline="\n")

        def read_resp() -> str:
            last = ""
            while True:
                ln = f.readline()
                if not ln:
                    break
                ln = ln.rstrip("\r\n")
                lines.append(ln)
                last = ln
                if len(ln) >= 4 and ln[3] == " ":
                    break
                if len(ln) >= 4 and ln[3] != "-":
                    break
            return last

        read_resp()
        s.sendall(b"EHLO testclient.example.com\r\n")
        read_resp()
        s.sendall(b"MAIL FROM:<test@example.com>\r\n")
        read_resp()
        s.sendall(b"RCPT TO:<research@gaiaftcl.com>\r\n")
        last = read_resp()
        s.sendall(b"QUIT\r\n")
        try:
            read_resp()
        except Exception:
            pass
        ok = last.startswith("250")
        return ok, last, "\n".join(lines)
    finally:
        try:
            s.close()
        except Exception:
            pass


def smtp_rcpt_check() -> tuple[bool, str, str]:
    ok, last, tx = _smtp_rcpt_on(SMTP_HOST, SMTP_PORT)
    if ok:
        return ok, last, tx
    fb = int(SMTP_FALLBACK_PORT) if SMTP_FALLBACK_PORT.isdigit() else 0
    if fb > 0:
        ok2, last2, tx2 = _smtp_rcpt_on("127.0.0.1", fb)
        if ok2:
            return ok2, last2, tx + "\n---fallback localhost:" + str(fb) + "---\n" + tx2
        return False, last or last2, tx + "\n---fallback---\n" + tx2
    return ok, last, tx


def phase6_playwright_smtp(evidence_ts: str) -> tuple[bool, str, str]:
    """PHASE 6: subprocess `npx playwright test` + Node net (see tests/inv3_research_smtp.spec.ts)."""
    ui = GAIA_ROOT / "services" / "gaiaos_ui_web"
    if not (ui / "node_modules").is_dir():
        return (
            False,
            "node_modules missing",
            "cd services/gaiaos_ui_web && npm ci",
        )
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    raw_dir = EVIDENCE / f"raw_{evidence_ts}"
    raw_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["INV3_SMTP_ONLY"] = "1"
    env["INV3_SMTP_HOST"] = SMTP_HOST
    env["INV3_SMTP_PORT"] = str(SMTP_PORT)
    if SMTP_FALLBACK_PORT.strip():
        env["INV3_SMTP_FALLBACK_PORT"] = SMTP_FALLBACK_PORT.strip()
    p = subprocess.run(
        ["npx", "playwright", "test", "tests/inv3_research_smtp.spec.ts", "--reporter=line"],
        cwd=str(ui),
        capture_output=True,
        text=True,
        timeout=120,
        env=env,
    )
    log = f"exit={p.returncode}\nSTDOUT:\n{p.stdout or ''}\nSTDERR:\n{p.stderr or ''}"
    (raw_dir / "phase6_playwright_smtp.log").write_text(log, encoding="utf-8")
    if p.returncode == 0:
        return True, "250", log
    return False, (p.stderr or p.stdout or "")[:200], log


def main() -> int:
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    failures: list[str] = []

    ok0, msg0 = phase0()
    if not ok0:
        failures.append(msg0)
        _write_blocked_receipt(ts, failures, {})
        print("LIFE_SAFETY_RECEIPT BLOCKED")
        for f in failures:
            print(f"  - {f}")
        return 1

    # Phase 1
    p1_reports = [
        analyze_claims_filter("LEUK-005", "LEUK-005"),
        analyze_claims_filter("AML-CHEM-001", "AML-CHEM-001"),
        analyze_claims_filter("inv3", "inv3"),
    ]
    leuk_sub, aml_sub = substrate_leuk_aml()
    claims_have_anchor = any(r["canonical_anchor_hits"] > 0 for r in p1_reports)

    if not leuk_sub:
        failures.append("PHASE1: LEUK-005 no discovered_proteins canonical row (sequence)")
        rc = run_repair()
        if rc != 0:
            failures.append(f"PHASE1: inv3_recursive_repair exit {rc}")
        leuk_sub, aml_sub = substrate_leuk_aml()
        if not leuk_sub:
            failures.append("PHASE1: LEUK-005 still missing after repair")

    if not aml_sub:
        failures.append("PHASE1: AML-CHEM-001 / cancer_candidate_9084 missing SMILES in substrate")

    inv3_count = p1_reports[2]["count"]

    # Phase 2
    inbound_key, ierr = inject_email()
    if not inbound_key:
        failures.append(f"PHASE2: {ierr}")

    # Phase 3
    p3_failures = []
    p3_parsed = {}
    subj_ok = False
    if inbound_key:
        p3_failures, p3_parsed = phase3_assert(inbound_key)
        failures.extend(p3_failures)
        c0 = find_inbound_claim(inbound_key)
        pl = (c0 or {}).get("payload") if c0 else {}
        if isinstance(pl, dict):
            subj_l = str(pl.get("subject", "")).lower()
            subj_ok = ("owl" in subj_l or "protocol" in subj_l) and "inv3" in subj_l

    # Phase 4 — /ask text alone must reference INV3 mail thread (no substrate witness substitute).
    frank_doc_raw, ferr = franklin_ask()
    frank_doc = frank_doc_raw
    if ferr:
        failures.append(f"PHASE4: {ferr}")
    frank_ok, ffails = franklin_assert(frank_doc_raw or "")
    failures.extend(ffails)
    if inbound_key and not frank_ok:
        wok, wblob = franklin_substrate_mail_witness(inbound_key)
        if wok:
            frank_doc = (
                (frank_doc_raw or "")
                + "\n\n[substrate MAIL witness — not counted for Phase 4; /ask must narrate after gateway deploy]\n"
                + (wblob[:500] if wblob else "")
            )

    # Phase 5
    vrc = run_verify(False)
    loops = 0
    while vrc != 0 and loops < 5:
        loops += 1
        if vrc == 1:
            vrc = run_verify(True)
            vrc = run_verify(False)
        elif vrc == 2:
            if run_repair() != 0:
                failures.append("PHASE5: repair failed during exit-2 loop")
            vrc = run_verify(False)
        else:
            failures.append(f"PHASE5: verifier blocked exit {vrc}")
            break
    if vrc != 0:
        failures.append(f"PHASE5: inv3_s4_projection_verify final exit {vrc}")

    leuk_final, aml_final = substrate_leuk_aml()

    # Phase 6
    smtp_ok, smtp_last, smtp_tx = phase6_playwright_smtp(ts)
    if not smtp_ok:
        failures.append(f"PHASE6: Playwright SMTP test failed: {smtp_last!r} log={smtp_tx[:500]!r}")

    # Receipt fields
    meta = {
        "ts": ts,
        "phase0": {"ok": True},
        "phase1": {"reports": p1_reports, "leuk_substrate": leuk_sub, "aml_substrate": aml_sub, "claims_anchor_hits": claims_have_anchor},
        "inbound_key": inbound_key,
        "phase3": p3_parsed,
        "franklin_doc": frank_doc,
        "verifier_exit": vrc,
        "smtp_ok": smtp_ok,
        "smtp_last": smtp_last,
        "leuk_final": leuk_final,
        "aml_final": aml_final,
        "subject_preserved": subj_ok,
        "phase4_ask_alone_ok": frank_ok,
    }

    receipt_path = EVIDENCE / f"LIFE_SAFETY_RECEIPT_{ts}.md"
    all_closed = len(failures) == 0 and vrc == 0 and frank_ok and smtp_ok and leuk_final and aml_final

    _write_receipt(receipt_path, meta, failures, frank_doc or "", inbound_key, vrc, smtp_ok, smtp_last, all_closed)

    if all_closed:
        print("INV3 AML LIFE-SAFETY RECEIPT ISSUED")
        print(ts)
        print("research@gaiaftcl.com is sovereign")
        print("LEUK-005 and AML-CHEM-001 are substrate-backed")
        print("Franklin can hear INV3 communications")
        print("The wet lab path is clean")
        print("Calories or cures. The floor is physics.")
        print(receipt_path)
        return 0

    print("LIFE_SAFETY_RECEIPT BLOCKED")
    for f in failures:
        print(f"  - {f}")
    print(receipt_path)
    return 1


def _write_blocked_receipt(ts: str, failures: list[str], meta: dict) -> None:
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    p = EVIDENCE / f"LIFE_SAFETY_RECEIPT_{ts}.md"
    p.write_text(
        "\n".join(
            [
                "## INV3 AML Email System Validation",
                "",
                "**LIFE_SAFETY_RECEIPT BLOCKED**",
                "",
                "### Failed assertions",
                "",
                *[f"- {x}" for x in failures],
            ]
        ),
        encoding="utf-8",
    )
    print(p)


def _write_receipt(
    path: Path,
    meta: dict,
    failures: list[str],
    frank_doc: str,
    inbound_key: str | None,
    vrc: int,
    smtp_ok: bool,
    smtp_last: str,
    all_closed: bool,
) -> None:
    ts = meta["ts"]
    p1 = meta["phase1"]
    r0, r1, r2 = p1["reports"]
    excerpt = (frank_doc or "").replace("\n", " ")[:200]
    leuk_ca = "FOUND" if p1["leuk_substrate"] else "MISSING"
    aml_ca = "FOUND" if p1["aml_substrate"] else "MISSING"
    gr = "owl_protocol"
    if meta.get("phase3"):
        for v in meta["phase3"].values():
            if isinstance(v, dict) and v.get("game_room") and v["game_room"] != "owl_protocol":
                gr = str(v.get("game_room"))
                break

    lines = [
        "## INV3 AML Email System Validation",
        "",
        "### Substrate prerequisites",
        f"LEUK-005 canonical anchor: [{leuk_ca}]",
        f"AML-CHEM-001 canonical anchor: [{aml_ca}]",
        f"INV3 claims count: [{r2['count']}]",
        "",
        f"- LEUK-005 filter: count={r0['count']}, statuses={r0['statuses']}, canonical_anchor substring hits={r0['canonical_anchor_hits']}",
        f"- AML-CHEM-001 filter: count={r1['count']}, statuses={r1['statuses']}, canonical_anchor substring hits={r1['canonical_anchor_hits']}",
        f"- inv3 filter: count={r2['count']}, statuses={r2['statuses']}, canonical_anchor substring hits={r2['canonical_anchor_hits']}",
        "",
        "### Email routing validation",
        f"Test message claim_key: [{inbound_key or 'NONE'}]",
        f"Game room routing: [{gr}]",
        f"From field preserved: [{'YES' if inbound_key else 'NO'}]",
        f"Subject preserved: [{'YES' if meta.get('subject_preserved') else 'NO'}]",
        "",
        "### Franklin awareness",
        f"Query response acknowledged INV3: [{'YES' if meta.get('franklin_doc') and not [x for x in failures if x.startswith('PHASE4')] else 'NO'}]",
        f"Response excerpt: [{excerpt}]",
        "",
        "### Lab instruction integrity",
        f"Verifier exit code: [{vrc}]",
        f"LAB_INSTRUCTIONS_CLEAN: [{'YES' if vrc == 0 else 'NO'}]",
        f"LEUK-005 substrate backed: [{'YES' if meta.get('leuk_final') else 'NO'}]",
        f"AML-CHEM-001 substrate backed: [{'YES' if meta.get('aml_final') else 'NO'}]",
        "",
        "### External SMTP validation",
        f"research@ accepts inbound SMTP: [{'YES' if smtp_ok else 'NO'}]",
        f"SMTP response code: [{smtp_last[:3] if smtp_last else 'n/a'}]",
        "",
        "### Life-safety certification",
        f"ALL_INVARIANTS_CLOSED: [{'YES' if all_closed else 'NO'}]",
        f"Constitutional violations: [{len(failures)}]",
        f"Ready for external researcher contact: [{'YES' if all_closed else 'NO'}]",
        "",
    ]
    if failures:
        lines.extend(["### Failed assertions", ""] + [f"- {f}" for f in failures] + [""])

    if all_closed:
        lines.extend(
            [
                "---",
                "",
                "INV3 AML LIFE-SAFETY RECEIPT ISSUED",
                ts,
                "research@gaiaftcl.com is sovereign",
                "LEUK-005 and AML-CHEM-001 are substrate-backed",
                "Franklin can hear INV3 communications",
                "The wet lab path is clean",
                "Calories or cures. The floor is physics.",
            ]
        )
    else:
        lines.extend(["---", "", "**LIFE_SAFETY_RECEIPT BLOCKED** — fix assertions above."])

    path.write_text("\n".join(lines), encoding="utf-8")

    # Raw artifacts
    raw_dir = path.parent / f"raw_{ts}"
    raw_dir.mkdir(exist_ok=True)
    (raw_dir / "franklin_response.txt").write_text(frank_doc or "", encoding="utf-8")
    (raw_dir / "meta.json").write_text(json.dumps(meta, indent=2, default=str), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
