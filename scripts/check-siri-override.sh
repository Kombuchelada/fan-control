#!/bin/sh
# Integration check against the installed helper: a curve must stay in effect when
# something else rewrites the fans' targets. Opening Siri does exactly that: macOS drops
# every fan's target to its minimum and leaves the fans in forced mode.
#
#   SIGN_IDENTITY="Developer ID Application: …" scripts/check-siri-override.sh
#
# SIGN_IDENTITY must be the identity the installed helper was signed with ("-" for an
# ad-hoc build), because the helper only accepts clients signed like the app.
# Opens Siri and briefly runs the fans at full speed. Exits 0 if the check passes, 1 if
# not, 2 if it couldn't be run (for example because Siri is turned off).
set -eu
cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:?set SIGN_IDENTITY to the identity the installed helper was signed with}"
swift build --product fanctl >/dev/null
FANCTL=.build/debug/fanctl
WORK="$(mktemp -d)"
CLIENT="$WORK/fanctl-client"
cp "$FANCTL" "$CLIENT"
codesign --force --sign "$IDENTITY" --identifier app.fancontrol.FanControl "$CLIENT" 2>/dev/null

cleanup() {
    [ -n "${A:-}" ] && kill "$A" 2>/dev/null
    osascript -e 'tell application "Siri" to quit' 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

# Exits 0 when every fan is forced to its maximum (what Full Speed asks for).
at_full_speed() {
    $FANCTL status | tee /dev/stderr | awk '/Fan/ { split($0, r, /[(–)]/); max = r[3] + 0; target = $NF + 0
        if ($0 !~ /forced/ || target < max - 5) bad = 1 }
        END { exit bad }'
}

# The client (standing in for the app) follows Full Speed and stays running.
"$CLIENT" client maximum 60 & A=$!
sleep 2
if ! at_full_speed; then
    echo "SETUP FAILED: the client never took control of the fans"
    exit 2
fi

open -a Siri
sleep 5

if ! at_full_speed; then
    echo "FAIL: the fans' targets were changed and the helper didn't set them again"
    # Such a helper leaves the fans forced at minimum. Asking for automatic control makes
    # it start over, so they aren't left that way.
    "$CLIENT" client automatic 1 >/dev/null 2>&1 || true
    exit 1
fi
# The targets are right, but only count that if Siri really did change them.
if /usr/bin/log show --last 15s --predicate 'subsystem == "app.fancontrol.helper"' 2>/dev/null |
    grep -q "taken off its target"; then
    echo "PASS: the helper set the fans' targets again after Siri changed them"
else
    echo "NOT RUN: opening Siri didn't change the fans' targets (is Siri turned on?)"
    exit 2
fi
