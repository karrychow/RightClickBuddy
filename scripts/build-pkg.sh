#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="$ROOT_DIR/.build"
EXPORT_DIR="$BUILD_DIR/export"
APP_NAME="RightClickBuddy"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
PKG_ID="com.karry.RightClickBuddy.pkg"
PKG_VERSION="1.0.0"

mkdir -p "$DIST_DIR"

"$ROOT_DIR/scripts/build-app.sh"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at: $APP_PATH" >&2
  exit 1
fi

PKG_PATH="$DIST_DIR/$APP_NAME.pkg"

pkgbuild \
  --identifier "$PKG_ID" \
  --version "$PKG_VERSION" \
  --install-location "/Applications" \
  --component "$APP_PATH" \
  "$PKG_PATH"

echo "Built installer: $PKG_PATH"