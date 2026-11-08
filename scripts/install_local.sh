#!/bin/bash
# Build this fork for the current Mac and install it to /Applications.
#
#   scripts/install_local.sh
#
# - Native-arch release build (faster than the universal release build).
# - No Sparkle feed in Info.plist, so the official auto-updater never
#   replaces this fork's build.
# - Signed with the stable local identity from scripts/setup_signing.sh when
#   present, so Screen Recording / Accessibility grants survive reinstalls.
#   Falls back to ad-hoc (grants must be re-approved after every install).
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

SIGN_IDENTITY="SideScreen Local Signing"
SIGN_KEYCHAIN="$HOME/Library/Keychains/sidescreen-signing.keychain-db"
if security find-certificate -c "$SIGN_IDENTITY" "$SIGN_KEYCHAIN" >/dev/null 2>&1; then
    echo "Signing with '$SIGN_IDENTITY'..."
    security unlock-keychain -p sidescreen-local "$SIGN_KEYCHAIN"
    SIGN=(codesign --force --options runtime --timestamp=none
          --keychain "$SIGN_KEYCHAIN" --sign "$SIGN_IDENTITY")
    SPARKLE="$STAGE/Contents/Frameworks/Sparkle.framework"
    # Inside-out order, same as scripts/sign_app.sh.
    "${SIGN[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc" 2>/dev/null
    "${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" 2>/dev/null
    "${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate" 2>/dev/null
    "${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app" 2>/dev/null
    "${SIGN[@]}" "$SPARKLE" 2>/dev/null
    "${SIGN[@]}" --entitlements "$ROOT_DIR/MacHost/SideScreen.entitlements" "$STAGE" 2>/dev/null
    codesign --verify --strict "$STAGE"
else
    echo "Signing ad-hoc (run scripts/setup_signing.sh once to keep permissions across installs)..."
    "$ROOT_DIR/scripts/sign_app.sh" "$STAGE" - >/dev/null 2>&1
fi
NEW_REQ="$(codesign -d -r- "$STAGE" 2>/dev/null | grep designated || true)"
OLD_REQ=""
[ -d "$DEST" ] && OLD_REQ="$(codesign -d -r- "$DEST" 2>/dev/null | grep designated || true)"

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

if [ "$NEW_REQ" != "$OLD_REQ" ] || [[ "$NEW_REQ" == *cdhash* ]]; then
    # Grants belong to the previous signature and no longer match. Clear them
    # so macOS asks again cleanly instead of showing a stale, inert toggle.
    tccutil reset ScreenCapture com.sidescreen.app >/dev/null 2>&1 || true
    tccutil reset Accessibility com.sidescreen.app >/dev/null 2>&1 || true
    PERMS_RESET=1
fi

open "$DEST"
if [ -n "${PERMS_RESET:-}" ]; then
    echo "Done. Signature changed — grant Screen Recording (and Accessibility for touch) again."
else
    echo "Done. Same signature as before — existing permissions are kept."
fi
