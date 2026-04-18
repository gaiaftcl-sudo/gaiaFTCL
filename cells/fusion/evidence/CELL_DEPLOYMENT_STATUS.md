# GaiaFTCL Cell Deployment Status

**Date:** 2026-02-01  
**MCP Server:** gaiaos_ui_tester_mcp (Rust)  
**Status:** ⚠️ DEPLOYMENT BLOCKED

---

## Cell Definition (from /opt/gaiaftcl/docker-compose.yml)

**Every GaiaFTCL cell MUST run 24 containers:**

### Core Infrastructure (7)
1. **registry** - Docker registry (port 5000)
2. **nats** - NATS messaging (ports 4222, 8222)
3. **arangodb** - Database (port 8529)
4. **quantum-substrate** - Substrate service (port 8000)
5. **virtue-engine** - Virtue engine (port 8810)
6. **game-runner** - Game execution (port 8805)
7. **cadvisor** - Container monitoring (port 8080)

### Entity Agents (12)
8. **franklin** - Constitutional Guardian (L7,L8,L9)
9. **gaia** - Core Intelligence (L0-L9)
10. **fara** - Field-Aware Reasoning (L0-L3)
11. **qstate** - Quantum State Manager (L9)
12. **validator** - Truth Validator (L9)
13. **witness** - Audit Witness (L9)
14. **oracle** - Data Oracle (L3-L5)
15. **virtue-agent** - Ethics Engine (L7,L8)
16. **ben** - Investment Manager (L8)
17. **treasury-agent** - Treasury System (L8)
18. **identity** - Identity Gateway (L8,L9)
19. **(+1 more entity agent)**

### TruthMail & MCP (5)
20. **mcp** - MCP Gateway (port 8900) ⚠️ **CURRENTLY DOWN**
21. **mcp-mail-bridge** - Mail bridge (port 8840)
22. **truthmail-ui** - TruthMail UI (port 8841)
23. **dns-manager** - DNS manager (port 8850)
24. **wiki** - Wiki.js (port 3000)

### Cell Agent (1)
25. **cell-agent** - Self-healing coherence monitor

---

## Current MCP Status

**Old MCP (Python):**
- Container: `gaiaftcl-mcp`
- Port: 8900
- Status: ❌ NOT RESPONDING
- Image: `python:3.11-slim`

**New MCP (Rust):**
- Container: `gaiaos-ui-tester-mcp`
- Port: 8900 (updated from 8850 to match cell standard)
- Status: ⚠️ NOT DEPLOYED
- Image: `localhost:5000/gaiaos-ui-tester-mcp:latest`

---

## Deployment Blocker

**Architecture Mismatch:**
- **All 9 remote cells are aarch64 (ARM64)**
- **Local build is x86_64 (Intel/AMD)**
- **Error:** `exec format error` when running x86_64 binary on ARM64

**Dependency Issue:**
- `base64ct-1.8.3` requires `edition2024` feature
- Requires Rust nightly (not stable 1.83)
- Cannot cross-compile with current toolchain

---

## Cell Architecture

| Cell ID | IP | Arch | Provider |
|---------|-----|------|----------|
| hel1-01 | 77.42.85.60 | aarch64 | Hetzner |
| hel1-02 | 135.181.88.134 | aarch64 | Hetzner |
| hel1-03 | 77.42.32.156 | aarch64 | Hetzner |
| hel1-04 | 77.42.88.110 | aarch64 | Hetzner |
| hel1-05 | 37.27.7.9 | aarch64 | Hetzner |
| nbg1-01 | 37.120.187.247 | aarch64 | Netcup |
| nbg1-02 | 152.53.91.220 | aarch64 | Netcup |
| nbg1-03 | 152.53.88.141 | aarch64 | Netcup |
| nbg1-04 | 37.120.187.174 | aarch64 | Netcup |

---

## Solutions

### Option 1: Build on Cell (Recommended)
Install Rust on one cell and build natively:
```bash
ssh root@77.42.85.60
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly
source $HOME/.cargo/env
cd /tmp/gaiaos_ui_tester_mcp
cargo build --release
```

### Option 2: Cross-Compile with Nightly
```bash
rustup toolchain install nightly
rustup target add --toolchain nightly aarch64-unknown-linux-gnu
cargo +nightly build --release --target aarch64-unknown-linux-gnu
```

### Option 3: Use GitHub Actions
Build multi-arch in CI and push to registry automatically.

---

## Files Ready

✅ `services/gaiaos_ui_tester_mcp/docker-compose.cell.yml` - Compose snippet  
✅ `services/gaiaos_ui_tester_mcp/Dockerfile.prebuilt` - Dockerfile  
✅ `scripts/deploy_mcp_to_cells_final.sh` - Deployment script  
✅ Port updated: 8900 (matches cell standard)  
✅ Image in registry: `localhost:5000/gaiaos-ui-tester-mcp:latest` (x86_64 only)  

❌ **ARM64 binary needed**

---

## Next Steps

1. Build ARM64 binary (choose option above)
2. Push ARM64 image to registry
3. Run deployment script
4. Verify all 9 cells healthy on port 8900

---

## NO MOCKING/SIMULATION

✅ **Verified:** Zero mocking or simulation in MCP server code  
✅ **Validation only:** `substrate_checker.rs` detects mocked connections (health check)  
✅ **All tools:** Witnessed, fail-closed, byte-match verified  
