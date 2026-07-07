# DataLayer Studio iPadOS 开发与测试备忘

| 项目 | 内容 |
| --- | --- |
| 状态 | 本地开发备忘（随实施持续更新） |
| 日期 | 2026-07-06 |
| 适用范围 | `OverlayTouch`、`OverlayTouchHost` 模拟器壳、真机临时 Xcode 壳、签名与安装启动验证 |
| 关联文档 | `docs/ipad-product-design.md`（产品现状）、`docs/ipad-technical-design.md`（架构现状） |

## 0. 原则

- iPadOS/iOS 开发不能影响 macOS 端既有功能、视觉表现、导出结果和构建/发布流程。
- **日常开发优先用模拟器（§1）**，真机只用于性能/热基准、硬编行为和中断路径验证（§4）。
- 正式 iOS 壳工程在 `App/DataLayerStudioMobile.xcodeproj`（已入库）；除此之外不提交其他 Xcode 工程，历史 `/tmp` 临时壳只作备忘（§4.2）。不提交证书、provisioning profile、xcuserdata。
- 本地视频、FIT、导出产物和 `assets/resourses/` 都不提交。
- iPad 版只导出合成成片（2026-07-06 已定决策）；透明 HEVC-alpha/ProRes 浮层仅属 macOS/CLI，iOS 侧无需验证。
- 涉及共享层（`OverlayCore`、`OverlayStudioKit`）或平台条件编译后，必跑 macOS 回归（§5）。

## 1. 模拟器开发工作流（日常首选）

两条通道：

- **SwiftPM 壳（纯命令行快速迭代）**：`Sources/OverlayTouchHost/` + `scripts/build_touch_sim_app.sh`，见下方命令。
- **正式 Xcode 壳（涉及 StoreKit / 签名 / entitlements / 真机时用）**：`App/DataLayerStudioMobile.xcodeproj`，bundle id `run.libo.datalayer-studio.mobile`，共享 scheme 已挂 `.storekit` 配置（StoreKit 本地测试须经 Xcode scheme 运行）。

```sh
# 正式壳：模拟器构建
xcodebuild -project App/DataLayerStudioMobile.xcodeproj -scheme DataLayerStudioMobile \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build

# 正式壳：真机 SDK 签名构建（自动签名，App ID 已注册）
xcodebuild -project App/DataLayerStudioMobile.xcodeproj -scheme DataLayerStudioMobile \
  -destination generic/platform=iOS -allowProvisioningUpdates build
```

SwiftPM 壳相关代码：`Sources/OverlayTouch/`（编辑器）、`Sources/OverlayTouchHost/`（executable 壳）、`scripts/build_touch_sim_app.sh`（构建、组装 `.build/ios-sim/DataLayer Studio Touch.app`、安装启动）。

```sh
# 只构建组装
scripts/build_touch_sim_app.sh

# 构建并安装启动（默认 iPad Pro 13-inch (M5)，可用 SIM_DEVICE_NAME 覆盖）
scripts/build_touch_sim_app.sh --run

# 带本地样本自动载入 + 自动导出（仅模拟器编译路径，正式包不含此行为）
# TOUCH_AUTOEXPORT 传任意非空值即触发合成导出
TOUCH_AUTOLOAD_VIDEO=$PWD/assets/resourses/1kmrun.mov \
TOUCH_AUTOLOAD_FIT=$PWD/assets/resourses/478396517558812771.fit \
TOUCH_AUTOEXPORT=1 TOUCH_AUTOEXPORT_MAX_SECONDS=20 \
scripts/build_touch_sim_app.sh --run
```

验证手段：

- 截图：`xcrun simctl io <device> screenshot out.png`。
- 导出产物：`xcrun simctl get_app_container <device> run.libo.datalayer-studio.overlaytouchhost data`，产物在其 `Documents/` 下；可用 `ffprobe` 核对编码/时长/音轨，`ffmpeg` 抽帧核对浮层烧入。
- 崩溃排查：`~/Library/Logs/DiagnosticReports/overlay-touch-host-*.ips`；异常原因用 `simctl spawn <device> log show --predicate 'process == "overlay-touch-host"'` 找 `Terminating app` 行。
- 模型层单元测试（macOS 直接跑）：`swift test --filter OverlayTouchTests`。

已知点：

- 模拟器没有硬件编码器：`OverlayHardwareProfile` 探测为空，写出设置自动省略仅硬编支持的加速属性（技术文档 §4.2）；HEVC/H.264 走软件编码，慢但可完整验证链路。
- 交叉编译链接时的 `using sysroot for 'MacOSX' but targeting 'iPhone'` 警告可忽略（产物 `otool -l` 确认 platform 7）。
- 模拟器壳的 Info.plist 由脚本内嵌生成（fit/gpx UTI、四语言 `CFBundleLocalizations`、`UIFileSharingEnabled`、照片写入权限文案）；改 plist 就改脚本。

## 2. SwiftPM iOS 编译检查

改动 `OverlayTouch` 后，除 macOS 构建外至少跑一次 iOS 编译（模拟器或真机 SDK 任一，改共享层建议两个都跑）：

