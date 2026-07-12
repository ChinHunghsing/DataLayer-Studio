#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-DataLayer Studio}"
# TestFlight/App Store builds must pass APP_VERSION from ASC; this date default is only for local app bundles.
# 构建号规则见 AGENTS.md：yyyyMMddNN，同日多次构建用 APP_BUILD 覆盖 NN。
APP_VERSION="${APP_VERSION:-$(date +%Y.%m.%d)}"
APP_BUILD="${APP_BUILD:-$(date +%Y%m%d)01}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-run.libo.datalayer-studio}"
SWIFT_PRODUCT="${SWIFT_PRODUCT:-datalayer-studio}"
APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
LEGAL_DIR="$RESOURCES_DIR/Legal"
APP_ICON_NAME="DataLayerStudio"
APP_ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.png"
ABOUT_BADGE_SOURCE="$ROOT_DIR/assets/readme/fable5verified.png"
COMPONENT_THUMBNAILS_SOURCE="$ROOT_DIR/Resources/ComponentThumbnails"
APP_LOCALIZATIONS=(en zh zh-Hans zh-Hans-CN zh-Hant zh-Hant-TW zh_CN zh_TW ja)

cd "$ROOT_DIR"
swift build -c release --arch arm64 --product "$SWIFT_PRODUCT"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$LEGAL_DIR"
cp "$ROOT_DIR/.build/release/$SWIFT_PRODUCT" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/LICENSE.md" "$LEGAL_DIR/LICENSE.md"
cp "$ROOT_DIR/NOTICE.md" "$LEGAL_DIR/NOTICE.md"
cp "$ROOT_DIR/README.md" "$LEGAL_DIR/README.md"
cp "$ABOUT_BADGE_SOURCE" "$RESOURCES_DIR/fable5verified.png"
cp -R "$COMPONENT_THUMBNAILS_SOURCE" "$RESOURCES_DIR/ComponentThumbnails"

if [[ ! -f "$APP_ICON_SOURCE" ]]; then
    echo "Missing app icon source: $APP_ICON_SOURCE" >&2
    exit 1
fi

APP_ICONSET_DIR="$RESOURCES_DIR/$APP_ICON_NAME.iconset"
rm -rf "$APP_ICONSET_DIR"
mkdir -p "$APP_ICONSET_DIR"
sips -z 16 16 "$APP_ICON_SOURCE" --out "$APP_ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$APP_ICON_SOURCE" --out "$APP_ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$APP_ICON_SOURCE" --out "$APP_ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$APP_ICON_SOURCE" --out "$APP_ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$APP_ICON_SOURCE" --out "$APP_ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$APP_ICON_SOURCE" --out "$APP_ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$APP_ICON_SOURCE" --out "$APP_ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$APP_ICON_SOURCE" --out "$APP_ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$APP_ICON_SOURCE" --out "$APP_ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$APP_ICON_SOURCE" --out "$APP_ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$APP_ICONSET_DIR" -o "$RESOURCES_DIR/$APP_ICON_NAME.icns"
rm -rf "$APP_ICONSET_DIR"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleAllowMixedLocalizations</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>$APP_ICON_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_IDENTIFIER</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh</string>
        <string>zh-Hans</string>
        <string>zh-Hans-CN</string>
        <string>zh-Hant</string>
        <string>zh-Hant-TW</string>
        <string>zh_CN</string>
        <string>zh_TW</string>
        <string>ja</string>
    </array>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>DataLayer Studio Project</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>run.libo.datalayer-studio.project</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>dlsproj</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>DataLayer Studio Layout Preset</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>run.libo.datalayer-studio.layout-preset</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>dlspreset</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>FIT Activity File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.garmin.fit</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>fit</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>GPX Activity File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.topografix.gpx</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>gpx</string>
            </array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>run.libo.datalayer-studio.project</string>
            <key>UTTypeDescription</key>
            <string>DataLayer Studio Project</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.json</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>dlsproj</string>
                </array>
                <key>public.mime-type</key>
                <string>application/vnd.datalayer-studio.project+json</string>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>run.libo.datalayer-studio.layout-preset</string>
            <key>UTTypeDescription</key>
            <string>DataLayer Studio Layout Preset</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.json</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>dlspreset</string>
                </array>
                <key>public.mime-type</key>
                <string>application/vnd.datalayer-studio.layout-preset+json</string>
            </dict>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.garmin.fit</string>
            <key>UTTypeDescription</key>
            <string>FIT Activity File</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>fit</string>
                </array>
                <key>public.mime-type</key>
                <string>application/vnd.ant.fit</string>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.topografix.gpx</string>
            <key>UTTypeDescription</key>
            <string>GPX Activity File</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.xml</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>gpx</string>
                </array>
                <key>public.mime-type</key>
                <string>application/gpx+xml</string>
            </dict>
        </dict>
    </array>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.video</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
    <key>LSArchitecturePriority</key>
    <array>
        <string>arm64</string>
    </array>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

for locale in "${APP_LOCALIZATIONS[@]}"; do
    LPROJ_DIR="$RESOURCES_DIR/$locale.lproj"
    mkdir -p "$LPROJ_DIR"
    cat > "$LPROJ_DIR/InfoPlist.strings" <<STRINGS
CFBundleName = "$APP_NAME";
CFBundleDisplayName = "$APP_NAME";
STRINGS
    cat > "$LPROJ_DIR/Localizable.strings" <<STRINGS
"app.name" = "$APP_NAME";
STRINGS
done

xattr -cr "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
