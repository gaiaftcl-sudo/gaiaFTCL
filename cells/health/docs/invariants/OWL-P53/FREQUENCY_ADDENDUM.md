# FREQUENCY_ADDENDUM — OWL-P53 frequency channel (v1)

**Policy:** [FREQUENCY_BAND_POLICY.md](FREQUENCY_BAND_POLICY.md) **Option B** — numeric bands **only** here, not in [`INVARIANT_SPEC.md`](INVARIANT_SPEC.md).

## 1. Channel semantics

The **frequency** S4 channel carries **derived** features from acoustic and/or bioelectric time series: FFT magnitude, band-limited power, phase, and optional cross-channel coherence with imaging / stress markers. Each feature is tagged **M/T/I/A** per GH-FS-001 epistemic rules.

## 2. Candidate bands (appendix — not normative core)

The following **Hz** values appear in unified-frequency and UI **draft** material as **candidates** for OWL “domain” windows. They are **not** validated clinical endpoints in v1. Each MUST be labeled **(T) Tested** (instrument calibration / replay) or **(A) Assumed** (design placeholder).

| Band center (Hz) | Label | Provenance note |
|------------------|-------|-----------------|
| 444 | **(A)** | Design candidate — requires pre-registered PQ correlation to other four channels before promotion. |
| 540 | **(A)** | Same. |
| 372 | **(A)** | Same. |
| 630 | **(A)** | Same. |
| 348 | **(A)** | Same. |

**Parent document ID** `GH-OWL-UNIFIED-FREQ-001` does not yet have a standalone `.md` — see [`PHASE1_GAP_LIST.md`](PHASE1_GAP_LIST.md). Until authored, cross-reference [`GAIAOS/docs/GAIAFTCL_CLI_ARCHITECTURE.md`](../../../../../GAIAOS/docs/GAIAFTCL_CLI_ARCHITECTURE.md) **[I]**.

## 3. Nested IQ/OQ/PQ for frequency

- **IQ:** Instrument calibration / replay chain identified **[I]** per deployment.  
- **OQ:** Synthetic waveforms with known spectral content; verify feature extraction stability.  
- **PQ:** PQ-v1 correlation study per [`PQ_PROTOCOL.md`](PQ_PROTOCOL.md); PQ-v2 human studies **separate**.

## 4. Promotion rule

Move a band from **(A)** to **(T)** or **(M)** only with cited evidence and change control; update this addendum and epistemic tags in receipts.
