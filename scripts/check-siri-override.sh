#!/bin/sh
# Integration check against the installed helper: when Siri opens, the fans go quiet for a
# few seconds and then return to the curve. macOS quiets them by dropping every fan's
# target to its minimum, leaving the fans in forced mode; the helper has to allow that
# pause and then set its own targets again.
#
#   SIGN_IDENTITY="Developer ID Application: …" scripts/check-siri-override.sh
#
# SIGN_IDENTITY must be the identity the installed helper was signed with ("-" for an
# ad-hoc build), because the helper only accepts clients signed like the app.
# Opens Siri and briefly runs the fans at full speed. Run it with the CPU below 90 °C:
# above that the helper skips the pause. Exits 0 if the check passes, 1 if not, 2 if it
# couldn't be run (for example because Siri is turned off).
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

# Exits 0 when every fan is forced to its maximum (what Full Speed asks for), or with
# "minimum" to its minimum (where macOS puts it for Siri).
targets_at() {
    $FANCTL status | awk -v want="$1" '/Fan/ { split($0, r, /[(–)]/); target = $NF + 0
        wanted = want == "minimum" ? r[2] + 0 : r[3] + 0
        if ($0 !~ /forced/ || target < wanted - 5 || target > wanted + 5) bad = 1 }
        END { exit bad }'
}

# The client (standing in for the app) follows Full Speed and stays running.
"$CLIENT" client maximum 60 & A=$!
sleep 2
if ! targets_at maximum; then
    $FANCTL status
    echo "SETUP FAILED: the client never took control of the fans"
    exit 2
fi

# Watch for three seconds: a helper that undoes the change at once only shows it briefly.
open -a Siri
QUIETED=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    targets_at minimum && QUIETED=1
    sleep 0.2
done
$FANCTL status
if [ "$QUIETED" = 0 ]; then
    echo "NOT RUN: opening Siri didn't change the fans' targets (is Siri turned on?)"
    exit 2
fi
if ! targets_at minimum; then
    echo "FAIL: the helper didn't leave the fans quiet for Siri"
    exit 1
fi

sleep 6
$FANCTL status
if targets_at maximum; then
    echo "PASS: the fans went quiet for Siri, then returned to the curve"
else
    echo "FAIL: the helper didn't return the fans to the curve after Siri quieted them"
    # Such a helper leaves the fans forced at minimum. Asking for automatic control makes
    # it start over, so they aren't left that way.
    "$CLIENT" client automatic 1 >/dev/null 2>&1 || true
    exit 1
fi
