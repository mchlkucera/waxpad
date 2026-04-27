#!/bin/bash
set -euo pipefail

APP_NAME="Waxpad"
BUNDLE_ID="com.michalkucera.waxpad"
BUILD_DIR=".build/arm64-apple-macosx/debug"
APP_DIR="$HOME/Applications/$APP_NAME.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Building $APP_NAME..."
swift build

# Kill running instance if any
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    echo "Stopping running $APP_NAME..."
    pkill -x "$APP_NAME" || true
    sleep 1
fi

echo "Creating app bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Copy app icon
if [ -f "$SCRIPT_DIR/Waxpad/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/Waxpad/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
    echo "App icon installed."
fi

cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Waxpad</string>
    <key>CFBundleIdentifier</key>
    <string>com.michalkucera.waxpad</string>
    <key>CFBundleName</key>
    <string>Waxpad</string>
    <key>CFBundleDisplayName</key>
    <string>Waxpad</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Re-register with Launch Services so Spotlight picks up the icon
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR"
touch "$APP_DIR"

echo ""
echo "Done! $APP_DIR is ready."
echo "Launching $APP_NAME..."
open "$APP_DIR"

echo ""
echo "---"
echo "Add to Login Items (start on boot)?"
echo "  Run: osascript -e 'tell application \"System Events\" to make login item at end with properties {path:\"$APP_DIR\", hidden:false}'"
