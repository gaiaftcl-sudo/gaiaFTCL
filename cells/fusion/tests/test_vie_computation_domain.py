"""
Computation VIE domain: schema mapping, ingest provenance, receipt stability.
"""
import hashlib
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "services"))

from vie_v2.transformer import InvariantTransformer


def _load_computation_schema():
    schema_path = os.path.join(
        ROOT, "services", "vie_v2", "domain_schemas", "computation_workload.json"
    )
    with open(schema_path, encoding="utf-8") as f:
        return json.load(f)


def test_computation_schema_maps_domain_and_entity():
    schema = _load_computation_schema()
    tr = InvariantTransformer()
    raw = {
        "job_id": "bench-001",
        "workload_class": "gpu_kernel",
        "resource_pressure": 0.4,
        "queue_depth": 2,
        "success_metric": 0.95,
        "runtime_seconds": 12.5,
        "cpu_utilization": 0.3,
        "wall_clock_skew": 0.01,
        "sla_headroom": 0.8,
        "host_id": "cell-gpu-01",
    }
    v = tr.map_to_vqbit(raw, schema)
    assert v.get("domain") == "computation"
    assert v.get("entity_id") == "bench-001"
    assert v.get("domain_instance") == "workload_receipt"


def test_attach_ingest_provenance_sha256_and_receipt_refresh():
    schema = _load_computation_schema()
    tr = InvariantTransformer()
    raw = {"job_id": "j1", "workload_class": "test", "runtime_seconds": 1.0}
    v = tr.map_to_vqbit(raw, schema)
    h_before = v["receipt_hash"]
    tr.attach_ingest_provenance(v, raw, "computation_workload", schema)
    assert v["provenance"]["domain_schema_name"] == "computation_workload"
    assert len(v["provenance"]["source_payload_sha256"]) == 64
    expect = hashlib.sha256(
        json.dumps(raw, sort_keys=True, default=str).encode("utf-8")
    ).hexdigest()
    assert v["provenance"]["source_payload_sha256"] == expect
    assert v["receipt_hash"] != h_before


def test_payload_change_changes_source_digest():
    schema = _load_computation_schema()
    tr = InvariantTransformer()
    r1 = {"job_id": "x", "workload_class": "a", "runtime_seconds": 1.0}
    r2 = {**r1, "runtime_seconds": 2.0}
    v1 = tr.map_to_vqbit(r1, schema)
    v2 = tr.map_to_vqbit(r2, schema)
    tr.attach_ingest_provenance(v1, r1, "computation_workload", schema)
    tr.attach_ingest_provenance(v2, r2, "computation_workload", schema)
    assert v1["provenance"]["source_payload_sha256"] != v2["provenance"]["source_payload_sha256"]
