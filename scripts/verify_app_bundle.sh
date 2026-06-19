#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-"$ROOT_DIR/.build/DataLayer Studio.app"}"
CONTENTS_DIR="$APP_PATH/Contents"
LEGAL_DIR="$CONTENTS_DIR/Resources/Legal"

failures=0

fail() {
    echo "error: $*" >&2
    failures=$((failures + 1))
}

require_file() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        fail "missing required file: $path"
    fi
}

if [[ ! -d "$APP_PATH" ]]; then
    fail "missing app bundle: $APP_PATH"
fi

require_file "$CONTENTS_DIR/Info.plist"
require_file "$CONTENTS_DIR/MacOS/DataLayer Studio"
require_file "$CONTENTS_DIR/Resources/DataLayerStudio.icns"
require_file "$LEGAL_DIR/LICENSE.md"
require_file "$LEGAL_DIR/NOTICE.md"
require_file "$LEGAL_DIR/README.md"

for locale in en zh-Hans zh-Hant ja; do
    require_file "$CONTENTS_DIR/Resources/$locale.lproj/InfoPlist.strings"
    require_file "$CONTENTS_DIR/Resources/$locale.lproj/Localizable.strings"
done

if [[ -f "$CONTENTS_DIR/Info.plist" ]]; then
    plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null || fail "invalid Info.plist"
fi

if [[ -f "$LEGAL_DIR/LICENSE.md" ]]; then
    grep -q 'PolyForm Noncommercial License 1.0.0' "$LEGAL_DIR/LICENSE.md" || fail "bundled LICENSE.md must name the PolyForm Noncommercial license"
    grep -q 'https://polyformproject.org/licenses/noncommercial/1.0.0' "$LEGAL_DIR/LICENSE.md" || fail "bundled LICENSE.md must contain the canonical license URL"
fi

if [[ -f "$LEGAL_DIR/NOTICE.md" ]]; then
    grep -q 'DataLayer Studio' "$LEGAL_DIR/NOTICE.md" || fail "bundled NOTICE.md must identify DataLayer Studio"
fi

if [[ -f "$LEGAL_DIR/README.md" ]]; then
    grep -q '## License' "$LEGAL_DIR/README.md" || fail "bundled README.md must include the License section"
fi

if (( failures > 0 )); then
    exit 1
fi

echo "App bundle verification passed: $APP_PATH"
