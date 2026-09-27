#!/usr/bin/env bash
# Builds, copies the .app to ~/Applications, and registers a launchd agent
# so it starts automatically every time you log in.
#
#   ./install.sh            # installs MeetingAirplane (default)
#   ./install.sh cat        # installs MeetingCat
#
# Only one variant can be installed at a time: installing one removes the
# other, so you never get two reminders for the same meeting.
set -euo pipefail

cd "$(dirname "$0")"

VARIANT="${1:-airplane}"
case "$VARIANT" in
    airplane) APP_NAME="MeetingAirplane"; LABEL="com.user.meetingairplane"; LOG_BASE="meetingairplane"; OTHER="cat" ;;
    cat)      APP_NAME="MeetingCat";      LABEL="com.user.meetingcat";      LOG_BASE="meetingcat";      OTHER="airplane" ;;
    *) echo "✗ unknown variant: $VARIANT (expected airplane|cat)" >&2; exit 1 ;;
esac
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"

# Build first, so a failed build leaves the currently installed variant alone.
./build.sh "$VARIANT"

# Remove the other variant (no-op if it isn't installed).
./uninstall.sh "$OTHER" --quiet

# Install to ~/Applications.
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/${APP_NAME}.app"
cp -R "build/${APP_NAME}.app" "$HOME/Applications/"

APP_EXEC="$HOME/Applications/${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

# Write the launchd agent plist.
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${APP_EXEC}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/${LOG_BASE}.out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/${LOG_BASE}.err.log</string>
</dict>
</plist>
EOF

# (Re)load.
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

cat <<EOF

✓ ${APP_NAME} installed and running.

FIRST-LAUNCH NOTE
  macOS will pop up a Calendar permission request the first time the app
  tries to read events. Grant it — otherwise the app can't see your
  meetings. If you miss the popup, go to:
    System Settings → Privacy & Security → Calendars → enable ${APP_NAME}

OUTLOOK
  This reads from the macOS Calendar app. If your Outlook account is not
  already added there, open Calendar.app once and add it via:
    System Settings → Internet Accounts → Microsoft Exchange / Outlook

TEST THE ANIMATION RIGHT NOW
  ~/Applications/${APP_NAME}.app/Contents/MacOS/${APP_NAME} --test

LOGS
  /tmp/${LOG_BASE}.out.log
  /tmp/${LOG_BASE}.err.log

EOF
