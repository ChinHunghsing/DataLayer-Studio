---
name: dls-export
description: 维护 DataLayer Studio 的 TransparentVideoWriter、CompositedVideoWriter、TimelineVideoWriter、OverlayRenderer、导出设置、透明 Alpha、音视频合成、逐帧内存与 ExportEntitlement。修改 Sources/OverlayCore/Video、渲染器、GUI/CLI 导出入口、免费版水印/1080p 限制，或排查导出时长、沙盒权限、黑帧、音频、透明发灰和内存暴涨时使用。
---

# DataLayer Studio 导出

## 商业与授权红线

- Mac App Store 是付费完整版。
- GitHub Release、自编译和 CLI 是免费版：编辑与预览完整，导出最长边按 1080p 档位钳制并带 `Made with DataLayer Studio` 水印。
- 限制以 `OverlayCore.ExportEntitlement` 为唯一核心规则，并贯穿 `TransparentVideoWriter`、`CompositedVideoWriter`、`TimelineVideoWriter`；GUI 的 `PurchaseAuthorizationStore` 与 CLI 只负责传入权益。
- 免费版预览、输出设置、CLI、README 和 Release 说明必须清楚展示限制并引导购买 Mac App Store 完整版。不得删除、绕过或只在 UI 层实现限制。
- iOS 是独立订阅模型：编辑/预览免费，无有效订阅不启动导出；不要把 macOS 免费版水印策略误套到 iOS。

## 写出不变量

- 视频按帧流式读取、渲染和写入；禁止缓存整段帧、大图或完整音频。循环内维持既有 autorelease 边界。
- 透明 HEVC/ProRes 4444 保持正确 Alpha，空白帧全透明；普通合成的无视频区是黑帧，音频空隙静音。
- 不同编码、尺寸、帧率和方向的视频继续经 composition 规范化；每片段应用自己的 transform。
- 时间计算保留分数帧精度，特别是 29.97 fps、裁剪边界和最后一帧；不要用整数秒或累计浮点步进替代现有时间基准。
- 临时文件放目标目录并在失败、取消、崩溃恢复路径清理；覆盖现有文件前保持确认与可写性判断。
- App、CLI 和 writer 复用同一时间线预检；不要只修某个入口。

## 最小验证

```bash
swift test --filter ExportEntitlementTests
swift test --filter TransparentVideoWriterTests
swift test --filter CompositedVideoWriterTests
swift test --filter TimelineVideoWriterTests
swift test --filter OverlayRendererTests
```

按改动范围选最窄集合；涉及 Alpha、跨片段合成、时长或内存时必须做实际编码/解码断言。影响 App 可见行为后运行 `scripts/build_app_bundle.sh`。
