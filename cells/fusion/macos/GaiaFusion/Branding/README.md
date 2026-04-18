# GaiaFusion branding (C4)

## Masters (authoritative inputs)

| Asset | SHA256 |
|-------|--------|
| `sources/app_icon_master.png` | `77e552eca11cc2f40e2a0f0c3e494cca124a0fe2c3605c2bca468e60a4d64258` |
| `sources/splash_master.png` | `1cca1d25c7c4336540b05980c197d1d19d197297444776b289a616299beebff4` |

## Derived artifacts (regenerate — do not hand-edit)

Run:

`bash cells/fusion/scripts/generate_gaiafusion_branding_assets.sh`

Outputs:

- `generated/AppIcon.iconset/` — intermediate for `iconutil`
- `GaiaFusion/Resources/Branding/AppIcon.icns` — SHA256 `44173d2766774c77b573fcb02fd585c405883897ef583d0f0782c58c34774347` (receipt at generation time; re-run script updates)
- `GaiaFusion/Resources/Branding/Splash.imageset/splash@1x.png` — SHA256 `08b427d678d5527abb3168fef78f132807989b91534e26bd471d3a7b0bb7d135`
- `GaiaFusion/Resources/Branding/Splash.imageset/splash@2x.png` — (see `shasum` after generation)

`package_gaiafusion_app.sh` copies `AppIcon.icns` to `Contents/Resources/` and sets `CFBundleIconFile` = `AppIcon`.
