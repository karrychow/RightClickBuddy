#!/usr/bin/env bash
#
# Reset the App Group container so settings can be saved again.
#
# The container gets locked to whatever code-signing identity created it. After re-signing
# with a different identity (adhoc / personal / team switch), the app is denied write access
# ("You don't have permission to save settings.json"). Deleting it lets the current build
# recreate a fresh, owned container.
#
# REQUIREMENT: the terminal you run this in must have **Full Disk Access**
#   System Settings ▸ Privacy & Security ▸ Full Disk Access ▸ add & enable your terminal app.
# (Plain rm/Finder are denied without it — the container is data-vault protected.)
#
set -euo pipefail

GC="$HOME/Library/Group Containers/group.com.karry.RightClickBuddy"
APP="/Applications/RightClickBuddy.app"

echo "==> Quitting app + extension"
pkill -x RightClickBuddy 2>/dev/null || true
pkill -x RightClickBuddyFinderSync 2>/dev/null || true
sleep 1

echo "==> Deleting locked container: $GC"
if rm -rf "$GC" 2>/dev/null && [ ! -e "$GC" ]; then
  echo "    ✅ removed"
else
  echo "    ❌ could not delete."
  echo "    Grant Full Disk Access to THIS terminal app and re-run:"
  echo "      System Settings ▸ Privacy & Security ▸ Full Disk Access"
  exit 1
fi

echo "==> Relaunching app (recreates a fresh container under the current signature)"
open "$APP"
sleep 2

echo "Done. Open Settings, toggle something — the red 'can't save settings.json' banner should be gone."
