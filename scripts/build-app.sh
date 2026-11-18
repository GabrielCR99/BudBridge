#!/bin/zsh
# Builds BudBridge.app (release) into ./build and ad-hoc signs it.
set -euo pipefail
cd "${0:A:h}/.."

# Record the real SDK in the binary (SwiftPM writes the deployment target there), so macOS
# treats BudBridge as a current app: e.g. the macOS 26 look rather than compatibility mode.
sdk="$(xcrun --show-sdk-version)"
link=(-Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$sdk")
swift build -c release --product BudBridge "${link[@]}"
bin="$(swift build -c release --product BudBridge --show-bin-path "${link[@]}")/BudBridge"

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
