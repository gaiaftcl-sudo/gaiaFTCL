# GaiaFTCL Dual-User Validation
- ts_utc: 20260407T174024Z
- out_dir: /Users/richardgillespie/Documents/FoT8D/GAIAOS/evidence/discord/dual_user/20260407T174024Z
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

  ✘  1 [chromium] › tests/discord/discord_dual_user_validation.spec.ts:127:7 › Dual-user sovereign handshake › live moorer + observer convergence (4.8m)


  1) [chromium] › tests/discord/discord_dual_user_validation.spec.ts:127:7 › Dual-user sovereign handshake › live moorer + observer convergence 

    [31mTest timeout of 280000ms exceeded.[39m

    Error: browserContext._wrapApiCall: ENOENT: no such file or directory, open '/Users/richardgillespie/Documents/FoT8D/GAIAOS/services/gaiaos_ui_web/test-results/.playwright-artifacts-0/traces/45a067b830092d7a9ee5-dac4edeb3c0add4fe131.trace'

    Error: keyboard.press: Test ended.
    Browser logs:

    <launching> /Users/richardgillespie/Library/Caches/ms-playwright/chromium-1208/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing --disable-field-trial-config --disable-background-networking --disable-background-timer-throttling --disable-backgrounding-occluded-windows --disable-back-forward-cache --disable-breakpad --disable-client-side-phishing-detection --disable-component-extensions-with-background-pages --disable-component-update --no-default-browser-check --disable-default-apps --disable-dev-shm-usage --disable-extensions --disable-features=AvoidUnnecessaryBeforeUnloadCheckSync,BoundaryEventDispatchTracksNodeRemoval,DestroyProfileOnBrowserClose,DialMediaRouteProvider,GlobalMediaControls,HttpsUpgrades,LensOverlay,MediaRouter,PaintHolding,ThirdPartyStoragePartitioning,Translate,AutoDeElevate,RenderDocument,OptimizationHints --enable-features=CDPScreenshotNewSurface --allow-pre-commit-input --disable-hang-monitor --disable-ipc-flooding-protection --disable-popup-blocking --disable-prompt-on-repost --disable-renderer-backgrounding --force-color-profile=srgb --metrics-recording-only --no-first-run --password-store=basic --use-mock-keychain --no-service-autorun --export-tagged-pdf --disable-search-engine-choice-screen --unsafely-disable-devtools-self-xss-warnings --edge-skip-compat-layer-relaunch --enable-automation --disable-infobars --disable-search-engine-choice-screen --disable-sync --no-sandbox --disable-blink-features=AutomationControlled --user-data-dir=/var/folders/5x/j3fn3d2d5x7gtdyc46rk487h0000gn/T/playwright_chromiumdev_profile-Y4P1ad --remote-debugging-pipe --no-startup-window
    <launched> pid=81032
    [pid=81032][err] [81259:75941553:0407/134115.550793:ERROR:sandbox/mac/system_services.cc:31] SetApplicationIsDaemon: Error Domain=NSOSStatusErrorDomain Code=-50 "paramErr: error in user parameter list" (-50)
    [pid=81032][err] [81032:75940553:0407/134120.064469:ERROR:components/device_event_log/device_event_log_impl.cc:202] [13:41:20.061] FIDO: touch_id_context.mm:89 Touch ID authenticator unavailable because keychain-access-group entitlement is missing or incorrect. Expected value: .com.google.chrome.for.testing.webauthn
    [pid=81032][err] [81032:75940553:0407/134120.498577:ERROR:components/device_event_log/device_event_log_impl.cc:202] [13:41:20.497] FIDO: touch_id_context.mm:89 Touch ID authenticator unavailable because keychain-access-group entitlement is missing or incorrect. Expected value: .com.google.chrome.for.testing.webauthn
    [pid=81032][err] 2026-04-07 13:44:31.622 Google Chrome for Testing[81032:75940569] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 0
    [pid=81032][err] 2026-04-07 13:44:32.136 Google Chrome for Testing[81032:75940569] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 0
    [pid=81032][err] 2026-04-07 13:44:38.900 Google Chrome for Testing[81032:75940569] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 0
    [pid=81032][err] 2026-04-07 13:44:57.442 Google Chrome for Testing[81032:75940569] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 0
    [pid=81032][err] 2026-04-07 13:44:57.945 Google Chrome for Testing[81032:75940569] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 0
    [pid=81032][err] 2026-04-07 13:44:58.526 Google Chrome for Testing[81032:75940569] NSSpellServer dataFromCheckingString timed out, index is 1
    [pid=81032][err] 2026-04-07 13:44:59.028 Google Chrome for Testing[81032:75940569] NSSpellServer dataFromCheckingString timed out, index is 2
    [pid=81032][err] 2026-04-07 13:45:08.418 Google Chrome for Testing[81032:75940569] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 2
    [pid=81032][err] 2026-04-07 13:45:08.689 Google Chrome for Testing[81032:75940569] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 2
    [pid=81032][err] 2026-04-07 13:45:09.538 Google Chrome for Testing[81032:75940569] NSSpellServer dataFromCheckingString timed out, index is 3
    [pid=81032][err] 2026-04-07 13:45:09.788 Google Chrome for Testing[81032:75940569] NSSpellServer dataFromCheckingString timed out, index is 4
    [pid=81032][err] 2026-04-07 13:45:18.796 Google Chrome for Testing[81032:75946251] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 4
    [pid=81032][err] 2026-04-07 13:45:18.923 Google Chrome for Testing[81032:75946251] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 4
    [pid=81032][err] 2026-04-07 13:45:19.967 Google Chrome for Testing[81032:75946251] NSSpellServer dataFromCheckingString timed out, index is 5
    [pid=81032][err] 2026-04-07 13:45:20.095 Google Chrome for Testing[81032:75946251] NSSpellServer dataFromCheckingString timed out, index is 6
    [pid=81032][err] 2026-04-07 13:45:25.972 Google Chrome for Testing[81032:75940569] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 6
    [pid=81032][err] 2026-04-07 13:45:26.043 Google Chrome for Testing[81032:75940569] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 6
    [pid=81032][err] 2026-04-07 13:45:27.057 Google Chrome for Testing[81032:75940893] NSSpellServer dataFromCheckingString timed out, index is 7
    [pid=81032][err] 2026-04-07 13:45:27.127 Google Chrome for Testing[81032:75940893] NSSpellServer dataFromCheckingString timed out, index is 8
    [pid=81032] <gracefully close start>
    [pid=81032][err] [81032:75940640:0407/134603.930524:ERROR:base/process/process_mac.cc:53] task_policy_set TASK_CATEGORY_POLICY: (os/kern) invalid argument (4)
    [pid=81032][err] [81032:75940640:0407/134603.930551:ERROR:base/process/process_mac.cc:98] task_policy_set TASK_SUPPRESSION_POLICY: (os/kern) invalid argument (4)
    [pid=81032][err] [81032:75940640:0407/134603.930567:ERROR:base/process/process_mac.cc:53] task_policy_set TASK_CATEGORY_POLICY: (os/kern) invalid argument (4)
    [pid=81032][err] [81032:75940640:0407/134603.930571:ERROR:base/process/process_mac.cc:98] task_policy_set TASK_SUPPRESSION_POLICY: (os/kern) invalid argument (4)

      46 |   await page.keyboard.press("Enter");
      47 |   await page.waitForTimeout(700);
    > 48 |   await page.keyboard.press("Enter");
         |                       ^
      49 |   await page.waitForTimeout(700);
      50 |   await page.keyboard.press("Enter");
      51 |   await page.waitForTimeout(1200);
        at runSlash (/Users/richardgillespie/Documents/FoT8D/GAIAOS/services/gaiaos_ui_web/tests/discord/discord_dual_user_validation.spec.ts:48:23)
        at /Users/richardgillespie/Documents/FoT8D/GAIAOS/services/gaiaos_ui_web/tests/discord/discord_dual_user_validation.spec.ts:223:28

    attachment #1: trace (application/zip) ─────────────────────────────────────────────────────────
    test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/trace.zip
    Usage:

        npx playwright show-trace test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/trace.zip

    ────────────────────────────────────────────────────────────────────────────────────────────────

  1 failed
    [chromium] › tests/discord/discord_dual_user_validation.spec.ts:127:7 › Dual-user sovereign handshake › live moorer + observer convergence 
