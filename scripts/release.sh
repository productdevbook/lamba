#!/usr/bin/env bash
# release.sh: build, sign, notarize and package Lamba, update the Sparkle feed and (optionally) publish.
#
# Usage:
#   ./scripts/release.sh 1.0.0                 full release
#   ./scripts/release.sh 1.0.0 --no-notarize   signed build + DMG only (no Apple round trip, no feed)
#
# Signing: the "Developer ID Application" identity in the keychain (override with SIGN_IDENTITY).
#   APPLE_TEAM_ID            10-character team id
#
# Notarization, one of:
#   NOTARY_PROFILE           a keychain profile from `xcrun notarytool store-credentials <name>`
#   ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID     an App Store Connect API key
#   APPLE_ID, APPLE_APP_PASSWORD                an Apple ID with an app-specific password
#
# Sparkle: the feed is signed with the EdDSA key in the login keychain (account "lamba", created with
# `generate_keys --account lamba`). On another machine set SPARKLE_KEY_FILE to the exported key.
#
# Publishing (optional):
#   R2_BUCKET                upload the DMG, Lamba.dmg (latest) and appcast.xml to <bucket>/lamba/ with wrangler
#   GH_RELEASE=1             also create a GitHub release with the DMG attached
set -euo pipefail

NOTARIZE=1
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --no-notarize) NOTARIZE=0 ;;
    -*) echo "unknown option: $arg"; exit 1 ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done
VERSION="${POSITIONAL[0]:?usage: release.sh <version> [--no-notarize] (e.g. 1.0.0)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.2.3"; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/build/release-$VERSION"
APP="$ROOT/build/Lamba.app"
DMG="$OUT/Lamba-$VERSION.dmg"
APPCAST_DIR="$OUT/appcast"
CDN_PREFIX="https://cdn.productdevbook.com/lamba/"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"

: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY" \
  || { echo "missing signing identity: $SIGN_IDENTITY"; exit 1; }

if [ "$NOTARIZE" = 0 ]; then
  NOTARY_AUTH=()
elif [ -n "${NOTARY_PROFILE:-}" ]; then
  NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
elif [ -n "${ASC_KEY_PATH:-}" ]; then
  NOTARY_AUTH=(--key "$ASC_KEY_PATH" --key-id "${ASC_KEY_ID:?}" --issuer "${ASC_ISSUER_ID:?}")
else
  : "${APPLE_ID:?set NOTARY_PROFILE, ASC_KEY_PATH/ASC_KEY_ID/ASC_ISSUER_ID, or APPLE_ID and APPLE_APP_PASSWORD}"
  NOTARY_AUTH=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "${APPLE_APP_PASSWORD:?}")
fi

rm -rf "$OUT"
mkdir -p "$OUT"

# --- Version -----------------------------------------------------------------------------------
echo "→ Version $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Support/Info.plist
sed -i '' -E "s/(static let current = )\"[^\"]+\"/\1\"$VERSION\"/" Sources/LambaCore/Constants.swift
BUILD=$(date +%Y%m%d%H%M)

# --- Test and build ----------------------------------------------------------------------------
echo "→ Testing"
swift test 2>&1 | tail -3
echo "→ Building and signing"
VERSION="$VERSION" BUILD="$BUILD" SIGN_IDENTITY="$SIGN_IDENTITY" ./scripts/build-app.sh

for signed in "$APP" "$APP/Contents/Resources/app.lamba.helper" "$APP/Contents/Resources/lamba" "$APP/Contents/Frameworks/Sparkle.framework"; do
  details=$(codesign -dvv "$signed" 2>&1)
  echo "$details" | grep -q "flags=.*runtime" || { echo "hardened runtime missing: $signed"; exit 1; }
  echo "$details" | grep -q "^Timestamp=" || { echo "secure timestamp missing: $signed"; exit 1; }
  echo "$details" | grep -q "^TeamIdentifier=$APPLE_TEAM_ID" || { echo "wrong team: $signed"; exit 1; }
done

# --- Notarize the app --------------------------------------------------------------------------
if [ "$NOTARIZE" = 1 ]; then
  echo "→ Notarizing the app"
  ditto -c -k --keepParent "$APP" "$OUT/Lamba.zip"
  xcrun notarytool submit "$OUT/Lamba.zip" "${NOTARY_AUTH[@]}" --wait
  xcrun stapler staple "$APP"
  rm "$OUT/Lamba.zip"
