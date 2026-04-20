# OQ — Operational Qualification — OWL-P53-INV1

**Parent:** [INVARIANT_SPEC.md](INVARIANT_SPEC.md)  
**Related:** [IQ_PROTOCOL.md](IQ_PROTOCOL.md) · [PQ_PROTOCOL.md](PQ_PROTOCOL.md)

## 1. Purpose

OQ demonstrates that the **documented** composite gate semantics (five channels, drift rules) can be exercised in **synthetic** or **fixture** runs without human subjects data, consistent with GH-FS-001 research-instrument posture.

## 2. Scope (v1)

- **Synthetic envelopes** — lab or file-backed inputs that populate the five channels with known epistemic tags **M/T/I/A**.  
- **Negative paths** — intentional drift in one vs two channels; expect **watch** vs **REFUSED** per [`INVARIANT_SPEC.md`](INVARIANT_SPEC.md) §4.  
- **Registry / projection UI** — **[I]** until Communion spec sections and implementation align (see [`PHASE1_GAP_LIST.md`](PHASE1_GAP_LIST.md)).

## 3. Traceability

OQ cases SHALL reference:

- Channel definitions — [`INVARIANT_SPEC.md`](INVARIANT_SPEC.md) §3.  
- Composite gate — [`INVARIANT_SPEC.md`](INVARIANT_SPEC.md) §4.  
- Frequency channel — [`FREQUENCY_ADDENDUM.md`](FREQUENCY_ADDENDUM.md) (no normative Hz in core spec).

## 4. OQ exit criteria (v1)

| Gate | Requirement |
|------|----------------|
| OQ-1 | At least one **held** path with all five channels in-bounds (synthetic). |
| OQ-2 | At least one **watch** path (single-channel drift). |
| OQ-3 | At least one **REFUSED** path (multi-channel drift). |
| OQ-4 | Receipt artifact captures channel tags + composite outcome (format **[I]** until aligned with mesh JSON). |

Human **PQ-v2** criteria are **out of scope** for OQ — see [PQ_PROTOCOL.md](PQ_PROTOCOL.md).
