#!/usr/bin/env bash
set -euo pipefail

echo "=== Mac Cell Provisioning (Phase 0) ==="
echo "This script performs the one-time interactive setup required for the headless qualification pipeline."
echo "It requires your interaction and administrator privileges."
echo ""

# 1. TCC Grants
echo "--- Step 1: TCC Grants ---"
echo "Please ensure that your terminal (e.g., Terminal.app, iTerm2, or Cursor) has:"
echo "  1. Full Disk Access"
echo "  2. Accessibility"
echo "Go to System Settings -> Privacy & Security to grant these permissions."
read -p "Press Enter when you have verified TCC grants..."

# 2. Notary Credentials
echo ""
echo "--- Step 2: Notary Credentials ---"
echo "We will now store your Apple Developer ID credentials in the keychain for headless notarization."
echo "You will need your Apple ID, Team ID, and an App-Specific Password."
read -p "Enter a profile name to store these credentials (e.g., mac-cell-notary): " PROFILE_NAME
if [ -z "$PROFILE_NAME" ]; then
    PROFILE_NAME="mac-cell-notary"
fi

echo "Running: xcrun notarytool store-credentials \"$PROFILE_NAME\""
xcrun notarytool store-credentials "$PROFILE_NAME" || {
    echo "Failed to store notary credentials. Please run manually: xcrun notarytool store-credentials \"$PROFILE_NAME\""
}
echo "Credentials stored under profile: $PROFILE_NAME"
echo "Please update scripts/pq_mac_cell_notary_gate.sh to use this profile name if you changed it from the default."

# 3. Sudoers Configuration
echo ""
echo "--- Step 3: Sudoers Configuration ---"
echo "To allow the pipeline to run headlessly, we need to allow specific commands to run via sudo without a password."
SUDOERS_FILE="/tmp/mac_cell_sudoers"
USER_NAME=$(whoami)

cat <<EOF > "$SUDOERS_FILE"
# Sudoers configuration for Mac Cell Headless Pipeline
$USER_NAME ALL=(ALL) NOPASSWD: /usr/sbin/installer, /usr/bin/xcode-select, /sbin/pfctl
EOF

echo "The following sudoers configuration will be installed to /etc/sudoers.d/mac_cell:"
cat "$SUDOERS_FILE"
echo ""
read -p "Press Enter to install this configuration (requires sudo)..."

sudo visudo -c -f "$SUDOERS_FILE" || {
    echo "Invalid sudoers file generated. Aborting."
    rm -f "$SUDOERS_FILE"
    exit 1
}

sudo cp "$SUDOERS_FILE" /etc/sudoers.d/mac_cell
sudo chmod 0440 /etc/sudoers.d/mac_cell
sudo chown root:wheel /etc/sudoers.d/mac_cell
rm -f "$SUDOERS_FILE"

echo "Sudoers configuration installed successfully."
echo ""
echo "=== Provisioning Complete ==="
echo "The Mac Cell is now ready for headless qualification."
