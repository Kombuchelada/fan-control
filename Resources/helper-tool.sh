#!/bin/sh
# Installs or removes the Fan Control privileged helper. Run as root by the app.
#   helper-tool.sh install <path to Fan Control.app>
#   helper-tool.sh uninstall
set -eu

LABEL="app.fancontrol.helper"
HELPER="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

stop() {
    # The helper returns fans to automatic control when it is stopped.
    launchctl bootout "system/$LABEL" 2>/dev/null || true
}

case "${1:-}" in
install)
    APP="${2:?missing app path}"
    stop
    mkdir -p /Library/PrivilegedHelperTools
    install -m 755 -o root -g wheel "$APP/Contents/Library/LaunchServices/$LABEL" "$HELPER"
    # A downloaded app carries the quarantine flag; the user has already approved the app
    # itself, so don't let the copied helper be held back by it.
    xattr -d com.apple.quarantine "$HELPER" 2>/dev/null || true
    install -m 644 -o root -g wheel "$APP/Contents/Resources/$LABEL.plist" "$PLIST"
    launchctl bootstrap system "$PLIST"
    ;;
uninstall)
    stop
    rm -f "$HELPER" "$PLIST"
    ;;
*)
    echo "usage: $0 install <app> | uninstall" >&2
    exit 64
    ;;
esac
