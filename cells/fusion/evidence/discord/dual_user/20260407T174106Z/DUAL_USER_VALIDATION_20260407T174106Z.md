# GaiaFTCL Dual-User Validation
- ts_utc: 20260407T174106Z
- out_dir: /Users/richardgillespie/Documents/FoT8D/cells/fusion/evidence/discord/dual_user/20260407T174106Z
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

    Error: browserContext._wrapApiCall: ENOENT: no such file or directory, open '/Users/richardgillespie/Documents/FoT8D/cells/fusion/services/gaiaos_ui_web/test-results/.playwright-artifacts-0/traces/45a067b830092d7a9ee5-dac4edeb3c0add4fe131.network'

    Error: keyboard.press: Test ended.
    Browser logs:

    <launching> /Users/richardgillespie/Library/Caches/ms-playwright/chromium-1208/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing --disable-field-trial-config --disable-background-networking --disable-background-timer-throttling --disable-backgrounding-occluded-windows --disable-back-forward-cache --disable-breakpad --disable-client-side-phishing-detection --disable-component-extensions-with-background-pages --disable-component-update --no-default-browser-check --disable-default-apps --disable-dev-shm-usage --disable-extensions --disable-features=AvoidUnnecessaryBeforeUnloadCheckSync,BoundaryEventDispatchTracksNodeRemoval,DestroyProfileOnBrowserClose,DialMediaRouteProvider,GlobalMediaControls,HttpsUpgrades,LensOverlay,MediaRouter,PaintHolding,ThirdPartyStoragePartitioning,Translate,AutoDeElevate,RenderDocument,OptimizationHints --enable-features=CDPScreenshotNewSurface --allow-pre-commit-input --disable-hang-monitor --disable-ipc-flooding-protection --disable-popup-blocking --disable-prompt-on-repost --disable-renderer-backgrounding --force-color-profile=srgb --metrics-recording-only --no-first-run --password-store=basic --use-mock-keychain --no-service-autorun --export-tagged-pdf --disable-search-engine-choice-screen --unsafely-disable-devtools-self-xss-warnings --edge-skip-compat-layer-relaunch --enable-automation --disable-infobars --disable-search-engine-choice-screen --disable-sync --no-sandbox --disable-blink-features=AutomationControlled --user-data-dir=/var/folders/5x/j3fn3d2d5x7gtdyc46rk487h0000gn/T/playwright_chromiumdev_profile-5If7ow --remote-debugging-pipe --no-startup-window
    <launched> pid=81489
    [pid=81489][err] [81728:75943646:0407/134135.149069:ERROR:sandbox/mac/system_services.cc:31] SetApplicationIsDaemon: Error Domain=NSOSStatusErrorDomain Code=-50 "paramErr: error in user parameter list" (-50)
    [pid=81489][err] [81489:75942581:0407/134139.534594:ERROR:components/device_event_log/device_event_log_impl.cc:202] [13:41:39.534] FIDO: touch_id_context.mm:89 Touch ID authenticator unavailable because keychain-access-group entitlement is missing or incorrect. Expected value: .com.google.chrome.for.testing.webauthn
    [pid=81489][err] [81489:75942581:0407/134140.832933:ERROR:components/device_event_log/device_event_log_impl.cc:202] [13:41:40.832] FIDO: touch_id_context.mm:89 Touch ID authenticator unavailable because keychain-access-group entitlement is missing or incorrect. Expected value: .com.google.chrome.for.testing.webauthn
    [pid=81489][err] 2026-04-07 13:43:26.502 Google Chrome for Testing[81489:75942901] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 0
    [pid=81489][err] 2026-04-07 13:43:27.014 Google Chrome for Testing[81489:75942901] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 0
    [pid=81489][err] 2026-04-07 13:45:09.634 Google Chrome for Testing[81489:75948324] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 0
    [pid=81489][err] 2026-04-07 13:45:10.135 Google Chrome for Testing[81489:75948324] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 0
    [pid=81489][err] 2026-04-07 13:45:10.651 Google Chrome for Testing[81489:75948324] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 0
    [pid=81489][err] 2026-04-07 13:45:11.157 Google Chrome for Testing[81489:75948324] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 0
    [pid=81489][err] 2026-04-07 13:45:19.638 Google Chrome for Testing[81489:75948324] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 0
    [pid=81489][err] 2026-04-07 13:45:20.139 Google Chrome for Testing[81489:75948324] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 0
    [pid=81489][err] 2026-04-07 13:45:20.687 Google Chrome for Testing[81489:75948324] NSSpellServer dataFromCheckingString timed out, index is 1
    [pid=81489][err] 2026-04-07 13:45:21.079 Google Chrome for Testing[81489:75948324] NSSpellServer dataFromCheckingString succeeded, index is 0
    [pid=81489][err] 2026-04-07 13:45:26.729 Google Chrome for Testing[81489:75947546] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 0
    [pid=81489][err] 2026-04-07 13:45:27.231 Google Chrome for Testing[81489:75947546] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 0
    [pid=81489][err] 2026-04-07 13:45:27.777 Google Chrome for Testing[81489:75948324] NSSpellServer dataFromCheckingString timed out, index is 1
    [pid=81489][err] 2026-04-07 13:45:28.278 Google Chrome for Testing[81489:75948324] NSSpellServer dataFromCheckingString timed out, index is 2
    [pid=81489][err] 2026-04-07 13:45:38.224 Google Chrome for Testing[81489:75948324] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 2
    [pid=81489][err] 2026-04-07 13:45:38.475 Google Chrome for Testing[81489:75948324] NSSpellServer dataFromGeneratingCandidatesForSelectedRange timed out, index is 2
    [pid=81489][err] 2026-04-07 13:45:39.230 Google Chrome for Testing[81489:75942743] NSSpellServer dataFromCheckingString timed out, index is 3
    [pid=81489][err] 2026-04-07 13:45:39.487 Google Chrome for Testing[81489:75942743] NSSpellServer dataFromCheckingString timed out, index is 4
    [pid=81489][err] 2026-04-07 13:45:44.223 Google Chrome for Testing[81489:75948324] NSSpellServer dataFromGeneratingCandidatesForSelectedRange succeeded, index is 3
    [pid=81489][err] 2026-04-07 13:45:45.249 Google Chrome for Testing[81489:75942743] NSSpellServer dataFromCheckingString succeeded, index is 2
    [pid=81489][err] 2026-04-07 13:45:50.490 Google Chrome for Testing[81489:75942743] NSSpellServer dataFromGeneratingCandidatesForSelectedRange succeeded, index is 1
    [pid=81489][err] 2026-04-07 13:45:51.544 Google Chrome for Testing[81489:75942743] NSSpellServer dataFromCheckingString succeeded, index is 0
    [pid=81489] <gracefully close start>
    [pid=81489][err] [81489:75942725:0407/134609.694687:ERROR:base/process/process_mac.cc:53] task_policy_set TASK_CATEGORY_POLICY: (os/kern) invalid argument (4)
    [pid=81489][err] [81489:75942725:0407/134609.694719:ERROR:base/process/process_mac.cc:98] task_policy_set TASK_SUPPRESSION_POLICY: (os/kern) invalid argument (4)
    [pid=81489][err] [81489:75942725:0407/134609.694821:ERROR:base/process/process_mac.cc:98] task_policy_set TASK_SUPPRESSION_POLICY: (os/kern) invalid argument (4)

      48 |   await page.keyboard.press("Enter");
      49 |   await page.waitForTimeout(700);
    > 50 |   await page.keyboard.press("Enter");
         |                       ^
      51 |   await page.waitForTimeout(1200);
      52 |   return Date.now();
      53 | }
        at runSlash (/Users/richardgillespie/Documents/FoT8D/cells/fusion/services/gaiaos_ui_web/tests/discord/discord_dual_user_validation.spec.ts:50:23)
        at /Users/richardgillespie/Documents/FoT8D/cells/fusion/services/gaiaos_ui_web/tests/discord/discord_dual_user_validation.spec.ts:184:7

    Error: ENOENT: no such file or directory, open '/Users/richardgillespie/Documents/FoT8D/cells/fusion/services/gaiaos_ui_web/test-results/.playwright-artifacts-0/04d0221a6504d8dc5d8745c9d4575a90.zip'

    [31mTest timeout of 30000ms exceeded.[39m

    attachment #1: screenshot (image/png) ──────────────────────────────────────────────────────────
    test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/test-failed-1.png
    ────────────────────────────────────────────────────────────────────────────────────────────────

    attachment #2: screenshot (image/png) ──────────────────────────────────────────────────────────
    test-results/discord_dual_user_validati-85cea-moorer-observer-convergence-chromium/test-failed-2.png
    ────────────────────────────────────────────────────────────────────────────────────────────────

  1 failed
    [chromium] › tests/discord/discord_dual_user_validation.spec.ts:127:7 › Dual-user sovereign handshake › live moorer + observer convergence 
