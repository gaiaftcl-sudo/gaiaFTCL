# GaiaHealth video assets

GitHub **does not render** HTML `<video>` in wiki or repository Markdown (sanitized). **Inline players:** after [enabling GitHub Pages](#github-pages) from `/docs`, open **`https://gaiaftcl-sudo.github.io/gaiaFTCL/`** — full HTML5 `<video>` embeds. **Fallback in Markdown:** clickable poster PNG → raw MP4 (see `cells/health/wiki/Home.md`).

The CURE/state-machine MP4 is stored as a **plain git blob** (not LFS) so `raw.githubusercontent.com/.../file.mp4` works from wiki Markdown. The master export was **re-encoded (H.264/AAC)** to stay **under GitHub’s 100 MiB per-file limit**; verify integrity with **SHA-256** on [`wiki/GaiaFTCL-Health-Mac-Cell-Wiki.md`](../../../wiki/GaiaFTCL-Health-Mac-Cell-Wiki.md) after pull.

### GitHub Pages

Repo **Settings → Pages → Build and deployment**: source **Deploy from a branch**, branch **`main`**, folder **`/docs`**. Site URL: `https://gaiaftcl-sudo.github.io/gaiaFTCL/` (project site; may take ~1 min after push).

| File | Description |
|------|-------------|
| [`poster-code-as-physics.png`](./poster-code-as-physics.png) | Poster for kinematic-pipeline MP4 (wiki: click poster → raw MP4) |
| [`poster-engineering-the-cure.png`](./poster-engineering-the-cure.png) | Poster for CURE / state-machine MP4 |
| [`code-as-physics-gaiahealth-kinematic-pipeline.mp4`](./code-as-physics-gaiahealth-kinematic-pipeline.mp4) | *Code as Physics — Validating the GaiaHealth Kinematic Pipeline* |
| [`Engineering_the_CURE__The_GaiaHealth_State_Machine.mp4`](./Engineering_the_CURE__The_GaiaHealth_State_Machine.mp4) | *Engineering the CURE — The GaiaHealth State Machine* (11-state lifecycle; H.264 re-encode for repo size limit) |

**Raw MP4 (kinematic):** `https://raw.githubusercontent.com/gaiaftcl-sudo/gaiaFTCL/main/docs/media/videos/gaiahealth/code-as-physics-gaiahealth-kinematic-pipeline.mp4`  

**Raw MP4 (state machine):** `https://raw.githubusercontent.com/gaiaftcl-sudo/gaiaFTCL/main/docs/media/videos/gaiahealth/Engineering_the_CURE__The_GaiaHealth_State_Machine.mp4`

**GitHub Pages:** `https://gaiaftcl-sudo.github.io/gaiaFTCL/#health` (kinematic) · `https://gaiaftcl-sudo.github.io/gaiaFTCL/#health-cure` (CURE / state machine)

**Raw posters:** [`poster-code-as-physics.png`](https://raw.githubusercontent.com/gaiaftcl-sudo/gaiaFTCL/main/docs/media/videos/gaiahealth/poster-code-as-physics.png) · [`poster-engineering-the-cure.png`](https://raw.githubusercontent.com/gaiaftcl-sudo/gaiaFTCL/main/docs/media/videos/gaiahealth/poster-engineering-the-cure.png)
