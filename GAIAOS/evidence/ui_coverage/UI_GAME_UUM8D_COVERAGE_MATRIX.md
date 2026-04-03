# UI GAME UUM-8D COVERAGE MATRIX

**Purpose:** Map domains → games → UI surfaces and games → UUM-8D dimensions → UI elements.

**Branch:** phase-a-baseline  
**Date:** 2026-01-31  
**Status:** ✅ **100% COVERAGE ACHIEVED**

---

## MATRIX 1: DOMAIN → GAME → UI SURFACE

### Domain: FTCL (Field Truth Closure Layer)

| game_id | game_name | ui_surface_mapping | status |
|---------|-----------|-------------------|--------|
| G_FTCL_INVEST_001 | Investment Acquisition | `/contract.html` (game:G_FTCL_INVEST_001) | ✅ **COVERED** |
| G_FTCL_PROFIT_DIST | Profit Distribution | `/contract.html` (game:G_FTCL_PROFIT_DIST) | ✅ **COVERED** |

### Domain: INFRASTRUCTURE (Infrastructure Management)

| game_id | game_name | ui_surface_mapping | status |
|---------|-----------|-------------------|--------|
| G_FTCL_UPDATE_FLEET_V1 | Fleet Update | `/contract.html` (game:G_FTCL_UPDATE_FLEET_V1) | ✅ **COVERED** |
| G_FTCL_ROLLBACK_V1 | Fleet Rollback | `/contract.html` (game:G_FTCL_ROLLBACK_V1) | ✅ **COVERED** |

**Analysis:**
- All 4 games are rendered in the contract coverage UI
- Each game has a stable selector: `data-testid="game:{game_id}"`
- Contract UI provides read-only view of all game metadata
- UI source: `apps/gaiaos_browser_cell/web/contract.html`
- Contract manifest: `apps/gaiaos_browser_cell/src/ui_contract/ui_contract_manifest.json`

**Coverage:** 4/4 games (100%)

---

## MATRIX 2: GAME → UUM-8D DIMENSIONS → UI ELEMENTS

### Game: G_FTCL_UPDATE_FLEET_V1 (Fleet Update)

| uum8d_dimension | dim_key | required_for_game | ui_element | selector | status |
|-----------------|---------|-------------------|------------|----------|--------|
| Temporal | d0 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_UPDATE_FLEET_V1:d0"` | ✅ **COVERED** |
| Prudence | d4 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_UPDATE_FLEET_V1:d4"` | ✅ **COVERED** |
| Justice | d5 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_UPDATE_FLEET_V1:d5"` | ✅ **COVERED** |
| Temperance | d6 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_UPDATE_FLEET_V1:d6"` | ✅ **COVERED** |
| Fortitude | d7 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_UPDATE_FLEET_V1:d7"` | ✅ **COVERED** |

**Envelopes:**
- FLEET_UPDATE_REQUEST: `data-testid="env:G_FTCL_UPDATE_FLEET_V1:{base64}"`
- FLEET_UPDATE_COMMITMENT: `data-testid="env:G_FTCL_UPDATE_FLEET_V1:{base64}"`
- FLEET_UPDATE_TRANSACTION: `data-testid="env:G_FTCL_UPDATE_FLEET_V1:{base64}"`
- FLEET_UPDATE_REPORT: `data-testid="env:G_FTCL_UPDATE_FLEET_V1:{base64}"`

**Coverage:** 5/5 dimensions + 4/4 envelopes (100%)

---

### Game: G_FTCL_ROLLBACK_V1 (Fleet Rollback)

| uum8d_dimension | dim_key | required_for_game | ui_element | selector | status |
|-----------------|---------|-------------------|------------|----------|--------|
| Temporal | d0 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_ROLLBACK_V1:d0"` | ✅ **COVERED** |
| Prudence | d4 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_ROLLBACK_V1:d4"` | ✅ **COVERED** |
| Justice | d5 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_ROLLBACK_V1:d5"` | ✅ **COVERED** |
| Temperance | d6 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_ROLLBACK_V1:d6"` | ✅ **COVERED** |
| Fortitude | d7 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_ROLLBACK_V1:d7"` | ✅ **COVERED** |

**Envelopes:**
- ROLLBACK_REQUEST: `data-testid="env:G_FTCL_ROLLBACK_V1:{base64}"`
- ROLLBACK_COMMITMENT: `data-testid="env:G_FTCL_ROLLBACK_V1:{base64}"`
- ROLLBACK_TRANSACTION: `data-testid="env:G_FTCL_ROLLBACK_V1:{base64}"`

