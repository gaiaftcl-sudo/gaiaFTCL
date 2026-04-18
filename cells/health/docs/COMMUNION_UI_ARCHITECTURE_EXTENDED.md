# GaiaHealth S4↔C4 Communion UI — Extended architecture narrative

| Field | Value |
|-------|--------|
| **Document ID** | **GH-S4C4-COMM-EXT-001** |
| **Companion** | **GH-S4C4-COMM-001** — [`S4_C4_COMMUNION_UI_SPEC.md`](S4_C4_COMMUNION_UI_SPEC.md) |
| **Status** | **Design target & roadmap** — not a shipped binary manifest; individual claims require benchmarks, IRB, and calibration before operational use. |
| **Patents** | USPTO 19/460,960 · USPTO 19/096,071 |

---

## 1. Architectural philosophy and executive overview

**Substrate fidelity:** digital representations must track biophysical phenomena without undocumented distortion. **Epistemic honesty:** provenance is cryptographically and categorically explicit (**M/T/I/A**).

**Five pillars:** (1) global **WASM** orchestration shell, (2) **multi-modal S4** ingest, (3) **C4 invariant registry**, (4) **projection workbench**, (5) **epistemic ledger**. Together they support bioenergetic modeling, THz-scale proteostasis probes (where instrumented), breathomics, epigenetic age models, and metabolic stoichiometry in a **plugin-extensible** architecture.

---

## 2. Global shell and plugin architecture

### 2.1 WASM and out-of-browser hosting

Target: **sandboxed WASM** with **WASI-class** capabilities for filesystem, clocks, and controlled I/O to instruments. Refer to the **pinned** toolchain in `cells/health`; “WASM 3.0” labels in prose denote **forward alignment** with the spec, not an unchecked marketing claim.

### 2.2 Biological ABI

Isolate **hot-path** exchange of typed structs (Karmem-like IDL discipline): Rust/C++/Python plugins must agree on **layout-stable** envelopes to avoid share-nothing bottleneck on large tensors (OCR/ECAR traces, THz arrays).

### 2.3 BON / CF / BioModTool

**BON** — JSON-profiled biological payloads with payload/metadata separation. Compression figures (e.g. “~87%”) are **design targets** until measured on representative cohorts. **Construction File** + **BioModTool** biomass objectives use mmol·gDW⁻¹·h⁻¹ toward BOF rows where metabolic plugins are enabled.

---

## 3. Multi-modal S4 ingest

### 3.1 Bioenergetics (OCR / ECAR)

Ingest Seahorse-class **OCR** and **ECAR**; build **OCR vs ECAR** workbench maps; optional scripted sequences (oligomycin → FCCP → rotenone/antimycin) for segment extraction — all **[M]** on raw channels, **[T]** on derived stoichiometries.

### 3.2 THz / vibrational proteostasis

Sub-300 GHz and sub-45 GHz band goals for **hHsp70** conformation discrimination — **[I]** until calibrated vs gold biophysics.

### 3.3 Breathomics and RQ

VOC / SCFA proxies + **RQ = VCO₂/VO₂** — substrate oxidation interpretation bands (~1.0 carb, ~0.7 lipid, ~0.8–0.85 protein/mixed).

### 3.4 Neural metabolic imaging

FRET lactate sensors, tractography overlays — deep models are **[I]** with confidence bands.

### 3.5 Epigenetic clocks & narratives

DNAm clocks (**[I]**); NLP on narratives (**[A]/[I]**) — **firewalled** from **[M]** thermodynamic channels.

---

## 4. C4 invariant registry (baselines, not diagnoses)

Registry rows: **ID, value/range, default tag, DOI set, review status.**

### 4.1 NESS / entropy

Discrete entropy \(H_\tau = -\sum_S P(s)\log_2 P(s)\). **NESS** framing — not literal “zero entropy biology.”

### 4.2 P/O ratios

Mechanistic baselines **2.5** (NADH-linked) and **1.5** (succinate-class) — **literature bands**; recalibrate per cohort.

### 4.3 SCFA molar baseline

**60 : 20 : 20** (acetate : propionate : butyrate) as **population prior** — swap for cohort DOIs when locking.

### 4.4 Essential amino acids (IAAO)

Use published IAAO requirement tables with **citation+stratum**; no autonomous amyloid claims without **[M]** tissue context.

### 4.5 Zinc ionophore hypotheses

**Zn²⁺ + polyphenol** stoichiometry as **experimental therapeutics** — mark **[I]**; falsify with **[M]** OCR/VOC predictions per intervention envelopes.

---

## 5. Projection workbench

**Fractal UX** and **multi-target oncology overlays** (Warburg / NaWa-class metrics) are **[I]**-heavy unless fit to **[M]** flux data. Natural compounds (berberine, curcumin, EGCG, D₃) appear as **mechanism-tagged** pathways, not guaranteed outcomes.

---

## 6. Epistemic ledger and vQbit collapse

### 6.1 M/T/I/A

| Tag | Name | Examples |
|-----|------|----------|
| **M** | Machine | Raw instruments |
| **T** | Tool | Deterministic transforms (P/O from OCR, unit fixes) |
| **I** | Intelligence | ML / clocks / classifiers |
| **A** | Agent | Human narrative, clinical judgment |

Filters must never show **[I]** as **[M]**.

### 6.2 vQbit collapse

Measurements exist in superposition until **witnessed collapse** into the ledger — **falsifiable** predictions per intervention; failed predictions adjust trust and may yield **REFUSED** / **BLOCKED** per constitutional rules.

---

## 7. Implementation roadmap

| Phase | Focus |
|-------|--------|
| **1** | WASM host shell, ledger, M/T/I/A, vQbit settlement, registry bootstrap rows |
| **2** | BON guidelines, Seahorse/GC-API connectors, THz DSP to **[M]** tensors |
| **3** | Workbench UX, Warburg 3D, epistemic overlays |
| **4** | Clinical validation loops; **[I]** models tune **priors** under governance — **not unbounded drift of [M] truth** |

---

## Related

- [`OBLIGATE_COUPLING_BIOPHYSICS_ANALOGY.md`](../../../docs/OBLIGATE_COUPLING_BIOPHYSICS_ANALOGY.md)
- [`../../../docs/M8_S4_C4_SUBSTRATE_CONTEXT.md`](../../../docs/M8_S4_C4_SUBSTRATE_CONTEXT.md)
