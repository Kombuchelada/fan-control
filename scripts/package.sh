#!/bin/sh
# Builds the app and zips it for distribution as build/Fan-Control.zip.
#
#   scripts/package.sh
#       ad-hoc signed zip (Gatekeeper will block it on other Macs)
#   SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=<profile> scripts/package.sh
#       Developer ID signed, notarized by Apple and stapled, ready to publish
#
# NOTARY_PROFILE names credentials saved with `xcrun notarytool store-credentials`.
set -eu
cd "$(dirname "$0")/.."

APP="build/Fan Control.app"
ZIP="build/Fan-Control.zip"

zip_app() {
    rm -f "$ZIP"
    # ditto keeps the bundle's structure, symlinks and code signature intact.
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
}

scripts/build.sh
zip_app

if [ -n "${NOTARY_PROFILE:-}" ]; then
    [ -n "${SIGN_IDENTITY:-}" ] || { echo "NOTARY_PROFILE needs SIGN_IDENTITY: Apple only notarizes Developer ID signed apps." >&2; exit 64; }
    echo "Submitting to Apple for notarization (usually a few minutes)…"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m
    # Attach the notarization ticket to the app so it also opens offline, then re-zip.
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    zip_app
    spctl --assess --type execute --verbose=2 "$APP"
fi

shasum -a 256 "$ZIP"
