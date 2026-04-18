# GaiaFTCL Dual-User Validation
- ts_utc: 20260406T161323Z
- out_dir: /Users/richardgillespie/Documents/FoT8D/cells/fusion/evidence/discord/dual_user/20260406T161323Z
- owl_channel: https://discord.com/channels/1487775674356990064/1487775675665354835
- observer_channel: https://discord.com/channels/1487775674356990064/1487775675665354835
- user_a_channel: https://discord.com/channels/1487775674356990064/1487775675665354835
- user_b_channel: https://discord.com/channels/1487775674356990064/1487775675665354835

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

  ✓  1 [chromium] › tests/discord/discord_dual_user_validation.spec.ts:80:7 › Dual-user sovereign handshake › live moorer + observer convergence (26.2s)

  1 passed (28.1s)

## Hard invariant gate
WITNESS: /Users/richardgillespie/Documents/FoT8D/cells/fusion/evidence/discord/dual_user/20260406T161323Z/DUAL_USER_WITNESS.json
user_a_source=gaiaftcl-discord-bot-owl
user_b_source=gaiaftcl-discord-bot-governance
user_a_release_id=unknown-release
user_b_release_id=unknown-release
convergence_ms=297
CALORIE: dual-user hard invariants passed

STATE: CALORIE
WITNESS_JSON: /Users/richardgillespie/Documents/FoT8D/cells/fusion/evidence/discord/dual_user/20260406T161323Z/DUAL_USER_WITNESS.json
REPORT_MD: /Users/richardgillespie/Documents/FoT8D/cells/fusion/evidence/discord/dual_user/20260406T161323Z/DUAL_USER_VALIDATION_20260406T161323Z.md
