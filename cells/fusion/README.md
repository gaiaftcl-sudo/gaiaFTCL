<p align="center">
  <img src="assets/branding/gaiaos-icon-256.png" alt="GaiaOS Logo" width="200">
</p>

# GaiaOS - Field of Truth Operating System

**Metal GPU (MPS-GNN) + 8D Quantum @ 800 Hz + 15,154 Exam Questions + Production UI**

---

## FINAL UI DOCS + EVIDENCE (CLICK)

- `OPEN_THESE_DOCS_FIRST.md`
- `doc/BROWSER_CELL_UI_FINAL.md`
- `apps/gaiaos_browser_cell/doc/UI_ALL_WORLDS_FINAL.md`
- `apps/gaiaos_browser_cell/validation_artifacts/LATEST/INDEX.md`

## Quick Start (Mac)

```bash
./start_gaiaos.sh
```

Opens: http://localhost:3000

**That's it. Everything works.**

---

## What's Included

| Component | Port | Purpose |
|-----------|------|---------|
| **Open WebUI** | 3000 | 🎯 **Main interface** (multimodal, 50+ languages) |
| ArangoDB | 8529 | Knowledge base (15,154 questions) |
| Ollama | 11434 | LLM engine (gaia, franklin, llava, llama3.1) |
| Substrate | 8888 | 8D quantum @ 800 Hz (Metal GPU) |
| Visual Server | 9000 | 3D rendering + exam recording |
| GaiaFS | 8100 | Quantum filesystem |

---

## Installation

### Mac (DMG)

```bash
# Build DMG
cd installer
./create_full_dmg.sh

# Install
open build/full/GaiaOS-Full-1.0.0.dmg
# Drag to Applications, double-click
```

### Hetzner (From GaiaOS ISO)

```bash
# After booting from GaiaOS ISO, run:
/opt/gaiaos/deploy/add_webui.sh
```

### Development (Local Docker)

```bash
# Start full stack
./start_gaiaos.sh

# Stop
./stop_gaiaos.sh
```

---

## Features

### ✅ Multimodal AI Chat
- Text, images, PDFs, audio, video
- Streaming responses
- Multiple models (switch on the fly)

### ✅ Professional Exams
- 87 certification exams
- 15,154 exam questions
- USMLE, Bar Exam, PE, CFA, etc.
- Full video recordings

### ✅ Multilingual
- 50+ languages built-in
- Auto-detect user language
- RTL support

### ✅ Voice I/O
- Speech-to-text input
- Text-to-speech output
- Character voices (GAIA, Franklin)

### ✅ Knowledge Base
- ArangoDB with full exam catalog
- RAG document upload
- Semantic search

---

## Project Structure

```
cells/fusion/
├── installer/
│   ├── create_full_dmg.sh       # Mac DMG builder
│   └── create_dmg.sh            # Basic DMG (deprecated)
├── deploy/
│   ├── add_webui.sh             # Hetzner deployment
│   └── README.md                # Deployment docs
├── arango/
│   ├── docker-compose.yml       # ArangoDB container
│   ├── start_container.sh       # Start script
│   └── import_exam_knowledge.js # Import 15k questions
├── exam-video/
│   └── src/                     # Exam recording system
├── models/
│   ├── gaia.modelfile           # GAIA character
│   └── franklin.modelfile       # Ben Franklin character
├── docker-compose.yml           # Full stack (all services)
├── start_gaiaos.sh              # ⭐ ONE-COMMAND START
├── stop_gaiaos.sh               # Clean shutdown
└── README.md                    # This file
```

---

## Development

### Start Stack

```bash
./start_gaiaos.sh
```

Services start in order:
1. ArangoDB (knowledge base)
2. Ollama (LLM engine)
3. Open WebUI (web interface)

Browser opens to http://localhost:3000

### Check Status

```bash
docker-compose ps

# Should show:
# gaiaos-arangodb   healthy
# gaiaos-ollama     healthy
# gaiaos-webui      healthy
```

### View Logs

```bash
docker-compose logs -f
```

### Add Custom Models

```bash
# Create GAIA model
docker exec gaiaos-ollama ollama create gaia -f /models/gaia.modelfile

# Create Franklin model
docker exec gaiaos-ollama ollama create franklin -f /models/franklin.modelfile
```

