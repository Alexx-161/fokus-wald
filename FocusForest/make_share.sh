#!/bin/bash
# Builds a shareable Fokus-Wald.zip (Apple silicon + Intel, macOS 14+) with a step-by-step guide.
# Usage: ./make_share.sh [output.zip]   (default: ~/Desktop/Fokus-Wald.zip)
set -euo pipefail
cd "$(dirname "$0")"
OUT="${1:-$HOME/Desktop/Fokus-Wald.zip}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Keep local paths (and so the user name) out of the binary; build outside the project so the
# path remapping does not touch the module cache.
BUILD="${TMPDIR:-/tmp}/focusforest-share"
for ARCH in arm64 x86_64; do
    swift build -c release --triple "$ARCH-apple-macosx14.0" --scratch-path "$BUILD/$ARCH" \
        -Xswiftc -file-prefix-map -Xswiftc "$PWD=."
done

PKG="$WORK/Fokus-Wald"
APP="$PKG/Fokus-Wald.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$BUILD/arm64/release/FocusForest" "$BUILD/x86_64/release/FocusForest" \
    -output "$APP/Contents/MacOS/FocusForest"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Fokus-Wald</string>
    <key>CFBundleDisplayName</key><string>Fokus-Wald</string>
    <key>CFBundleIdentifier</key><string>local.focusforest.app</string>
    <key>CFBundleExecutable</key><string>FocusForest</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleURLTypes</key>
    <array><dict>
        <key>CFBundleURLName</key><string>local.focusforest.app</string>
        <key>CFBundleURLSchemes</key><array><string>fokuswald</string></array>
    </dict></array>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"

ICON_B64="$(base64 -i Resources/AppIcon-256.png | tr -d '\n')"
python3 - "$ICON_B64" Resources/Anleitung.template.html "$PKG/Bitte zuerst lesen.html" <<'PY'
import sys
icon, src, dst = sys.argv[1:4]
open(dst, "w").write(open(src).read().replace("{{ICON}}", icon))
PY

rm -f "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$PKG" "$OUT"
echo "Fertig: $OUT"
