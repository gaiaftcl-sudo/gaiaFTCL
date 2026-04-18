# GaiaFTCL Dual-User Validation
- ts_utc: 20260407T174127Z
- out_dir: /Users/richardgillespie/Documents/FoT8D/cells/fusion/evidence/discord/dual_user/20260407T174127Z
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

  ✘  1 [chromium] › tests/discord/discord_dual_user_validation.spec.ts:127:7 › Dual-user sovereign handshake › live moorer + observer convergence (4.1m)


  1) [chromium] › tests/discord/discord_dual_user_validation.spec.ts:127:7 › Dual-user sovereign handshake › live moorer + observer convergence 

    TimeoutError: page.waitForSelector: Timeout 90000ms exceeded.
    Call log:
    [2m  - waiting for locator('#app-mount') to be visible[22m


      160 |     ]);
      161 |     await Promise.all([
    > 162 |       pageA.waitForSelector("#app-mount", { state: "visible", timeout: 90_000 }),
          |             ^
      163 |       pageB.waitForSelector("#app-mount", { state: "visible", timeout: 90_000 }),
      164 |     ]);
      165 |
        at /Users/richardgillespie/Documents/FoT8D/cells/fusion/services/gaiaos_ui_web/tests/discord/discord_dual_user_validation.spec.ts:162:13

    Error: browserContext._wrapApiCall: ENOENT: no such file or directory, open '/Users/richardgillespie/Documents/FoT8D/cells/fusion/services/gaiaos_ui_web/test-results/.playwright-artifacts-0/traces/resources/b418429407b965eb4c0d3dc3265f89006114a456.wasm'

    Error: ENOENT: no such file or directory, open '/Users/richardgillespie/Documents/FoT8D/cells/fusion/services/gaiaos_ui_web/test-results/.playwright-artifacts-0/6cce9c6d63c8017ddca0c9a55dee73a1.zip'

    [31mTest timeout of 30000ms exceeded.[39m

    attachment #1: screenshot (image/png) ──────────────────────────────────────────────────────────
    test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/test-failed-2.png
    ────────────────────────────────────────────────────────────────────────────────────────────────

    attachment #2: screenshot (image/png) ──────────────────────────────────────────────────────────
    test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/test-failed-1.png
    ────────────────────────────────────────────────────────────────────────────────────────────────

  1 failed
    [chromium] › tests/discord/discord_dual_user_validation.spec.ts:127:7 › Dual-user sovereign handshake › live moorer + observer convergence 
