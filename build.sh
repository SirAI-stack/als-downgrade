#!/bin/zsh
# Builds "ALS Downgrade.app" in ./dist (macOS, needs Xcode Command Line Tools).
set -e
cd "$(dirname "$0")"
A="dist/ALS Downgrade.app"
rm -rf "$A"; mkdir -p "$A/Contents/MacOS" "$A/Contents/Resources"
swiftc -O -target arm64-apple-macos11 app/main.swift -o dist/arm64
swiftc -O -target x86_64-apple-macos11 app/main.swift -o dist/x86_64
lipo -create dist/arm64 dist/x86_64 -output "$A/Contents/MacOS/ALSDowngrade"
rm dist/arm64 dist/x86_64
cp als_downgrade.py "$A/Contents/Resources/"
cp app/Info.plist "$A/Contents/Info.plist"
cp app/AppIcon.icns "$A/Contents/Resources/"
codesign --force -s - "$A"
D="dist/ALS-Downgrade-1.2.dmg"; T=$(mktemp -d)
cp -R "$A" "$T/"; ln -s /Applications "$T/Applications"
rm -f "$D"; hdiutil create -volname "ALS Downgrade" -srcfolder "$T" -ov -format UDZO "$D" >/dev/null
rm -rf "$T"
echo "Built: $A and $D"
