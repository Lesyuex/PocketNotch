#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCHEME="${SCHEME:-PocketNotch}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PROJECT_ROOT/Build}"
DIST_DIR="${DIST_DIR:-$PROJECT_ROOT/dist}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-}"

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$SCHEME.app"

echo "Building $SCHEME ($CONFIGURATION)..."

xcodebuild \
  -project "$PROJECT_ROOT/PocketNotch.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  clean build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build product is missing: $APP_PATH" >&2
  exit 1
fi

DEFAULT_PETS_PATH="$APP_PATH/Contents/Resources/DefaultPets"
PET_MANIFEST=""
if [[ -d "$DEFAULT_PETS_PATH" ]]; then
  PET_MANIFEST="$(find "$DEFAULT_PETS_PATH" -name pet.json -print -quit)"
fi
if [[ -z "$PET_MANIFEST" ]]; then
  echo "Packaged app does not contain DefaultPets." >&2
  exit 1
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing app with: $SIGN_IDENTITY"
  codesign --deep --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP_PATH"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$DIST_DIR/PocketNotch-${VERSION}-${BUILD_NUMBER}.dmg"
STAGING_DIR="$(mktemp -d /tmp/PocketNotchDMG.XXXXXX)"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$DIST_DIR"
ditto "$APP_PATH" "$STAGING_DIR/PocketNotch.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating $DMG_PATH..."
rm -f "$DMG_PATH"
if diskutil image create from --help >/dev/null 2>&1; then
  diskutil image create from \
    --volumeName "Pocket Notch" \
    --format UDZO \
    "$STAGING_DIR" \
    "$DMG_PATH"
else
  hdiutil create \
    -volname "Pocket Notch" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    "$DMG_PATH"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

if [[ -n "$NOTARIZE_PROFILE" ]]; then
  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "NOTARIZE_PROFILE requires SIGN_IDENTITY." >&2
    exit 1
  fi
  "$SCRIPT_DIR/notarize.sh" "$DMG_PATH" "$NOTARIZE_PROFILE"
fi

hdiutil verify "$DMG_PATH"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

echo "Package complete:"
echo "  App: $APP_PATH"
echo "  DMG: $DMG_PATH"
echo "  SHA: $DMG_PATH.sha256"
