#!/bin/bash
# Builds FocusForest.app into ./build (pass --install to also copy it to /Applications).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/FocusForest.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FocusForest "$APP/Contents/MacOS/FocusForest"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>FocusForest</string>
    <key>CFBundleDisplayName</key><string>Fokus-Wald</string>
    <key>CFBundleIdentifier</key><string>local.focusforest.app</string>
    <key>CFBundleExecutable</key><string>FocusForest</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Fertig: $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/FocusForest.app"
    cp -R "$APP" /Applications/
    echo "Installiert: /Applications/FocusForest.app"
fi
