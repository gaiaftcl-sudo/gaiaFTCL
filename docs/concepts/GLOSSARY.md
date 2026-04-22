---
title: Glossary — Franklin wiki refresh
status: concept-spine
franklin_refresh: v2
---

# Glossary (non-exhaustive)

| Term | Short definition |
|------|-------------------|
| **Klein bottle** | Mesh topology metaphor: **no boundary** on the cell-to-cell graph; see [mesh-topology.md](./mesh-topology.md). |
| **No boundary** | No “outside” to break out to: loss of quorum → **REFUSED**, stay in-manifold; operational expression of Klein-bottle closure (see program `README` + [mesh-topology.md](./mesh-topology.md)). |
| **Helsinki / Nuremberg split** | **5** mesh cells (Hetzner) + **4** (Netcup) in program ASCII; geographic quorum zones. |
| **CALORIE / CURE / REFUSED** | Mesh terminal states; **CALORIE/CURE** need ≥5 cells, **REFUSED** from any one cell; [mesh-topology.md](./mesh-topology.md). |
| **Quorum (5-of-9)** | ≥5 cells required for **CALORIE** / **CURE**; **REFUSED** does not need 5. |
| **τ** | **Sovereign time:** **Bitcoin block height** — **authoritative** in receipt policy when required; **wall clock supplementary** ([receipt-lifecycle.md](./receipt-lifecycle.md)). |
| **Wall clock** | UTC / `ts_utc` — **supplementary** to τ. |
| **9.54 × 10⁻⁷** | Numerical **closure** threshold (substrate–formal-proof gap) — do not drop on relevant pages; see [receipt-lifecycle.md](./receipt-lifecycle.md). |
| **Mycelia** | C-004: **P2P** mesh communication; **Mother** must not become a central **constitutional** server. |
| **Substrate mandate** | C-003: substrate wins over S⁴ projection; “When S⁴ and C⁴ disagree, the substrate wins. Always.” (program `README`). |
| **Covenantal authority** | Regulatory/operator framing: obligation bound to signed receipts, roles, and **C-001** culture. |
| **witnessed_local / countersigned / disputed** | Health chain terms — map to mesh terminals; see [receipt-lifecycle.md](./receipt-lifecycle.md). |
| **quarantined** | **Operational** state — map to **REFUSED-class** for mesh read when progress on the protected path is blocked ([receipt-lifecycle.md](./receipt-lifecycle.md)). |
| **Orphan mode / fostering** | Health operator patterns (invariants) — still **C-001** receipt-bound. |
| **\[I\]** (epistemic) | **Inferred** — use on **first** use of **analogical** Father/Mother (and similar) per page where the wiki **house voice** applies. |
| **Father** | **[I]** analogy: **Franklin** — **Mac admin mesh cell** on the shared **vQbit** plane with domain cells on the host; **sovereign network** cell IDs stay the nine ([franklin-role.md](./franklin-role.md)). |
| **Mother** | **[I]** analogy: distributed coordination — **draft** until owner; **C-004** P2P-only ([`../../cells/franklin/MOTHER_DRAFT.md`](../../cells/franklin/MOTHER_DRAFT.md)). |
| **Domain** | Cross-domain programs (FSD, swarm, ATC, …) sharing gates; not an extra cell count. |
| **Franklin** | Mac admin cell: GAMP automation, `admin-cell`, `franklin_mac_admin_gamp5_receipt_v1`; shares vQbit substrate with other cells on the Mac. |
| **TestRobot** | **Ambiguous** — use [three-way table](../../cells/franklin/MIGRATION_FROM_TESTROBOT.md). |
| **C-001…C-010** | Constitutional invariants ([constitutional-invariants.md](./constitutional-invariants.md)). |
| **vQbit** | Entropy-delta measurement / 76-byte ABI surface — IP-sensitive ([vqbit-surface.md](./vqbit-surface.md)). |
| **UUM-8D** | M⁸ = S⁴ × C⁴ ([uum-8d.md](./uum-8d.md)). |
| **Two nines** | **Nine mesh cells** vs **nine fusion plant kinds** — different ([cell-taxonomy.md](./cell-taxonomy.md)). |

**What changed:** [`../franklin-wiki-refresh/WHAT_CHANGED_FRANKLIN_WIKI_V2.md`](../franklin-wiki-refresh/WHAT_CHANGED_FRANKLIN_WIKI_V2.md)
