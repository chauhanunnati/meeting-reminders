#!/usr/bin/env bash
# Removes the launchd agent and the installed .app.
#
#   ./uninstall.sh          # removes MeetingAirplane (default)
#   ./uninstall.sh cat      # removes MeetingCat
#
# Pass --quiet as the second argument to skip the calendar-permission note
# (install.sh uses this when switching variants).
set -euo pipefail

VARIANT="${1:-airplane}"
QUIET="${2:-}"
case "$VARIANT" in
    airplane) APP_NAME="MeetingAirplane"; LABEL="com.user.meetingairplane" ;;
    cat)      APP_NAME="MeetingCat";      LABEL="com.user.meetingcat" ;;
    *) echo "✗ unknown variant: $VARIANT (expected airplane|cat)" >&2; exit 1 ;;
esac
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"

if [ -f "$PLIST_PATH" ]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    echo "✓ Removed ${APP_NAME} launch agent"
fi

if [ -d "$HOME/Applications/${APP_NAME}.app" ]; then
    rm -rf "$HOME/Applications/${APP_NAME}.app"
    echo "✓ Removed ~/Applications/${APP_NAME}.app"
fi

if [ "$QUIET" != "--quiet" ]; then
    echo ""
    echo "Note: this does NOT revoke calendar permission."
    echo "To revoke: System Settings → Privacy & Security → Calendars → remove ${APP_NAME}."
fi
