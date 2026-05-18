#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

bash "$ROOT_DIR/scripts/dev-build-debug.sh"
bash "$ROOT_DIR/scripts/dev-install-debug.sh"

# Launch the app (helps LaunchServices notice the new bundle).
open -a "/Applications/RightClickBuddy.app" || true

bash "$ROOT_DIR/scripts/dev-reload-findersync.sh"

echo "--- codesign (installed appex) ---"
codesign -dv --verbose=4 "/Applications/RightClickBuddy.app/Contents/PlugIns/RightClickBuddyFinderSync.appex" 2>&1 | egrep -n "Identifier=|CandidateCDHash|Signature=|TeamIdentifier=" || true

echo "--- Done. Now right-click in Finder and look for the Debug stamp item. ---"
