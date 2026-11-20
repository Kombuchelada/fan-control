#!/bin/sh
# Runs the unit tests. Works with just the Command Line Tools (no Xcode), which
# keep the Swift Testing framework outside the default search paths.
set -eu
cd "$(dirname "$0")/.."
DEV="$(xcode-select -p)"
case "$DEV" in
*CommandLineTools*)
    F="$DEV/Library/Developer/Frameworks"
    exec swift test -Xswiftc -F"$F" -Xlinker -F"$F" -Xlinker -rpath -Xlinker "$F" \
        -Xlinker -rpath -Xlinker "$DEV/Library/Developer/usr/lib" "$@"
    ;;
*) exec swift test "$@" ;;
esac
