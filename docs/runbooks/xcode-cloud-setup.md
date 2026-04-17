# Xcode Cloud Dispatcher Setup

This runbook documents the configuration required to bridge GitHub Actions to Apple's Xcode Cloud infrastructure for production GxP builds.

## GitHub Secrets Required

Navigate to **Settings > Secrets and variables > Actions > Secrets** in the GitHub repository and add the following:

| Secret Name | Value |
|---|---|
| `APP_STORE_CONNECT_ISSUER_ID` | `0be0b98b-ed15-45d9-a644-9a1a26b22d31` |
| `APP_STORE_CONNECT_KEY_ID` | `706IRVGBDV3B` |
| `APP_STORE_CONNECT_PRIVATE_KEY` | The exact contents of the `.p8` file downloaded on Oct 31, 2025. |

## GitHub Variables Required

Navigate to **Settings > Secrets and variables > Actions > Variables** in the GitHub repository and add the following:

| Variable Name | Value |
|---|---|
| `XCODE_CLOUD_WORKFLOW_ID` | The UUID of the Xcode Cloud workflow. |

### How to obtain the `XCODE_CLOUD_WORKFLOW_ID`
1. Log into [App Store Connect](https://appstoreconnect.apple.com).
2. Go to **Apps > GaiaFusion > Xcode Cloud > Manage > Workflows**.
3. Click your workflow.
4. Copy the UUID from the end of the URL: `https://appstoreconnect.apple.com/teams/.../apps/.../ci/workflows/{workflow-id}`.

## Triggering the Build

The workflow `.github/workflows/xcode-cloud-dispatch.yml` is configured to trigger automatically when a signed qualification tag is pushed:

```bash
git tag -s oq-2026-04-17-mac-cell -m "OQ passed"
git push --tags
```

It can also be triggered manually via the GitHub Actions UI (`workflow_dispatch`).
