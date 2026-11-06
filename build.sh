#!/usr/bin/env bash
# Build Headroom.app and install it to /Applications.
#
# Signs with the Apple Development identity of the team in project.yml. A stable
# identity is what keeps the widget registered across rebuilds.
#
#   ./build.sh            build, install and launch
#   ./build.sh --no-install   build only; the app is left in .build-xcode
#
set -euo pipefail
cd "$(dirname "$0")"

command -v xcodegen >/dev/null || {
    echo "xcodegen is required:  brew install xcodegen" >&2
    exit 1
}

DERIVED=".build-xcode"
APP="$DERIVED/Build/Products/Release/Headroom.app"

VERSION_SETTINGS=$(scripts/version.sh)

xcodegen generate
xcodebuild build \
    -project Headroom.xcodeproj \
    -scheme Headroom \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    $VERSION_SETTINGS

echo
codesign --verify --deep --strict "$APP" && echo "Signature OK: $APP"
echo "Version: ${VERSION_SETTINGS:-from project.yml}"

[[ "${1:-}" == "--no-install" ]] && exit 0

# Must not be running, or the copy replaces a live bundle.
osascript -e 'quit app "Headroom"' 2>/dev/null || true
# Quitting the app leaves the extension alive, and macOS would go on drawing
# widgets with its old code for days, ignoring whatever new fields bundle.json has.
pkill -x HeadroomWidget || true
rm -rf "/Applications/Headroom.app"
cp -R "$APP" /Applications/

echo
echo "Installed /Applications/Headroom.app"
open "/Applications/Headroom.app"

sleep 3
echo
echo "Widget registration:"
pluginkit -m -p com.apple.widgetkit-extension 2>/dev/null | grep -i "se.frodlund.claude-usage.widget" \
    || echo "  Not registered yet. Open the widget gallery once; macOS registers on demand."
