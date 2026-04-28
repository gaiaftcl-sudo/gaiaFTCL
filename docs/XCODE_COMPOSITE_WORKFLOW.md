# Xcode Composite Workflow (Canonical Repo)

This runbook defines the single supported local development entrypoint.

## Canonical repo

- `/Users/richardgillespie/Documents/GaiaFTCL-MacCells/gaiaFTCL`

Do not develop or push from `/Users/richardgillespie/Documents/FoT8D`.

## Open in Xcode

- Workspace: `cells/xcode/GaiaComposite.xcworkspace`
- Canonical console project: `cells/fusion/macos/GaiaFTCLConsole/GaiaFTCLConsole.xcodeproj`

## Deterministic build/test/sprout path

1. Run health gate:
   - `scripts/repo_health_gate.sh`
2. Run composite workflow:
   - `scripts/run_xcode_composite_sprout.sh`
3. In Xcode workspace, build and run the needed schemes.

## Drift prevention

- Never commit timestamped runtime trees:
  - `runtime/sprout-cells/`
  - `runtime/local-run/`
  - `evidence/runs/`
- Never keep duplicate numbered project directories (`GaiaFTCLConsole 2+`).
