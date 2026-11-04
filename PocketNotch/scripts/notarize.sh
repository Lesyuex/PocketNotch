#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:-}"
KEYCHAIN_PROFILE="${2:-${NOTARIZE_PROFILE:-POCKETNOTCH_NOTARY}}"

if [[ -z "$DMG_PATH" ]] || [[ ! -f "$DMG_PATH" ]]; then
  echo "Usage: $0 <dmg-path> [keychain-profile]" >&2
  exit 1
fi

echo "Submitting $DMG_PATH with keychain profile $KEYCHAIN_PROFILE..."
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "Notarization complete: $DMG_PATH"
