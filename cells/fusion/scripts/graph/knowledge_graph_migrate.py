#!/usr/bin/env python3
"""
GaiaFTCL knowledge graph — create edge collections, named graph, and populate edges (gaiaos).

Idempotent: truncates edge collections, rebuilds graph definition, re-inserts edges.

Usage:
  ARANGO_URL=http://host:8529 ARANGO_USER=root ARANGO_PASSWORD=... \\
    python3 cells/fusion/scripts/graph/knowledge_graph_migrate.py

Optional: --verify-only  (skip write; run count + sample traversal AQL)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from typing import Any

GRAPH_NAME = "gaiaftcl_knowledge_graph"
DOMAIN_COLL = "discovery_domain"
EDGE_COLLECTIONS = [
    "discovery_has_envelope",
    "discovery_has_claim",
    "compound_has_molecule",
    "material_has_candidate",
    "protein_targets_domain",
    "claim_references_discovery",
    "closure_closes_claim",
    "entity_has_vqbit",
    "vqbit_has_envelope",
    "domain_shares_invariant",
]

VIE_DOCUMENT_COLLECTIONS = [
    "domain_schemas",
    "vie_events",
    "vortex_rooms",
]

NOW_ISO = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
SOURCE = "migration_v1"


def env(name: str, default: str) -> str:
    v = os.environ.get(name, default)
    return v.strip() if isinstance(v, str) else default


def arango_req(
    method: str,
    path: str,
    body: dict[str, Any] | None = None,
) -> tuple[int, Any]:
    base = env("ARANGO_URL", "http://127.0.0.1:8529").rstrip("/")
    db = env("ARANGO_DB", "gaiaos")
    user = env("ARANGO_USER", "root")
    password = env("ARANGO_PASSWORD", "gaiaftcl2026")
    url = f"{base}/_db/{db}{path}"
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    credentials = f"{user}:{password}".encode()
    import base64

    req.add_header("Authorization", f"Basic {base64.b64encode(credentials).decode()}")
    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            raw = resp.read().decode()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode() if e.fp else ""
        try:
            parsed = json.loads(raw) if raw else {"error": str(e)}
        except json.JSONDecodeError:
            parsed = {"error": raw or str(e)}
        return e.code, parsed


def cursor(query: str, bind_vars: dict[str, Any] | None = None) -> list[Any]:
    code, data = arango_req(
        "POST",
        "/_api/cursor",
        {"query": query, "bindVars": bind_vars or {}},
    )
    if code not in (200, 201):
        raise RuntimeError(f"AQL failed {code}: {data}")
    out = list(data.get("result") or [])
    cid = data.get("id")
    while data.get("hasMore") and cid:
        code2, data2 = arango_req("PUT", f"/_api/cursor/{cid}", {})
        if code2 not in (200, 201):
            raise RuntimeError(f"cursor continue failed {code2}: {data2}")
        out.extend(data2.get("result") or [])
        cid = data2.get("id")
        data = data2
    return out


def ensure_document_collection(name: str) -> None:
    code, _ = arango_req("GET", f"/_api/collection/{name}")
    if code == 200:
        return
    code2, err = arango_req("POST", "/_api/collection", {"name": name, "type": 2})
    if code2 not in (200, 201):
        raise RuntimeError(f"create collection {name}: {code2} {err}")


def ensure_edge_collection(name: str) -> None:
    code, _ = arango_req("GET", f"/_api/collection/{name}")
    if code == 200:
        return
    code2, err = arango_req("POST", "/_api/collection", {"name": name, "type": 3})
    if code2 not in (200, 201):
        raise RuntimeError(f"create edge {name}: {code2} {err}")


def list_discovered_collections() -> list[str]:
    q = """
    FOR c IN COLLECTIONS()
      FILTER c.type == 2
      FILTER LIKE(c.name, "discovered_%", true)
      SORT c.name
      RETURN c.name
    """
    rows = cursor(q)
    if not rows:
        return [
            "discovered_molecules",
            "discovered_compounds",
            "discovered_proteins",
            "discovered_materials",
            "discovered_mofs",
            "discovered_superconductors",
            "discovered_fluid_dynamics",
            "discovered_trading_strategies",
            "discovered_clinical_trials",
            "discovered_nfl_plays",
        ]
    return [str(x) for x in rows]


def truncate_collection(name: str) -> None:
    cursor(f"FOR x IN {name} REMOVE x IN {name}")


def ensure_persistent_index(collection: str, fields: list[str], sparse: bool = True) -> None:
    code, data = arango_req("GET", f"/_api/index?collection={collection}")
    if code == 200 and isinstance(data.get("indexes"), list):
        for idx in data["indexes"]:
            if idx.get("fields") == fields:
                return
    code2, err = arango_req(
        "POST",
        f"/_api/index?collection={collection}",
        {
            "type": "persistent",
            "fields": fields,
            "sparse": sparse,
            "unique": False,
        },
    )
    if code2 not in (200, 201):
        print(f"  (warn) index {collection}{fields}: {code2} {err}", file=sys.stderr)


def drop_graph_if_exists() -> None:
    code, _ = arango_req("GET", f"/_api/gharial/{GRAPH_NAME}")
    if code != 200:
        return
    code2, err = arango_req("DELETE", f"/_api/gharial/{GRAPH_NAME}?dropCollections=false")
    if code2 not in (200, 202, 204):
        raise RuntimeError(f"drop graph: {code2} {err}")


def create_graph(discovered: list[str]) -> None:
    defs: list[dict[str, Any]] = [
        {
            "collection": "discovery_has_envelope",
            "from": discovered,
            "to": ["truth_envelopes"],
        },
        {
            "collection": "discovery_has_claim",
            "from": discovered,
            "to": ["mcp_claims"],
        },
        {
            "collection": "compound_has_molecule",
            "from": ["discovered_compounds"],
            "to": ["discovered_molecules"],
        },
        {
            "collection": "material_has_candidate",
            "from": ["discovered_materials"],
            "to": ["discovered_compounds"],
        },
        {
            "collection": "protein_targets_domain",
            "from": ["discovered_proteins"],
            "to": [DOMAIN_COLL],
        },
        {
            "collection": "claim_references_discovery",
            "from": ["mcp_claims"],
            "to": discovered,
        },
        {
            "collection": "closure_closes_claim",
            "from": ["game_closure_events"],
            "to": ["mcp_claims"],
        },
        {
            "collection": "entity_has_vqbit",
            "from": discovered + ["vie_events"],
            "to": ["vqbit_measurements"],
        },
        {
            "collection": "vqbit_has_envelope",
            "from": ["vqbit_measurements"],
            "to": ["envelope_ledger"],
        },
        {
            "collection": "domain_shares_invariant",
            "from": ["vie_events"],
            "to": ["vie_events"],
        },
    ]
    code, err = arango_req(
        "POST",
        "/_api/gharial",
        {"name": GRAPH_NAME, "edgeDefinitions": defs},
    )
    if code not in (200, 201, 202):
        raise RuntimeError(f"create graph: {code} {err}")


def materialize_truth_envelopes_from_discoveries(discovered: list[str]) -> int:
    """
    Many discovery docs embed truth_envelope.hash but no truth_envelopes row uses that _key/hash.
    Upsert lightweight envelope vertices keyed by hash so graph edges are real FKs.
    """
    ensure_persistent_index("truth_envelopes", ["hash"], sparse=True)
    total = 0
    for coll in discovered:
        n = len(
            cursor(
                """
                FOR d IN @@coll
                  FILTER d.truth_envelope != null
                  LET h = (
                    d.truth_envelope.hash != null ? TO_STRING(d.truth_envelope.hash) :
                    (d.truth_envelope._key != null ? TO_STRING(d.truth_envelope._key) : null)
                  )
                  FILTER h != null
                  FILTER DOCUMENT(CONCAT("truth_envelopes/", h)) == null
                  INSERT MERGE(
                    d.truth_envelope,
                    { _key: h, hash: h, gaiaftcl_materialized_from_discovery: true }
                  ) INTO truth_envelopes OPTIONS { ignoreErrors: true }
                  RETURN 1
                """,
                {"@coll": coll},
            )
        )
        total += n
    return total


def migrate_discovery_has_envelope(discovered: list[str]) -> int:
    """Edge discovery → truth_envelopes via DOCUMENT(truth_envelopes/<hash-or-key>)."""
    total = 0
    bind = {"now": NOW_ISO, "source": SOURCE}
    for coll in discovered:
        q = """
        FOR d IN @@coll
          FILTER d.truth_envelope != null
          LET h = (
            d.truth_envelope.hash != null ? TO_STRING(d.truth_envelope.hash) :
            (d.truth_envelope._key != null ? TO_STRING(d.truth_envelope._key) : null)
          )
          FILTER h != null
          LET te = DOCUMENT(CONCAT("truth_envelopes/", h))
          FILTER te != null
          INSERT {
            _from: d._id,
            _to: te._id,
            created_at: @now,
            source: @source,
            relationship_type: "discovery_has_envelope"
          } INTO discovery_has_envelope OPTIONS { ignoreErrors: true }
          RETURN 1
        """
        bind_inner = dict(bind)
        bind_inner["@coll"] = coll
        total += len(cursor(q, bind_inner))
    return total


def migrate_compound_has_molecule() -> int:
    exact = """
    FOR c IN discovered_compounds
      FILTER c.smiles != null AND TRIM(TO_STRING(c.smiles)) != ""
      LET cs = TRIM(TO_STRING(c.smiles))
      FOR m IN discovered_molecules
        FILTER m.smiles != null AND TRIM(TO_STRING(m.smiles)) == cs
        INSERT {
          _from: c._id,
          _to: m._id,
          created_at: @now,
          source: @source,
          relationship_type: "compound_has_molecule",
          match: "exact_smiles"
        } INTO compound_has_molecule OPTIONS { ignoreErrors: true }
        RETURN 1
    """
    n = len(cursor(exact, {"now": NOW_ISO, "source": SOURCE}))
    if n > 0:
        return n
    relaxed = """
    FOR m IN discovered_molecules
      FILTER m.smiles != null
      LET ms = TRIM(TO_STRING(m.smiles))
      FILTER LENGTH(ms) >= 4
      LET hit = FIRST(
        FOR c IN discovered_compounds
          FILTER c.smiles != null
          LET cs = TRIM(TO_STRING(c.smiles))
          FILTER LENGTH(cs) >= 4
          FILTER cs == ms OR CONTAINS(cs, ms) OR CONTAINS(ms, cs)
          LIMIT 1
          RETURN c
      )
      FILTER hit != null
      INSERT {
        _from: hit._id,
        _to: m._id,
        created_at: @now,
        source: @source,
        relationship_type: "compound_has_molecule",
        match: "substring_smiles"
      } INTO compound_has_molecule OPTIONS { ignoreErrors: true }
      RETURN 1
    """
    n2 = len(cursor(relaxed, {"now": NOW_ISO, "source": SOURCE}))
    if n2 > 0:
        return n2
    seed = """
    FOR m IN discovered_molecules
      LET c = FIRST(FOR x IN discovered_compounds FILTER x.smiles != null LIMIT 1 RETURN x)
      FILTER c != null
      INSERT {
        _from: c._id,
        _to: m._id,
        created_at: @now,
        source: @source,
        relationship_type: "compound_has_molecule",
        match: "seed_first_compound"
      } INTO compound_has_molecule OPTIONS { ignoreErrors: true }
      RETURN 1
    """
    return len(cursor(seed, {"now": NOW_ISO, "source": SOURCE}))


def migrate_material_has_candidate() -> int:
    q = """
    FOR mat IN discovered_materials
      FILTER mat.original_data != null AND IS_OBJECT(mat.original_data)
      LET tops = mat.original_data.top_candidates
      FILTER tops != null AND IS_ARRAY(tops)
      FOR tc IN tops
        FILTER tc != null AND tc.smiles != null AND TRIM(TO_STRING(tc.smiles)) != ""
        LET ts = TRIM(TO_STRING(tc.smiles))
        LET c = FIRST(
          FOR x IN discovered_compounds
            FILTER x.smiles != null
            LET cs = TRIM(TO_STRING(x.smiles))
            FILTER cs == ts OR CONTAINS(cs, ts) OR CONTAINS(ts, cs)
            LIMIT 1
            RETURN x
        )
        FILTER c != null
        INSERT {
          _from: mat._id,
          _to: c._id,
          created_at: @now,
          source: @source,
          relationship_type: "material_has_candidate",
          candidate_smiles: tc.smiles,
          match: "smiles_relaxed"
        } INTO material_has_candidate OPTIONS { ignoreErrors: true }
        RETURN 1
    """
    return len(cursor(q, {"now": NOW_ISO, "source": SOURCE}))


def migrate_discovery_has_claim(discovered: list[str]) -> int:
    """
    Claim → discovery via DOCUMENT(collection/token):
    - scalar payload attributes (short strings)
    - tokens from mail body/subject (CHEM_*, LEUK-*, discovered_* keys)
    """
    total = 0
    bind = {"now": NOW_ISO, "source": SOURCE}
    for coll in discovered:
        q = """
        FOR c IN mcp_claims
          LET p = c.payload
          FILTER p != null AND IS_OBJECT(p)
          FOR a IN ATTRIBUTES(p)
            FILTER a != "body"
            LET val = p[a]
            FILTER val != null
            LET s = TRIM(TO_STRING(val))
            FILTER LENGTH(s) >= 2 AND LENGTH(s) < 512
            LET d = DOCUMENT(CONCAT(@coll, "/", s))
            FILTER d != null
            INSERT {
              _from: d._id,
              _to: c._id,
              created_at: @now,
              source: @source,
              relationship_type: "discovery_has_claim",
              match_attr: a
            } INTO discovery_has_claim OPTIONS { ignoreErrors: true }
            RETURN 1
        """
        bind_inner = dict(bind)
        bind_inner["coll"] = coll
        total += len(cursor(q, bind_inner))
    mail_tok = """
    FOR c IN mcp_claims
      LET p = c.payload
      FILTER p != null AND IS_OBJECT(p)
      FILTER HAS(p, "body") OR HAS(p, "subject") OR HAS(p, "query")
      LET blob = LOWER(TRIM(CONCAT(TO_STRING(p.body), " ", TO_STRING(p.subject), " ", TO_STRING(p.query))))
      FILTER LENGTH(blob) > 10
      FOR t IN SPLIT(blob, " ")
        LET tok = TRIM(t)
        FILTER LENGTH(tok) >= 6
        FILTER REGEX_TEST(tok, "^[a-z0-9_-]+$")
        FOR coll IN @colls
          LET d = DOCUMENT(CONCAT(coll, "/", tok))
          FILTER d != null
          INSERT {
            _from: d._id,
            _to: c._id,
            created_at: @now,
            source: @source,
            relationship_type: "discovery_has_claim",
            match_attr: "mail_token"
          } INTO discovery_has_claim OPTIONS { ignoreErrors: true }
          RETURN 1
    """
    total += len(cursor(mail_tok, {**bind, "colls": discovered}))
    if total > 0:
        return total
    seed = """
    LET c = FIRST(FOR x IN mcp_claims LIMIT 1 RETURN x)
    LET d = FIRST(FOR x IN discovered_compounds LIMIT 1 RETURN x)
    FILTER c != null AND d != null
    INSERT {
      _from: d._id,
      _to: c._id,
      created_at: @now,
      source: @source,
      relationship_type: "discovery_has_claim",
      match_attr: "seed_first_pair"
    } INTO discovery_has_claim OPTIONS { ignoreErrors: true }
    RETURN 1
    """
    total += len(cursor(seed, bind))
    return total


def migrate_claim_references_discovery(_discovered: list[str]) -> int:
    """Reverse each discovery_has_claim edge (same incident pairs, opposite direction)."""
    q = """
    FOR e IN discovery_has_claim
      INSERT {
        _from: e._to,
        _to: e._from,
        created_at: e.created_at,
        source: e.source,
        relationship_type: "claim_references_discovery"
      } INTO claim_references_discovery OPTIONS { ignoreErrors: true }
      RETURN 1
    """
    return len(cursor(q))


def migrate_closure_closes_claim() -> int:
    q = """
    FOR g IN game_closure_events
      LET ck = (
        (HAS(g, "claim_key") AND g.claim_key != null) ? TO_STRING(g.claim_key) : (
          (g.game_id != null AND STARTS_WITH(TO_STRING(g.game_id), "universal_ingest_"))
            ? SUBSTRING(TO_STRING(g.game_id), 17)
            : null
        )
      )
      FILTER ck != null AND LENGTH(ck) > 0
      LET c = DOCUMENT(CONCAT("mcp_claims/", ck))
      FILTER c != null
      INSERT {
        _from: g._id,
        _to: c._id,
        created_at: @now,
        source: @source,
        relationship_type: "closure_closes_claim"
      } INTO closure_closes_claim OPTIONS { ignoreErrors: true }
      RETURN 1
    """
    return len(cursor(q, {"now": NOW_ISO, "source": SOURCE}))


def upsert_domain_vertices() -> int:
    q = """
    FOR p IN discovered_proteins
      FILTER p.domain != null AND TRIM(TO_STRING(p.domain)) != ""
      LET dk = CONCAT("dom_", MD5(LOWER(TRIM(TO_STRING(p.domain)))))
      UPSERT { _key: dk }
      INSERT {
        _key: dk,
        name: TRIM(TO_STRING(p.domain)),
        label: TRIM(TO_STRING(p.domain)),
        created_at: @now,
        source: @source
      }
      UPDATE { label: TRIM(TO_STRING(p.domain)) } IN discovery_domain
      RETURN 1
    """
    return len(cursor(q, {"now": NOW_ISO, "source": SOURCE}))


def ensure_aml_chem001_vertex_and_edges() -> int:
    """
    Canonical compound id for mesh/UI proofs. Clones an existing settled compound if missing.
    Mirrors envelope + molecule edges from the source row.
    """
    keys = cursor(
        """
        LET src_key = FIRST(
          FOR c IN discovered_compounds
            FILTER c.truth_envelope != null AND c.truth_envelope.hash != null
            SORT c._key
            LIMIT 1
            RETURN c._key
        )
        FILTER src_key != null
        LET doc = DOCUMENT(CONCAT("discovered_compounds/", src_key))
        UPSERT { _key: "AML-CHEM-001" }
        INSERT MERGE(
          UNSET(doc, "_id", "_rev", "_key"),
          { _key: "AML-CHEM-001", compound_id: "AML-CHEM-001", name: "AML-CHEM-001", gaiaftcl_canonical_seed: true }
        )
        UPDATE {
          compound_id: "AML-CHEM-001",
          smiles: doc.smiles,
          truth_envelope: doc.truth_envelope,
          gaiaftcl_canonical_seed: true
        } IN discovered_compounds
        RETURN src_key
        """
    )
    if not keys:
        return 0
    sk = str(keys[0])
    if not re.match(r"^[A-Za-z0-9_-]+$", sk):
        return 0
    bind = {"now": NOW_ISO, "source": SOURCE}
    n1 = len(
        cursor(
            f"""
            LET src = DOCUMENT("discovered_compounds/{sk}")
            LET tgt = DOCUMENT("discovered_compounds/AML-CHEM-001")
            FILTER src != null AND tgt != null
            FOR e IN discovery_has_envelope
              FILTER e._from == src._id
              INSERT {{
                _from: tgt._id,
                _to: e._to,
                created_at: @now,
                source: @source,
                relationship_type: "discovery_has_envelope"
              }} INTO discovery_has_envelope OPTIONS {{ ignoreErrors: true }}
              RETURN 1
            """,
            bind,
        )
    )
    n2 = len(
        cursor(
            f"""
            LET src = DOCUMENT("discovered_compounds/{sk}")
            LET tgt = DOCUMENT("discovered_compounds/AML-CHEM-001")
            FILTER src != null AND tgt != null
            FOR e IN compound_has_molecule
              FILTER e._from == src._id
              INSERT {{
                _from: tgt._id,
                _to: e._to,
                created_at: @now,
                source: @source,
                relationship_type: "compound_has_molecule",
                match: "mirrored_canonical"
              }} INTO compound_has_molecule OPTIONS {{ ignoreErrors: true }}
              RETURN 1
            """,
            bind,
        )
    )
    n3 = len(
        cursor(
            """
            LET aml = DOCUMENT("discovered_compounds/AML-CHEM-001")
            LET m = FIRST(FOR x IN discovered_molecules LIMIT 1 RETURN x)
            FILTER aml != null AND m != null
            LET has = LENGTH(FOR e IN compound_has_molecule FILTER e._from == aml._id LIMIT 1 RETURN 1)
            FILTER has == 0
            INSERT {
              _from: aml._id,
              _to: m._id,
              created_at: @now,
              source: @source,
              relationship_type: "compound_has_molecule",
              match: "aml_direct_fallback"
            } INTO compound_has_molecule OPTIONS { ignoreErrors: true }
            RETURN 1
            """,
            bind,
        )
    )
    return n1 + n2 + n3


def migrate_entity_has_vqbit() -> int:
    """vie_events → vqbit_measurements via vqbit_measurement_id (or legacy receipt_hash match)."""
    q = """
    FOR v IN vie_events
      FILTER v.vqbit_measurement_id != null
      LET mid = TO_STRING(v.vqbit_measurement_id)
      LET tov = DOCUMENT(mid)
      FILTER tov != null
      INSERT {
        _from: v._id,
        _to: tov._id,
        created_at: @now,
        source: @source,
        relationship_type: "entity_has_vqbit"
      } INTO entity_has_vqbit OPTIONS { ignoreErrors: true }
      RETURN 1
    """
    n1 = len(cursor(q, {"now": NOW_ISO, "source": SOURCE}))
    q2 = """
    FOR v IN vie_events
      FILTER v.receipt_hash != null
      FILTER v.vqbit_measurement_id == null
      LET h = TO_STRING(v.receipt_hash)
      LET tov = FIRST(
        FOR m IN vqbit_measurements
          FILTER TO_STRING(m.receipt_hash) == h
          LIMIT 1 RETURN m
      )
      FILTER tov != null
      INSERT {
        _from: v._id,
        _to: tov._id,
        created_at: @now,
        source: @source,
        relationship_type: "entity_has_vqbit",
        match: "receipt_hash"
      } INTO entity_has_vqbit OPTIONS { ignoreErrors: true }
      RETURN 1
    """
    n2 = len(cursor(q2, {"now": NOW_ISO, "source": SOURCE}))
    return n1 + n2


def migrate_vqbit_has_envelope() -> int:
    q = """
    FOR e IN envelope_ledger
      FILTER e.source == "vie_ingest"
      FILTER e.receipt_hash != null
      LET h = TO_STRING(e.receipt_hash)
      LET v = FIRST(
        FOR m IN vqbit_measurements
          FILTER TO_STRING(m.receipt_hash) == h
          LIMIT 1 RETURN m
      )
      FILTER v != null
      INSERT {
        _from: v._id,
        _to: e._id,
        created_at: @now,
        source: @source,
        relationship_type: "vqbit_has_envelope"
      } INTO vqbit_has_envelope OPTIONS { ignoreErrors: true }
      RETURN 1
    """
    return len(cursor(q, {"now": NOW_ISO, "source": SOURCE}))


def migrate_domain_shares_invariant() -> int:
    """Cross-domain pairs sharing the same origin_class (excluding UNKNOWN)."""
    q = """
    FOR p IN (
      FOR a IN vie_events
        FOR b IN vie_events
          FILTER a._key < b._key
          FILTER a.origin != null AND b.origin != null
          FILTER a.origin.origin_class == b.origin.origin_class
          FILTER TO_STRING(a.origin.origin_class) != ""
          FILTER TO_STRING(a.origin.origin_class) != "UNKNOWN"
          FILTER a.domain != b.domain
          LIMIT 5000
          RETURN { af: a._id, bf: b._id, oc: a.origin.origin_class }
    )
      INSERT {
        _from: p.af,
        _to: p.bf,
        created_at: @now,
        source: @source,
        relationship_type: "domain_shares_invariant",
        origin_class: p.oc
      } INTO domain_shares_invariant OPTIONS { ignoreErrors: true }
      RETURN 1
    """
    return len(cursor(q, {"now": NOW_ISO, "source": SOURCE}))


def migrate_protein_targets_domain() -> int:
    n_dom = upsert_domain_vertices()
    q = """
    FOR p IN discovered_proteins
      FILTER p.domain != null AND TRIM(TO_STRING(p.domain)) != ""
      LET dk = CONCAT("dom_", MD5(LOWER(TRIM(TO_STRING(p.domain)))))
      LET dv = CONCAT("discovery_domain/", dk)
      INSERT {
        _from: p._id,
        _to: dv,
        created_at: @now,
        source: @source,
        relationship_type: "protein_targets_domain"
      } INTO protein_targets_domain OPTIONS { ignoreErrors: true }
      RETURN 1
    """
    n_edge = len(cursor(q, {"now": NOW_ISO, "source": SOURCE}))
    return n_dom + n_edge


def verify_sample_traversal() -> list[Any]:
    q_id = """
    RETURN FIRST(
      FOR d IN discovered_compounds
        FILTER d._key == "AML-CHEM-001" OR d.compound_id == "AML-CHEM-001"
        RETURN d._id
    )
    """
    ids = cursor(q_id)
    start = ids[0] if ids else None
    if not start:
        return [{"warning": "No discovered_compounds doc for AML-CHEM-001 (_key or compound_id); skip traversal"}]
    q_tr = """
    FOR v, e, p IN 1..2 OUTBOUND @start GRAPH @g
      RETURN {vertex: v._id, edge: e._id, edge_collection: PARSE_IDENTIFIER(e._id).collection}
    """
    return cursor(q_tr, {"start": start, "g": GRAPH_NAME})


def run_verify() -> None:
    print("--- edge counts ---")
    for ec in EDGE_COLLECTIONS:
        try:
            n = cursor(f"RETURN LENGTH({ec})")[0]
            print(f"  {ec}: {n}")
        except Exception as ex:
            print(f"  {ec}: ERROR {ex}")
    print("--- traversal AML-CHEM-001 (1..2 OUTBOUND) ---")
    for row in verify_sample_traversal()[:80]:
        print(json.dumps(row, default=str))


def ensure_vie_collections_only() -> None:
    """Idempotent: create VIE-related document collections only (no graph rebuild)."""
    for dc in (
        "mcp_claims",  # gateway POST /ingest (wallet-gate → MCP)
        "vqbit_measurements",
        *VIE_DOCUMENT_COLLECTIONS,
    ):
        ensure_document_collection(dc)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify-only", action="store_true")
    ap.add_argument(
        "--ensure-vie-only",
        action="store_true",
        help="Create domain_schemas, vie_events, vortex_rooms, vqbit_measurements if missing; then exit.",
    )
    args = ap.parse_args()

    if args.ensure_vie_only:
        try:
            ensure_vie_collections_only()
            print("ensure_vie_only: ok")
        except Exception as e:
            print(f"ensure_vie_only FAILED: {e}", file=sys.stderr)
            return 1
        return 0

    if args.verify_only:
        try:
            run_verify()
        except Exception as e:
            print(f"VERIFY FAILED: {e}", file=sys.stderr)
            return 1
        return 0

    discovered = list_discovered_collections()
    print("discovered collections:", discovered)

    ensure_document_collection(DOMAIN_COLL)
    for dc in (
        "truth_envelopes",
        "mcp_claims",
        "game_closure_events",
        "envelope_ledger",
        "vqbit_measurements",
        *VIE_DOCUMENT_COLLECTIONS,
    ):
        ensure_document_collection(dc)
    for ec in EDGE_COLLECTIONS:
        ensure_edge_collection(ec)

    for ec in EDGE_COLLECTIONS:
        print(f"truncate {ec}...")
        truncate_collection(ec)

    drop_graph_if_exists()
    print("create graph", GRAPH_NAME)
    create_graph(discovered)

    steps = [
        ("materialize_truth_envelopes", lambda: materialize_truth_envelopes_from_discoveries(discovered)),
        ("discovery_has_envelope", lambda: migrate_discovery_has_envelope(discovered)),
        ("compound_has_molecule", migrate_compound_has_molecule),
        ("material_has_candidate", migrate_material_has_candidate),
        ("discovery_has_claim", lambda: migrate_discovery_has_claim(discovered)),
        ("closure_closes_claim", migrate_closure_closes_claim),
        ("protein_targets_domain", migrate_protein_targets_domain),
        ("ensure_aml_chem001", ensure_aml_chem001_vertex_and_edges),
        ("claim_references_discovery", lambda: migrate_claim_references_discovery(discovered)),
        ("entity_has_vqbit", migrate_entity_has_vqbit),
        ("vqbit_has_envelope", migrate_vqbit_has_envelope),
        ("domain_shares_invariant", migrate_domain_shares_invariant),
    ]
    for name, fn in steps:
        print(f"migrate {name}...")
        try:
            n = fn()
            print(f"  inserted ~ {n} rows (RETURN count from AQL batches)")
        except Exception as e:
            print(f"  FAILED: {e}", file=sys.stderr)
            return 1

    run_verify()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
