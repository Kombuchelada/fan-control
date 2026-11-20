#!/bin/sh
# Builds the app and packages it for distribution as build/Fan-Control.zip and, with an
# installer certificate, build/Fan-Control.pkg.
#
#   scripts/package.sh
#       ad-hoc signed zip (Gatekeeper will block it on other Macs)
#   SIGN_IDENTITY="Developer ID Application: …" INSTALLER_IDENTITY="Developer ID Installer: …" \
#   NOTARY_PROFILE=<profile> scripts/package.sh
#       Developer ID signed zip and installer package, both notarized and stapled, ready to publish
#
# NOTARY_PROFILE names credentials saved with `xcrun notarytool store-credentials`.
# Leave out INSTALLER_IDENTITY to skip the .pkg.
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

if [ -n "${INSTALLER_IDENTITY:-}" ]; then
    scripts/make-pkg.sh "$APP" build/Fan-Control.pkg
fi
