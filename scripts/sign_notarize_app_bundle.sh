#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-"$ROOT_DIR/.build/DataLayer Studio.app"}"
ZIP_PATH="${2:-"$ROOT_DIR/DataLayer-Studio-macOS-arm64.zip"}"
SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:-${SIGN_IDENTITY:-}}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: missing app bundle: $APP_PATH" >&2
    exit 1
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "error: missing Developer ID Application signing identity" >&2
    echo "Create/install one from Apple Developer, then set DEVELOPER_ID_APPLICATION if more than one exists." >&2
    exit 1
fi

codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -f "$ZIP_PATH" "$ZIP_PATH.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

ASC_BYPASS_KEYCHAIN="${ASC_BYPASS_KEYCHAIN:-1}" asc notarization submit --file "$ZIP_PATH" --wait
xcrun stapler staple "$APP_PATH"
spctl -a -vv "$APP_PATH"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

echo "$ZIP_PATH"
