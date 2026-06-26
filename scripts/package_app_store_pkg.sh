#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP_PATH="${1:-"$ROOT_DIR/.build/DataLayer Studio.app"}"
PROFILE_PATH="${APP_STORE_PROVISIONING_PROFILE:-}"
PKG_PATH="${2:-"$ROOT_DIR/DataLayer-Studio-AppStore.pkg"}"
APP_IDENTITY="${APPLE_DISTRIBUTION:-${APP_STORE_APP_IDENTITY:-}}"
INSTALLER_IDENTITY="${MAC_INSTALLER_DISTRIBUTION:-${APP_STORE_INSTALLER_IDENTITY:-}}"
ENTITLEMENTS_PATH="$ROOT_DIR/Resources/AppStore.entitlements"
PROFILE_PLIST="$(mktemp "${TMPDIR:-/tmp}/datalayer-profile.XXXXXX.plist")"
SIGN_ENTITLEMENTS="$(mktemp "${TMPDIR:-/tmp}/datalayer-appstore-entitlements.XXXXXX.plist")"
SIGNED_ENTITLEMENTS="$(mktemp "${TMPDIR:-/tmp}/datalayer-signed-entitlements.XXXXXX.plist")"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/datalayer-appstore-package.XXXXXX")"
APP_PATH="$STAGING_DIR/$(basename "$SOURCE_APP_PATH")"

clean_bundle_metadata() {
    find "$APP_PATH" -name '._*' -type f -delete
    xattr -cr "$APP_PATH" 2>/dev/null || true
}

cleanup() {
    rm -f "$PROFILE_PLIST" "$SIGN_ENTITLEMENTS" "$SIGNED_ENTITLEMENTS"
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

if [[ ! -d "$SOURCE_APP_PATH" ]]; then
    echo "error: missing app bundle: $SOURCE_APP_PATH" >&2
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
    INSTALLER_IDENTITY="$(security find-certificate -a -c "3rd Party Mac Developer Installer" -p | openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null | sed -n 's/.*CN=\([^,]*3rd Party Mac Developer Installer[^,]*\).*/\1/p' | head -n 1)"
fi

if [[ -z "$APP_IDENTITY" ]]; then
    echo "error: missing Apple Distribution signing identity" >&2
    exit 1
fi

if [[ -z "$INSTALLER_IDENTITY" ]]; then
    echo "error: missing Mac Installer Distribution signing identity" >&2
    exit 1
fi

security cms -D -i "$PROFILE_PATH" > "$PROFILE_PLIST" 2>/dev/null || \
    openssl cms -inform DER -verify -noverify -in "$PROFILE_PATH" -out "$PROFILE_PLIST" >/dev/null 2>&1
APP_IDENTIFIER="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$PROFILE_PLIST")"
TEAM_IDENTIFIER="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.team-identifier" "$PROFILE_PLIST")"
KVSTORE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.ubiquity-kvstore-identifier" "$PROFILE_PLIST" 2>/dev/null || true)"
BUNDLE_IDENTIFIER="${APP_IDENTIFIER#${TEAM_IDENTIFIER}.}"

if [[ -z "$APP_IDENTIFIER" || -z "$TEAM_IDENTIFIER" ]]; then
    echo "error: provisioning profile is missing application identifier entitlements" >&2
    exit 1
fi

if [[ -z "$KVSTORE_IDENTIFIER" ]]; then
    echo "error: provisioning profile is missing iCloud key-value store entitlement" >&2
    echo "Enable iCloud Key-value storage for $APP_IDENTIFIER and regenerate the Mac App Store profile." >&2
    exit 1
fi

SIGN_KVSTORE_IDENTIFIER="$KVSTORE_IDENTIFIER"
if [[ "$SIGN_KVSTORE_IDENTIFIER" == *"*"* ]]; then
    if [[ "$BUNDLE_IDENTIFIER" == "$APP_IDENTIFIER" ]]; then
        echo "error: cannot derive bundle identifier from app identifier: $APP_IDENTIFIER" >&2
        exit 1
    fi
    SIGN_KVSTORE_IDENTIFIER="${SIGN_KVSTORE_IDENTIFIER//\*/$BUNDLE_IDENTIFIER}"
fi

if [[ "$SIGN_KVSTORE_IDENTIFIER" == *"*"* ]]; then
    echo "error: signed iCloud key-value store entitlement cannot contain wildcards" >&2
    exit 1
fi

cp "$ENTITLEMENTS_PATH" "$SIGN_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APP_IDENTIFIER" "$SIGN_ENTITLEMENTS" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :com.apple.application-identifier $APP_IDENTIFIER" "$SIGN_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_IDENTIFIER" "$SIGN_ENTITLEMENTS" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :com.apple.developer.team-identifier $TEAM_IDENTIFIER" "$SIGN_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Set :com.apple.developer.ubiquity-kvstore-identifier $SIGN_KVSTORE_IDENTIFIER" "$SIGN_ENTITLEMENTS"

COPYFILE_DISABLE=1 ditto "$SOURCE_APP_PATH" "$APP_PATH"
cp "$PROFILE_PATH" "$APP_PATH/Contents/embedded.provisionprofile"
clean_bundle_metadata
codesign --force --deep --options runtime --entitlements "$SIGN_ENTITLEMENTS" --sign "$APP_IDENTITY" "$APP_PATH"
clean_bundle_metadata
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -d --xml --entitlements - "$APP_PATH" > "$SIGNED_ENTITLEMENTS" 2>/dev/null
SIGNED_APP_IDENTIFIER="$(/usr/libexec/PlistBuddy -c "Print :com.apple.application-identifier" "$SIGNED_ENTITLEMENTS")"

if [[ "$SIGNED_APP_IDENTIFIER" != "$APP_IDENTIFIER" ]]; then
    echo "error: signed app identifier does not match provisioning profile" >&2
    exit 1
fi

for entitlement in \
    com.apple.security.app-sandbox \
    com.apple.security.files.user-selected.read-write \
    com.apple.security.network.client
do
    signed_value="$(/usr/libexec/PlistBuddy -c "Print :$entitlement" "$SIGNED_ENTITLEMENTS" 2>/dev/null || true)"
    if [[ "$signed_value" != "true" ]]; then
        echo "error: signed app is missing required entitlement: $entitlement" >&2
        exit 1
    fi
done

signed_kvstore_identifier="$(/usr/libexec/PlistBuddy -c "Print :com.apple.developer.ubiquity-kvstore-identifier" "$SIGNED_ENTITLEMENTS" 2>/dev/null || true)"
if [[ "$signed_kvstore_identifier" != "$SIGN_KVSTORE_IDENTIFIER" ]]; then
    echo "error: signed app iCloud key-value store entitlement does not match provisioning profile" >&2
    exit 1
fi

rm -f "$PKG_PATH"
COPYFILE_DISABLE=1 productbuild --component "$APP_PATH" /Applications --sign "$INSTALLER_IDENTITY" "$PKG_PATH"
pkgutil --check-signature "$PKG_PATH"

echo "$PKG_PATH"
