#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="RightClickBuddy"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
DEBUG_APP="$DERIVED_DATA/Build/Products/Debug/$SCHEME.app"
INSTALL_APP="/Applications/$SCHEME.app"

if [[ ! -d "$DEBUG_APP" ]]; then
  echo "Debug app not found at: $DEBUG_APP" >&2
  echo "Run: bash $ROOT_DIR/scripts/dev-build-debug.sh" >&2
  exit 1
fi

# Best-effort quit running processes before replacing the bundle.
pkill -x "$SCHEME" 2>/dev/null || true
pkill -x "${SCHEME}FinderSync" 2>/dev/null || true

# Ensure sudo can prompt (must be run from an interactive terminal).
if ! sudo -v; then
  echo "sudo failed. Please run this script from Terminal so it can prompt for a password." >&2
  exit 1
fi

sudo rm -rf "$INSTALL_APP"
sudo ditto "$DEBUG_APP" "$INSTALL_APP"

# If quarantine is present (rare for local builds), remove it.
sudo xattr -dr com.apple.quarantine "$INSTALL_APP" 2>/dev/null || true

echo "Installed: $INSTALL_APP"
