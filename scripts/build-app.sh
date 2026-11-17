#!/bin/zsh
# Builds MeloBuds Control.app (release) into ./build and ad-hoc signs it.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release --product MeloBudsControl
bin="$(swift build -c release --show-bin-path)/MeloBudsControl"

app="build/MeloBuds Control.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/MeloBudsControl"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

codesign --force --options runtime --sign - "$app"
echo "Built $app"
