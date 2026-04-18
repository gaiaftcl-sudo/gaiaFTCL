# GaiaFTCL substrate context — M8 = S4 × C4

**Audience:** Integrators, substrate engineers, and reviewers working on S4↔C4 projection, INV3 tooling, and GaiaHealth cross-links.

**This document is constitutional ontology and runnable pointers for the repository. It is not an LLM system prompt; M8 does not depend on anything under `docs/prompts/`.**

**Location:** Canonical copy: **`docs/M8_S4_C4_SUBSTRATE_CONTEXT.md`** (trackable name; avoids legacy sandbox paths and `GAIA*.md` local exclude patterns).

**Ontology**

- **M8** = **S4 × C4**.
- **S4 (manifest domain):** documents, SMILES strings in markdown, lab protocols, exported text, UI copy.
- **C4 (constraint domain):** ArangoDB substrate records (`discovered_molecules`, `discovered_proteins`, `mcp_claims`, …), MCP claims, Franklin-witnessed discovery rows, entropy-delta / envelope lifecycle where applicable.
- **Projection rule:** **S4 is always a projection of C4.** If S4 and C4 disagree, **the substrate (C4) wins.** Correct the **map** (S4), not the asserted discovery truth in C4, unless C4 itself is shown wrong by **new witnessed evidence** (then update C4 first, then re-project S4).

**vQbit (program language)**  
Operational meaning in-repo: the **entropy / constraint delta** across M8 — **not** a hardware qubit. It names **full constraint geometry** before a **premature classical projection** (e.g. sloppy SMILES export). **AML-CHEM-001** and **LEUK-005** are **INV3** program IDs; canonical structure for comparison lives in **C4** collections when ingested.

**INV3 verification**  
Tooling: [`cells/fusion/scripts/inv3_s4_projection_verify.py`](../cells/fusion/scripts/inv3_s4_projection_verify.py); witness output under [`cells/fusion/evidence/inv3_s4_projection/`](../cells/fusion/evidence/inv3_s4_projection/).

**Apply gate**  
No edits to lab markdown without **`INV3_VERIFY_APPLY=I_UNDERSTAND`** (human receipt).

**Blocked**  
Gateway unreachable → **BLOCKED**. No invented structures. No assuming the lab file is authoritative over C4.

**Floor**  
S4 serves C4. The lab protocol is the **map**; witnessed substrate is the **contract**. Clean the map to match the contract before wet lab.

**GaiaHealth (Biologit cell):** Extended S4↔C4 communion UI, invariant-baseline registry design, and **vQbit** settlement framing — **[GH-S4C4-COMM-001](../cells/health/docs/S4_C4_COMMUNION_UI_SPEC.md)** (*design target;* `BioligitPrimitive` remains the MD vertex ABI in §0).

---

### Constitutional anchor (repository rules)

Self-heal on C4≠S4 projection, fail-closed, MCP-only writes, receipts to human — stated in root **`.cursorrules`** under **“C4 SUBSTRATE VS S4 CLIENT — CONSTITUTIONAL ARCHITECTURE (M8)”**. That section is **normative policy text** embedded in the repo; this M8 file states the **ontology** above.

---

## See also (analogy only)

**Evolutionary / microbiology metaphor** for transport, obligate coupling, and pre-encapsulation routing — **[`docs/OBLIGATE_COUPLING_BIOPHYSICS_ANALOGY.md`](OBLIGATE_COUPLING_BIOPHYSICS_ANALOGY.md)** (*non-normative* **[I]**; no WASM export; does not change M8 projection rules above).
