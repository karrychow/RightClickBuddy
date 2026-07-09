#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/RightClickBuddy.xcodeproj"
SCHEME="RightClickBuddy"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"

# Build unsigned first
echo "=== Building unsigned debug app ==="
"$ROOT_DIR/scripts/dev-build-debug.sh"

BUILD_DIR="$DERIVED_DATA/Build/Products/Debug"
APP_PATH="$BUILD_DIR/$SCHEME.app"
EXT_PATH="$APP_PATH/Contents/PlugIns/${SCHEME}FinderSync.appex"

# Signing identity.
#   - Set SIGN_IDENTITY to a substring of the identity you want, e.g.:
#       SIGN_IDENTITY="Apple Development: you@example.com" bash scripts/dev-build-signed.sh
#   - Otherwise the first available "Apple Development" identity is used.
# Simpler alternative that needs no certificate at all: scripts/dev-deploy-adhoc.sh (ad-hoc signing).
# Match by SHA-1 hash (2nd column), not the name — names can be duplicated in the
# keychain, which makes `codesign --sign <name>` fail with "ambiguous".
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -F "$SIGN_IDENTITY" | head -1 | awk '{print $2}')
else
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | awk '{print $2}')
fi
if [[ -z "$IDENTITY" ]]; then
  echo "No signing identity found. Available identities:" >&2
  security find-identity -v -p codesigning >&2
  echo "Tip: scripts/dev-deploy-adhoc.sh uses ad-hoc signing and needs no certificate." >&2
  exit 1
fi
echo "=== Signing with identity hash: $IDENTITY ==="

# Sign the extension first
echo "--- Signing FinderSync extension ---"
codesign --force --sign "$IDENTITY" --entitlements "$ROOT_DIR/FinderSync/RightClickBuddyFinderSync.entitlements" "$EXT_PATH"

# Sign the main app (embedding the signed extension)
echo "--- Signing main app ---"
codesign --force --sign "$IDENTITY" --entitlements "$ROOT_DIR/App/RightClickBuddy.entitlements" --deep "$APP_PATH"

# Verify
echo "=== Verification ==="
codesign -dv --verbose=2 "$APP_PATH" 2>&1 | head -5
codesign -dv --verbose=2 "$EXT_PATH" 2>&1 | head -5
echo "=== Signed successfully ==="
echo "$APP_PATH"
