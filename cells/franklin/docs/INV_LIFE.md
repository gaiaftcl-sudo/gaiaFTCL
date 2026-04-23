# INV_LIFE and PoL (reference — not fully shipped on all lanes)

**vQbit substrate:** A cell that processes **vQbit**-tagged work must preserve **vQbit/CALORIE** semantics. **No silent discard**; **REFUSED** and **FATAL** for illegal transitions (see plan INV_LIFE §2.1–2.3, §2.4 **proof gate**).

**PoL (Proof of Liveness) — when shipped:** Target evidence layout: `evidence/pol/<cell_id>/<τ>/` with `pol_receipt.json` and optional `pol_receipt.bin` (torsion, round-trip, peer). **SETTLED** in the Fusion **envelope** is **gated** on valid **PoL** + GAMP5 (not “SETTLED” on intent alone) — [PATH_TABLE_S3.md](PATH_TABLE_S3.md) §3, plan Appendix A.

**Until PoL is operational:** Rely on **GAMP5 + OQ** and existing receipts; do not label hardware **SETTLED** as PoL-complete without the proof artifacts.

**No duplicate receipt types:** Use **append-only** `fo_cell_substrate` and extend only via **vQbit_Expert_ABI** (see [VQBIT_EXPERT_ABI.md](VQBIT_EXPERT_ABI.md)); avoid parallel “shadow” receipt families for the same fact.

**Cross-refs:** `docs/concepts/mesh-topology.md` (Klein), `IMPLEMENTATION_PLAN.md` (Father / torsion as roadmap), [ROADMAP_PHYSICS.md](ROADMAP_PHYSICS.md). Mesh terminal-state vocabulary remains governed by the repo [`.cursorrules`](../../../.cursorrules) in concert with this doc (substrate, not a parallel story).
