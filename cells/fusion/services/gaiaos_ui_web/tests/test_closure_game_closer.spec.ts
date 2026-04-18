import { test, expect } from "./setup/wallet-auth";

const UI_BASE = process.env.PLAYWRIGHT_BASE_URL || "http://localhost:3000";

/**
 * Closure Game "Closer" — Full loop test with ledger verification.
 * Master template for recursive invariant testing.
 * Flow: Connect wallet → Evaluate → Submit Evidence → Verify → Generate Receipt → Verify envelope.
 */
test.describe("Closure Game Closer", () => {
  test("full loop: evaluate → submit evidence → verify → generate receipt → envelope has wallet", async ({
    page,
    request,
    wallet: testWallet,
  }) => {
    const testNonce = `test_nonce_closer_${Date.now()}`;

    await page.goto("/");
    await page.getByPlaceholder("0xRick_playwright_...").fill(testWallet);
    await page.getByRole("button", { name: "Connect" }).click();

    await page.goto("/closure-game");

    // 1. Evaluate claim → assert OFFERED
    await page.getByPlaceholder("Claim text...").fill("The sky is blue.");
    await page.getByRole("button", { name: "Evaluate" }).click();
    await expect(page.locator("main").getByText(/CLOSURE OFFERED|CLOSURE REFUSED|Provenance:/i)).toBeVisible({
      timeout: 10000,
    });

    // 2. Submit evidence (nonce to echo sink)
    await page.getByPlaceholder("Nonce (e.g. test_nonce_123)").fill(testNonce);
    await page.getByRole("button", { name: "Submit" }).click();
    await expect(page.getByText("Evidence recorded.")).toBeVisible({ timeout: 5000 });

    // 3. Verify evidence
    await page.getByRole("button", { name: "Verify" }).click();
    await expect(page.locator("main").getByText(/Verified\. Hash:/i)).toBeVisible({ timeout: 5000 });

    // 4. Generate receipt
    await page.getByRole("button", { name: "Generate Receipt" }).click();
    await expect(page.locator("main").getByText(/CLOSURE PERFORMED|Provenance:/i)).toBeVisible({ timeout: 5000 });

    // 5. Verify envelope via API — report call produces envelope with wallet
    const reportRes = await request.post(`${UI_BASE}/api/mcp/execute`, {
      headers: {
        "Content-Type": "application/json",
        "X-Wallet-Address": testWallet,
        "X-Environment-ID": "local",
      },
      data: {
        name: "closure_game_report_v1",
        params: {},
      },
    });
    expect(reportRes.status()).toBe(200);
    const reportBody = await reportRes.json();
    const callId = reportBody.witness?.call_id;
    expect(callId).toBeDefined();

    const evidenceRes = await request.get(`${UI_BASE}/api/evidence/${callId}`);
    expect(evidenceRes.status()).toBe(200);
    const evidence = await evidenceRes.json();
    expect(evidence.wallet_address).toBe(testWallet);
  });

  test("anonymous call to echo returns 400", async ({ request }) => {
    const res = await request.post(`${UI_BASE}/api/echo/nonce`, {
      headers: { "Content-Type": "application/json" },
      data: { nonce: "test_anon", agent_id: "anon" },
    });
    expect(res.status()).toBe(400);
  });

  test("full loop via API: verify evidence produces envelope with wallet", async ({ request, wallet: testWallet }) => {
    const testNonce = `test_nonce_api_${Date.now()}`;

    // Submit nonce (requires wallet)
    const echoRes = await request.post(`${UI_BASE}/api/echo/nonce`, {
      headers: {
        "Content-Type": "application/json",
        "X-Wallet-Address": testWallet,
      },
      data: { nonce: testNonce, agent_id: testWallet },
    });
    expect(echoRes.status()).toBe(200);
    const echoData = await echoRes.json();
    expect(echoData.recorded).toBe(true);

    // Verify evidence
    const verifyRes = await request.post(`${UI_BASE}/api/mcp/execute`, {
      headers: {
        "Content-Type": "application/json",
        "X-Wallet-Address": testWallet,
        "X-Environment-ID": "local",
      },
      data: {
        name: "closure_verify_evidence_v1",
        params: {
          domain_id: "generic",
          evidence_type: "HTTP_ECHO_SINK",
          nonce: testNonce,
          agent_id: testWallet,
        },
      },
    });
    expect(verifyRes.status()).toBe(200);
    const verifyBody = await verifyRes.json();
    expect(verifyBody.ok).toBe(true);
    expect(verifyBody.result?.verified).toBe(true);
    const evidenceHash = verifyBody.result?.evidence_hash;
    expect(evidenceHash).toBeDefined();

    const verifyCallId = verifyBody.witness?.call_id;
    expect(verifyCallId).toBeDefined();

    const evidenceRes = await request.get(`${UI_BASE}/api/evidence/${verifyCallId}`);
    expect(evidenceRes.status()).toBe(200);
    const evidence = await evidenceRes.json();
    expect(evidence.wallet_address).toBe(testWallet);
  });
});
