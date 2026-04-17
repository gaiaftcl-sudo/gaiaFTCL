# GaiaFTCL Dual-User Validation
- ts_utc: 20260407T131225Z
- out_dir: /Users/richardgillespie/Documents/FoT8D/GAIAOS/evidence/discord/dual_user/20260407T131225Z
- owl_channel: https://discord.com/channels/1487775674356990064/1487775675665354835
- observer_channel: https://discord.com/channels/1487775674356990064/1487775675665354835
- user_a_channel: https://discord.com/channels/1487775674356990064/1487775675665354835
- user_b_channel: https://discord.com/channels/1487775674356990064/1487775675665354835
- phase2_hook: bash /Users/richardgillespie/Documents/FoT8D/GAIAOS/scripts/dual_user_phase2_hook.sh

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

  ✘  1 [chromium] › tests/discord/discord_dual_user_validation.spec.ts:127:7 › Dual-user sovereign handshake › live moorer + observer convergence (2.4m)


  1) [chromium] › tests/discord/discord_dual_user_validation.spec.ts:127:7 › Dual-user sovereign handshake › live moorer + observer convergence 

    Error: [2mexpect([22m[31mreceived[39m[2m).[22mtoBeLessThanOrEqual[2m([22m[32mexpected[39m[2m)[22m

    Expected: <= [32m2000[39m
    Received:    [31m3051[39m

      287 |     expect(releaseA).toBe(releaseB);
      288 |     expect(sourceA).not.toBe(sourceB);
    > 289 |     expect(convergenceMs).toBeLessThanOrEqual(2000);
          |                           ^
      290 |
      291 |     if (requireEarth && !earthFullMoor) {
      292 |       throw new Error(
        at /Users/richardgillespie/Documents/FoT8D/GAIAOS/services/gaiaos_ui_web/tests/discord/discord_dual_user_validation.spec.ts:289:27

    Error: browserContext._wrapApiCall: ENOENT: no such file or directory, open '/Users/richardgillespie/Documents/FoT8D/GAIAOS/services/gaiaos_ui_web/test-results/.playwright-artifacts-0/traces/45a067b830092d7a9ee5-dac4edeb3c0add4fe131.trace'

    Error: ENOENT: no such file or directory, open '/Users/richardgillespie/Documents/FoT8D/GAIAOS/services/gaiaos_ui_web/test-results/.playwright-artifacts-0/e28f05330a2d22af0bc53572b0fbd22e.zip'

    [31mTest timeout of 30000ms exceeded.[39m

    attachment #1: screenshot (image/png) ──────────────────────────────────────────────────────────
    test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/test-failed-2.png
    ────────────────────────────────────────────────────────────────────────────────────────────────

    attachment #2: screenshot (image/png) ──────────────────────────────────────────────────────────
    test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/test-failed-1.png
    ────────────────────────────────────────────────────────────────────────────────────────────────

  1 failed
    [chromium] › tests/discord/discord_dual_user_validation.spec.ts:127:7 › Dual-user sovereign handshake › live moorer + observer convergence 
