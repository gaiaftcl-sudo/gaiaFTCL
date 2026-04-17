# Live Qualification Run Guide (GAMP 5 Sovereign Validation)

This guide provides the exact steps to execute the human-in-the-loop (HITL) qualification flow for the Fusion Mac app. The environment has been cleaned (stale receipts and `~/.gaiaftcl` removed), and the latest `gaiaftcl` CLI and `GaiaFusion.app` artifacts have been rebuilt.

**IMPORTANT:** You must run these commands in your native Mac Terminal (or a Cursor terminal tab) so you can interact with the prompts and the UI. Do not use an automated agent for these steps.

## Step 1: Installation Qualification (IQ)

The IQ phase verifies that the CLI and its dependencies are correctly installed and can generate the necessary cryptographic identities (wallet and cell).

1. **Open your terminal and navigate to the `GAIAOS` directory:**
   ```bash
   cd /Users/richardgillespie/Documents/FoT8D/GAIAOS
   ```

2. **Execute the IQ command:**
   ```bash
   .build/release/gaiaftcl gate run --iq
   ```

3. **What to expect:**
   - You will see a prominent `HUMAN VERIFICATION REQUIRED` banner.
   - The script will pause and ask: `Press [Enter] to confirm and proceed...`
   - **Action:** Press `Enter`.
   - The CLI will output `CALORIE` (or `CURE`) and a JSON receipt.
   - A new `~/.gaiaftcl` directory will be created with your wallet and cell identity.

## Step 2: Operational Qualification (OQ)

The OQ phase verifies that the core operational logic (like the WASM constitutional substrate) functions correctly. It also includes a specific test to validate $\phi$-convergence (Golden Ratio scaling) to ensure the vQbit substrate is protected against harmonic resonance noise.

1. **Execute the OQ command:**
   ```bash
   .build/release/gaiaftcl gate run --oq
   ```

2. **What to expect:**
   - **$\phi$-Stagger:** You will notice a slight, non-rhythmic delay (stochastic stagger) before the script executes, outputting `[vQbitScalingProvider] Enforcing stochastic Phi-stagger: sleeping for X.XXXs...`. This proves the $\phi$-invariant is actively preventing rhythmic synchronization.
   - You will see the `HUMAN VERIFICATION REQUIRED` banner.
   - The script will pause and ask: `Press [Enter] to confirm and proceed...`
   - **Action:** Press `Enter`.
   - The CLI will output `CALORIE` (or `CURE`) and a JSON receipt.

## Step 3: Performance Qualification (PQ)

The PQ phase verifies the end-to-end performance, specifically launching the `GaiaFusion.app` and ensuring it runs without crashing.

1. **Execute the PQ command:**
   ```bash
   .build/release/gaiaftcl gate run --pq
   ```

2. **What to expect:**
   - You will see the `HUMAN VERIFICATION REQUIRED` banner.
   - The script will pause and ask: `Press [Enter] to confirm and proceed...`
   - **Action:** Press `Enter`.
   - The `GaiaFusion.app` will launch in the foreground.
   - **Action:** Interact with the app (e.g., click around, verify the UI loads).
   - **Action:** Manually quit the app (Cmd+Q or via the menu).
   - The terminal command will block until you quit the app. Once quit, it will verify no crash logs were generated and output `CALORIE` (or `CURE`) with a JSON receipt.

## Verification

After completing all three steps, you can verify the receipts were generated successfully:

```bash
ls -l macos/GaiaFusion/evidence/iq/
ls -l macos/GaiaFusion/evidence/oq/
ls -l macos/GaiaFusion/evidence/pq/
```

If all receipts are present and the app launched and closed cleanly, the Sovereign Validation is complete.