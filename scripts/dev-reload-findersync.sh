#!/usr/bin/env bash
set -euo pipefail

EXT_ID="com.karry.RightClickBuddy.FinderSync"

/usr/bin/pluginkit -e ignore -i "$EXT_ID" 2>/dev/null || true
/usr/bin/pluginkit -e use -i "$EXT_ID" 2>/dev/null || true

# Restart Finder to ensure it re-loads the extension.
osascript -e 'tell application "Finder" to quit' 2>/dev/null || true
sleep 0.5
osascript -e 'tell application "Finder" to activate' 2>/dev/null || true

# Show current election result (authoritative).
/usr/bin/pluginkit -m -i "$EXT_ID" -vv || true
