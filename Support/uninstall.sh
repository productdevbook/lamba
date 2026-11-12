#!/bin/sh
# Removes everything Lamba installed outside the app bundle. Run with sudo.
set -u
LABEL="dev.hamur.lamba.helper"
launchctl bootout "system/$LABEL" 2>/dev/null
launchctl bootout system/app.lamba.helper 2>/dev/null
rm -f /Library/LaunchDaemons/app.lamba.helper.plist /Library/PrivilegedHelperTools/app.lamba.helper \
      /var/run/app.lamba.helper.sock /var/log/app.lamba.helper.log
rm -f "/Library/LaunchDaemons/$LABEL.plist" \
      "/Library/PrivilegedHelperTools/$LABEL" \
      "/var/run/$LABEL.sock" \
      "/var/log/$LABEL.log" \
      /usr/local/bin/lamba
echo "Lamba helper removed. Delete Lamba.app to finish."
