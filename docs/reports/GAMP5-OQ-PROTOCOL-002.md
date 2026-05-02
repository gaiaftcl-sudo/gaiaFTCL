# GaiaFTCL GAMP 5 — Operational Qualification Protocol (Self-Review Loop)

**Protocol ID:** GAMP5-OQ-PROTOCOL-002  
**Version:** 1.0  
**Author:** Rick Gillespie, FortressAI Research Institute  
**Status:** APPROVED — binding git commit SHA: `1259487613195af1d3ac605007bba6b567fe08f7`  
**Prerequisite:** [GAMP5-OQ-PROTOCOL-001](./GAMP5-OQ-PROTOCOL-001.md) conventions where applicable  
**PQ scope:** [GAMP5-PQ-SCOPE-001](./GAMP5-PQ-SCOPE-001.md) (PQ-SR-001…003 and PQ-001…005)

---

## Purpose

Qualify the **Franklin Consciousness self-review loop**: proactive domain standard improvement against persisted constitutional thresholds, evidence in GRDB, NATS → vQbit VM → C⁴ observation (FranklinConsciousnessService is **NATS-only**; no USD calls).

---

## OQ Tests — Self-Review (OQ-SR)

### OQ-SR-001 — Review cycle row exists

**Requirement:** `franklin_review_cycles` has ≥ 1 row after one full cycle.

**Command:**
```bash
sqlite3 ~/Library/Application\ Support/GaiaFTCL/substrate.sqlite \
  "SELECT count(*) FROM franklin_review_cycles;"
```
**Pass:** count ≥ 1

---

### OQ-SR-002 — Domain improvement receipt

**Requirement:** `franklin_learning_receipts` has **`kind='domain_improvement'`**.

**Command:**
```bash
sqlite3 ~/Library/Application\ Support/GaiaFTCL/substrate.sqlite \
  "SELECT count(*) FROM franklin_learning_receipts WHERE kind='domain_improvement';"
```
**Pass:** count ≥ 1

---

### OQ-SR-003 — Health improves on improvement path

**Requirement:** On the same cycle row, **`post_health_score > prior_health_score`** when **`action_taken='improved'`**.

**Command:**
```bash
sqlite3 ~/Library/Application\ Support/GaiaFTCL/substrate.sqlite \
  "SELECT id, domain, prior_health_score, post_health_score
   FROM franklin_review_cycles
   WHERE action_taken='improved'
   AND post_health_score > prior_health_score;"
```
**Pass:** ≥ 1 row

---

### OQ-SR-004 — No aesthetic weight above 1.0

**Requirement:** No **`aesthetic_rules_json`** weight exceeds **1.0**.

**Command:**
```bash
sqlite3 ~/Library/Application\ Support/GaiaFTCL/substrate.sqlite \
  "SELECT id, domain,
     json_extract(aesthetic_rules_json,'$.weights.s1_weight'),
     json_extract(aesthetic_rules_json,'$.weights.s2_weight'),
     json_extract(aesthetic_rules_json,'$.weights.s3_weight'),
     json_extract(aesthetic_rules_json,'$.weights.s4_weight')
   FROM language_game_contracts
   WHERE json_extract(aesthetic_rules_json,'$.weights.s1_weight') > 1.0
      OR json_extract(aesthetic_rules_json,'$.weights.s2_weight') > 1.0
      OR json_extract(aesthetic_rules_json,'$.weights.s3_weight') > 1.0
      OR json_extract(aesthetic_rules_json,'$.weights.s4_weight') > 1.0;"
```
**Pass:** 0 rows

*(Uses **`aesthetic_rules_json`** on **`language_game_contracts`**; seeded/backfilled via **`v7`**, **`v9_contract_aesthetic_backfill`**, and **`LanguageGameContractSeeder.patchAestheticDefaultsIfNeeded`**.)*

---

### OQ-SR-005 — No regression on improvement receipts

**Requirement:** For each **`domain_improvement`** receipt, **`new_weight > old_weight`** for the improved dimension (parsed from **`payload_json`**).

**Command:**
```bash
sqlite3 ~/Library/Application\ Support/GaiaFTCL/substrate.sqlite \
  "SELECT id, payload_json FROM franklin_learning_receipts WHERE kind='domain_improvement';"
```
**Pass:** Parse each **`payload_json`**; **`new_weight`** must be strictly greater than **`old_weight`** for the stated **`dimension_improved`**.

---

## Two-commit seal (evidence)

Live OQ execution seals **`docs/reports/GAMP5-OQ-EVIDENCE-002.md`** per **[GAMP5-DEVIATION-PROCEDURE-001.md](./GAMP5-DEVIATION-PROCEDURE-001.md)**. Commit 2 message must contain:

`OQ-SIGNOFF: GAMP5-OQ-PROTOCOL-002 v1.0`

---

## Revision history

| Version | Date | Notes |
|---------|------|--------|
| 1.0 | 2026-05-02 | Initial protocol — self-review loop OQ-SR-001…005 |
