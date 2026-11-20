#!/bin/sh
# Integration check against the installed helper: when two Fan Control apps share it
# (two user accounts), one app quitting must not take the fans away from the other.
#
#   SIGN_IDENTITY="Developer ID Application: …" scripts/check-multi-client.sh
#
# SIGN_IDENTITY must be the identity the installed helper was signed with ("-" for an
# ad-hoc build), because the helper only accepts clients signed like the app.
# Briefly runs the fans at full speed. Exits 0 if the check passes, 1 if not.
set -eu
cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:?set SIGN_IDENTITY to the identity the installed helper was signed with}"
swift build --product fanctl >/dev/null
FANCTL=.build/debug/fanctl
WORK="$(mktemp -d)"
CLIENT="$WORK/fanctl-client"
cp "$FANCTL" "$CLIENT"
codesign --force --sign "$IDENTITY" --identifier app.fancontrol.FanControl "$CLIENT" 2>/dev/null

cleanup() { [ -n "${A:-}" ] && kill "$A" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

# Exits 0 when every fan is forced to its maximum (what Full Speed asks for).
at_full_speed() {
    $FANCTL status | tee /dev/stderr | awk '/Fan/ { split($0, r, /[(–)]/); max = r[3] + 0; target = $NF + 0
        if ($0 !~ /forced/ || target < max - 5) bad = 1 }
        END { exit bad }'
}

# Client A (this user's app) follows Full Speed and stays running.
"$CLIENT" client maximum 60 & A=$!
sleep 2
if ! at_full_speed; then
    echo "SETUP FAILED: client A never took control of the fans"
    exit 2
fi

# Client B (the other account's app) takes over, then quits. RELEASE=0 skips the
# "automatic" request the app sends as it quits, leaving only the disconnect.
if [ "${RELEASE:-1}" = 1 ]; then
    "$CLIENT" client quiet 2 --release
else
    "$CLIENT" client quiet 2
fi
sleep 3

# A is still running, so its Full Speed curve should be back in effect.
if at_full_speed; then
    echo "PASS: client A's curve is in effect after client B quit"
else
    echo "FAIL: client B quitting took the fans away from client A"
    exit 1
fi
