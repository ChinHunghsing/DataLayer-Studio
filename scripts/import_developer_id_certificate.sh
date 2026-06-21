#!/usr/bin/env bash
set -euo pipefail

if (( $# < 2 )); then
    echo "usage: $0 DeveloperIDApplication.cer developer-id.key" >&2
    exit 1
fi

CERT_PATH="$1"
KEY_PATH="$2"
KEYCHAIN_PATH="${KEYCHAIN_PATH:-"$HOME/Library/Keychains/login.keychain-db"}"

if [[ ! -f "$CERT_PATH" ]]; then
    echo "error: missing certificate: $CERT_PATH" >&2
    exit 1
fi

if [[ ! -f "$KEY_PATH" ]]; then
    echo "error: missing private key: $KEY_PATH" >&2
    exit 1
fi

security import "$KEY_PATH" -k "$KEYCHAIN_PATH" -T /usr/bin/codesign -T /usr/bin/security
security import "$CERT_PATH" -k "$KEYCHAIN_PATH" -T /usr/bin/codesign -T /usr/bin/security

identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)"
if [[ -z "$identity" ]]; then
    echo "error: Developer ID Application identity was not found after import" >&2
    exit 1
fi

echo "$identity"
