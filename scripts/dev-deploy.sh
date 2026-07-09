#!/usr/bin/env bash
#
# One-shot local deploy: build + sign + install to /Applications + reload the
# FinderSync extension + (re)launch the main app.
#
# Run this from an interactive Terminal — it needs keychain access (codesign)
# and sudo (to replace the bundle in /Applications). It will NOT work over a
# non-interactive session because codesign cannot reach the login keychain.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="RightClickBuddy"
INSTALL_APP="/Applications/$SCHEME.app"

echo "==> 1/4  Build + sign"
bash "$ROOT_DIR/scripts/dev-build-signed.sh"

echo "==> 2/4  Install to $INSTALL_APP (sudo)"
bash "$ROOT_DIR/scripts/dev-install-debug.sh"

echo "==> 3/4  Reload FinderSync extension + restart Finder"
bash "$ROOT_DIR/scripts/dev-reload-findersync.sh"

echo "==> 4/4  Launch main app (starts the IPC server)"
open "$INSTALL_APP"

echo "Done. Right-click in Finder (Desktop/Downloads/…) and try Open With."
