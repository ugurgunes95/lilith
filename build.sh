#!/bin/sh
# Usage: ./build.sh [--install]   builds build/Lilith.app, optionally copies to /Applications
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Lilith.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Lilith "$APP/Contents/MacOS/"
mkdir -p "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built $APP"
if [ "$1" = "--install" ]; then
    rm -rf /Applications/Lilith.app
    cp -R "$APP" /Applications/
    echo "Installed /Applications/Lilith.app"
fi
