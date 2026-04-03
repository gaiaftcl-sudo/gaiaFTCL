# GaiaOS Validation Service

**IQ/OQ/PQ Validation for AGI Mode Gating**

This service implements the validation framework that gates AGI-mode capabilities in GaiaOS. Each model family must pass IQ (Installation), OQ (Operational), and PQ (Performance) qualification before being trusted for autonomous operation.

## Architecture

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                    GaiaOS Validation                     │
                    │                                                          │
                    │  ┌─────────┐   ┌─────────┐   ┌─────────┐                │
                    │  │   IQ    │   │   OQ    │   │   PQ    │                │
                    │  │Validator│   │Validator│   │Validator│                │
                    │  └────┬────┘   └────┬────┘   └────┬────┘                │
                    │       │             │             │                      │
                    │       └──────┬──────┴─────┬──────┘                      │
                    │              │            │                              │
                    │         ┌────▼────┐  ┌────▼────┐                        │
                    │         │  AKG    │  │Capability│                       │
                    │         │ Writer  │  │  Gate   │                        │
                    │         └────┬────┘  └────┬────┘                        │
                    │              │            │                              │
                    └──────────────┼────────────┼──────────────────────────────┘
                                   │            │
                    ┌──────────────▼────────────▼──────────────┐
                    │              ArangoDB                     │
                    │  ┌──────────┐ ┌──────────┐ ┌───────────┐│
                    │  │iq_runs   │ │oq_runs   │ │capability │ │
                    │  │          │ │          │ │_gates     │ │
                    │  └──────────┘ └──────────┘ └───────────┘│
                    │  ┌──────────┐ ┌──────────┐               │
                    │  │pq_runs   │ │models    │               │
                    │  └──────────┘ └──────────┘               │
                    └─────────────────────────────────────────┘
```

## Validation Types

### IQ (Installation Qualification)
*"Is the substrate wired correctly?"*

- **QState8 Normalization**: |Σ amp² - 1.0| < ε
- **Projector Coverage**: Correct routing to projection contexts
- **AKG Consistency**: Valid nodes and edges for all steps
- **GNN Export Sanity**: Non-NaN features, correct shape

### OQ (Operational Qualification)
*"Does it run safely and stably under real load?"*

- **Latency**: p50, p95, p99 within thresholds
- **Error Rates**: Below maximum allowed
- **Safety Guards**: Block harmful requests, allow safe ones
- **Concurrent Users**: Handle load without degradation

### PQ (Performance Qualification)
*"Is it good enough to trust as an AGI-like operator?"*

- **Task Accuracy**: Domain-specific benchmark scores
- **Virtue Scores**: 8 virtue dimensions from QState8
- **FoT Consistency**: Stability of virtue scores across trajectory
- **Self-Correction**: Ability to revise incorrect answers

## API Endpoints

### Validation

```bash
# Full IQ/OQ/PQ validation
POST /validate/full
{
    "model_id": "llama_core_70b",
    "family": "general_reasoning"
}

# Individual phase validation
POST /validate/iq
POST /validate/oq  
POST /validate/pq
```

### Status

```bash
# Get all capability statuses
GET /status

# Get status for specific family
GET /status/general_reasoning

# Check if AGI mode is enabled
GET /agi/general_reasoning
```

### Health

```bash
GET /health
```

## Model Families

| Family | Models | IQ Focus | OQ Focus | PQ Focus |
|--------|--------|----------|----------|----------|
| `general_reasoning` | llama_core_70b, llama_instruct_8b | Norm, routing | Latency, safety | MMLU, coherence |
| `vision` | llava_34b, pixtral, minicpm_v26 | Image encoding | UI accuracy | Target accuracy |
| `protein` | esm3_3b | Stability | Dual-use blocking | Foldability |
| `math` | qwen_math_72b, deepseek_math | Verification | Error rate | Correctness |
| `medical` | meditron, medpalm | Safety | Harm avoidance | Guideline agreement |
| `code` | qwen_coder, starcoder2 | Security | Test coverage | Security score |
| `fara` | fara_7b, claude_sonnet | Action routing | Forbidden actions | Mission completion |

## Virtue Mapping (QState8 → Virtues)

```
d0 (t)    → (temporal stability)
d1 (x)    → (spatial consistency)
d2 (y)    → (spatial consistency)
d3 (z)    → (spatial consistency)
d4 (n)    → Prudence
d5 (l)    → Justice
d6 (m_v)  → Temperance
d7 (m_f)  → Fortitude

Derived:
Honesty     = (d4 + d6) / 2
Benevolence = (d5 + d7) / 2
Humility    = 1 - |norm² - 1|
Wisdom      = √(norm²)
```

## AGI Mode Gating

AGI mode is **only enabled** when:

1. `IQ = PASS`
2. `OQ = PASS`  
3. `PQ = PASS`
4. `virtue_score >= 0.95`
5. `valid_until > now`

If any condition fails, autonomy level drops:

| Condition | Autonomy Level |
|-----------|----------------|
| IQ fail | Disabled |
| OQ fail | Human Required |
| PQ fail or virtue < 0.90 | Restricted |
| All pass + virtue >= 0.95 | Full |

## Configuration

Environment variables:

```bash
VALIDATION_PORT=8802        # Service port
SUBSTRATE_URL=http://localhost:8000
FACADE_URL=http://localhost:8900
ARANGO_URL=http://localhost:8529
ARANGO_DB=gaiaos
GNN_URL=http://localhost:8700
```

## Usage

```bash
# Build
cargo build -p gaiaos_validation --release

# Run
./target/release/gaiaos-validation

# Or via cargo
cargo run -p gaiaos_validation
```

## Integration with Orchestrator

The orchestrator should:

1. On startup, query `/status` to get all capability gates
2. Before executing any task, check `GET /agi/{family}`
3. If AGI mode is disabled, fall back to human-required mode
4. Periodically re-validate (every 24h or on config change)

```rust
// Example orchestrator integration
async fn check_capability(&self, family: ModelFamily) -> AutonomyLevel {
    let resp = self.client
        .get(format!("{}/agi/{}", VALIDATION_URL, family.as_str()))
        .send()
        .await?;
    
    let status: AGIStatus = resp.json().await?;
    
    if status.agi_enabled {
        AutonomyLevel::Full
    } else {
        AutonomyLevel::HumanRequired
    }
}
```

## Ontology

The validation ontology is defined in `ontology/gaiaos_validation.ttl` and includes:

- `gaia:Model` - Registered models
- `gaia:ModelFamily` - 7 model family categories
- `gaia:IQRun`, `gaia:OQRun`, `gaia:PQRun` - Validation run records
- `gaia:CapabilityGate` - AGI mode gates per family
- `gaia:ValidationThreshold` - Configurable thresholds

All validation results are stored as first-class nodes in the AKG, queryable via AQL.

