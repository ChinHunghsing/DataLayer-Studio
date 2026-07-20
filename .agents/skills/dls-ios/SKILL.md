---
name: dls-ios
description: 维护 DataLayer Studio 的 OverlayTouch、OverlayTouchHost、正式 iOS 壳、iPad/iPhone 布局、StoreKit 2 订阅导出门、签名、模拟器与真机验证。修改 Sources/OverlayTouch、Sources/OverlayStudioKit、App/DataLayerStudioMobile.xcodeproj、移动端文案或跨平台条件编译时使用。
---

# DataLayer Studio iOS

## 开始前

完整阅读 `docs/ios/ipados-development-testing.md` 的相关流程；涉及订阅、App record、StoreKit 或权益时再读 `docs/ios/mobile-subscription-design.md`。

## 平台边界

- `OverlayStudioKit` 保持平台中立，禁止 import AppKit/UIKit；iOS 专属实现用 `#if os(iOS)` 门控。
- macOS 现有功能、视觉、导出与发布不能回退。改共享层或条件编译后，必须跑 macOS 测试和 App bundle 构建。
- iPadOS 横屏优先，iPhone 竖屏优先；同时保留合理的尺寸适配和可访问性。
- `OverlayTouchHost` 是 SwiftPM 调试壳；StoreKit、正式 entitlement、签名和发布使用 `App/DataLayerStudioMobile.xcodeproj`。
- 本地素材只放已忽略的 `assets/resourses/`；不提交临时 Xcode 工程、设备素材、导出物、证书、profile 或 xcuserdata。

## 订阅红线

- iOS 使用独立 App record 与 bundle id `run.libo.datalayer-studio.mobile`；绝不把 iOS platform 加入 macOS App record `6782545770`。
- 免费用户可完整编辑和预览，但导出需要有效订阅。权益门只放在 `TouchStudioModel.export()` 共享入口，正式壳强制，SwiftPM 调试壳可按既有方式放行。
- StoreKit 2 本地验签与 `Transaction.currentEntitlements` / `updates` 是客户端真相；退款、撤销、宽限期、恢复购买与离线缓存语义不得简化。
- 新文案同步 `TouchLocalization.swift` 的英文、简中、繁中、日文四表并跑键位测试。

## 最小验证

只改 Touch 层：

```bash
swift test --filter OverlayTouchTests
swift build
scripts/build_touch_sim_app.sh
```

改共享层或平台条件编译：

```bash
swift test
scripts/build_app_bundle.sh
scripts/verify_app_bundle.sh
```

并按开发文档至少跑一次 iOS 模拟器或 iPhoneOS 编译。仅在用户可见行为、硬编、热性能、中断、StoreKit 或签名需要时做对应模拟器/真机验证。
