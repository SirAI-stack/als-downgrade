#!/bin/zsh
# Builds "ALS Downgrade.app" in ./dist (macOS, needs Xcode Command Line Tools).
set -e
cd "$(dirname "$0")"
A="dist/ALS Downgrade.app"
rm -rf "$A"; mkdir -p "$A/Contents/MacOS" "$A/Contents/Resources"
swiftc -O app/main.swift -o "$A/Contents/MacOS/ALSDowngrade"
cp als_downgrade.py "$A/Contents/Resources/"
cp app/Info.plist "$A/Contents/Info.plist"
cp app/AppIcon.icns "$A/Contents/Resources/"
codesign --force -s - "$A"
echo "Built: $A"
