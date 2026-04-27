#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT="FranklinApp"
BUILD_DIR="${ROOT}/.build/arm64-apple-macosx/release"
DIST_DIR="${ROOT}/dist"
APP_DIR="${DIST_DIR}/${PRODUCT}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"

swift build -c release --package-path "${ROOT}" --product "${PRODUCT}" >/dev/null
[[ -x "${BUILD_DIR}/${PRODUCT}" ]] || { echo "REFUSED: missing release executable ${BUILD_DIR}/${PRODUCT}" >&2; exit 1; }

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
cp "${BUILD_DIR}/${PRODUCT}" "${MACOS_DIR}/${PRODUCT}"

cat > "${CONTENTS}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>FranklinApp</string>
  <key>CFBundleIdentifier</key><string>com.gaia.franklin</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>FranklinApp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
</dict>
</plist>
PLIST

echo "APP: ${APP_DIR}"
