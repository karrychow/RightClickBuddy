#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="$ROOT_DIR/.build"
UNINSTALL_ROOT="$BUILD_DIR/uninstall-root"
SCRIPTS_DIR="$BUILD_DIR/uninstall-scripts"
APP_NAME="RightClickBuddy"
PKG_ID="com.karry.RightClickBuddy.pkg"
UNINSTALL_PKG_ID="com.karry.RightClickBuddy.uninstall"
PKG_VERSION="1.0.0"

mkdir -p "$DIST_DIR"
rm -rf "$UNINSTALL_ROOT" "$SCRIPTS_DIR"
mkdir -p "$UNINSTALL_ROOT" "$SCRIPTS_DIR"

cat >"$SCRIPTS_DIR/postinstall" <<'EOF'
#!/bin/bash
set -euo pipefail

APP_PATH="/Applications/RightClickBuddy.app"

if [[ -d "$APP_PATH" ]]; then
  rm -rf "$APP_PATH"
fi

# Forget the main install receipt if present
/usr/sbin/pkgutil --forget "com.karry.RightClickBuddy.pkg" >/dev/null 2>&1 || true
EOF

chmod +x "$SCRIPTS_DIR/postinstall"

UNINSTALL_PKG_PATH="$DIST_DIR/$APP_NAME-Uninstall.pkg"

pkgbuild \
  --identifier "$UNINSTALL_PKG_ID" \
  --version "$PKG_VERSION" \
  --scripts "$SCRIPTS_DIR" \
  --root "$UNINSTALL_ROOT" \
  "$UNINSTALL_PKG_PATH"

echo "Built uninstall package: $UNINSTALL_PKG_PATH"