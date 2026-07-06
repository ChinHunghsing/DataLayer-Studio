#!/usr/bin/env bash
set -euo pipefail

# 组装 iPadOS 模拟器调试用 App 壳（不签名分发，只做本地开发验证）。
# 用法：
#   scripts/build_touch_sim_app.sh            # 只构建并组装 .app
#   scripts/build_touch_sim_app.sh --run      # 构建后安装到 iPad 模拟器并启动
# 可选环境变量：
#   SIM_DEVICE_NAME   目标模拟器名称（默认 iPad Pro 13-inch (M5)）
#   TOUCH_AUTOLOAD_VIDEO / TOUCH_AUTOLOAD_FIT 启动时自动载入的本地样本路径（仅模拟器调试）

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-DataLayer Studio Touch}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-run.libo.datalayer-studio.overlaytouchhost}"
SWIFT_PRODUCT="overlay-touch-host"
CONFIGURATION="${CONFIGURATION:-debug}"
SCRATCH_PATH="$ROOT_DIR/.build/ios-sim"
TRIPLE="arm64-apple-ios26.0-simulator"
SIM_DEVICE_NAME="${SIM_DEVICE_NAME:-iPad Pro 13-inch (M5)}"

SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
SIM_PLATFORM="$(xcrun --sdk iphonesimulator --show-sdk-platform-path)"
SIM_SDK_VERSION="$(xcrun --sdk iphonesimulator --show-sdk-version)"

cd "$ROOT_DIR"
swift build \
    -c "$CONFIGURATION" \
    --product "$SWIFT_PRODUCT" \
    --triple "$TRIPLE" \
    --sdk "$SIM_SDK" \
    -Xswiftc -sdk -Xswiftc "$SIM_SDK" \
    -Xswiftc -F -Xswiftc "$SIM_PLATFORM/Developer/Library/Frameworks" \
    --scratch-path "$SCRATCH_PATH"

BIN_PATH="$(swift build \
    -c "$CONFIGURATION" \
    --product "$SWIFT_PRODUCT" \
    --triple "$TRIPLE" \
    --sdk "$SIM_SDK" \
    -Xswiftc -sdk -Xswiftc "$SIM_SDK" \
    -Xswiftc -F -Xswiftc "$SIM_PLATFORM/Developer/Library/Frameworks" \
    --scratch-path "$SCRATCH_PATH" \
    --show-bin-path)"

APP_DIR="$SCRATCH_PATH/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
cp "$BIN_PATH/$SWIFT_PRODUCT" "$APP_DIR/$SWIFT_PRODUCT"

cat > "$APP_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
        <string>zh-Hant</string>
        <string>ja</string>
    </array>
    <key>CFBundleExecutable</key>
    <string>$SWIFT_PRODUCT</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_IDENTIFIER</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>DataLayer Studio</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>$(date +%Y%m%d)01</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>iPhoneSimulator</string>
    </array>
    <key>DTPlatformName</key>
    <string>iphonesimulator</string>
    <key>DTSDKName</key>
    <string>iphonesimulator$SIM_SDK_VERSION</string>
    <key>MinimumOSVersion</key>
    <string>26.0</string>
    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
        <integer>2</integer>
    </array>
    <key>UILaunchScreen</key>
    <dict/>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UIFileSharingEnabled</key>
    <true/>
    <key>LSSupportsOpeningDocumentsInPlace</key>
    <true/>
    <key>NSPhotoLibraryAddUsageDescription</key>
    <string>Save composited videos you export to your photo library.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Garmin FIT Activity</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.garmin.fit</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>GPX Activity</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.topografix.gpx</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Movie</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.movie</string>
            </array>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.garmin.fit</string>
            <key>UTTypeDescription</key>
            <string>Garmin FIT Activity</string>
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
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.topografix.gpx</string>
            <key>UTTypeDescription</key>
            <string>GPX Activity</string>
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
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true
echo "Assembled: $APP_DIR"

if [[ "${1:-}" == "--run" ]]; then
    DEVICE_ID="$(xcrun simctl list devices available | grep -F "$SIM_DEVICE_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
    if [[ -z "$DEVICE_ID" ]]; then
        echo "No available simulator named: $SIM_DEVICE_NAME" >&2
        exit 1
    fi
    xcrun simctl bootstatus "$DEVICE_ID" -b
    xcrun simctl install "$DEVICE_ID" "$APP_DIR"
    LAUNCH_ENV=()
    if [[ -n "${TOUCH_AUTOLOAD_VIDEO:-}" ]]; then
        LAUNCH_ENV+=("SIMCTL_CHILD_TOUCH_AUTOLOAD_VIDEO=$TOUCH_AUTOLOAD_VIDEO")
    fi
    if [[ -n "${TOUCH_AUTOLOAD_FIT:-}" ]]; then
        LAUNCH_ENV+=("SIMCTL_CHILD_TOUCH_AUTOLOAD_FIT=$TOUCH_AUTOLOAD_FIT")
    fi
    if [[ -n "${TOUCH_AUTOEXPORT:-}" ]]; then
        LAUNCH_ENV+=("SIMCTL_CHILD_TOUCH_AUTOEXPORT=$TOUCH_AUTOEXPORT")
    fi
    if [[ -n "${TOUCH_AUTOEXPORT_MAX_SECONDS:-}" ]]; then
        LAUNCH_ENV+=("SIMCTL_CHILD_TOUCH_AUTOEXPORT_MAX_SECONDS=$TOUCH_AUTOEXPORT_MAX_SECONDS")
    fi
    env "${LAUNCH_ENV[@]}" xcrun simctl launch --terminate-running-process "$DEVICE_ID" "$BUNDLE_IDENTIFIER"
    echo "Launched $BUNDLE_IDENTIFIER on $SIM_DEVICE_NAME ($DEVICE_ID)"
fi
