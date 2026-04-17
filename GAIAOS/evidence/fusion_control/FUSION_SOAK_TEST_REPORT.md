# FUSION_SOAK_TEST_REPORT

Generated: 2026-04-05T16:30:48.066Z
Schema: gaiaftcl_fusion_soak_summary_ui_v1
GAIA_ROOT: `/Users/richardgillespie/Documents/FoT8D/GAIAOS`
git HEAD: `5729f829de92bf819c217d586e6601daec9c1631`

## NSTX-U / Metal (window tail)

| Field | Value |
| --- | --- |
| JSONL | `/Users/richardgillespie/Documents/FoT8D/GAIAOS/evidence/fusion_control/long_run_signals.jsonl` |
| batch rows (window) | 558 |
| total cycles (sum in window) | 279000 |
| wall_time_ms min / p50 / max | 5 / 6 / 35 |
| worst ε max in window | 9.536743e-7 |
| last signals tail τ_wall / τ_gpu_us / ε / cycles | 8 / 860 / 9.536743e-7 / 500 |
| first_ts / last_ts | 2026-04-05T09:34:06Z / 2026-04-05T09:35:10Z |
| last_control_matrix (sidecar, not table row) wall_ms / ε | 8 / 9.536743e-7 |

## Soak violations JSONL

| JSONL | `/Users/richardgillespie/Documents/FoT8D/GAIAOS/evidence/fusion_control/soak_violations.jsonl` |
| fusion_soak_violation_v1 lines (tail) | 0 |

## PCSSP fault receipts

| receipt_rows | 16 |
| refused_count | 16 |
| latency_ms min / max | 0 / 0 |

## TORAX episode metrics

| rows | 8000 |
| ΔH min / max / last | 9.536743e-7 / 9.536743e-7 / 9.536743e-7 |

## Cycle scaling

Inner batch size: `FUSION_VALIDATION_CYCLES`. Up to 100,000 per batch by default; set `FUSION_ALLOW_HIGH_CYCLES=1` for up to 1,000,000 per `fusion_control` invocation.
