#!/bin/bash
# Builds "LAN Monitor.app" from the Swift package and ad-hoc signs it
# so it can run locally without a Gatekeeper prompt.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="LAN Monitor"
APP_DIR="${APP_NAME}.app"
BUNDLE_ID="com.local.lanmonitor"

echo "Building release binary..."
swift build -c release

echo "Assembling ${APP_DIR}..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp ".build/release/LANMonitor" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Ad-hoc code signing..."
codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "Gotowe: $APP_DIR"
echo "Uruchom:  open \"$APP_DIR\""
