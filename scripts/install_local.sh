#!/bin/bash
# Build this fork for the current Mac and install it to /Applications.
#
#   scripts/install_local.sh
#
# - Native-arch release build (faster than the universal release build).
# - No Sparkle feed in Info.plist, so the official auto-updater never
#   replaces this fork's build.
# - Ad-hoc signed: macOS treats it as a new app, so Screen Recording and
#   Accessibility must be granted again after the first install.
# - The previously installed app is moved to ~/.Trash, not deleted.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
ARCH="$(uname -m)"
DEST="/Applications/SideScreen.app"
STAGE="$(mktemp -d)/SideScreen.app"

echo "Building Side Screen $VERSION ($ARCH)..."
cd "$ROOT_DIR/MacHost"
swift build -c release --arch "$ARCH"
BIN_DIR="$(swift build -c release --arch "$ARCH" --show-bin-path)"

echo "Assembling app bundle..."
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources" "$STAGE/Contents/Frameworks"
cp "$BIN_DIR/SideScreen" "$STAGE/Contents/MacOS/"
cp -R "$BIN_DIR/Sparkle.framework" "$STAGE/Contents/Frameworks/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$STAGE/Contents/Resources/"

cat > "$STAGE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>SideScreen</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.sidescreen.app</string>
    <key>CFBundleName</key><string>Side Screen</string>
    <key>CFBundleDisplayName</key><string>Side Screen</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><false/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Side Screen needs screen recording access to capture your virtual display and stream it to your Android device.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Side Screen needs Local Network access so your Android tablet can connect to the Mac over WiFi for wireless mode.</string>
    <key>NSBonjourServices</key>
    <array><string>_sidescreen._tcp</string></array>
</dict>
</plist>
EOF

echo "Signing (ad-hoc)..."
"$ROOT_DIR/scripts/sign_app.sh" "$STAGE" - >/dev/null 2>&1

echo "Installing to $DEST..."
pkill -x SideScreen 2>/dev/null || true
sleep 1
if [ -d "$DEST" ]; then
    BACKUP="$HOME/.Trash/SideScreen-previous-$(date +%Y%m%d-%H%M%S).app"
    mv "$DEST" "$BACKUP"
    echo "  previous app moved to $BACKUP"
fi
ditto "$STAGE" "$DEST"
rm -rf "$(dirname "$STAGE")"

# Old permission grants belong to the previous signature and no longer match.
# Clear them so macOS asks again cleanly instead of showing a stale toggle.
tccutil reset ScreenCapture com.sidescreen.app >/dev/null 2>&1 || true
tccutil reset Accessibility com.sidescreen.app >/dev/null 2>&1 || true

open "$DEST"
echo "Done. Grant Screen Recording (and Accessibility for touch) when asked."
