#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/RightClickBuddy.xcodeproj"
SCHEME="RightClickBuddy"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"

mkdir -p "$DERIVED_DATA"

# Build number = git commit count (monotonic, reproducible per commit).
BUILD_NUMBER=$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_DEBUG_DYLIB=NO \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Debug/$SCHEME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Debug app not found at: $APP_PATH" >&2
  exit 1
fi

echo "Built Debug app: $APP_PATH"
