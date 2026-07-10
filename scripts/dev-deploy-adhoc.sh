#!/usr/bin/env bash
#
# Local deploy using AD-HOC signing — no keychain / Developer ID needed.
# Ad-hoc signing is sufficient to run the sandboxed FinderSync extension on THIS Mac.
# (For a public GitHub release you still need Developer ID + notarization — separate flow.)
#
# Only prompts you for the sudo password (to replace the bundle in /Applications).
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/RightClickBuddy.xcodeproj"
SCHEME="RightClickBuddy"
DERIVED="$ROOT_DIR/.build/DerivedData"
APP="$DERIVED/Build/Products/Debug/$SCHEME.app"
EXT="$APP/Contents/PlugIns/${SCHEME}FinderSync.appex"
INSTALL_APP="/Applications/$SCHEME.app"
EXT_ID="com.karry.RightClickBuddy.FinderSync"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Build number = git commit count (monotonic, reproducible per commit).
BUILD_NUMBER=$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)

echo "==> 1/5  Build single binary (ENABLE_DEBUG_DYLIB=NO), unsigned  [build $BUILD_NUMBER]"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -derivedDataPath "$DERIVED" -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" build >/dev/null
echo "    built: $APP"

echo "==> 2/5  Ad-hoc sign (extension + app, with entitlements)"
codesign --force --sign - --entitlements "$ROOT_DIR/FinderSync/RightClickBuddyFinderSync.entitlements" "$EXT"
codesign --force --sign - --entitlements "$ROOT_DIR/App/RightClickBuddy.entitlements" "$APP"
codesign --verify --deep --strict "$APP" && echo "    signature OK"

echo "==> 3/5  Install to $INSTALL_APP (sudo; also clears the old broken nested bundle)"
pkill -x "$SCHEME" 2>/dev/null || true
pkill -x "${SCHEME}FinderSync" 2>/dev/null || true
sudo rm -rf "$INSTALL_APP"
sudo ditto "$APP" "$INSTALL_APP"
sudo xattr -dr com.apple.quarantine "$INSTALL_APP" 2>/dev/null || true

echo "==> 4/5  Register the canonical copy, drop the DerivedData one (avoid dup bundle-id)"
"$LSREGISTER" -u "$APP" 2>/dev/null || true
"$LSREGISTER" -f "$INSTALL_APP" 2>/dev/null || true

echo "==> 5/5  Reload FinderSync extension + restart Finder + launch app"
/usr/bin/pluginkit -e ignore -i "$EXT_ID" 2>/dev/null || true
/usr/bin/pluginkit -e use -i "$EXT_ID" 2>/dev/null || true
killall Finder 2>/dev/null || true
sleep 1
open "$INSTALL_APP"

echo ""
echo "Done. Right-click in Finder (Desktop/Downloads/…) → Open With → pick an app."
echo "NOTE: ad-hoc signed = THIS machine only. A GitHub release needs Developer ID + notarization."
