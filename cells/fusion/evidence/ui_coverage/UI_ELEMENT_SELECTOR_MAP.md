# UI ELEMENT SELECTOR MAP

**Purpose:** Map every UI element to stable selectors for testability.

**Branch:** phase-a-baseline  
**Date:** 2026-01-31  
**Status:** ✅ **100% COVERAGE FOR CONTRACT ITEMS**

---

## CONTRACT UI ELEMENTS (100% COVERED)

### Domain Elements

| ui_element_id | selector | mapped_game_id | mapped_dim_key | source_path |
|---------------|----------|----------------|----------------|-------------|
| DOMAIN_FTCL | `data-testid="domain:FTCL"` | N/A | N/A | `apps/gaiaos_browser_cell/web/contract.html` |
| DOMAIN_INFRASTRUCTURE | `data-testid="domain:INFRASTRUCTURE"` | N/A | N/A | `apps/gaiaos_browser_cell/web/contract.html` |

**Coverage:** 2/2 domains (100%)

---

### Game Elements

| ui_element_id | selector | mapped_game_id | mapped_dim_key | source_path |
|---------------|----------|----------------|----------------|-------------|
| GAME_UPDATE_FLEET | `data-testid="game:G_FTCL_UPDATE_FLEET_V1"` | G_FTCL_UPDATE_FLEET_V1 | N/A | `apps/gaiaos_browser_cell/web/contract.html` |
| GAME_ROLLBACK | `data-testid="game:G_FTCL_ROLLBACK_V1"` | G_FTCL_ROLLBACK_V1 | N/A | `apps/gaiaos_browser_cell/web/contract.html` |
| GAME_INVEST | `data-testid="game:G_FTCL_INVEST_001"` | G_FTCL_INVEST_001 | N/A | `apps/gaiaos_browser_cell/web/contract.html` |
| GAME_PROFIT_DIST | `data-testid="game:G_FTCL_PROFIT_DIST"` | G_FTCL_PROFIT_DIST | N/A | `apps/gaiaos_browser_cell/web/contract.html` |

**Coverage:** 4/4 games (100%)

---

### UUM-8D Dimension Elements (Per-Game)

**Pattern:** `data-testid="dim:{game_id}:{dim_key}"`

**Total Game-Level Dimensions:** 20 (4 games × 5 dimensions each)

| game_id | d0 | d4 | d5 | d6 | d7 | status |
|---------|----|----|----|----|-----|--------|
| G_FTCL_UPDATE_FLEET_V1 | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| G_FTCL_ROLLBACK_V1 | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| G_FTCL_INVEST_001 | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| G_FTCL_PROFIT_DIST | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |

**Coverage:** 20/20 game dimensions (100%)

---

### UUM-8D Dimension Elements (Global)

**Pattern:** `data-testid="dim:all:{dim_key}"`

| ui_element_id | selector | mapped_dim_key | source_path |
|---------------|----------|----------------|-------------|
| DIM_ALL_D0 | `data-testid="dim:all:d0"` | d0 (Temporal) | `apps/gaiaos_browser_cell/web/contract.html` |
| DIM_ALL_D1 | `data-testid="dim:all:d1"` | d1 (Spatial X) | `apps/gaiaos_browser_cell/web/contract.html` |
| DIM_ALL_D2 | `data-testid="dim:all:d2"` | d2 (Spatial Y) | `apps/gaiaos_browser_cell/web/contract.html` |
| DIM_ALL_D3 | `data-testid="dim:all:d3"` | d3 (Spatial Z) | `apps/gaiaos_browser_cell/web/contract.html` |
| DIM_ALL_D4 | `data-testid="dim:all:d4"` | d4 (Prudence) | `apps/gaiaos_browser_cell/web/contract.html` |
| DIM_ALL_D5 | `data-testid="dim:all:d5"` | d5 (Justice) | `apps/gaiaos_browser_cell/web/contract.html` |
| DIM_ALL_D6 | `data-testid="dim:all:d6"` | d6 (Temperance) | `apps/gaiaos_browser_cell/web/contract.html` |
| DIM_ALL_D7 | `data-testid="dim:all:d7"` | d7 (Fortitude) | `apps/gaiaos_browser_cell/web/contract.html` |

**Coverage:** 8/8 dimensions (100%)

---

### Envelope Elements (Per-Game)

**Pattern:** `data-testid="env:{game_id}:{base64(subject)}"`

**Total Game-Level Envelopes:** 11

| game_id | envelope_count | status |
|---------|----------------|--------|
| G_FTCL_UPDATE_FLEET_V1 | 4 | ✅ 4/4 |
| G_FTCL_ROLLBACK_V1 | 3 | ✅ 3/3 |
| G_FTCL_INVEST_001 | 2 | ✅ 2/2 |
| G_FTCL_PROFIT_DIST | 2 | ✅ 2/2 |

**Coverage:** 11/11 game envelopes (100%)

---

### Envelope Elements (Global)

**Pattern:** `data-testid="env:all:{base64(subject)}"`

**Total Envelopes:** 16 (11 game-specific + 5 generic)

**Coverage:** 16/16 envelopes (100%)

---

## BROWSER CELL UI ELEMENTS (EXISTING, UNCHANGED)

### Status Panel Elements

| ui_element_id | selector | status |
|---------------|----------|--------|
| STATUS_PANEL | `#status` | ✅ Present (no data-testid) |
| STATUS_CONNECTION | **SELECTOR_MISSING** | ❌ No stable selector |
| STATUS_CELL_ID | **SELECTOR_MISSING** | ❌ No stable selector |
| STATUS_WORLD | **SELECTOR_MISSING** | ❌ No stable selector |
| STATUS_REV | **SELECTOR_MISSING** | ❌ No stable selector |

**Note:** Browser Cell UI (index.html) remains unchanged. Contract UI is separate.

---

## SELECTOR GAPS SUMMARY (UPDATED)

### Contract UI (NEW)

| gap_category | count | status |
|--------------|-------|--------|
| Domain selectors | 2 | ✅ 100% COVERED |
| Game selectors | 4 | ✅ 100% COVERED |
| Game dimension selectors | 20 | ✅ 100% COVERED |
| Game envelope selectors | 11 | ✅ 100% COVERED |
| Global dimension selectors | 8 | ✅ 100% COVERED |
| Global envelope selectors | 16 | ✅ 100% COVERED |

**Total Contract Selectors:** 61/61 (100%)

### Browser Cell UI (EXISTING, UNCHANGED)

| gap_category | count | status |
|--------------|-------|--------|
| Panel-level selectors present | 8 | ✅ Present |
| Child element selectors missing | 18 | ❌ Still missing |
| 3D scene selectors missing | 2 | ❌ Still missing |

**Note:** Browser Cell UI gaps remain unchanged. Contract UI provides 100% coverage for contract items.

---

## VERIFICATION COMMANDS

**Check contract selectors:**
```bash
open http://localhost:8896/contract.html
# Inspect elements with data-testid attributes
```

**Run selector tests:**
```bash
cd apps/gaiaos_browser_cell
npx playwright test 30_contract_coverage.spec.ts
```

**List all contract selectors:**
```bash
grep -o 'data-testid="[^"]*"' apps/gaiaos_browser_cell/web/contract.html | sort | uniq
```

---

**END OF SELECTOR MAP**
