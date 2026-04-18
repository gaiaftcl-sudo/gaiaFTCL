# UI COVERAGE SOURCE MAP

**Purpose:** Canonical registry of domains, games, envelopes, and UUM-8D dimensions with exact source paths.

**Branch:** phase-a-baseline  
**Date:** 2026-01-31

---

## 1. DOMAINS

**Primary Source:** `services/gaiaos_ui/src/api/domains.rs` (lines 1-100)

**Loading Strategy:**
1. ArangoDB Knowledge Graph (`gaiaos_domains` collection)
2. Fallback: `config/domains.json`
3. Minimal defaults if both fail

**Structure:**
```rust
pub struct DomainMeta {
    pub id: String,
    pub label: String,
    pub color: String,
    pub icon: String,
    pub priority: i32,
    pub description: String,
    pub risk_tier: String,
    pub virtue_requirements: VirtueRequirements,
}
```

**Virtue Requirements:**
- `honesty: Option<f64>`
- `justice: Option<f64>`
- `prudence: Option<f64>`
- `temperance: Option<f64>`
- `beneficence: Option<f64>`

**Cell Registry:** `ftcl/config/cell_registry.json`

### Domain Inventory (from tracked sources)

| domain_id | domain_name | version | source_path |
|-----------|-------------|---------|-------------|
| FTCL | Field Truth Closure Layer | 1.0 | `services/gaiaos_ui/src/api/domains.rs` |
| (loaded dynamically from ArangoDB or config) | (runtime) | (runtime) | `config/domains.json` (fallback) |

---

## 2. GAMES

**Primary Source:** `ftcl/games/` directory

**Game Registry Loader:** `services/gaiaos_game_runner/src/main.rs` (lines 1840-1864)

**Loading Path:** `ftcl/ui_validation/game_registry/` directory

**Structure:**
```rust
pub struct GameGraphPackage {
    pub meta: serde_json::Value,
    pub game_graph: serde_json::Value,
    pub invariants: serde_json::Value,
    pub measurement_procedures: serde_json::Value,
    pub ui_contract: serde_json::Value,
    pub agent_contract: serde_json::Value,
}
```

### Game Inventory (from tracked sources)

| game_id | domain_id | game_name | source_path |
|---------|-----------|-----------|-------------|
| G_FTCL_UPDATE_FLEET_V1 | FTCL | Fleet Update | `ftcl/games/G_FTCL_UPDATE_FLEET_V1.yaml` |
| G_FTCL_ROLLBACK_V1 | FTCL | Fleet Rollback | `ftcl/games/G_FTCL_ROLLBACK_V1.yaml` |
| G_FTCL_INVEST_001 | FTCL | Investment Acquisition | `ftcl/games/G_FTCL_INVEST_001.yaml` |
| G_FTCL_PROFIT_DIST | FTCL | Profit Distribution | `ftcl/games/G_FTCL_PROFIT_DIST.yaml` |

---

## 3. ENVELOPES

**Primary Source:** Workspace rules (`.cursorrules`) + Game YAML definitions

**Canonical Envelope Types (from .cursorrules):**
- `MAIL`
- `COMMITMENT`
- `IDENTITY`
- `OBLIGATION`
- `MOVE`
- `PROOF`

