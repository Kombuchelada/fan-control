#!/bin/sh
# Builds "build/Fan Control.app".
#   scripts/build.sh            build the app
#   scripts/build.sh --install  also copy it to /Applications and launch it
#
# By default the app is ad-hoc signed, which is all a build for your own Mac needs.
# Set SIGN_IDENTITY to a "Developer ID Application: …" certificate in your keychain
# to sign for distribution (hardened runtime and a secure timestamp, as notarization requires).
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

# The helper only accepts XPC connections from a client signed as $APP_ID and, when
# it is Developer ID signed, by the same team. So both must use the same identity.
IDENTITY="${SIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
    SIGN_FLAGS="--options runtime"
else
    SIGN_FLAGS="--options runtime --timestamp"
fi
# shellcheck disable=SC2086
codesign --force --sign "$IDENTITY" $SIGN_FLAGS --identifier "$HELPER_ID" "$APP/Contents/Library/LaunchServices/$HELPER_ID"
# shellcheck disable=SC2086
codesign --force --sign "$IDENTITY" $SIGN_FLAGS --identifier "$APP_ID" "$APP"
codesign --verify --strict --deep "$APP"
echo "Built $APP (signed with ${SIGN_IDENTITY:-ad-hoc signature})"

if [ "${1:-}" = "--install" ]; then
    osascript -e 'tell application id "app.fancontrol.FanControl" to quit' 2>/dev/null || true
    rm -rf "/Applications/Fan Control.app"
    cp -R "$APP" /Applications/
    open "/Applications/Fan Control.app"
    echo "Installed to /Applications"
fi
