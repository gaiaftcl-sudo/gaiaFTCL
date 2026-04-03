# UI Contract: Definitions & Semantics

## Core Concepts

### CONTRACT COVERAGE vs UI REALIZATION

These are **two separate scorecards** that must never be conflated:

#### 1. CONTRACT COVERAGE
**Definition:** Whether every canonical item (from `evidence/ui_expected/*.json`) has a mapping entry in `ui_surface_map.json`.

**Scorecard Fields:**
- `total_items`: Total count of canonical items across all 6 files
- `mapped_items`: Count of items with a mapping entry in `ui_surface_map.json`
- `unmapped_items`: Count of items missing from `ui_surface_map.json`

**Success Condition:** `mapped_items == total_items` AND `unmapped_items == 0`

**Meaning:** 100% contract coverage means every canonical item is **accounted for** in the contract, regardless of whether it's implemented in the UI.

---

#### 2. UI REALIZATION
**Definition:** Whether a mapped item is **actually present** in the running Browser Cell UI with a stable selector.

**Scorecard Fields:**
- `ui_total_items`: Total count of canonical items (same as `total_items`)
- `ui_present_items`: Count of items with `ui_mapping.status == "UI_PRESENT"`
- `ui_absent_items`: Count of items with `ui_mapping.status == "UI_ABSENT"`
- `ui_present_requires_proof_violations`: Count of `UI_PRESENT` items missing route/selector/assertion
- `invalid_route_violations`: Count of `UI_PRESENT` items using non-allowed routes

**Success Condition:** 
- `ui_present_items == ui_total_items` 
- `ui_absent_items == 0`
- `ui_present_requires_proof_violations == 0`
- `invalid_route_violations == 0`

**Meaning:** 100% UI realization means every canonical item is **rendered in the real UI** with verifiable proof (route + selector + assertion).

---

## UI_PRESENT Proof Requirements

For an item to be marked `UI_PRESENT`, it **must** provide:

1. **route**: The real app route where it appears (e.g., `/index.html`)
2. **selector**: A stable `data-testid` selector (e.g., `[data-testid='contract-ftcl']`)
3. **assertion**: What text/state proves it exists (e.g., "label text equals FTCL")

**Allowed Routes:**
- `/index.html` (real Browser Cell UI)
- ❌ NOT `/contract.html`, `/envelopes.html`, or any audit/coverage pages

---

## File Manifest

### Canonical Sources (Read-Only Authority)
- `evidence/ui_expected/domains.json`
- `evidence/ui_expected/games.json`
- `evidence/ui_expected/envelopes.json`
- `evidence/ui_expected/uum8d_dimensions.json`
- `evidence/ui_expected/game_envelopes.json`
- `evidence/ui_expected/game_dimensions.json`
- `evidence/ui_expected/CANONICALS.SHA256` (lockfile)

### Contract Files (Generated/Maintained)
- `ui_contract_manifest.json`: Master index with file hashes and counts
- `ui_surface_map.json`: Mapping of every canonical item to contract + UI status
- `UI_ABSENT_BACKLOG.json`: Machine-readable backlog of `UI_ABSENT` items
- `UI_ABSENT_BACKLOG.md`: Human-readable backlog with priority ordering

---

## MCP Tools

### `ui_contract_generate`
**Purpose:** Validate canonical integrity and contract completeness.

**Returns:**
- Contract coverage scorecard
- UI realization scorecard
- Counts by kind
- Validation errors (if any)

**Fail Conditions:**
- Missing canonical files
- Hash mismatches
- Unmapped items
- Invalid routes for `UI_PRESENT` items

---

### `ui_contract_report`
**Purpose:** Generate scorecards + backlog for `UI_ABSENT` items.

**Returns:** Same as `ui_contract_generate`, plus:
- Generates `UI_ABSENT_BACKLOG.json`
- Generates `UI_ABSENT_BACKLOG.md`

**Backlog Priority Order:**
1. `game_envelope` (game-specific envelopes)
2. `envelope` (global envelopes)
3. `game_dimension` (game-specific dimension mappings)
4. `dimension` (UUM-8D global dimensions)
5. `game` (game definitions)
6. `domain` (domain definitions)

Within each kind, sorted lexicographically by ID.

---

## Enforcement Rules

1. **Canonical Freeze:** All canonical files are locked with SHA-256 hashes in `CANONICALS.SHA256`. Server validates on startup.

2. **Fail-Closed:** Any validation failure (missing file, hash mismatch, duplicate ID, invalid JSON) returns 500 with explicit error.

3. **Route Validation:** `UI_PRESENT` items must use allowed routes only. Audit/coverage pages are explicitly rejected.

4. **Proof Requirements:** `UI_PRESENT` items must have route + selector + assertion (non-empty strings). Missing any field is a violation.

5. **Contract Completeness:** Every canonical item must have a mapping entry. `unmapped_items > 0` is a failure.

---

## Canonical Validation Lifecycle

**Validation Timing:**
- Canonical file integrity is validated **once per server process start** using `OnceLock` (Rust synchronization primitive)
- This is a performance optimization: validation runs on first MCP call, result is cached for the process lifetime
- Runtime tampering of canonical files requires a server restart to be detected

**Hash Attestation:**
- Every MCP tool response includes `canonicals_hash` field
- This is the SHA-256 hash of the `CANONICALS.SHA256` lockfile
- External tools can verify canonical integrity by:
  1. Computing SHA-256 of `evidence/ui_expected/CANONICALS.SHA256`
  2. Comparing to `canonicals_hash` in tool response
  3. If mismatch: canonical files were modified after server start

**Design Rationale:**
- Startup validation prevents server from running with corrupted canonicals
- Per-call hash attestation enables external verification without per-call I/O overhead
- Fail-closed: server won't start if canonicals are invalid

---

## Example: 100% Contract, 44% UI Realization

```json
{
  "contract_coverage": {
    "total_items": 61,
    "mapped_items": 61,
    "unmapped_items": 0
  },
  "ui_coverage": {
    "ui_total_items": 61,
    "ui_present_items": 27,
    "ui_absent_items": 34,
    "ui_present_requires_proof_violations": 0,
    "invalid_route_violations": 0
  }
}
```

**Interpretation:**
- ✅ Contract: 100% (all items mapped)
- ⚠️ UI: 44% (27/61 items rendered in real UI)
- 📋 Backlog: 34 items need UI implementation
