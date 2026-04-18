# GaiaFTCL Dual-User Validation
- ts_utc: 20260406T153609Z
- out_dir: /Users/richardgillespie/Documents/FoT8D/cells/fusion/evidence/discord/dual_user/20260406T153609Z
- owl_channel: https://discord.com/channels/1487775674356990064/1487775675665354835
- observer_channel: https://discord.com/channels/1487775674356990064/1487775675665354835

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

  ✘  1 [chromium] › tests/discord/discord_dual_user_validation.spec.ts:53:7 › Dual-user sovereign handshake › live moorer + observer convergence (21.3s)


  1) [chromium] › tests/discord/discord_dual_user_validation.spec.ts:53:7 › Dual-user sovereign handshake › live moorer + observer convergence 

    Error: [2mexpect([22m[31mreceived[39m[2m).[22mnot[2m.[22mtoBe[2m([22m[32mexpected[39m[2m) // Object.is equality[22m

    Expected: not [32m"gaiaftcl-discord-bot-governance"[39m

      131 |     if (!releaseA || !releaseB) throw new Error(`REFUSED: missing release_id in responses (A=${releaseA ?? "none"}, B=${releaseB ?? "none"})`);
      132 |     expect(releaseA).toBe(releaseB);
    > 133 |     expect(sourceA).not.toBe(sourceB);
          |                         ^
      134 |     expect(convergenceMs).toBeLessThanOrEqual(2000);
      135 |   });
      136 | });
        at /Users/richardgillespie/Documents/FoT8D/cells/fusion/services/gaiaos_ui_web/tests/discord/discord_dual_user_validation.spec.ts:133:25

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
    [chromium] › tests/discord/discord_dual_user_validation.spec.ts:53:7 › Dual-user sovereign handshake › live moorer + observer convergence 
