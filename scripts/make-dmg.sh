#!/bin/bash
# Builds a distributable build/Lamba-<version>.dmg (app + Applications shortcut).
#
# Release: SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=<keychain profile> ./scripts/make-dmg.sh
#   (create the profile once with: xcrun notarytool store-credentials <profile>)
# Without those variables the DMG is ad-hoc signed and only suitable for local testing.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Support/Info.plist)"
DMG="build/Lamba-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R build/Lamba.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Lamba $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -quiet "$DMG"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
else
  echo "warning: no SIGN_IDENTITY; this DMG will be blocked by Gatekeeper on other Macs" >&2
fi
echo "Built $DMG"
