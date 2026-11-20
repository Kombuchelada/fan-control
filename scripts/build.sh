#!/bin/sh
# Builds "build/Fan Control.app".
#   scripts/build.sh            build the app
#   scripts/build.sh --install  also copy it to /Applications and launch it
set -eu
cd "$(dirname "$0")/.."

APP="build/Fan Control.app"
HELPER_ID="app.fancontrol.helper"
APP_ID="app.fancontrol.FanControl"

swift build -c release --product FanControl
swift build -c release --product FanControlHelper
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchServices"
cp "$BIN/FanControl" "$APP/Contents/MacOS/FanControl"
cp "$BIN/FanControlHelper" "$APP/Contents/Library/LaunchServices/$HELPER_ID"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/helper-tool.sh "Resources/$HELPER_ID.plist" "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signatures. The helper only accepts XPC connections from a client whose
# signing identifier is $APP_ID, so the app must be signed with it.
codesign --force --sign - --identifier "$HELPER_ID" --options runtime "$APP/Contents/Library/LaunchServices/$HELPER_ID"
codesign --force --sign - --identifier "$APP_ID" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
    osascript -e 'tell application id "app.fancontrol.FanControl" to quit' 2>/dev/null || true
    rm -rf "/Applications/Fan Control.app"
    cp -R "$APP" /Applications/
    open "/Applications/Fan Control.app"
    echo "Installed to /Applications"
fi
