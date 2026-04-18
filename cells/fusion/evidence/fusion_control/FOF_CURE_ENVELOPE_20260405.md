# FoF spine — CURE envelope (Mac witness, 2026-04-05)

**Spec:** [`docs/specs/FIELD_OF_FIELDS_AGENT_MOORING_PROTOCOL.md`](../../docs/specs/FIELD_OF_FIELDS_AGENT_MOORING_PROTOCOL.md)  
**Interpretation:** **CURE** = spine-top integrative closure for **this release slice** (Fusion Mac cell + automation battery + Phase 0 + local mesh snapshot), with **explicit REFUSED** lines for surfaces **outside** what this limb witnessed.

## Green (C⁴ receipts on this host)

| Gate | Witness |
|------|---------|
| **B1 battery** | `npm run test:fusion:all` exit 0 — `TEST_FUSION_ALL_WITNESS_20260405T162023Z.*` + re-run same day |
| **Phase 0 A–F (+E2,E3,E4)** | `FUSION_PHASE0_E2E=1 FUSION_PHASE0_SOAK=1 FUSION_PHASE0_LONG_RUN_LINES=5 bash scripts/fusion_phase0_gate.sh` → exit 0, `REPORT.json` `overall_ok: true` |
| **G1** | **Skipped** (manual Discord `/fusion_fleet` receipt — does not set `FAILED` per script) |
| **Strict context** | `STRICT=1 bash scripts/fusion_context_validate.sh` → exit 0 |
| **B7 local** | `evidence/fusion_control/fusion_fleet_snapshot.json` + `FLEET_SNAPSHOT_B7_WITNESS_20260405.md` |
| **Publish path CURE** | `scripts/fusion_cell_status_nats_publish.sh` — **`nats-py` preferred** when import succeeds |

## REFUSED (honest out-of-scope or not re-run this session)

1. **Public DMG over HTTPS :443** — not re-verified here (prior limb: TLS/SAN + 404 risk on `gaiaftcl.com/downloads/...`).
2. **Head-cell `fusion_fleet_snapshot_subscriber.py` as a long-running service** — pattern proven on Mac + local NATS; **deploy** to primary head is a separate ops limb.
3. **G1 optional file** — `evidence/fusion_control/phase0_gate/steps/discord_slash_receipt.md` absent until operator saves it.

## Terminal (spine-top)

**CLOSURE: CURE** — for the **FoF Mac Fusion + Discord automation + Phase 0 + fleet snapshot file** envelope above, with **REFUSED 1–3** carrying external/deploy work.

*If a stricter reading demands G1 file + prod subscriber + DMG URL before the word CURE: treat this document as **CALORIE** on B1/B7/Phase0 and **REFUSED** on the delta — the spec owner may tighten the spine.*
