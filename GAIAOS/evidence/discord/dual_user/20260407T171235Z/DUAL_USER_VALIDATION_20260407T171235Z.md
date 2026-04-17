# GaiaFTCL Dual-User Validation
- ts_utc: 20260407T171235Z
- out_dir: /Users/richardgillespie/Documents/FoT8D/GAIAOS/evidence/discord/dual_user/20260407T171235Z
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

  ✘  1 [chromium] › tests/discord/discord_dual_user_validation.spec.ts:127:7 › Dual-user sovereign handshake › live moorer + observer convergence (4.7m)


  1) [chromium] › tests/discord/discord_dual_user_validation.spec.ts:127:7 › Dual-user sovereign handshake › live moorer + observer convergence 

    Error: Test timeout of 280000ms exceeded

      188 |     const mountB = pageB.locator("#app-mount");
      189 |     await expect.poll(async () => (await mountA.innerText()).length, { timeout: 20_000 }).toBeGreaterThan(100);
    > 190 |     await expect.poll(async () => (await mountB.innerText()).length, { timeout: 20_000 }).toBeGreaterThan(100);
          |     ^
      191 |     let textA = await mountA.innerText();
      192 |
      193 |     const earth1 = parseEarthMooring(textA);
        at /Users/richardgillespie/Documents/FoT8D/GAIAOS/services/gaiaos_ui_web/tests/discord/discord_dual_user_validation.spec.ts:190:5

    [31mFixture "trace recording" timeout of 30000ms exceeded during teardown.[39m

    Error: browserContext._wrapApiCall: Test ended.

    Error: End of central directory record signature not found. Either not a zip file, or file is truncated.

    attachment #1: screenshot (image/png) ──────────────────────────────────────────────────────────
    test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/test-failed-1.png
    ────────────────────────────────────────────────────────────────────────────────────────────────

    attachment #2: screenshot (image/png) ──────────────────────────────────────────────────────────
    test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/test-failed-2.png
    ────────────────────────────────────────────────────────────────────────────────────────────────

  1 failed
    [chromium] › tests/discord/discord_dual_user_validation.spec.ts:127:7 › Dual-user sovereign handshake › live moorer + observer convergence 
