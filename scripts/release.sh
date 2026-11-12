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
# Publishing: downloads and the update feed are GitHub releases of RELEASES_REPO
# (default productdevbook/lamba).
#   PUBLISH=1                create release v<version> with the DMG, Lamba.dmg and appcast.xml (uses `gh`)
#   TAP=1                    update Casks/lamba.rb in productdevbook/homebrew-tap (`brew install --cask
#                            productdevbook/tap/lamba`); pushes over SSH (GIT_SSH_COMMAND for a deploy key)
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
RELEASES_REPO="${RELEASES_REPO:-productdevbook/lamba}"
RELEASES_URL="https://github.com/$RELEASES_REPO/releases"
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

for signed in "$APP" "$APP/Contents/Resources/dev.hamur.lamba.helper" "$APP/Contents/Resources/lamba" "$APP/Contents/Frameworks/Sparkle.framework"; do
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
curl -fsSL "$RELEASES_URL/latest/download/appcast.xml" -o "$APPCAST_DIR/appcast.xml" \
  || echo "  (no published appcast yet, starting a new one)"
KEY_ARGS=(--account lamba)
[ -n "${SPARKLE_KEY_FILE:-}" ] && KEY_ARGS=(--ed-key-file "$SPARKLE_KEY_FILE")
"$SPARKLE_BIN/generate_appcast" "${KEY_ARGS[@]}" \
  --download-url-prefix "$RELEASES_URL/download/v$VERSION/" \
  --embed-release-notes \
  --maximum-deltas 0 \
  "$APPCAST_DIR"

# --- Publish -----------------------------------------------------------------------------------
if [ "${PUBLISH:-}" = 1 ]; then
  echo "→ Publishing v$VERSION to $RELEASES_REPO"
  # The feed points at the latest release, so the DMG and feed go up together in one release.
  cp "$DMG" "$OUT/Lamba.dmg"
  NOTES_ARGS=(--notes "Lamba $VERSION")
  [ -f "$NOTES" ] && NOTES_ARGS=(--notes "$(sed -e 's/<[^>]*>//g' "$NOTES" | sed '/^[[:space:]]*$/d')")
  gh release create "v$VERSION" --repo "$RELEASES_REPO" --title "Lamba $VERSION" "${NOTES_ARGS[@]}" \
    "$DMG" "$OUT/Lamba.dmg" "$APPCAST_DIR/appcast.xml"
fi

if [ "${TAP:-}" = 1 ]; then
  echo "→ Homebrew cask $VERSION"
  SHA256=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
  TAP_DIR="$OUT/homebrew-tap"
  git clone -q git@github.com:productdevbook/homebrew-tap.git "$TAP_DIR"
  mkdir -p "$TAP_DIR/Casks"
  cat > "$TAP_DIR/Casks/lamba.rb" <<CASK
cask "lamba" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/productdevbook/lamba/releases/download/v#{version}/Lamba-#{version}.dmg"
  name "Lamba"
  desc "Status light, Pomodoro, Dock and Claude Code sessions for the menu bar"
  homepage "https://github.com/productdevbook/lamba"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: ">= :ventura"

  app "Lamba.app"

  uninstall quit:      "dev.hamur.lamba",
            launchctl: "dev.hamur.lamba.helper",
            delete:    [
              "/Library/LaunchDaemons/dev.hamur.lamba.helper.plist",
              "/Library/PrivilegedHelperTools/dev.hamur.lamba.helper",
              "/usr/local/bin/lamba",
            ]

  zap trash: [
    "~/Library/Application Support/Lamba",
    "~/Library/Caches/dev.hamur.lamba",
    "~/Library/HTTPStorages/dev.hamur.lamba",
    "~/Library/Preferences/dev.hamur.lamba.plist",
  ]
end
CASK
  git -C "$TAP_DIR" add Casks/lamba.rb
  if git -C "$TAP_DIR" commit -q -m "Update lamba to $VERSION"; then
    git -C "$TAP_DIR" push -q
  else
    echo "  (cask already up to date)"
  fi
fi

echo
echo "✓ $DMG"
echo "✓ $APPCAST_DIR/appcast.xml"
if [ "${PUBLISH:-}" != 1 ]; then
  echo
  echo "Not published. Run again with PUBLISH=1, or push a v$VERSION tag to let GitHub Actions do it."
fi
echo "Commit the version bump and tag it: git commit -am \"Release $VERSION\" && git tag v$VERSION"
