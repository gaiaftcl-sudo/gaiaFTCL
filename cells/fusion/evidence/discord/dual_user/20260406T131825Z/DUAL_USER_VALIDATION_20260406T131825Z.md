# GaiaFTCL Dual-User Validation
- ts_utc: 20260406T131825Z
- out_dir: /Users/richardgillespie/Documents/FoT8D/cells/fusion/evidence/discord/dual_user/20260406T131825Z
- owl_channel: https://discord.com/channels/1487775674356990064/1487775675665354835
- observer_channel: https://discord.com/channels/1487775674356990064/1487775675665354835

## No-simulation gate
🔍 Running Simulation Detection Audit...
[0;32m✅ NO SIMULATION CODE DETECTED[0m

## Witness preflight

## Dual-user Playwright run

> gaiaos_ui_web@0.1.0 test:e2e:discord:dual-user
> sh -c 'unset CI 2>/dev/null; DISCORD_DUAL_USER_RUN=1 playwright test --config=playwright.discord.config.ts --grep "Dual-user sovereign handshake" --headed'


Running 1 test using 1 worker

  ✘  1 [chromium] › tests/discord/discord_dual_user_validation.spec.ts:44:7 › Dual-user sovereign handshake › live moorer + observer convergence (14.9s)


  1) [chromium] › tests/discord/discord_dual_user_validation.spec.ts:44:7 › Dual-user sovereign handshake › live moorer + observer convergence 

    TimeoutError: locator.waitFor: Timeout 6000ms exceeded.
    Call log:
    [2m  - waiting for getByRole('option', { name: /moor/i }).first() to be visible[22m


      25 |   const cmdName = cmd.replace(/^\//, "");
      26 |   const suggestion = page.getByRole("option", { name: new RegExp(cmdName, "i") }).first();
    > 27 |   await suggestion.waitFor({ state: "visible", timeout: 6_000 });
         |                    ^
      28 |   await page.keyboard.press("Enter");
      29 |   await page.waitForTimeout(1200);
      30 |   return Date.now();
        at runSlash (/Users/richardgillespie/Documents/FoT8D/cells/fusion/services/gaiaos_ui_web/tests/discord/discord_dual_user_validation.spec.ts:27:20)
        at /Users/richardgillespie/Documents/FoT8D/cells/fusion/services/gaiaos_ui_web/tests/discord/discord_dual_user_validation.spec.ts:78:5

    attachment #1: screenshot (image/png) ──────────────────────────────────────────────────────────
    test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/test-failed-1.png
    ────────────────────────────────────────────────────────────────────────────────────────────────

    attachment #2: screenshot (image/png) ──────────────────────────────────────────────────────────
    test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/test-failed-2.png
    ────────────────────────────────────────────────────────────────────────────────────────────────

    Error Context: test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/error-context.md

    attachment #4: trace (application/zip) ─────────────────────────────────────────────────────────
    test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/trace.zip
    Usage:

        npx playwright show-trace test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/trace.zip

    ────────────────────────────────────────────────────────────────────────────────────────────────

  1 failed
    [chromium] › tests/discord/discord_dual_user_validation.spec.ts:44:7 › Dual-user sovereign handshake › live moorer + observer convergence 
