#!/bin/zsh
# Builds FantasyTicker.app next to this script.
set -e
cd "$(dirname "$0")"
APP=FantasyTicker.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 main.swift -o "$APP/Contents/MacOS/FantasyTicker"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>FantasyTicker</string>
  <key>CFBundleIdentifier</key><string>local.fantasyticker</string>
  <key>CFBundleExecutable</key><string>FantasyTicker</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "Built $(pwd)/$APP"
