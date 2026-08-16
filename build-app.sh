#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
swift build -c release

APP="$ROOT/Vimshot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/vimshot "$APP/Contents/MacOS/vimshot"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Vimshot</string>
    <key>CFBundleExecutable</key>
    <string>vimshot</string>
    <key>CFBundleIdentifier</key>
    <string>com.shivom.vimshot</string>
    <key>CFBundleName</key>
    <string>Vimshot</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Use a persistent local signing identity when available. A fresh ad-hoc
# signature changes after every build and makes macOS Accessibility treat the
# rebuilt app as a different executable.
SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(.*\)"/\1/p' | head -1)
if [ -n "$SIGNING_IDENTITY" ]; then
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP" >/dev/null
else
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi
printf 'Built %s\n' "$APP"
