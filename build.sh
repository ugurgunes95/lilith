#!/bin/sh
# Usage: ./build.sh [--install]   builds build/Lilith.app, optionally copies to /Applications
set -e
cd "$(dirname "$0")"
ARCHS="--arch arm64 --arch x86_64"  # universal: Apple Silicon and Intel
swift build -c release $ARCHS
APP=build/Lilith.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release $ARCHS --show-bin-path)/Lilith" "$APP/Contents/MacOS/"
mkdir -p "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# A stable identity keeps Accessibility grants across rebuilds; ad-hoc signatures change every build.
# Create it once with ./make-signing-cert.sh.
SIGN=-
security find-identity -p codesigning | grep -q '"Lilith Code Signing"' && SIGN="Lilith Code Signing"
codesign --force --sign "$SIGN" "$APP"
echo "Built $APP"
if [ "$1" = "--install" ]; then
    rm -rf /Applications/Lilith.app
    cp -R "$APP" /Applications/
    echo "Installed /Applications/Lilith.app"
fi
