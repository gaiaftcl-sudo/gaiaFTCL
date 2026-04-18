# Canonical media bundle (GaiaFTCL repo)

This folder holds **curated** binary assets referenced from documentation: **video (Git LFS)**, **images**, and **PDFs**. Paths are stable for links in Markdown and GitHub rendering.

## Layout

| Path | Kind | Notes |
|------|------|--------|
| `video/*.mp4` | Video | Git LFS — QMOV therapeutic clips (copied from local BenOS data path; BenOS tree remains gitignored). |
| `images/*.png` | Screenshot | Tokamak UI + Fusion dashboard (README + wiki landing). |
| `pdf/*.pdf` | Documents | Local copies from `~/Documents` (see manifest for sources). |

## Manifest (SHA-256)

Run `shasum -a 256 docs/media/**/*` locally to refresh. Values below were captured at bundle creation.

| Relative path | SHA-256 | Notes |
|---------------|---------|--------|
| `video/hope_for_aml.mp4` | `3f947a9889389f2f0d59a85426ef5fd09d54a40b2d186fb22eb912d3b941a6ef` | QMOV clip (LFS). |
| `video/leukemia_therapeutics.mp4` | `a88d7ee8aa6f01b72ea8abf2c48a724afe95a1ea0f77268e70524f2dca642302` | QMOV clip (LFS). |
| `images/fusion-dashboard.png` | `20be873d66546b39cac48e03f9c7df8367f5e5d3212fecbd315059ce2cb0f4d4` | Fusion dashboard witness. |
| `images/gaiafusion-ui-tokamak-20260414.png` | `c0be4b6ebb71acc66b5e73f0e578727e1413855079e980464631c6d75d79714a` | Tokamak UI (aligned with wiki `images/`). |
| `pdf/labinstructions.pdf` | `888c6f1aa6f184467b41e327eb7048e27681a171504455615189fa8a127d71f6` | Source: `~/Documents/labinstructions.pdf` |
| `pdf/quantum_closure_proof.pdf` | `fe4b8b1ea8b812ed7635645ed747c23a1e42beadbf689c6b419ddba98d2aa4b6` | Source: `~/Documents/quantum_closure_proof.pdf` |

## Git LFS

MP4 files use Git LFS (see root `.gitattributes`). After clone, run:

```bash
git lfs install
git lfs pull
```
