#!/bin/sh
# Installs the Lamba root helper and CLI. Run as root by the app (one admin prompt).
# Usage: install-helper.sh /path/to/Lamba.app
set -eu

APP="$1"
LABEL="dev.hamur.lamba.helper"
RESOURCES="$APP/Contents/Resources"
HELPER_DST="/Library/PrivilegedHelperTools/$LABEL"
PLIST_DST="/Library/LaunchDaemons/$LABEL.plist"
CLI_DST="/usr/local/bin/lamba"

[ "$(id -u)" -eq 0 ] || { echo "must run as root" >&2; exit 1; }
[ -f "$RESOURCES/$LABEL" ] || { echo "helper missing in $APP" >&2; exit 1; }

launchctl bootout "system/$LABEL" 2>/dev/null || true

install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
install -o root -g wheel -m 755 "$RESOURCES/$LABEL" "$HELPER_DST"
install -o root -g wheel -m 644 "$RESOURCES/$LABEL.plist" "$PLIST_DST"
install -d -m 755 /usr/local/bin
# A symlink keeps the CLI in step with the app after every update.
rm -f "$CLI_DST"
ln -s "$RESOURCES/lamba" "$CLI_DST"

# The helper's earlier id (before the app became dev.hamur.lamba).
launchctl bootout system/app.lamba.helper 2>/dev/null || true
rm -f /Library/LaunchDaemons/app.lamba.helper.plist /Library/PrivilegedHelperTools/app.lamba.helper \
      /var/run/app.lamba.helper.sock /var/log/app.lamba.helper.log

# Remove leftovers of pre-release builds (setuid prototype, and the product's earlier name "Glint").
rm -f /usr/local/libexec/magsafeled
launchctl bootout system/app.glint.helper 2>/dev/null || true
rm -f /Library/LaunchDaemons/app.glint.helper.plist /Library/PrivilegedHelperTools/app.glint.helper \
      /var/run/app.glint.helper.sock /var/log/app.glint.helper.log /usr/local/bin/glint

launchctl bootstrap system "$PLIST_DST"
