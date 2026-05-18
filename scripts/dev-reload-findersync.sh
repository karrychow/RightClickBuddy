#!/usr/bin/env bash
set -euo pipefail

EXT_ID="com.karry.RightClickBuddy.FinderSync"

/usr/bin/pluginkit -e ignore -i "$EXT_ID" 2>/dev/null || true
/usr/bin/pluginkit -e use -i "$EXT_ID" 2>/dev/null || true

# Restart Finder to ensure it re-loads the extension.
killall Finder 2>/dev/null || true

# Show current election result (authoritative).
/usr/bin/pluginkit -m -i "$EXT_ID" -vv || true