**Game-Specific Envelope Types (from ftcl/games/*.yaml):**
- `REQUEST` - Proposal/request moves
- `COMMITMENT` - Binding commitment moves
- `TRANSACTION` - Payment/execution moves
- `REPORT` - Status/reporting moves
- `CLAIM` - Claim/assertion moves

**Envelope Structure:**
```yaml
envelope:
  X-FTCL-Type: <TYPE>
  X-FTCL-Game: <GAME_ID>
  X-FTCL-Domain: <DOMAIN>
  X-FTCL-Cost: <AMOUNT>
  X-FTCL-Value-ID: <sha256 hash>
```

### Envelope Inventory (from tracked sources)

| envelope_subject | envelope_type | producer_game_id | source_path |
|------------------|---------------|------------------|-------------|
| FLEET_UPDATE_REQUEST | REQUEST | G_FTCL_UPDATE_FLEET_V1 | `ftcl/games/G_FTCL_UPDATE_FLEET_V1.yaml` |
| FLEET_UPDATE_COMMITMENT | COMMITMENT | G_FTCL_UPDATE_FLEET_V1 | `ftcl/games/G_FTCL_UPDATE_FLEET_V1.yaml` |
| FLEET_UPDATE_TRANSACTION | TRANSACTION | G_FTCL_UPDATE_FLEET_V1 | `ftcl/games/G_FTCL_UPDATE_FLEET_V1.yaml` |
| FLEET_UPDATE_REPORT | REPORT | G_FTCL_UPDATE_FLEET_V1 | `ftcl/games/G_FTCL_UPDATE_FLEET_V1.yaml` |
| ROLLBACK_REQUEST | REQUEST | G_FTCL_ROLLBACK_V1 | `ftcl/games/G_FTCL_ROLLBACK_V1.yaml` |
| ROLLBACK_COMMITMENT | COMMITMENT | G_FTCL_ROLLBACK_V1 | `ftcl/games/G_FTCL_ROLLBACK_V1.yaml` |
| ROLLBACK_TRANSACTION | TRANSACTION | G_FTCL_ROLLBACK_V1 | `ftcl/games/G_FTCL_ROLLBACK_V1.yaml` |
| INVESTMENT_CLAIM | CLAIM | G_FTCL_INVEST_001 | `ftcl/games/G_FTCL_INVEST_001.yaml` |
| INVESTMENT_COMMITMENT | COMMITMENT | G_FTCL_INVEST_001 | `ftcl/games/G_FTCL_INVEST_001.yaml` |
| PROFIT_DISTRIBUTION_REQUEST | REQUEST | G_FTCL_PROFIT_DIST | `ftcl/games/G_FTCL_PROFIT_DIST.yaml` |
| PROFIT_DISTRIBUTION_TRANSACTION | TRANSACTION | G_FTCL_PROFIT_DIST | `ftcl/games/G_FTCL_PROFIT_DIST.yaml` |
| (generic) | MAIL | (any) | `.cursorrules` (workspace rules) |
| (generic) | IDENTITY | (any) | `.cursorrules` (workspace rules) |
| (generic) | OBLIGATION | (any) | `.cursorrules` (workspace rules) |
| (generic) | MOVE | (any) | `.cursorrules` (workspace rules) |
| (generic) | PROOF | (any) | `.cursorrules` (workspace rules) |

---

## 4. UUM-8D DIMENSIONS

**Primary Source:** `services/franklin_guardian/src/lib.rs` (lines 45-56)

**Canonical Structure:**
```rust
pub struct QState8 {
    pub d0: f64, // t - temporal
    pub d1: f64, // x - spatial x
    pub d2: f64, // y - spatial y
    pub d3: f64, // z - spatial z
    pub d4: f64, // n - prudence
    pub d5: f64, // l - justice
    pub d6: f64, // m_v - temperance
    pub d7: f64, // m_f - fortitude
}
```

### UUM-8D Dimension Inventory

| dim_key | dim_name | source_path |
|---------|----------|-------------|
| d0 | Temporal (t) | `services/franklin_guardian/src/lib.rs:47` |
| d1 | Spatial X (x) | `services/franklin_guardian/src/lib.rs:48` |
| d2 | Spatial Y (y) | `services/franklin_guardian/src/lib.rs:49` |
| d3 | Spatial Z (z) | `services/franklin_guardian/src/lib.rs:50` |
| d4 | Prudence (n) | `services/franklin_guardian/src/lib.rs:51` |
| d5 | Justice (l) | `services/franklin_guardian/src/lib.rs:52` |
| d6 | Temperance (m_v) | `services/franklin_guardian/src/lib.rs:53` |
| d7 | Fortitude (m_f) | `services/franklin_guardian/src/lib.rs:54` |

**Virtue Mapping (from domains.rs):**
- Honesty (not directly mapped to d0-d7)
- Justice → d5
- Prudence → d4
- Temperance → d6
- Beneficence (not directly mapped to d0-d7)
- Fortitude → d7

---

## VERIFICATION COMMANDS

**Domains:**
```bash
rg "DomainMeta|domains\.json" services/gaiaos_ui/src/api/domains.rs
```

**Games:**
```bash
ls -la ftcl/games/*.yaml
rg "game_id|GameGraphPackage" services/gaiaos_game_runner/src/main.rs
```

**Envelopes:**
```bash
rg "X-FTCL-Type|envelope" ftcl/games/*.yaml
rg "MAIL|COMMITMENT|IDENTITY|OBLIGATION|MOVE|PROOF" .cursorrules
```

**UUM-8D:**
```bash
rg "QState8|d0.*d1.*d2.*d3.*d4.*d5.*d6.*d7" services/franklin_guardian/src/lib.rs
```

---

**END OF SOURCE MAP**
