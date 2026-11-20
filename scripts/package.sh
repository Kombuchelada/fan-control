#!/bin/sh
# Builds the app and zips it for distribution as build/Fan-Control.zip.
set -eu
cd "$(dirname "$0")/.."
scripts/build.sh
rm -f build/Fan-Control.zip
# ditto keeps the bundle's structure, symlinks and code signature intact.
ditto -c -k --sequesterRsrc --keepParent "build/Fan Control.app" build/Fan-Control.zip
shasum -a 256 build/Fan-Control.zip
