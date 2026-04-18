# GaiaOS UI Web

GaiaOS Multi-Substrate Digital Twin — Field substrate dashboard for Atmosphere, Ocean, Biosphere, Molecular, Astro, closure proofs, and aviation entropy.

## User Guide

**[USER_GUIDE.md](./USER_GUIDE.md)** — Full user guide with narratives for every page, wallet flow, games, and troubleshooting.

## Quick Start

**Terminal 1 — MCP server (required for Closure Game, Domain Tubes):**

```bash
cd cells/fusion/services/gaiaos_ui_tester_mcp
MCP_PORT=8901 cargo run
```

**Terminal 2 — Web app:**

```bash
cd cells/fusion/services/gaiaos_ui_web
MCP_BASE_URL=http://localhost:8901 npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Run Tests

**One command (from GAIAOS root):**

```bash
./scripts/validate_ui.sh
```

**Or manually:** Start MCP (`cd services/gaiaos_ui_tester_mcp && MCP_PORT=8901 cargo run`), then:

```bash
MCP_BASE_URL=http://localhost:8901 npm run test:e2e:full
```

See [USER_GUIDE.md](./USER_GUIDE.md#running-tests) for details.

## Scripts

| Script | Description |
|--------|-------------|
| `npm run dev` | Start Next.js dev server |
| `npm run build` | Production build |
| `npm run start` | Start production server |
| `npm run test:e2e` | Playwright tests (default MCP URL) |
| `npm run test:e2e:full` | Playwright tests with MCP at 8901 |
