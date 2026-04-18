# GaiaOS Dimensional Viewer

**Quantum 8D → 3D Projection with Virtue Gating**

A GaiaOS-native container that projects 8-dimensional UUM quantum coordinates to 3D viewer space while preserving maximum coherence. All projections are virtue-gated through Franklin Guardian.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   gaiaos-dimensional-viewer                     │
│  ┌──────────────┐    ┌──────────────┐    ┌─────────────────┐   │
│  │   Substrate  │───▶│  Projection  │───▶│  Virtue Gate    │   │
│  │   Client     │    │   Operator   │    │  (Franklin)     │   │
│  └──────────────┘    └──────────────┘    └─────────────────┘   │
│         ▲                   │                    │             │
│         │                   ▼                    ▼             │
│  ┌──────┴──────┐    ┌──────────────┐    ┌─────────────────┐   │
│  │  Quantum    │    │ ViewResponse │    │  WebSocket/REST │   │
│  │  Substrate  │    │ + Coherence  │    │  API            │   │
│  │  (8D data)  │    │   Tracking   │    │  (port 8750)    │   │
│  └─────────────┘    └──────────────┘    └─────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Key Features

| Feature | Description |
|---------|-------------|
| **Quantum-Native** | Reads 8D coordinates from substrate |
| **Virtue-Gated** | All projections validated by Franklin Guardian |
| **Coherence-Tracked** | Every projection reports information loss |
| **Performance-Specified** | 10K points/sec, <100ms latency |

## Quick Start

### Local Development

```bash
# Build and run with mock services
docker-compose up --build

# Access the viewer
open http://localhost:8750
```

### Integration with GaiaOS

Add to your main `docker-compose.yml`:

```yaml
services:
  gaiaos-dimensional-viewer:
    image: gaiaos/dimensional-viewer:latest
    container_name: gaiaos-dimensional-viewer
    restart: unless-stopped
    depends_on:
      - gaiaos-substrate
      - gaiaos-franklin-guardian
    environment:
      - SUBSTRATE_URL=http://gaiaos-substrate:8000
      - FRANKLIN_GUARDIAN_URL=http://gaiaos-franklin-guardian:8803
      - DEFAULT_VIRTUE_THRESHOLD=0.90
      - DEFAULT_DIMENSION_MAP=0,2,5
    ports:
      - "8750:8750"
    networks:
      - gaiaos-net
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Bevy WASM UI |
| `/health` | GET | Health check with dependency status |
| `/api/dependencies` | GET | Dependency connectivity status |
| `/api/project` | POST | Generate projected view |
| `/ws` | WebSocket | Real-time projection stream |
| `/metrics/coherence` | GET | Coherence metrics |

## Projection API

### POST /api/project

Request:
```json
{
  "cell_id": "cell-001",
  "layer_filter": {"layer_name": "vQbit"},
  "dimension_map": [0, 2, 5],
  "virtue_threshold": 0.90,
  "max_points": 1000
}
```

Response:
```json
{
  "layers": [
    {
      "name": "vQbit",
      "points": [
        {
          "position": [1.2, 0.5, 2.1],
          "original_coord": [1.2, 0.0, 0.5, 0.0, 0.0, 2.1, 0.0, 0.0],
          "coherence": 0.92
        }
      ],
      "virtue_scores": [0.95],
      "coherence_avg": 0.92
    }
  ],
  "metadata": {
    "total_points_8d": 5000,
    "points_displayed": 847,
    "virtue_pass_rate": 0.1694,
    "avg_coherence": 0.87,
    "projection_time_ms": 42.3
  }
}
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DIMENSIONAL_VIEWER_PORT` | `8750` | HTTP server port |
| `SUBSTRATE_URL` | `http://gaiaos-substrate:8000` | Quantum substrate URL |
| `FRANKLIN_GUARDIAN_URL` | `http://gaiaos-franklin-guardian:8803` | Franklin Guardian URL |
| `DEFAULT_VIRTUE_THRESHOLD` | `0.90` | Default virtue threshold |
| `DEFAULT_DIMENSION_MAP` | `0,2,5` | Default dimensions to display |
| `MAX_POINTS_PER_VIEW` | `10000` | Maximum points per view |
| `RUST_LOG` | `info` | Log level |

## IQ/OQ/PQ Validation

### Installation Qualification (IQ)

```bash
# Container builds and starts
docker build -t gaiaos/dimensional-viewer:latest .
docker run -d -p 8750:8750 gaiaos/dimensional-viewer:latest

# Health endpoint responds
curl http://localhost:8750/health
# Expected: {"status":"healthy","service":"dimensional-viewer",...}
```

### Operational Qualification (OQ)

```bash
# 8D → 3D projection works
curl -X POST http://localhost:8750/api/project \
  -H "Content-Type: application/json" \
  -d '{"dimension_map": [0, 2, 5], "virtue_threshold": 0.90}'

# Virtue gating enforced
# Higher threshold = fewer points displayed
```

### Performance Qualification (PQ)

| Metric | Target |
|--------|--------|
| Projection throughput | ≥10,000 points/sec |
| Concurrent requests | ≥50 simultaneous |
| Average coherence | ≥0.85 |
| Projection latency | <100ms for 1000 points |
| Memory usage | <2GB sustained |

## Mathematical Foundation

### Projection Operator

The projection operator maps 8D UUM coordinates to 3D viewer space:

```rust
pub fn project(&self, coord_8d: &[f32; 8]) -> ProjectedPoint {
    let vec8 = Vector8::from_row_slice(coord_8d);
    let vec3 = self.projection_matrix * vec8;
    
    let coherence_loss = self.compute_coherence_loss(coord_8d);
    
    ProjectedPoint {
        position: [vec3[0], vec3[1], vec3[2]],
        original_coord: *coord_8d,
        coherence: 1.0 - coherence_loss,
    }
}
```

### Coherence Calculation

Coherence measures information preserved in the projection:

```
coherence = 1 - (hidden_energy / total_energy)
```

Where `hidden_energy` is the sum of squared values in non-displayed dimensions.

## UI Controls

- **Left Mouse Button**: Rotate camera
- **Right Mouse Button**: Pan camera
- **Scroll Wheel**: Zoom in/out

## Dependency Graph

```
Infrastructure (NATS, ArangoDB, Ollama)
    ↓
Quantum Layer (Substrate, vChip, Brain) ← SOURCE
    ↓
Intelligence (GNN, Spatial Gateway, LLM Router, Dimensional Viewer) ← THIS
    ↓                                           ↑
Safety (Franklin Guardian, Validator, Virtue) ← GATE
    ↓
Orchestration (Core Agent, Quantum Facade, Validation)
```

## License

Part of the GaiaOS project.
