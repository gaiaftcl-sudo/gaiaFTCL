import { test as base } from "@playwright/test";
import * as ed25519 from "@noble/ed25519";
import { sha512 } from "@noble/hashes/sha2.js";
import { createHash } from "crypto";

ed25519.hashes.sha512 = sha512;

const TEST_SEED = "gaiaftcl-test-wallet-0xRick-do-not-use-in-production";
const privateKey = createHash("sha256").update(TEST_SEED).digest();

export async function signNonce(nonce: string): Promise<string> {
  return Buffer.from(await ed25519.sign(Buffer.from(nonce, "utf8"), privateKey)).toString("hex");
}

/**
 * Wallet fixture for recursive invariant testing.
 * One test wallet. One real Ed25519 key. Every test run uses it.
 * No mock. The constitutional door either accepts it or the test fails.
 */
export const test = base.extend<{ wallet: string }>({
  wallet: async ({}, use) => {
    const publicKey = await ed25519.getPublicKey(privateKey);
    const w = "0x" + Buffer.from(publicKey).toString("hex").slice(0, 40);
    await use(w);
  },
});

export { expect } from "@playwright/test";
