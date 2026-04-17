#!/usr/bin/env bash
set -euo pipefail

echo "=== Mac Cell Sudoers Provisioning ==="
echo "To allow the pipeline to run headlessly, we need to allow specific commands"
echo "to run via sudo without a password (pfctl, powermetrics, etc)."
echo ""

SUDOERS_FILE="/tmp/mac_cell_sudoers"
USER_NAME=$(whoami)

cat <<EOF > "$SUDOERS_FILE"
# Sudoers configuration for Mac Cell Headless Pipeline
$USER_NAME ALL=(ALL) NOPASSWD: /usr/sbin/installer, /usr/bin/xcode-select, /sbin/pfctl, /usr/bin/powermetrics, /bin/kill
EOF

echo "The following sudoers configuration will be installed to /etc/sudoers.d/mac_cell:"
cat "$SUDOERS_FILE"
echo ""
echo "This requires your password one time to install."

sudo visudo -c -f "$SUDOERS_FILE" || {
    echo "Invalid sudoers file generated. Aborting."
    rm -f "$SUDOERS_FILE"
    exit 1
}

sudo cp "$SUDOERS_FILE" /etc/sudoers.d/mac_cell
sudo chmod 0440 /etc/sudoers.d/mac_cell
sudo chown root:wheel /etc/sudoers.d/mac_cell
rm -f "$SUDOERS_FILE"

echo ""
echo "✅ Sudoers configuration installed successfully."
echo "The headless pipeline can now run without asking for a password."
