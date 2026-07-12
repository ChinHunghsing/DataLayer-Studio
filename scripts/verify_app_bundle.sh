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
require_file "$CONTENTS_DIR/Resources/fable5verified.png"
require_file "$LEGAL_DIR/LICENSE.md"
require_file "$LEGAL_DIR/NOTICE.md"
require_file "$LEGAL_DIR/README.md"

for locale in en zh zh-Hans zh-Hans-CN zh-Hant zh-Hant-TW zh_CN zh_TW ja; do
    require_file "$CONTENTS_DIR/Resources/$locale.lproj/InfoPlist.strings"
    require_file "$CONTENTS_DIR/Resources/$locale.lproj/Localizable.strings"
done

if [[ -f "$CONTENTS_DIR/Info.plist" ]]; then
    plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null || fail "invalid Info.plist"
    mixed_localizations="$(/usr/libexec/PlistBuddy -c "Print :CFBundleAllowMixedLocalizations" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true)"
    if [[ "$mixed_localizations" != "true" ]]; then
        fail "Info.plist must enable CFBundleAllowMixedLocalizations"
    fi
    exempt_encryption="$(/usr/libexec/PlistBuddy -c "Print :ITSAppUsesNonExemptEncryption" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true)"
    if [[ "$exempt_encryption" != "false" ]]; then
        fail "Info.plist must declare ITSAppUsesNonExemptEncryption=false"
    fi
    project_document_type="$(/usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes:0:LSItemContentTypes:0" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true)"
    project_document_extension="$(/usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes:0:CFBundleTypeExtensions:0" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true)"
    project_handler_rank="$(/usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes:0:LSHandlerRank" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true)"
    exported_project_type="$(/usr/libexec/PlistBuddy -c "Print :UTExportedTypeDeclarations:0:UTTypeIdentifier" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true)"
    if [[ "$project_document_type" != "run.libo.datalayer-studio.project" || "$exported_project_type" != "$project_document_type" ]]; then
        fail "Info.plist must export and register the DataLayer Studio project type"
    fi
    if [[ "$project_document_extension" != "dlsproj" ]]; then
        fail "Info.plist must register the .dlsproj extension"
    fi
    if [[ "$project_handler_rank" != "Owner" ]]; then
        fail "Info.plist must declare DataLayer Studio as the .dlsproj owner"
    fi
    preset_document_type="$(/usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes:1:LSItemContentTypes:0" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true)"
    preset_document_extension="$(/usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes:1:CFBundleTypeExtensions:0" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true)"
    preset_handler_rank="$(/usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes:1:LSHandlerRank" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true)"
    exported_preset_type="$(/usr/libexec/PlistBuddy -c "Print :UTExportedTypeDeclarations:1:UTTypeIdentifier" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true)"
    if [[ "$preset_document_type" != "run.libo.datalayer-studio.layout-preset" || "$exported_preset_type" != "$preset_document_type" ]]; then
        fail "Info.plist must export and register the DataLayer Studio layout preset type"
    fi
    if [[ "$preset_document_extension" != "dlspreset" ]]; then
        fail "Info.plist must register the .dlspreset extension"
    fi
    if [[ "$preset_handler_rank" != "Owner" ]]; then
        fail "Info.plist must declare DataLayer Studio as the .dlspreset owner"
    fi
    declared_localizations="$(/usr/libexec/PlistBuddy -c "Print :CFBundleLocalizations" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true)"
    for locale in en zh zh-Hans zh-Hans-CN zh-Hant zh-Hant-TW zh_CN zh_TW ja; do
        if ! printf '%s\n' "$declared_localizations" | grep -qx "    $locale"; then
            fail "Info.plist must declare localization: $locale"
        fi
    done
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
