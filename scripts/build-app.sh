#!/bin/bash
# Builds build/Lamba.app. Set SIGN_python3 scripts/strings.py >/dev/null
cp -R Support/Localization/*.lproj "$APP/Contents/Resources/"

IDENTITY="Developer ID Application: ..." for a release build;
# without it the app is ad-hoc signed (fine for local use, not for distribution).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)"

APP="build/Lamba.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Support/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/LambaApp" "$APP/Contents/MacOS/Lamba"
cp "$BIN/LambaHelper" "$APP/Contents/Resources/app.lamba.helper"
cp "$BIN/lamba" "$APP/Contents/Resources/lamba"
cp Support/lamba-hook "$APP/Contents/Resources/lamba-hook"
cp Support/app.lamba.helper.plist Support/install-helper.sh Support/uninstall.sh Support/AppIcon.icns "$APP/Contents/Resources/"

python3 scripts/strings.py >/dev/null
cp -R Support/Localization/*.lproj "$APP/Contents/Resources/"

IDENTITY="${SIGN_IDENTITY:--}"
SIGN_FLAGS=(--force --sign "$IDENTITY")
[ "$IDENTITY" != "-" ] && SIGN_FLAGS+=(--options runtime --timestamp)

codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Resources/app.lamba.helper"
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Resources/lamba"
APP_FLAGS=("${SIGN_FLAGS[@]}")
[ "$IDENTITY" != "-" ] && APP_FLAGS+=(--entitlements Support/Lamba.entitlements)
codesign "${APP_FLAGS[@]}" "$APP"
echo "Built $APP"