**Coverage:** 5/5 dimensions + 3/3 envelopes (100%)

---

### Game: G_FTCL_INVEST_001 (Investment Acquisition)

| uum8d_dimension | dim_key | required_for_game | ui_element | selector | status |
|-----------------|---------|-------------------|------------|----------|--------|
| Temporal | d0 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_INVEST_001:d0"` | ✅ **COVERED** |
| Prudence | d4 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_INVEST_001:d4"` | ✅ **COVERED** |
| Justice | d5 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_INVEST_001:d5"` | ✅ **COVERED** |
| Temperance | d6 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_INVEST_001:d6"` | ✅ **COVERED** |
| Fortitude | d7 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_INVEST_001:d7"` | ✅ **COVERED** |

**Envelopes:**
- INVESTMENT_CLAIM: `data-testid="env:G_FTCL_INVEST_001:{base64}"`
- INVESTMENT_COMMITMENT: `data-testid="env:G_FTCL_INVEST_001:{base64}"`

**Coverage:** 5/5 dimensions + 2/2 envelopes (100%)

---

### Game: G_FTCL_PROFIT_DIST (Profit Distribution)

| uum8d_dimension | dim_key | required_for_game | ui_element | selector | status |
|-----------------|---------|-------------------|------------|----------|--------|
| Temporal | d0 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_PROFIT_DIST:d0"` | ✅ **COVERED** |
| Prudence | d4 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_PROFIT_DIST:d4"` | ✅ **COVERED** |
| Justice | d5 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_PROFIT_DIST:d5"` | ✅ **COVERED** |
| Temperance | d6 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_PROFIT_DIST:d6"` | ✅ **COVERED** |
| Fortitude | d7 | ✅ Yes | Contract UI: Dimension badge | `data-testid="dim:G_FTCL_PROFIT_DIST:d7"` | ✅ **COVERED** |

**Envelopes:**
- PROFIT_DISTRIBUTION_REQUEST: `data-testid="env:G_FTCL_PROFIT_DIST:{base64}"`
- PROFIT_DISTRIBUTION_TRANSACTION: `data-testid="env:G_FTCL_PROFIT_DIST:{base64}"`

**Coverage:** 5/5 dimensions + 2/2 envelopes (100%)

---

## ALL UUM-8D DIMENSIONS (GLOBAL VIEW)

| dim_key | dim_name | ui_element | selector | status |
|---------|----------|------------|----------|--------|
| d0 | Temporal | Contract UI: Global dimension list | `data-testid="dim:all:d0"` | ✅ **COVERED** |
| d1 | Spatial X | Contract UI: Global dimension list | `data-testid="dim:all:d1"` | ✅ **COVERED** |
| d2 | Spatial Y | Contract UI: Global dimension list | `data-testid="dim:all:d2"` | ✅ **COVERED** |
| d3 | Spatial Z | Contract UI: Global dimension list | `data-testid="dim:all:d3"` | ✅ **COVERED** |
| d4 | Prudence | Contract UI: Global dimension list | `data-testid="dim:all:d4"` | ✅ **COVERED** |
| d5 | Justice | Contract UI: Global dimension list | `data-testid="dim:all:d5"` | ✅ **COVERED** |
| d6 | Temperance | Contract UI: Global dimension list | `data-testid="dim:all:d6"` | ✅ **COVERED** |
| d7 | Fortitude | Contract UI: Global dimension list | `data-testid="dim:all:d7"` | ✅ **COVERED** |

**Coverage:** 8/8 dimensions (100%)

---

## FINAL COVERAGE SUMMARY

| category | covered | total | percentage | status |
|----------|---------|-------|------------|--------|
| Domains | 2 | 2 | 100% | ✅ **COMPLETE** |
| Games | 4 | 4 | 100% | ✅ **COMPLETE** |
| Game Dimensions | 20 | 20 | 100% | ✅ **COMPLETE** |
| Game Envelopes | 11 | 11 | 100% | ✅ **COMPLETE** |
| All Dimensions | 8 | 8 | 100% | ✅ **COMPLETE** |
| All Envelopes | 16 | 16 | 100% | ✅ **COMPLETE** |

**Total Coverage:** 61/61 items (100%)

---

## VERIFICATION COMMANDS

**View contract UI:**
```bash
open http://localhost:8896/contract.html
```

**Run contract coverage tests:**
```bash
cd apps/gaiaos_browser_cell
npx playwright test 30_contract_coverage.spec.ts
```

**Check manifest:**
```bash
cat apps/gaiaos_browser_cell/src/ui_contract/ui_contract_manifest.json | jq .
```

---

**END OF COVERAGE MATRIX**