fi

# --- DMG ---------------------------------------------------------------------------------------
echo "→ Building the DMG"
if command -v create-dmg >/dev/null 2>&1; then
  create-dmg --volname "Lamba $VERSION" --volicon Support/AppIcon.icns \
    --window-pos 200 120 --window-size 540 380 --icon-size 100 \
    --icon "Lamba.app" 140 180 --hide-extension "Lamba.app" --app-drop-link 400 180 \
    "$DMG" "$APP"
else
  STAGING="$(mktemp -d)"
  ditto "$APP" "$STAGING/Lamba.app"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "Lamba $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -quiet "$DMG"
  rm -rf "$STAGING"
fi
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"

if [ "$NOTARIZE" = 0 ]; then
  echo
  echo "✓ Signed, not notarized: $DMG"
  exit 0
fi

echo "→ Notarizing the DMG"
xcrun notarytool submit "$DMG" "${NOTARY_AUTH[@]}" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

# --- Sparkle feed ------------------------------------------------------------------------------
# Start from the published feed so earlier releases stay listed, add this DMG and sign it.
echo "→ Updating the appcast"
mkdir -p "$APPCAST_DIR"
cp "$DMG" "$APPCAST_DIR/"
NOTES="$ROOT/release-notes/$VERSION.html"
[ -f "$NOTES" ] && cp "$NOTES" "$APPCAST_DIR/Lamba-$VERSION.html"
curl -fsSL "${CDN_PREFIX}appcast.xml" -o "$APPCAST_DIR/appcast.xml" \
  || echo "  (no published appcast yet, starting a new one)"
KEY_ARGS=(--account lamba)
[ -n "${SPARKLE_KEY_FILE:-}" ] && KEY_ARGS=(--ed-key-file "$SPARKLE_KEY_FILE")
"$SPARKLE_BIN/generate_appcast" "${KEY_ARGS[@]}" \
  --download-url-prefix "$CDN_PREFIX" \
  --maximum-deltas 0 \
  "$APPCAST_DIR"

# --- Publish -----------------------------------------------------------------------------------
if [ -n "${R2_BUCKET:-}" ]; then
  command -v wrangler >/dev/null 2>&1 || { echo "R2_BUCKET is set but wrangler is not installed (npm i -g wrangler)"; exit 1; }
  echo "→ Uploading to R2 ($R2_BUCKET/lamba/)"
  # The DMG first: installed copies offer the update as soon as the feed changes.
  wrangler r2 object put "$R2_BUCKET/lamba/Lamba-$VERSION.dmg" --file "$DMG" --remote
  wrangler r2 object put "$R2_BUCKET/lamba/Lamba.dmg" --file "$DMG" --remote
  [ -f "$APPCAST_DIR/Lamba-$VERSION.html" ] && \
    wrangler r2 object put "$R2_BUCKET/lamba/Lamba-$VERSION.html" --file "$APPCAST_DIR/Lamba-$VERSION.html" --remote
  wrangler r2 object put "$R2_BUCKET/lamba/appcast.xml" --file "$APPCAST_DIR/appcast.xml" --remote \
    --content-type application/xml
fi

if [ "${GH_RELEASE:-}" = 1 ]; then
  echo "→ GitHub release v$VERSION"
  NOTES_ARGS=(--generate-notes)
  [ -f "$NOTES" ] && NOTES_ARGS=(--notes-file "$NOTES")
  gh release create "v$VERSION" "$DMG" --title "Lamba $VERSION" "${NOTES_ARGS[@]}"
fi

echo
echo "✓ $DMG"
echo "✓ $APPCAST_DIR/appcast.xml"
if [ -z "${R2_BUCKET:-}" ]; then
  echo
  echo "Next: upload to the lamba/ folder of the CDN bucket, the DMG first (also as Lamba.dmg),"
  echo "then appcast.xml. Installed copies offer the update as soon as the feed changes."
fi
echo "Commit the version bump and tag it: git commit -am \"Release $VERSION\" && git tag v$VERSION"
