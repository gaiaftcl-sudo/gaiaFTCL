# Phase 0 — Citation verification gate (OWL-P53 package)

**Status:** Filled before authoring dependent specs. **Do not** treat rows with **n** as authoritative until the Action is closed.

| Cited artifact | Path on `main` (or URL) | Exists (y/n) | Verified content matches plan claim (y/n) | Action if n |
|----------------|-------------------------|--------------|-------------------------------------------|-------------|
| `S4_C4_COMMUNION_UI_SPEC.md` §5.3 (C4 Registry / Confirm–Deny) | [`cells/health/docs/S4_C4_COMMUNION_UI_SPEC.md`](../../S4_C4_COMMUNION_UI_SPEC.md) | **n** | **n** | **Author** §5.3+ in Communion spec **or** cite [`GaiaHealth/docs/UI_SPEC_S4C4_COMMUNION_V1.md`](../../../../../GaiaHealth/docs/UI_SPEC_S4C4_COMMUNION_V1.md) for registry/workbench detail; OWL-P53 docs link to whichever is canonical after CCR. |
| §5.5 (brainwave) | same (`S4_C4_COMMUNION_UI_SPEC.md`) | **n** | **n** | **Author** or cross-link **UI_SPEC_S4C4_COMMUNION_V1.md** (contains brainwave / five-domain ring narrative). |
| §8 “plugin ABI” (as in plan) | same — note: current **§8** is **Document control**, not plugin ABI | **n** | **n** | Plugin architecture is **[§2]( ../../S4_C4_COMMUNION_UI_SPEC.md#2-the-global-shell-and-dynamic-plugin-extension-architecture)** in `S4_C4_COMMUNION_UI_SPEC.md`. **Do not** cite non-existent §8 plugin ABI without adding a section or fixing references. |
| `GH-OWL-UNIFIED-FREQ-001` | Standalone file | **n** | **n** | Document ID referenced from [`GAIAOS/docs/GAIAFTCL_CLI_ARCHITECTURE.md`](../../../../../GAIAOS/docs/GAIAFTCL_CLI_ARCHITECTURE.md) and [`GaiaHealth/docs/UI_SPEC_S4C4_COMMUNION_V1.md`](../../../../../GaiaHealth/docs/UI_SPEC_S4C4_COMMUNION_V1.md). **Action:** add `cells/health/docs/GH-OWL-UNIFIED-FREQ-001.md` when ready **or** keep **[I]** parent pointer to CLI arch only. |
| `GH-OWL-NEURO-001` | Standalone | **n** (see CLI / UI spec refs) | partial | Referenced in CLI arch + UI spec; **Action:** treat as doc ID until standalone file exists. |
| `GFTCL-OWL-INV-001` | Standalone | **n** | partial | Same. |
| `GFTCL-PINEAL-001` | Standalone | **n** | partial | Same. |
| `GAMP5_LIFECYCLE.md` §4.2 (architectural CCR) | [`cells/lithography/docs/GAMP5_LIFECYCLE.md`](../../../../lithography/docs/GAMP5_LIFECYCLE.md) §4.2 | **y** | **y** | Three cell-owner signatures for RTL/firmware/ABI/ISA-class changes — **Health registry “mother invariant” topology** mapped in [`MOTHER_INVARIANT_CCR_DECISION.md`](MOTHER_INVARIANT_CCR_DECISION.md). |
| `S4C4Hash.swift` | [`cells/fusion/Sources/GaiaFTCLCore/Hashing/S4C4Hash.swift`](../../../../fusion/Sources/GaiaFTCLCore/Hashing/S4C4Hash.swift) | **y** | partial | Verify round-trip test payload in IQ when wiring OQ. |
| `projection_engine.swift` | (none under that name) | **n** | **n** | **[I]** — use actual mesh client / projection module name after grep in Mac Health cell. |
| `s4_ingestor.swift` | (none under that name) | **n** | **n** | **[I]** — ingestor naming TBD. |
| vQbit kinds `genetic`, `proteomic`, `cellular_stress`, `frequency`, `imaging` | Code search Health | **n** | **n** | **[I]** — kinds are **target schema** for OWL-P53; implement or map to existing `BioligitPrimitive` / envelope fields in Phase 2+ code. |
| PharmaVoice — Bennett quote | Paraphrase path (see [`SMALL_MOLECULE_INTEGRATION.md`](SMALL_MOLECULE_INTEGRATION.md) §3) | **y** (policy) | **y** | **Closed for v1:** no direct quote in normative bodies; primary URL not required when paraphrase path is used per plan. |
| Abegglen 2015 JAMA elephant TP53 | <https://doi.org/10.1001/jama.2015.13134> | **y** (external) | **y** | Use as **related biology** in `evidence/references/` — **not** human PQ cohort. |
| Cardilini et al. 2026 *Biol. Conserv.* | <https://doi.org/10.1016/j.biocon.2025.111593> | **y** (external) | **y** | Catalog methodology cross-reference only. |

**UI-spec note:** [`S4_C4_COMMUNION_UI_SPEC.md`](../../S4_C4_COMMUNION_UI_SPEC.md) contains **§4** “C4 invariant registry” themes and **§5.1–5.2** projection workbench; it does **not** currently contain numbered §5.3 / §5.5 as separate headings. Extended UI narrative exists under **`GaiaHealth/docs/UI_SPEC_S4C4_COMMUNION_V1.md`**.
