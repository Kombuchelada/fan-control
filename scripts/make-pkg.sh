#!/bin/sh
# Wraps a built (ideally notarized) Fan Control.app in a signed installer package.
#
#   INSTALLER_IDENTITY="Developer ID Installer: …" [NOTARY_PROFILE=<profile>] \
#       scripts/make-pkg.sh "<path to Fan Control.app>" [output.pkg]
#
# The package installs the app into /Applications, then (as root) installs or updates the
# fan helper and starts the app for the user at the screen. It refuses to install on Apple
# silicon or before macOS 14. With NOTARY_PROFILE set, the package is notarized and stapled.
set -eu
cd "$(dirname "$0")/.."

APP_SRC="${1:?usage: scripts/make-pkg.sh <Fan Control.app> [output.pkg]}"
OUT="${2:-build/Fan-Control.pkg}"
IDENTITY="${INSTALLER_IDENTITY:?set INSTALLER_IDENTITY to a \"Developer ID Installer: …\" certificate}"
PKG_ID="app.fancontrol.FanControl.pkg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_SRC/Contents/Info.plist")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root" "$WORK/scripts" "$WORK/packages"
ditto "$APP_SRC" "$WORK/root/Fan Control.app"
cp Resources/pkg/postinstall "$WORK/scripts/postinstall"

# Installer "relocates" bundles by default: if a copy with the same bundle ID exists
# anywhere else (say, a build folder), it updates that copy instead of /Applications.
pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$WORK/component.plist"

pkgbuild --root "$WORK/root" --component-plist "$WORK/component.plist" \
    --install-location /Applications --scripts "$WORK/scripts" \
    --identifier "$PKG_ID" --version "$VERSION" \
    "$WORK/packages/FanControl.pkg" >/dev/null

# Start from the distribution productbuild would generate, then add a title, the macOS
# minimum and an Intel-only check. (hostArchitectures="x86_64" alone would make Apple
# silicon Macs offer to install Rosetta instead of explaining that Fan Control can't work.)
productbuild --synthesize --package "$WORK/packages/FanControl.pkg" "$WORK/distribution.xml" >/dev/null
python3 - "$WORK/distribution.xml" <<'PY'
import sys
path = sys.argv[1]
xml = open(path).read()
extra = '''    <title>Fan Control</title>
    <options customize="never" require-scripts="false" hostArchitectures="x86_64,arm64"/>
    <domains enable_localSystem="true" enable_anywhere="false" enable_currentUserHome="false"/>
    <allowed-os-versions>
        <os-version min="14.0"/>
    </allowed-os-versions>
    <installation-check script="intelOnly()"/>
    <script><![CDATA[
    function intelOnly() {
        if (system.sysctl('hw.optional.arm64') == 1) {
            my.result.type = 'Fatal';
            my.result.title = 'Fan Control requires an Intel Mac';
            my.result.message = 'Fan Control controls the fans of Intel Macs. Macs with Apple silicon manage their fans differently and aren\\'t supported.';
            return false;
        }
        return true;
    }
    ]]></script>
'''
# Drop the synthesized <options> (we supply our own) and insert ours after the root element.
import re
xml = re.sub(r'\s*<options [^>]*/>', '', xml)
xml, count = re.subn(r'<installer-gui-script minSpecVersion="\d+">',
                    lambda m: '<installer-gui-script minSpecVersion="2">\n' + extra.rstrip('\n'), xml, count=1)
assert count == 1, xml
open(path, 'w').write(xml)
PY

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
productbuild --distribution "$WORK/distribution.xml" --package-path "$WORK/packages" \
    --sign "$IDENTITY" --timestamp "$OUT"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "Submitting $OUT to Apple for notarization…"
    xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m
    xcrun stapler staple "$OUT"
    spctl --assess --type install --verbose=2 "$OUT"
fi
pkgutil --check-signature "$OUT" | sed -n '1,3p'
shasum -a 256 "$OUT"
