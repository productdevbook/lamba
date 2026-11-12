#!/bin/bash
# Builds build/Lamba.app.
#
# Set SIGN_IDENTITY="Developer ID Application: …" for a release build (hardened runtime, secure
# timestamp, entitlements); without it the app is ad-hoc signed (fine for local use only).
# VERSION=1.2.3 and BUILD=<number> override the bundle's version for this build.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)"

APP="build/Lamba.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp Support/Info.plist "$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [ -n "${BUILD:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
fi
cp "$BIN/LambaApp" "$APP/Contents/MacOS/Lamba"
cp "$BIN/LambaHelper" "$APP/Contents/Resources/app.lamba.helper"
cp "$BIN/lamba" "$APP/Contents/Resources/lamba"
cp Support/lamba-hook "$APP/Contents/Resources/lamba-hook"
cp Support/app.lamba.helper.plist Support/install-helper.sh Support/uninstall.sh Support/AppIcon.icns "$APP/Contents/Resources/"
# Sparkle (automatic updates); the app's rpath points at Contents/Frameworks.
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

python3 scripts/strings.py >/dev/null
cp -R Support/Localization/*.lproj "$APP/Contents/Resources/"

IDENTITY="${SIGN_IDENTITY:--}"
SIGN_FLAGS=(--force --sign "$IDENTITY")
[ "$IDENTITY" != "-" ] && SIGN_FLAGS+=(--options runtime --timestamp)

# Inside out: Sparkle's helpers, then the framework, the bundled tools, and the app last.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for item in \
  "$SPARKLE/Versions/B/XPCServices/Installer.xpc" \
  "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
  "$SPARKLE/Versions/B/Autoupdate" \
  "$SPARKLE/Versions/B/Updater.app"; do
  [ -e "$item" ] || continue
  if [[ "$item" == *Downloader.xpc ]] && [ "$IDENTITY" != "-" ]; then
    codesign "${SIGN_FLAGS[@]}" --preserve-metadata=entitlements "$item"
  else
    codesign "${SIGN_FLAGS[@]}" "$item"
  fi
done
codesign "${SIGN_FLAGS[@]}" "$SPARKLE"
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Resources/app.lamba.helper"
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Resources/lamba"
APP_FLAGS=("${SIGN_FLAGS[@]}")
[ "$IDENTITY" != "-" ] && APP_FLAGS+=(--entitlements Support/Lamba.entitlements)
codesign "${APP_FLAGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