```sh
# 真机 SDK
IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
IOS_PLATFORM="$(xcrun --sdk iphoneos --show-sdk-platform-path)"
swift build --target OverlayTouch \
  --triple arm64-apple-ios26.0 \
  --sdk "$IOS_SDK" \
  -Xswiftc -sdk -Xswiftc "$IOS_SDK" \
  -Xswiftc -F -Xswiftc "$IOS_PLATFORM/Developer/Library/Frameworks" \
  --scratch-path .build/ios-device

# 模拟器 SDK（build_touch_sim_app.sh 内部即此方式）
SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
SIM_PLATFORM="$(xcrun --sdk iphonesimulator --show-sdk-platform-path)"
swift build --target OverlayTouch \
  --triple arm64-apple-ios26.0-simulator \
  --sdk "$SIM_SDK" \
  -Xswiftc -sdk -Xswiftc "$SIM_SDK" \
  -Xswiftc -F -Xswiftc "$SIM_PLATFORM/Developer/Library/Frameworks" \
  --scratch-path .build/ios-sim
```

只改文档不需要跑。CI 目前没有 iOS job（技术文档 §8-3 待办），编译信号靠本地。

## 3. 已验证环境

- Xcode：26.6，Build `17F113`；SDK：iOS/iPhoneOS 26.5。
- 模拟器：iPad Pro 13-inch (M5)，编辑器全链路（含软编导出）验证通过。
- 真机：M1 iPad Pro，iPadOS 27.0 beta——可安装启动 Xcode 26.6 构建的最小 App（P0 结论）。
- 组织开发团队：`LIGHTOUCH K.K.`，命令行签名 `DEVELOPMENT_TEAM=XUQV24QYZM`。钥匙串里若同时有 Personal Team 证书，不要默认拿它做 `DEVELOPMENT_TEAM`。

## 4. 真机验证流程

真机当前的验证目标：合成 HEVC 硬编导出的性能/热基准、导出中退后台/来电中断路径、触控/Pencil 手感。

正式壳工程已可直接构建真机包（§1 的 generic/platform=iOS 命令 + `-destination id=$DEVICE_ID` 安装）；下述 `/tmp` 临时壳流程保留作备忘，新验证优先走正式壳。

### 4.1 设备准备

1. iPad 连线并信任 Mac；打开 Developer Mode（`Settings → Privacy & Security → Developer Mode`，重启确认）。
2. Xcode 登录开发账号，确认 `LIGHTOUCH K.K.` 可见。
3. `xcrun devicectl list devices` 取 `$DEVICE_ID`；`xcrun devicectl device info details --device "$DEVICE_ID"` 需看到 `developerModeStatus: enabled`、`ddiServicesAvailable: true`。
4. 签名身份检查：`security find-identity -p codesigning -v`。不提交证书、provisioning profile、`.apple.env.local`。

### 4.2 /tmp 临时 Xcode 壳

正式 iOS 工程提交前，用 `/tmp` 下的临时壳（引用本地 SwiftPM package `/Users/albert/Develop/Shadow-TV/Overlay`，bundle id `run.libo.datalayer-studio.overlaytouchhost`）：

```swift
import OverlayTouch
import SwiftUI

@main
struct OverlayTouchHostApp: App {
    var body: some Scene {
        WindowGroup {
            OverlayTouchRootView()
        }
    }
}
```

构建 / 安装 / 启动：

```sh
xcodebuild \
  -project /tmp/datalayer-overlaytouch-host/OverlayTouchHost.xcodeproj \
  -scheme OverlayTouchHost \
  -configuration Debug \
  -destination id="$DEVICE_ID" \
  -derivedDataPath /tmp/datalayer-overlaytouch-host/DerivedData \
  DEVELOPMENT_TEAM=XUQV24QYZM \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build

xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  /tmp/datalayer-overlaytouch-host/DerivedData/Build/Products/Debug-iphoneos/OverlayTouchHost.app

xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  --terminate-existing \
  run.libo.datalayer-studio.overlaytouchhost
```

Xcode 26.6 的 `devicectl` 没有截图子命令，视觉确认看 iPad 屏幕。真机壳里没有模拟器的自动载入环境变量路径（`#if targetEnvironment(simulator)` 门控），素材走 Files 手工导入。

## 5. 本地样本与完成前回归

样本目录 `assets/resourses/`（.gitignore 已忽略）：一段视频与配套 FIT，FIT 开表时间是视频开始后第 49 秒；对表验证把视频 `00:00:49` 对齐 FIT elapsed `0`（打点对齐模式：视频时间 49、FIT 时间 0）。

改 `OverlayCore`、`OverlayStudioKit`、平台条件编译或任何可能影响 macOS 的代码后，至少跑：

```sh
swift test
scripts/build_app_bundle.sh
scripts/verify_app_bundle.sh
```

只改 `OverlayTouch`/`OverlayTouchHost` 时，至少跑：

```sh
swift test --filter OverlayTouchTests
swift build            # 确认 macOS 全量构建不断
```

并按 §2 跑一次 iOS 编译；需要看运行效果时按 §1 起模拟器。
