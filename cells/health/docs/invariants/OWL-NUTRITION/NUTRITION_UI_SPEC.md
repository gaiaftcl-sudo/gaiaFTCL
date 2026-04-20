# NUTRITION_UI_SPEC — GaiaHealth-internal (v1)

**Status:** DRAFT  
**Supersedes invented Communion §5.2.6 / §5.9 / §5.10 numbers** until CCR merges into [`S4_C4_COMMUNION_UI_SPEC.md`](../../S4_C4_COMMUNION_UI_SPEC.md).

## Principle

**UI is viewport, not oracle** — coherence from WASM constitutional layer; see Communion §1 philosophy in [`S4_C4_COMMUNION_UI_SPEC.md`](../../S4_C4_COMMUNION_UI_SPEC.md).

## Surfaces (target)

1. **Nutrition Intake** — food log composer, lab panel drop zone, wearable export import; PHI scrubber before seal **[I]**.  
2. **C4 Registry — Nutrition domain** — filter mother invariants; Confirm/Deny panel **[I]**.  
3. **Nutrition Configuration (Settings)** — ethical/religious/medical declarations; cadence; alerts **[I]**.  
4. **Nutrition Dashboard** — twelve mother summary; declared C4 badge **[I]**.

## Swift package path

Implement under [`cells/fusion/macos/MacHealth/`](../../../fusion/macos/MacHealth/) per [`REVIEWER_BRIEF.md`](../../REVIEWER_BRIEF.md) — see Phase 3 file list in repo.

## WCAG

**[I]** automated audit — target WCAG 2.2 AA.
