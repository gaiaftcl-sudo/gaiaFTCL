# GaiaFTCL Dual-User Validation
- ts_utc: 20260407T115317Z
- out_dir: /Users/richardgillespie/Documents/FoT8D/cells/fusion/evidence/discord/dual_user/20260407T115317Z
- owl_channel: https://discord.com/channels/1487775674356990064/1487775675665354835
- observer_channel: https://discord.com/channels/1487775674356990064/1487775675665354835
- user_a_channel: https://discord.com/channels/1487775674356990064/1487775675665354835
- user_b_channel: https://discord.com/channels/1487775674356990064/1487775675665354835
- phase2_hook: bash /Users/richardgillespie/Documents/FoT8D/cells/fusion/scripts/dual_user_phase2_hook.sh

## No-simulation gate
🔍 Running Simulation Detection Audit...
[0;32m✅ NO SIMULATION CODE DETECTED[0m

## Command force-refresh gate
REFRESH_FAIL app GET 401
REFRESH owl app_id=1490456471811653874 get=200 put=200 count=5 source=guild
REFRESH governance app_id=1490456095649431745 get=200 put=200 count=8 source=guild

## Witness preflight

## Dual-user Playwright run

> gaiaos_ui_web@0.1.0 test:e2e:discord:dual-user
> sh -c 'unset CI 2>/dev/null; DISCORD_DUAL_USER_RUN=1 playwright test --config=playwright.discord.config.ts --grep "Dual-user sovereign handshake" --headed'


Running 1 test using 1 worker

  ✓  1 [chromium] › tests/discord/discord_dual_user_validation.spec.ts:127:7 › Dual-user sovereign handshake › live moorer + observer convergence (38.1s)

  1 passed (40.0s)

## Hard invariant gate
WITNESS: /Users/richardgillespie/Documents/FoT8D/cells/fusion/evidence/discord/dual_user/20260407T115317Z/DUAL_USER_WITNESS.json
user_a_source=gaiaftcl-discord-bot-owl
user_b_source=gaiaftcl-discord-bot-governance
user_a_release_id=unknown-release
user_b_release_id=unknown-release
convergence_ms=153
CALORIE: dual-user hard invariants passed

STATE: CALORIE
WITNESS_JSON: /Users/richardgillespie/Documents/FoT8D/cells/fusion/evidence/discord/dual_user/20260407T115317Z/DUAL_USER_WITNESS.json
REPORT_MD: /Users/richardgillespie/Documents/FoT8D/cells/fusion/evidence/discord/dual_user/20260407T115317Z/DUAL_USER_VALIDATION_20260407T115317Z.md
