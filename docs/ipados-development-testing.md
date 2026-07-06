# DataLayer Studio iPadOS 开发与真机测试备忘

| 项目 | 内容 |
| --- | --- |
| 状态 | 本地开发备忘 |
| 日期 | 2026-07-06 |
| 适用范围 | `OverlayTouch`、`OverlayTouchHost` 模拟器壳、未来 iOS/iPadOS Xcode app shell、真机签名与安装启动验证 |

## 0. 原则

- iPadOS/iOS 开发不能影响 macOS 端既有功能、视觉表现、导出结果和构建/发布流程。
- 当前仓库只提交 SwiftPM 代码；真机验证用的临时 Xcode app shell 放 `/tmp`，不要提交。
- 本地视频、FIT、导出产物和 `assets/resourses/` 都不要提交。
- 涉及共享层或平台条件编译后，至少跑 macOS 回归：`swift test`、`scripts/build_app_bundle.sh`、`scripts/verify_app_bundle.sh`。

## 1. 已验证环境

- Xcode：26.6，Build `17F113`。
- SDK：iOS/iPhoneOS 26.5。
- 真机：M1 iPad Pro，iPadOS 27.0 beta。
- 结论：iPadOS 27 beta 真机可以安装并启动 Xcode 26.6 / iOS SDK 26.5 构建的最小 App。
- 当前组织开发团队：`LIGHTOUCH K.K.`，命令行签名使用 `DEVELOPMENT_TEAM=XUQV24QYZM`。
- 备注：如果钥匙串里同时有 Personal Team 的 Apple Development 证书，不要默认拿它做 `DEVELOPMENT_TEAM`；P0 测试时组织 Team 构建、安装和启动成功。

## 2. 设备准备

1. iPad 用线连接 Mac，并在设备上信任这台 Mac。
2. 打开 Developer Mode：iPad `Settings` -> `Privacy & Security` -> `Developer Mode`，打开后按系统提示重启并确认。
3. Xcode `Settings` -> `Apple Accounts` 中确认已登录开发账号，且 `LIGHTOUCH K.K.` 团队可见。
4. 查设备：

```sh
xcrun devicectl list devices
```

5. 查设备详情，把 `$DEVICE_ID` 换成上一步看到的设备标识：

```sh
xcrun devicectl device info details --device "$DEVICE_ID"
```

需要看到：

- `developerModeStatus: enabled`
- `ddiServicesAvailable: true`
- install / launch capabilities 可用

## 3. 签名检查

查看本机代码签名身份：

```sh
security find-identity -p codesigning -v
```

真机 Debug 构建默认传：

```sh
DEVELOPMENT_TEAM=XUQV24QYZM
```

不要提交证书、provisioning profile、`.apple.env.local` 或任何私钥。

## 4. SwiftPM iPhoneOS 编译

当前已提交的 iPadOS 入口是 SwiftPM library target：`OverlayTouch`。先确认它能为 iPhoneOS SDK 编译：

```sh
IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
IOS_PLATFORM="$(xcrun --sdk iphoneos --show-sdk-platform-path)"
swift build --target OverlayTouch \
  --triple arm64-apple-ios26.0 \
  --sdk "$IOS_SDK" \
  -Xswiftc -sdk -Xswiftc "$IOS_SDK" \
  -Xswiftc -F -Xswiftc "$IOS_PLATFORM/Developer/Library/Frameworks"
```

也可以让 Xcode 直接构建 SwiftPM scheme：

```sh
xcodebuild -scheme OverlayTouch \
  -destination generic/platform=iOS \
  -derivedDataPath /tmp/datalayer-overlaytouch-package-build \
  build
```

如果只是改文档，不需要跑这些命令。

## 4.5 模拟器开发工作流（日常首选）

日常 iPadOS 开发优先用模拟器，不依赖真机与签名。仓库已提交：

- `Sources/OverlayTouch/`：iPad 编辑器（会话模型 + 三栏 UI），iOS 专属代码用 `#if os(iOS)` 门控，macOS 构建仍然通过。
- `Sources/OverlayTouchHost/`：SwiftPM executable App 壳；macOS 下退化为提示用 CLI。
- `scripts/build_touch_sim_app.sh`：构建、组装 `.build/ios-sim/DataLayer Studio Touch.app`，`--run` 直接安装启动到 iPad 模拟器。

```sh
# 只构建组装
scripts/build_touch_sim_app.sh

# 构建并安装启动（默认 iPad Pro 13-inch (M5)，可用 SIM_DEVICE_NAME 覆盖）
scripts/build_touch_sim_app.sh --run

# 带本地样本自动载入 + 自动导出（仅模拟器调试路径，正式包不含此行为）
# iPad 版只导出合成成片，TOUCH_AUTOEXPORT 传任意非空值即可
TOUCH_AUTOLOAD_VIDEO=/path/to/video.mov \
TOUCH_AUTOLOAD_FIT=/path/to/activity.fit \
TOUCH_AUTOEXPORT=1 TOUCH_AUTOEXPORT_MAX_SECONDS=20 \
scripts/build_touch_sim_app.sh --run
```

- 截图验证：`xcrun simctl io <device> screenshot out.png`。
- 导出产物在 App 沙盒 Documents：`xcrun simctl get_app_container <device> run.libo.datalayer-studio.overlaytouchhost data`。
- 模拟器没有硬件编码器：`OverlayHardwareProfile` 探测为空，写出设置会自动省略仅硬编支持的加速属性；HEVC/H.264 走软件编码可完整验证导出链路。
- iPad 版产品决策（2026-07-06）：只导出最终成片（合成视频），不提供透明浮层导出；透明 HEVC-alpha/ProRes 浮层由 macOS 版承担。
- 模型层单元测试在 macOS 直接跑：`swift test --filter OverlayTouchTests`。

## 5. 真机 App 壳验证

在正式 iOS Xcode 工程提交前，用 `/tmp` 下的临时 Xcode app shell 做真机验证。这个 shell 只需要：

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

临时工程需引用本地 SwiftPM package：`/Users/albert/Develop/Shadow-TV/Overlay`，App bundle id 可用：

```text
run.libo.datalayer-studio.overlaytouchhost
```

构建到真机：

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
```

安装：

```sh
xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  /tmp/datalayer-overlaytouch-host/DerivedData/Build/Products/Debug-iphoneos/OverlayTouchHost.app
```

启动：

```sh
xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  --terminate-existing \
  run.libo.datalayer-studio.overlaytouchhost
```

当前 Xcode 26.6 的 `devicectl` 没有截图子命令；启动后视觉确认需要看 iPad 屏幕。

## 6. 本地样本素材

本地样本放：

```text
assets/resourses/
```

该目录已被 `.gitignore` 忽略。当前样本是一段视频与配套 FIT，FIT 的开表时间是视频开始后第 49 秒；做同步验证时，应把视频 `00:00:49` 对齐到 FIT elapsed `0`。

## 7. 完成前回归

改 `OverlayCore`、`OverlayStudioKit`、平台条件编译或任何可能影响 macOS 的代码后，至少跑：

```sh
swift test
scripts/build_app_bundle.sh
scripts/verify_app_bundle.sh
```

改 iPadOS/iOS 入口时，至少跑：

```sh
swift build --target OverlayTouch
```

并按第 4 节跑一次 iPhoneOS 编译。需要确认真机链路时，再按第 5 节安装启动。
