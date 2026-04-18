# GaiaFTCL Dual-User Validation
- ts_utc: 20260407T175348Z
- out_dir: /Users/richardgillespie/Documents/FoT8D/cells/fusion/evidence/discord/dual_user/20260407T175348Z
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

  ✘  1 [chromium] › tests/discord/discord_dual_user_validation.spec.ts:127:7 › Dual-user sovereign handshake › live moorer + observer convergence (4.7m)


  1) [chromium] › tests/discord/discord_dual_user_validation.spec.ts:127:7 › Dual-user sovereign handshake › live moorer + observer convergence 

    [31mTest timeout of 280000ms exceeded.[39m

    Error: browserContext._wrapApiCall: ENOENT: no such file or directory, open '/Users/richardgillespie/Documents/FoT8D/cells/fusion/services/gaiaos_ui_web/test-results/.playwright-artifacts-0/traces/45a067b830092d7a9ee5-dac4edeb3c0add4fe131.trace'

    Error: keyboard.press: Test ended.
    Browser logs:

    <launching> /Users/richardgillespie/Library/Caches/ms-playwright/chromium-1208/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing --disable-field-trial-config --disable-background-networking --disable-background-timer-throttling --disable-backgrounding-occluded-windows --disable-back-forward-cache --disable-breakpad --disable-client-side-phishing-detection --disable-component-extensions-with-background-pages --disable-component-update --no-default-browser-check --disable-default-apps --disable-dev-shm-usage --disable-extensions --disable-features=AvoidUnnecessaryBeforeUnloadCheckSync,BoundaryEventDispatchTracksNodeRemoval,DestroyProfileOnBrowserClose,DialMediaRouteProvider,GlobalMediaControls,HttpsUpgrades,LensOverlay,MediaRouter,PaintHolding,ThirdPartyStoragePartitioning,Translate,AutoDeElevate,RenderDocument,OptimizationHints --enable-features=CDPScreenshotNewSurface --allow-pre-commit-input --disable-hang-monitor --disable-ipc-flooding-protection --disable-popup-blocking --disable-prompt-on-repost --disable-renderer-backgrounding --force-color-profile=srgb --metrics-recording-only --no-first-run --password-store=basic --use-mock-keychain --no-service-autorun --export-tagged-pdf --disable-search-engine-choice-screen --unsafely-disable-devtools-self-xss-warnings --edge-skip-compat-layer-relaunch --enable-automation --disable-infobars --disable-search-engine-choice-screen --disable-sync --no-sandbox --disable-blink-features=AutomationControlled --user-data-dir=/var/folders/5x/j3fn3d2d5x7gtdyc46rk487h0000gn/T/playwright_chromiumdev_profile-6Dp2db --remote-debugging-pipe --no-startup-window
    <launched> pid=99860
    [pid=99860][err] [111:76021752:0407/135405.335252:ERROR:sandbox/mac/system_services.cc:31] SetApplicationIsDaemon: Error Domain=NSOSStatusErrorDomain Code=-50 "paramErr: error in user parameter list" (-50)
    [pid=99860][err] [99860:76020883:0407/135413.463036:ERROR:components/device_event_log/device_event_log_impl.cc:202] [13:54:13.462] FIDO: touch_id_context.mm:89 Touch ID authenticator unavailable because keychain-access-group entitlement is missing or incorrect. Expected value: .com.google.chrome.for.testing.webauthn
    [pid=99860][err] [99860:76020883:0407/135414.003703:ERROR:components/device_event_log/device_event_log_impl.cc:202] [13:54:14.002] FIDO: touch_id_context.mm:89 Touch ID authenticator unavailable because keychain-access-group entitlement is missing or incorrect. Expected value: .com.google.chrome.for.testing.webauthn
    [pid=99860][err] 2026-04-07 13:57:14.535 Google Chrome for Testing[99860:76021227] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 0
    [pid=99860] <gracefully close start>
    [pid=99860][err] [99860:76020967:0407/135844.703731:ERROR:base/process/process_mac.cc:53] task_policy_set TASK_CATEGORY_POLICY: (os/kern) invalid argument (4)
    [pid=99860][err] [99860:76020967:0407/135844.703760:ERROR:base/process/process_mac.cc:98] task_policy_set TASK_SUPPRESSION_POLICY: (os/kern) invalid argument (4)

      26 |   await focusComposer(page);
      27 |   await page.keyboard.press("Meta+A");
    > 28 |   await page.keyboard.press("Backspace");
         |                       ^
      29 |   await page.keyboard.type(cmd, { delay: 20 });
      30 |   const cmdName = cmd.replace(/^\//, "");
      31 |   const suggestion = appHint
        at runSlash (/Users/richardgillespie/Documents/FoT8D/cells/fusion/services/gaiaos_ui_web/tests/discord/discord_dual_user_validation.spec.ts:28:23)
        at /Users/richardgillespie/Documents/FoT8D/cells/fusion/services/gaiaos_ui_web/tests/discord/discord_dual_user_validation.spec.ts:184:7

    attachment #1: screenshot (image/png) ──────────────────────────────────────────────────────────
    test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/test-failed-1.png
    ────────────────────────────────────────────────────────────────────────────────────────────────

    attachment #2: screenshot (image/png) ──────────────────────────────────────────────────────────
    test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/test-failed-2.png
    ────────────────────────────────────────────────────────────────────────────────────────────────

    attachment #3: trace (application/zip) ─────────────────────────────────────────────────────────
    test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/trace.zip
    Usage:

        npx playwright show-trace test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/trace.zip

    ────────────────────────────────────────────────────────────────────────────────────────────────

  1 failed
    [chromium] › tests/discord/discord_dual_user_validation.spec.ts:127:7 › Dual-user sovereign handshake › live moorer + observer convergence 
