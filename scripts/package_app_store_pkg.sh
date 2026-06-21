#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-"$ROOT_DIR/.build/DataLayer Studio.app"}"
PROFILE_PATH="${APP_STORE_PROVISIONING_PROFILE:-}"
PKG_PATH="${2:-"$ROOT_DIR/DataLayer-Studio-AppStore.pkg"}"
APP_IDENTITY="${APPLE_DISTRIBUTION:-${APP_STORE_APP_IDENTITY:-}}"
INSTALLER_IDENTITY="${MAC_INSTALLER_DISTRIBUTION:-${APP_STORE_INSTALLER_IDENTITY:-}}"
ENTITLEMENTS_PATH="$ROOT_DIR/Resources/AppStore.entitlements"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: missing app bundle: $APP_PATH" >&2
    exit 1
fi

if [[ -z "$PROFILE_PATH" || ! -f "$PROFILE_PATH" ]]; then
    echo "error: set APP_STORE_PROVISIONING_PROFILE to a Mac App Store profile" >&2
    exit 1
fi

if [[ -z "$APP_IDENTITY" ]]; then
    APP_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Distribution:.*\)"/\1/p' | head -n 1)"
fi

if [[ -z "$INSTALLER_IDENTITY" ]]; then
    INSTALLER_IDENTITY="$(security find-certificate -a -c "3rd Party Mac Developer Installer" -p | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*CN *= *\([^,]*3rd Party Mac Developer Installer[^,]*\).*/\1/p' | head -n 1)"
fi

if [[ -z "$APP_IDENTITY" ]]; then
    echo "error: missing Apple Distribution signing identity" >&2
    exit 1
fi

if [[ -z "$INSTALLER_IDENTITY" ]]; then
    echo "error: missing Mac Installer Distribution signing identity" >&2
    exit 1
fi

cp "$PROFILE_PATH" "$APP_PATH/Contents/embedded.provisionprofile"
codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS_PATH" --sign "$APP_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -f "$PKG_PATH"
productbuild --component "$APP_PATH" /Applications --sign "$INSTALLER_IDENTITY" "$PKG_PATH"
pkgutil --check-signature "$PKG_PATH"

echo "$PKG_PATH"
