# Bundled cell stack (Docker) — not containerized Fusion

**GaiaFusion** (this macOS app) is **native Swift + Metal + embedded fusion-web**. It is **not** run inside Docker.

This folder ships **pinned copies** of the **minimal MCP C⁴ cell** used when you bring up the Linux sidecar guest (`FusionSidecarHost`) or Docker on a full **GAIAOS** tree:

- `docker-compose.fusion-sidecar.yml` — **ArangoDB** + one-shot DB/collection bootstrap (`scripts/fusion_sidecar_arango_bootstrap.sh`), **`fusion-sidecar-gateway`** + **`fusion-sidecar-tester`** (MCP ingress **:8803** in guest; `/claims` is live against `mcp_claims`, not 5xx).
- `fusion_sidecar_guest/` — systemd / virtiofs hints for the VM.

**Build contexts** in the compose file are **relative to the GAIAOS repository root** (`services/fot_mcp_gateway`, etc.). To run `docker compose` you need either:

1. A checkout of **GAIAOS** at the same revision as this app build, with this YAML at the repo root, **or**
2. virtiofs-mount the host GAIAOS tree into the Linux guest (see `deploy/mac_cell_mount/FUSION_SIDECAR_HOST_APP.md`).

Release builds refresh these files via `scripts/build_gaiafusion_composite_assets.sh` (copies this README + compose into `macos/GaiaFusion/GaiaFusion/Resources/fusion-sidecar-cell/`).

Norwich — **S⁴ serves C⁴.**
