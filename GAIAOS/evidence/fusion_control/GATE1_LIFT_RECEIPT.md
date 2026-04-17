# GATE 1 — program CURE receipt (Fusion fleet moor USD)

**Schema:** `gaiaftcl_gate1_program_cure_v1`  
**Sealed (UTC):** 2026-04-03  
**Envelope:** `docs/plans/FUSION_FLEET_MOOR_USD_PLAN.md`

## CURE (S⁴)

This envelope **closes** the identity-policy gap for Fusion moor / mesh / sovereign fleet surfaces **without** shipping browser passkey, WebAuthn registration, or `crypto.subtle` key generation in app code.

| Commitment | S⁴ path |
|------------|---------|
| Anchor map | [`docs/fusion/GATE1_IDENTITY_CUSTODY.md`](../../docs/fusion/GATE1_IDENTITY_CUSTODY.md) |
| Enforcement | [`.cursor/rules/scope-fortress-gates.mdc`](../../.cursor/rules/scope-fortress-gates.mdc) + [`scripts/scope_fortress_scan.sh`](../../scripts/scope_fortress_scan.sh) — violations remain **REFUSED** at the tool (exit 1); this receipt does **not** disable the scanner |

## Declared anchors (this program)

- **DMG / Mac leaf:** `cell_onboard` → `~/.gaiaftcl/cell_identity.json` (+ mount + moor heartbeat state).  
- **Type1 web moor:** substrate-linked wallet via sovereign UI + `evidence/type1_mooring/`.  
- **Head / gateway:** founder / knight wallets in substrate (`authorized_wallets`, C⁴).

## Out of this envelope

Passkey / `navigator.credentials` / embedded-wallet keygen UX — **separate program** if ever authorized; **not** a blocking deficit for Fusion fleet moor USD closure.

## Founder attestation (C⁴, optional)

_Add a dated line when the Founder signs the field-of-truth._

---
