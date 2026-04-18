# Fusion sidecar — host app (FusionSidecarHost)

**Purpose:** Run **`FusionSidecarHost.app`** on a Mac cell, boot the Linux guest, virtiofs-mount the host checkout, and bring up the **C⁴** stack with MCP ingress on **:8803**.

**Related:** [`../../evidence/fusion_control/FUSION_SIDECAR_ACTIVE_PLAN.md`](../../evidence/fusion_control/FUSION_SIDECAR_ACTIVE_PLAN.md) · [`../../evidence/fusion_control/FUSION_SIDECAR_FIELD_OF_FIELDS.md`](../../evidence/fusion_control/FUSION_SIDECAR_FIELD_OF_FIELDS.md)

## 1. Ship the host app

1. Build **`FusionSidecarHost.app`** locally (`cells/fusion/macos/FusionSidecarHost`).
2. Distribute **not** via App Store — zip/rsync/DMG to the cell Mac (self-signed / ad hoc is expected).

## 2. First launch (Gatekeeper)

If macOS blocks launch: **Right-click → Open** once.

## 3. Guest disk / virtiofs

1. Select kernel, initrd, and root disk image in the host UI as required by your image pipeline.
2. Optional: expose the **GAIAOS / gaiaFTCL** checkout read-only via virtiofs tag **`gaiaos`** (see guest README).

## 4. Guest: compose + health

In the guest, from the mounted tree (compose ships with Fusion):

```bash
docker compose -f docker-compose.fusion-sidecar.yml up -d --build
curl -sS http://127.0.0.1:8803/health
```

Canonical compose path in-tree: [`../../macos/GaiaFusion/GaiaFusion/Resources/fusion-sidecar-cell/docker-compose.fusion-sidecar.yml`](../../macos/GaiaFusion/GaiaFusion/Resources/fusion-sidecar-cell/docker-compose.fusion-sidecar.yml)

## 5. Bundle verify (no VM)

From repo root:

```bash
VERIFY_FUSION_SIDECAR_XCODE=1 bash cells/fusion/scripts/verify_fusion_sidecar_bundle.sh
```

---

*Norwich / GaiaFTCL — S⁴ serves C⁴.*
