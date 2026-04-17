#!/usr/bin/env bash
set -euo pipefail

echo "=== Headless CLT Installation ==="
echo "Mounting Command Line Tools DMG..."

DMG_PATH="$HOME/Downloads/Command_Line_Tools_for_Xcode_26.4.1.dmg"
if [ ! -f "$DMG_PATH" ]; then
    echo "Error: DMG not found at $DMG_PATH"
    exit 1
fi

hdiutil attach "$DMG_PATH" -nobrowse

echo "Locating package..."
PKG=$(find /Volumes -maxdepth 3 -name "Command Line Tools*.pkg" -print -quit)
if [ -z "$PKG" ]; then
    echo "Error: Package not found in mounted DMG."
    hdiutil detach "$(find /Volumes -maxdepth 1 -name "Command Line Developer Tools" -print -quit)"
    exit 1
fi

echo "Installing package headlessly (requires sudoers configuration)..."
sudo installer -pkg "$PKG" -target /

VOL=$(dirname "$(dirname "$PKG")")
echo "Detaching volume..."
hdiutil detach "$VOL"

echo "Forcing active developer path to CLT..."
sudo xcode-select --switch /Library/Developer/CommandLineTools

echo "Verifying installation..."
xcode-select -p
clang --version | head -1
make --version | head -1
xcrun --show-sdk-path

echo "=== CLT Installation Complete ==="
