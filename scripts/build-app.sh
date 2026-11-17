#!/bin/zsh
# Builds BudBridge.app (release) into ./build and ad-hoc signs it.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release --product BudBridge
bin="$(swift build -c release --show-bin-path)/BudBridge"

app="build/BudBridge.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/BudBridge"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp -R Resources/Panels "$app/Contents/Resources/Panels"

# Localizations: String Catalogs → <lang>.lproj/*.strings (English is the source language).
for catalog in Resources/Localizable.xcstrings Resources/InfoPlist.xcstrings; do
  xcrun xcstringstool compile "$catalog" --output-directory "$app/Contents/Resources"
done
mkdir -p "$app/Contents/Resources/en.lproj"

codesign --force --options runtime --sign - "$app"
echo "Built $app"
