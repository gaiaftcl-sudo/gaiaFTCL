# Sovereign facade automated audit

- **Runner:** `facade_audit_runner.mjs` (from GAIAOS root: `node tests/sovereign_facade/facade_audit_runner.mjs`)
- **Phase 1 (Playwright):** `services/gaiaos_ui_web/tests/sovereign_facade/` — spec and config live **inside** `gaiaos_ui_web` so `@playwright/test` resolves from that package (not `GAIAOS/node_modules`).
- **Functional Testing Requirement (S4 UI):** `docs/FUNCTIONAL_TESTING_REQUIREMENT_S4_UI.md` — mail vhost, SOGo, sovereign mesh, CI matrix, Definition of Done.
- **Phase 2 (browser SOGo, opt-in):** `S4_SOGO_BROWSER=1 npx playwright test -c tests/sovereign_facade/playwright.sovereign.config.ts`
- **Report output:** `evidence/sovereign_facade/PLAYWRIGHT_TEST_REPORT_V1.md`
- **Routing helper:** `verify_game_room.py`
