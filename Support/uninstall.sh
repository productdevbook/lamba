#!/bin/sh
# Removes everything Lamba installed outside the app bundle. Run with sudo.
set -u
LABEL="app.lamba.helper"
launchctl bootout "system/$LABEL" 2>/dev/null
rm -f "/Library/LaunchDaemons/$LABEL.plist" \
      "/Library/PrivilegedHelperTools/$LABEL" \
      "/var/run/$LABEL.sock" \
      "/var/log/$LABEL.log" \
      /usr/local/bin/lamba
echo "Lamba helper removed. Delete Lamba.app to finish."
