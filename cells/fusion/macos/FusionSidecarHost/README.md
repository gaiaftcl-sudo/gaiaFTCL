# FusionSidecarHost

Native macOS host for the **sovereign Fusion sidecar**: boots a **Linux VM** (Virtualization.framework) and TCP-forwards **127.0.0.1:8803** to the guest MCP gateway.

- **Operator guide:** [`../../deploy/mac_cell_mount/FUSION_SIDECAR_HOST_APP.md`](../../deploy/mac_cell_mount/FUSION_SIDECAR_HOST_APP.md)
- **Guest image:** [`../../deploy/mac_cell_mount/FUSION_SIDECAR_GUEST_IMAGE.md`](../../deploy/mac_cell_mount/FUSION_SIDECAR_GUEST_IMAGE.md)
- **Guest bootstrap (cloud-init, systemd, virtiofs):** [`../../deploy/mac_cell_mount/fusion_sidecar_guest/README.md`](../../deploy/mac_cell_mount/fusion_sidecar_guest/README.md)
- **Compose (guest):** [`../GaiaFusion/GaiaFusion/Resources/fusion-sidecar-cell/docker-compose.fusion-sidecar.yml`](../GaiaFusion/GaiaFusion/Resources/fusion-sidecar-cell/docker-compose.fusion-sidecar.yml)

## Build

```bash
cd macos/FusionSidecarHost
xcodebuild -scheme FusionSidecarHost -configuration Debug build -destination 'platform=macOS'
```

Open `FusionSidecarHost.xcodeproj` in **local Xcode** to run or Archive. **Not App Store:** ship **`FusionSidecarHost.app`** to Mac cells by zip/rsync/download; see **`../../deploy/mac_cell_mount/FUSION_SIDECAR_HOST_APP.md`** §5.

**Field of fields:** [`../../evidence/fusion_control/FUSION_SIDECAR_FIELD_OF_FIELDS.md`](../../evidence/fusion_control/FUSION_SIDECAR_FIELD_OF_FIELDS.md)

**Repo bundle verify (no VM):** `bash ../../scripts/verify_fusion_sidecar_bundle.sh` — add `VERIFY_FUSION_SIDECAR_XCODE=1` to include Xcode build.

## CLI (same surface as `scripts/fusion_surface.sh`)

From the built binary (or `xcodebuild` product), non-GUI runs delegate to bash:

```bash
GAIA_ROOT=/path/to/GAIAOS /path/to/FusionSidecarHost.app/Contents/MacOS/FusionSidecarHost --cli moor --nonstop --profile local
```

Optional `--gaia-root` instead of `GAIA_ROOT`. Optional `fusion` token after `--cli`. `--help` prints usage.
