# GaiaHealth S4↔C4 Communion UI Specification

| Field | Value |
|-------|--------|
| **Document ID** | **GH-S4C4-COMM-001** |
| **Version** | 1.0 |
| **Date** | 2026-04-18 |
| **Status** | **SPECIFICATION — design target & implementation roadmap** (not a shipped-feature manifest) |
| **Owner** | Richard Gillespie — FortressAI Research Institute, Norwich CT |
| **Patents** | USPTO 19/460,960 \| USPTO 19/096,071 |
| **Framework** | GAMP 5 Cat 5 \| M8 = S4 × C4 (projection discipline) |

---

## 0. Canonical measurement stack: `BioligitPrimitive`, `vQbit`, and M/T/I/A

This document describes **communion UI** — how the **manifest layer (S4)** meets **constraint truth (C4)** on the GaiaHealth cell. The following are all **canonical in FoT8D** and must not be read as competing primitives:

| Layer | Construct | Role |
|--------|-----------|------|
| **Health vertex / MD carrier** | [`BioligitPrimitive`](../wiki/BioligitPrimitive-ABI.md) (96-byte `#[repr(C)]` struct) | Structured biological geometry and simulation fields (binding ΔG, ADMET, M/I/A epistemic class at vertex). **This is the Biologit Cell’s scene primitive.** |
| **Manifold closure & ledger** | **`vQbit`** (Virtual Quantum Bit) semantics | Entropy-delta / witness / collapse onto the **Field of Truth** — settlement into CALORIE, CURE, REFUSED, BLOCKED with receipts. **Same epistemic law as GaiaFTCL-wide UUM-8D.** |
| **Provenance** | **M / T / I / A** tagging ([§6.1](#61-mti--tagging-schema)) | Machine / Tool / Intelligence / Agent — **extends** GaiaHealth’s vertex-level M/I/A to full-stack envelopes. |

**Projection rule:** S4 measurements (sensors, files, models) **project** to scalar fields comparable against **C4 invariants**; disagreement is **Torsion** (S4≠C4) until witnessed closure. **`BioligitPrimitive` feeds MD projections; `vQbit` collapse is how those projections become substrate-grade truth.**

**Related:** [GH-DS-001](DESIGN_SPECIFICATION.md), [GH-FS-001](FUNCTIONAL_SPECIFICATION.md), **[M8 substrate context — S4×C4](../../../docs/M8_S4_C4_SUBSTRATE_CONTEXT.md)** (canonical `docs/` copy; no GAIAOS path).

---

## 1. Architectural philosophy and executive overview

The operationalization of **GaiaHealth S4↔C4 Communion** is a paradigm for biocomputational engineering: **substrate fidelity** (digital representations track biophysical phenomena without undocumented loss) and **epistemic honesty** (every datum has verifiable provenance and explicit reliability class).

Five pillars instantiate communion:

1. **Global WebAssembly (WASM) shell** — near-native, sandboxed compute (see [§2](#2-the-global-shell-and-dynamic-plugin-extension-architecture)).
2. **Multi-modal S4 ingest** — sensors, files, wet-lab instruments, clinical narratives, neural/metabolic imaging (see [§3](#3-multi-modal-s4-ingest-achieving-substrate-fidelity)).
3. **C4 invariant registry** — stoichiometric, thermodynamic, and proteostatic baselines used to score incoming S4 streams (see [§4](#4-the-c4-invariant-registry-enforcing-biological-baselines)).
4. **Projection workbench** — high-dimensional visualization and operator cognition (see [§5](#5-the-projection-workbench)).
5. **Epistemic ledger** — immutable record of M/T/I/A tags and **vQbit** settlement/collapse (see [§6](#6-the-epistemic-ledger)).

**Regulatory stance:** GaiaHealth remains a **research instrument** where GH-FS-001 declares clinical decision support out of scope; communion defines **how** future modalities attach **without** claiming regulatory clearance by narrative alone.

---

## 2. The global shell and dynamic plugin extension architecture

### 2.1 WebAssembly and out-of-browser execution

The shell targets **sandboxed WASM modules** with a **non-browser** host profile (e.g. **WASI**-style capabilities where applicable): filesystem, clocks, and controlled I/O for instruments. Exact engine revision **tracks** the toolchain pinned in `cells/health` CI; “WASM 3.0” herein denotes **target semantics alignment** with the active spec, not an unversioned marketing label.

### 2.2 Biological ABI and data exchange

Host and plugins share data via a **typed ABI** (minimal copy, explicit layout). The design goal is **Karmem-like** deterministic layouts for Rust/C++/Python-compiled plugins so multi-modal streams (e.g. THz spectra + respirometry) share **aligned stoichiometry** without ad-hoc JSON drift at the hot path.

### 2.3 JSON / BON payloads and synthetic biology integration

**BON (Biological Object Notation)** — JSON-profiled envelopes that separate **payload** from **metadata** for large biological arrays. **Construction File (CF)** and **BioModTool**-style biomass objectives normalize flux units (e.g. mmol·gDW⁻¹·h⁻¹) for metabolic plugins. Compression ratios in legacy prose (e.g. “~87%”) are **design targets**; realized ratios require measured benchmarks per deployment.

---

## 3. Multi-modal S4 ingest: achieving substrate fidelity

### 3.1 Bioenergetics and wet-lab integration

Ingest **OCR** (oxygen consumption rate) and **ECAR** (extracellular acidification) from platforms such as Seahorse XF or high-resolution respirometry. The projection workbench presents **OCR vs ECAR** metabolic maps and supports scripted mitotropic sequences (e.g. oligomycin → FCCP → rotenone/antimycin) for **basal**, **ATP-linked**, **proton leak**, and **spare capacity** extraction — computed in **[T]** with **[M]** raw currents preserved.

### 3.2 Sub-terahertz spectroscopic fingerprinting (proteostasis)

Ingest **sub-THz** and related vibrational data for chaperone conformation (e.g. hHsp70). Registry lines treat **sub-45 GHz** and **ν < 300 GHz** bands as **hypothesis regions** for open/closed discrimination; model outputs carry **[I]** until cross-validated against **[M]** assay gold sets.

### 3.3 Continuous breathomics and VOCs

GC–MS breath streams → acetate / propionate / butyrate proxies where instrument supports; concurrent **OUR**, **CER**, **RQ = VCO₂/VO₂** for substrate oxidation interpretation (carbohydrate ~1.0, lipid ~0.7, mixed/protein ~0.8–0.85 bands).

### 3.4 Neural metabolic imaging and biosensors

FRET / lactate reporters (e.g. Laconic-class) at cellular resolution; UI stratifies trajectories by entropy character for **[I]** overlays on structural imaging — **never** substitute **[I]** for **[M]** without declared confidence.

### 3.5 Epigenetic clocks and narrative streams

DNAm clocks (Horvath/Hannum-class multivariate models) as **[I]** with cohort-specific priors. **NLP** on narratives = **[A]** or **[I]** only; sequestered from **[M]** thermodynamic channels per epistemic firewall rules.

---

## 4. The C4 invariant registry: enforcing biological baselines

The **C4 invariant registry** holds **literature-anchored baselines** and institutional calibration — **not** a substitute for peer review in publication. Each invariant row carries: **ID**, **value or range**, **M/T/I/A default**, **source DOI set**, **review status**.

### 4.1 Thermodynamic framing: NESS and entropy accounting

Discrete-state entropy:

\[
H_\tau = -\sum_{S} P(s(\tau)=S)\log_2 P(s(\tau)=S)
\]

**Interpretation:** “Zero internal entropy production” is an **ideal limit**; real biology is **NESS**. UI clusters low-entropy-production pathways vs chaotic trajectories as **diagnostic hints**, not diagnoses.

### 4.2 Mitochondrial P/O coupling baselines

| Substrate class | Mechanistic P/O baseline (design registry) | Notes |
|-----------------|-------------------------------------------|--------|
| NADH-linked (e.g. pyruvate/malate) | **2.5** | Literature consensus band; refine with org-specific oxphos models |
| FADH₂-linked (e.g. succinate) | **1.5** | Same |

Empirical P/O from **[M]** respirometry that persistently violates calibrated thresholds → **REFUSED** or **BLOCKED** envelope until instrument QA is **[M]**-witnessed.

### 4.3 SCFA stoichiometric baseline (colon fermentation)

**Design baseline ratio (Acetate : Propionate : Butyrate) ≈ 60 : 20 : 20 (molar).** Fecal concentration bands in source prose are **cohort-dependent**; lock ranges only with citations and IRB-approved cohort definitions.

| SCFA | Nominal share | Example fecal band (mM) * | Primary notes |
|------|----------------|---------------------------|---------------|
| Acetate | 60% | 39.9 – 114.9 | Systemic substrate; BBB crossing; HCA2 |
| Propionate | 20% | 12.8 – 27.2 | Gluconeogenesis / barrier signaling; FFAR3 |
| Butyrate | 20% | 10.3 – 24.6 | Colonocyte fuel; HDAC; tight junctions |

\* Illustrative literature bands — **replace with DOI-scoped tables** in production calibration.

Deviation triggers **dysbiosis risk projection [I]**, not automatic disease classification.

### 4.4 Proteostatic amino acid stoichiometry

Registry may include **IAAO-derived** essential amino acid requirements by age/sex stratum (exemplar mg/kg/d rows for leucine, methionine, phenylalanine, total protein in source spec). **All** require **primary citation + cohort** before operational use.

### 4.5 Zinc ionophore stoichiometry (virology hypotheses)

Low-concentration **Zn²⁺** + ionophore / polyphenol hypotheses (e.g. 2 µM class pairs) are **experimental therapeutics territory**. If tracked, mark as **[I]**/**[T]** with explicit **falsification windows** (OCR/VOC predictions) — **never** as unqualified **[M]** invariants without trial evidence.

---

## 5. The projection workbench

### 5.1 Fractal salutogenesis (UX)

Mid-range fractal layouts for operator comfort — **empirical UX claim**; validate with usability study receipts if marketed.

### 5.2 Metabolic reprogramming visualization (oncology)

Warburg-class views using metrics such as **Nath–Warburg number** and ATP-yield modeling — **models are [I]** unless fit to **[M]** tumor perfusion/flux data. Natural compounds (berberine, curcumin, EGCG, vitamin D₃) mapped as **multi-target overlays** with mechanism tags from curated pathway DBs (**[T]**) and literature (**[I]**).

---

## 6. The epistemic ledger

### 6.1 M/T/I/A tagging schema

| Tag | Origin | Definition / examples | Weight |
|-----|--------|----------------------|--------|
| **M** | Machine | Raw sensor / instrument output (Seahorse, GC–MS, THz ADC) | Highest substrate fidelity |
| **T** | Tool | Deterministic transforms (P/O from OCR, BOF from BioModTool, unit conversions) | Deterministic; assumptions explicit |
| **I** | Intelligence | ML/ statistical models (age clocks, trajectory classifiers) | Probabilistic — confidence intervals required |
| **A** | Agent | Human narrative, clinical judgment, patient report | Subjective but often essential context |

Workbench filters **must** show active tag filters to prevent **[I]**/**[A]** smuggling into **[M]** views.

### 6.2 vQbit collapse and Field of Truth settlement

A biological claim exists in **superposition** until **witnessed collapse**: envelope **SEALED → SETTLED** with hash-chained receipts. Interventions must declare **falsifiable predicted shifts** on **[M]** channels; failed predictions downgrade model trust and **REFUSED** or **BLOCKED** policy per constitutional WASM / mesh rules.

---

## 7. Implementation roadmap (phased)

| Phase | Focus | Deliverables |
|-------|--------|--------------|
| **1** | Core substrate & ledger | WASM host shell + epistemic ledger DB; M/T/I/A; vQbit settlement paths; C4 registry **bootstrap rows** (P/O, SCFA, declared-uncertainty ranges) |
| **2** | S4 plugins & APIs | BON schema guides; Seahorse / GC–MS connectors; THz DSP pipeline to **[M]** tensors |
| **3** | Projection workbench | Fractal UX shells; Warburg / multi-target 3D modules; tag overlays |
| **4** | Clinical validation & tuning | Closed-loop trials; **[I]** models update **ranges** under governance — **not unbounded drift** of **[M]** truth |

---

## 8. Document control

| Related ID | Title |
|------------|--------|
| GH-FS-001 | Functional Specification |
| GH-DS-001 | Design Specification |
| GH-RTM-001 | Requirements Traceability Matrix |
| GH-OWL-UNIFIED-FREQ-001 | OWL unified frequency framework (CLI arch cross-link) |

**Change history**

| Version | Date | Note |
|---------|------|------|
| 1.0 | 2026-04-18 | Initial communion UI specification integrated into `cells/health/docs/` |
