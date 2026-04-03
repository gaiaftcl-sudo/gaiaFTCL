# GaiaFTCL CI/CD Architecture

## Current State Problem

What we pushed to `GaiaFTCL/gaia-ftcl` was a **minimal distribution package** with Python stubs - NOT the full codebase.

The REAL codebase is here: `/Users/richardgillespie/Documents/FoT8D/GAIAOS/`

## Proper CI/CD Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          GaiaFTCL CI/CD Pipeline                            │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌─────────────┐
│  Developer   │────▶│   GitHub     │────▶│   GitHub     │────▶│    GHCR     │
│  (Local)     │push │   Repo       │     │   Actions    │     │  Registry   │
└──────────────┘     └──────────────┘     └──────────────┘     └─────────────┘
                            │                    │                     │
                            │                    │                     │
                            ▼                    ▼                     ▼
                     ┌──────────────┐     ┌──────────────┐     ┌─────────────┐
                     │   Webhook    │     │   Build &    │     │   docker    │
                     │   Trigger    │     │   Test       │     │   pull      │
                     └──────────────┘     └──────────────┘     └─────────────┘
                                                │                     │
                                                ▼                     ▼
                                         ┌──────────────┐     ┌─────────────┐
                                         │   Deploy     │     │  Production │
                                         │   to Cells   │     │   (5 Cells) │
                                         └──────────────┘     └─────────────┘
```

## Repository Structure

### Option A: Monorepo (Recommended)

Push the ENTIRE GAIAOS codebase to `GaiaFTCL/gaia-ftcl`:

```
GaiaFTCL/gaia-ftcl/
├── Cargo.toml                    # Workspace root
├── Cargo.lock
├── quantum_substrate/            # Rust: 8D vQbit core
│   ├── Cargo.toml
│   └── src/
├── virtue_engine/                # Rust: Ethics scoring
│   ├── Cargo.toml
│   └── src/
├── franklin_validator/           # Rust: Constitutional validation
│   ├── Cargo.toml
│   └── src/
├── gasm_runtime/                 # Rust: GASM execution
│   ├── Cargo.toml
│   └── src/
├── services/                     # Python & Rust services
│   ├── franklin_guardian/
│   ├── fara_agent/
│   ├── gaiaos_mcp_server/
│   └── ...
├── ftcl/                         # FTCL protocol definitions
│   ├── email/
│   ├── entities/
│   └── config/
├── deploy/                       # Deployment configs
│   ├── docker/
│   └── kubernetes/
├── scripts/                      # Automation scripts
├── docker-compose.yml            # Local development
├── docker-compose.gaiaftcl-cell.yml  # Production cell
└── .github/
    └── workflows/
        ├── ci.yml                # Test on every PR
        ├── build-images.yml      # Build Docker images
        └── deploy-cells.yml      # Deploy to production
```

### Option B: Split Repos (More Complex)

```
GaiaFTCL/
├── gaia-ftcl-core/       # Rust substrate (private)
├── gaia-ftcl-services/   # Python services (private)
├── gaia-ftcl-deploy/     # Deployment configs (private)
└── gaia-ftcl/            # Public distribution
```

## CI/CD Workflows

### 1. Continuous Integration (`ci.yml`)

Runs on every push/PR:

```yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test-rust:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - run: cargo test --workspace

  test-python:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - run: pip install pytest
      - run: pytest services/

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: cargo fmt --check
      - run: cargo clippy -- -D warnings
```

### 2. Build Images (`build-images.yml`)

Builds and pushes to GHCR on main branch:

```yaml
name: Build Images

on:
  push:
    branches: [main]
    paths:
      - 'quantum_substrate/**'
      - 'virtue_engine/**'
      - 'services/**'
      - 'deploy/docker/**'

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    
    strategy:
      matrix:
        service:
          - quantum-substrate
          - virtue-engine
          - mcp-gateway
          - franklin-guardian
          - fara-agent
          - game-runner
    
    steps:
      - uses: actions/checkout@v4
      
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      
      - uses: docker/build-push-action@v5
        with:
          context: .
          file: deploy/docker/Dockerfile.${{ matrix.service }}
          push: true
          tags: ghcr.io/gaiaftcl/${{ matrix.service }}:${{ github.sha }}
```

### 3. Deploy to Cells (`deploy-cells.yml`)

Deploys to production cells:

```yaml
name: Deploy to Cells

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy'
        required: true
        default: 'production'
        type: choice
        options:
          - staging
          - production

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    
    strategy:
      matrix:
        cell:
          - {id: hel1-01, ip: 77.42.85.60}
          - {id: hel1-02, ip: 135.181.88.134}
          - {id: hel1-03, ip: 77.42.32.156}
          - {id: hel1-04, ip: 77.42.88.110}
          - {id: hel1-05, ip: 37.27.7.9}
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Deploy to ${{ matrix.cell.id }}
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ matrix.cell.ip }}
          username: root
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          script: |
            cd /root/GAIAOS
            git pull
            docker compose -f docker-compose.gaiaftcl-cell.yml pull
            docker compose -f docker-compose.gaiaftcl-cell.yml up -d
```

## Image Registry (GHCR)

All images stored at `ghcr.io/gaiaftcl/`:

| Image | Source | Port |
|-------|--------|------|
| `quantum-substrate` | `quantum_substrate/` (Rust) | 8000 |
| `virtue-engine` | `virtue_engine/` (Rust) | 8810 |
| `mcp-gateway` | `services/fot_mcp_gateway/` (Python) | 8830 |
| `franklin-guardian` | `services/franklin_guardian/` (Rust) | 8803 |
| `fara-agent` | Custom Python | 8804 |
| `game-runner` | `deploy/docker/Dockerfile.cell-all` | 8805 |
| `akg-gnn` | `services/akg_gnn/` (Rust) | 8700 |

## Deployment Commands

### From GitHub Actions (automated):
```bash
# Triggered by merge to main or manual dispatch
gh workflow run deploy-cells.yml -f environment=production
```

### Manual deployment to a cell:
```bash
# SSH to cell and pull latest
ssh -i ~/.ssh/ftclstack-unified root@77.42.85.60 '
  cd /root/GAIAOS
  git pull origin main
  docker compose -f docker-compose.gaiaftcl-cell.yml pull
  docker compose -f docker-compose.gaiaftcl-cell.yml up -d
'
```

### User installation (distribution):
```bash
# Clone distribution repo
git clone https://github.com/GaiaFTCL/gaia-ftcl.git
cd gaia-ftcl
make bootstrap
make up
```

## Next Steps

1. **Push full GAIAOS codebase** to `GaiaFTCL/gaia-ftcl`
2. **Add CI/CD workflows** for testing and building
3. **Configure GHCR** with proper image tags
4. **Set up GitHub Secrets** for SSH keys and credentials
5. **Create deployment workflow** for 5 cells

## Secrets Required

In GitHub repo settings → Secrets:

| Secret | Description |
|--------|-------------|
| `SSH_PRIVATE_KEY` | SSH key for Hetzner cells |
| `ARANGO_PASSWORD` | ArangoDB password |
| `GHCR_TOKEN` | (auto: `GITHUB_TOKEN`) |
