#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/RightClickBuddy.xcodeproj"
SCHEME="RightClickBuddy"
BUILD_DIR="$ROOT_DIR/.build"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -archivePath "$ARCHIVE_PATH" \
  archive -quiet

# For unsigned/self-use builds we can take the .app directly from the archive.
APP_PATH="$ARCHIVE_PATH/Products/Applications/$SCHEME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Archived app not found at: $APP_PATH" >&2
  exit 1
fi

# Copy to a stable export path for packaging.
rm -rf "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"
cp -R "$APP_PATH" "$EXPORT_PATH/$SCHEME.app"

echo "Built app: $EXPORT_PATH/$SCHEME.app"