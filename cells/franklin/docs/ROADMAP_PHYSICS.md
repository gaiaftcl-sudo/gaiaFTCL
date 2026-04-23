# Roadmap — deferred / draft (measurement first)

**Rule:** do not claim as **normative** until each item has: **(a)** a measured baseline, **(b)** an acceptance test, **(c)** a committed path in the Qualification-Catalog or GAMP5 receipt class.

| Item | Target / draft | Milestone to promote |
|------|----------------|----------------------|
| **15s “full” hash** | Cold-start hash ≤ 15s on a named Mac profile | p95 in CI or labeled bench + receipt field |
| **1 ms torsion** | torsion in PoL or envelope (draft) | hardware trace + `pol_receipt` schema |
| **SSD auto-migration** | MANDATORY storage rules | `diskutil` or APFS health gate + GAMP5 step |
| **300s mesh heal (NATS FSM)** | 5 min heal; non-interactive | FSM in ring + evidence JSON |
| **Full PoL / Fusion envelope SETTLED** | Appendix A plan | [INV_LIFE.md](INV_LIFE.md) + two witnesses + green `pol_round_trip` |

**Until then:** [PATH_TABLE_S3.md](PATH_TABLE_S3.md) **SETTLED** row is **not** a merge gate; **OQ** and GAMP5 evidence remain the gates.
