# GaiaFTCL DNS — crystal / mycelium (canonical tracked copy)

> **Trackable path:** `docs/DNS_CRYSTAL_MYCELIUM.md` (avoids `GAIA*.md` local git exclude). Content aligned with legacy `GAIAOS/docs/GAIAFTCL_DNS_CRYSTAL_MYCELIUM.md` when present.

## Intent

**gaiaftcl.com** (or `DNS_DOMAIN`) is not owned by one “head” VM in the architecture sense. Every **wild cell with a static public IP** may run **`gaiaftcl-dns-authority`** and participate in reconciling the public zone (e.g. GoDaddy) toward **that cell’s** declared address (`CELL_IP` → `HEAD_PUBLIC_IP` in compose).

- **Cattle:** Cells are interchangeable; DNS authority is a **service of the cell**, not a singleton role.
- **Change control:** Any eligible cell may drive record updates when policy and credentials allow; coordination (who wins concurrent writes, TTL, apex vs subdomains) is an **operational closure** problem in **C4** (claims, receipts, mesh agreement), not something the repo hard-codes here.
- **S4 vs C4:** Registrar UI and public resolver answers are **S4** (what humans and the Internet see). **Who may write**, **drift**, **compromise**, and **failover** are **C4** (substrate truth).

## Surface health (healthy / sick / dying / captured)

The **mesh** should treat the DNS layer as part of the living surface:

| Signal (concept) | Meaning |
|------------------|--------|
| **Healthy** | Desired records match observed resolution; reconcile cycles succeed; no sustained drift. |
| **Sick** | Intermittent provider/API errors, elevated `consecutive_failures`, or partial drift. |
| **Dying** | Sustained reconcile failure, TTL expiring without successful publish, or loss of credential validity. |
| **Captured** | Observed DNS diverges from mesh-agreed desired state in a way that implies hijack, stale delegation, or hostile control — **fail-closed**; ingest as security/clamp claim, not “fix in UI only.” |

Concrete telemetry: **`gaiaftcl-dns-authority`** publishes after **every** reconcile cycle to **`gaiaftcl.dns.surface.{cell_id}`** (JSON: `status`, `resolved_ip`, `expected_ip`, `drift_detected`, `hostile_divergence`, `godaddy_response`, …). The Earth ingestor subscribes to **`gaiaftcl.dns.surface.>`**; **`hostile_divergence: true`** maps to **`terminal_signal: COLLAPSED`** in **`InvariantTransformer`**. Mesh snapshots also flow on subjects such as **`gaiaftcl.mesh.health.snapshot`**.

## Implementation pointers

- Compose: **`docker-compose.cell.yml`** → **`gaiaftcl-dns-authority`** (`DNS_DOMAIN`, `DNS_TTL`, `HEAD_PUBLIC_IP` / `CELL_IP`, GoDaddy secrets).
- Code: **`services/dns_authority`** (`reconcile.rs`, `CycleEvidence`, `ReconcileStatus`).
- Internal mesh resolution remains **Docker / NATS**-first; see **`mesh-config/NATS_DISCOVERY_PROTOCOL.md`** — public DNS is the **edge**, not the mycelium’s nervous system.

This document corrects any older wording that implied “only the head cell may run DNS.” In the crystal model, **each static-IP cell can be the DNS service**; **entanglement** and **health** are how the forest knows if the edge is trustworthy.

---

## See also

- **Living-network / transport metaphor (biology analogy, non-normative):** [`OBLIGATE_COUPLING_BIOPHYSICS_ANALOGY.md`](OBLIGATE_COUPLING_BIOPHYSICS_ANALOGY.md) — nanotube transport and obligate coupling in published symbiosis literature, mapped to mesh narrative.
