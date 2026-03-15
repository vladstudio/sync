#!/bin/bash
set -e
cd "$(dirname "$0")"

swift build -c release

APP=/tmp/Sync.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
cp .build/release/Sync "$APP/Contents/MacOS/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/MenuBarIcon.png "$APP/Contents/Resources/"
cp "Resources/MenuBarIcon@2x.png" "$APP/Contents/Resources/"
cp -R .build/release/Sync_Sync.bundle "$APP/Contents/Resources/" 2>/dev/null || true

pkill -x Sync 2>/dev/null || true
rm -rf /Applications/Sync.app
mv "$APP" /Applications/
touch /Applications/Sync.app
open /Applications/Sync.app
echo "==> Installed Sync.app"