### Import Knowledge

```bash
node arango/import_exam_knowledge.js
```

Imports 15,154 exam questions from qFoT.

---

## Deployment

### To Hetzner (Existing GaiaOS Server)

```bash
# From Mac, deploy to your server
ssh root@91.98.4.153 'bash -s' < deploy/add_webui.sh
```

### To New Hetzner Server (GaiaOS ISO)

1. Boot server from GaiaOS ISO
2. SSH to server
3. Run: `/opt/gaiaos/deploy/add_webui.sh`

---

## Usage

### Access Web UI

**Local**: http://localhost:3000  
**Hetzner**: http://YOUR_SERVER_IP:3000

### First Time Setup

1. Open web UI
2. Register first user (becomes admin)
3. Select model: `gaia` or `franklin` or `llava`
4. Start chatting!

### Multimodal Chat

```
User: [uploads image] "What's in this medical scan?"
GAIA: [analyzes via llava model] "This appears to be..."
```

### Exam System

```
User: "Run the USMLE Step 1 exam"
System: [loads 280 questions from ArangoDB]
        [records Franklin answering]
        [saves to MP4]
```

---

## Architecture

### Mac (Local Development)

```
Docker Desktop / OrbStack
  ├─ gaiaos-arangodb (knowledge)
  ├─ gaiaos-ollama (LLM)
  └─ gaiaos-webui (interface)
       ↓
Browser: http://localhost:3000
```

### Hetzner (Production)

```
GaiaOS ISO
  ├─ Docker (built-in hypervisor)
  │   ├─ gaiaos-arangodb
  │   ├─ gaiaos-ollama
  │   └─ gaiaos-webui
  └─ nginx (reverse proxy)
       ↓
Internet: https://gaiaos.cloud
```

---

## Requirements

### Mac
- macOS 14.0+
- **Metal-capable GPU** (M1/M2/M3 or Intel 2012+)
- Docker Desktop or OrbStack
- 16GB RAM (32GB recommended)
- 10GB free disk

### Hetzner
- GaiaOS ISO installed
- Docker available
- 8+ vCPU (CCX33 recommended)
- 32GB+ RAM

---

## Troubleshooting

### Services won't start

```bash
# Check Docker
docker ps -a

# Check logs
docker-compose logs

# Restart
docker-compose restart
```

### Can't access web UI

```bash
# Check if Open WebUI is running
curl http://localhost:3000

# Check if port is bound
lsof -i :3000

# Restart Open WebUI
docker restart gaiaos-webui
```

### Models not showing

```bash
# Check Ollama
docker exec gaiaos-ollama ollama list

# Pull models manually
docker exec gaiaos-ollama ollama pull llava:latest
```

---

## Build from Source

### Mac DMG

```bash
cd installer
./create_full_dmg.sh

# Wait 10-15 minutes (compiles all Rust services)
# Output: build/full/GaiaOS-Full-1.0.0.dmg
```

### Components Built

- `substrate-darwin` - 8D consciousness runtime
- `gaiaos_visual_server` - 3D visualization
- `gaiafs` - Quantum filesystem
- `exam-video` - Professional exam recorder

All bundled with ArangoDB + Ollama + Open WebUI.

---

## Status

✅ **ArangoDB** - Knowledge base with 15,154 questions  
✅ **Ollama** - Local LLM engine  
✅ **Open WebUI** - Production-ready interface  
✅ **Exam System** - 87 professional certification exams  
✅ **Voice Engine** - Character-conditioned TTS  
✅ **Metal Renderer** - 3D visualization  
✅ **Docker Integration** - Unified stack  
✅ **Mac DMG** - Complete installer  
✅ **Hetzner Deployment** - Production scripts  

---

## Support

**Documentation**:
- `/STACK_INTEGRATION.md` - Architecture overview
- `/ARANGODB_CONTAINER_SETUP.md` - Knowledge base details
- `/deploy/README.md` - Deployment guide

**Issues**:
- Open WebUI: https://github.com/open-webui/open-webui
- GaiaOS: https://gaiaos.net

---

**GaiaOS is now a complete, production-ready AI operating system with a professional user interface.**

