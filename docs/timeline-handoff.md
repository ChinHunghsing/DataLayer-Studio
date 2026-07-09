# DataLayer Studio 时间线改造交接文档

更新时间：2026-07-10
当前基线提交：`83e8605`

## 目标

把 DataLayer Studio 从“单视频 + 单运动文件”的工作流，逐步改造成一个轻量时间线：

- 一个工程可以包含多个视频和多个 FIT/GPX 运动文件。
- 视频片段按时间线顺序拼接。
- 运动文件作为数据浮层片段放在 overlay track 上，可以拖动、裁剪、叠加。
- 预览和导出都以时间线为权威数据源。
- 仍然保留原来的透明 Alpha 浮层导出质量，不能回归透明区域发灰问题。

主要参考资料：

- `docs/timeline-phase4-plan.md`
- `/Users/albert/Downloads/DataLayerStudio时间线改造方案.mhtml`

## 当前进展

### 已完成

- 时间线核心模型已经落地：
  - `Sources/OverlayCore/Timeline/TimelineModel.swift`
  - `TimelineProject`
  - `MediaAsset`
  - `TimelineTrack`
  - `TimelineClip`
- 旧单视频/单运动文件工作流可以迁移成时间线项目。
- 媒体池已经支持视频和运动文件资产。
- 时间线 UI 已经有基础可用状态：
  - `Sources/OverlayStudio/Views/ProjectTimelineView.swift`
  - 支持显示视频轨和浮层轨。
  - 支持选择片段。
  - 支持拖动浮层片段。
  - 支持非迁移片段的左右裁剪手柄。
  - 支持把运动文件从媒体池追加到浮层轨。
- 预览已经可以从当前时间线读取数据。
- 透明浮层和合成视频导出已经走时间线 writer：
  - `Sources/OverlayCore/Video/TimelineVideoWriter.swift`
  - 保持帧流式写出，不能把整段视频缓存进内存。
- 多个浮层片段、多条 overlay track 的合成路径已经具备基础能力。
- 多个视频片段按顺序拼接的导出路径已经具备基础能力。
- CLI 已经支持从时间线工程 JSON 导出，并禁止和单源参数混用。
- 工程保存和打开已补齐：
  - 菜单入口在 macOS App 内可用。
  - 工程保存为 JSON。
  - 媒体资产带 security-scoped bookmark，尽量支持重新打开外部文件。
  - 相关实现主要在 `Sources/OverlayStudio/Models/StudioModel.swift`。
- 当前上一轮验证结果：
  - `swift test --filter MediaPoolTests` 通过。
  - `swift test` 通过，299 个测试。
  - `scripts/build_app_bundle.sh` 通过。

### 已知状态差异

`docs/timeline-phase4-plan.md` 里仍然把“工程保存/打开”写成未完成或部分完成；这已经被提交 `83e8605` 补齐。后续接手时可以先更新那份阶段计划的状态，避免重复判断。

## 尚未完成或不应误判为已完成

- 不是完整 NLE，不支持复杂剪辑软件能力。
- 视频轨目前以“顺序拼接”为主，不要默认承诺：
  - 画中画。
  - 多视频重叠混合。
  - 多机位。
  - 转场。
- 不要默认承诺所有混合方向、混合分辨率视频都已经完整验证。接手时需要针对：
  - 竖屏 + 横屏混剪。
  - 不同分辨率混剪。
  - 不同帧率混剪。
  做独立测试。
- 轨道管理还很轻：
  - 是否需要新增/删除/重命名轨道，要看下一步产品需求。
  - `isLocked`、`isEnabled` 之类字段如果存在，也不等于 UI 行为已经完整。
- Undo/Redo 不要默认认为已经完整覆盖时间线编辑。
- 工程保存是 JSON + bookmark 的实用版本，不是最终工程包格式。
- bookmark 失效、源文件移动、权限失效时的恢复 UI 仍然可以继续优化。

## 重要设计边界

- Alpha 导出路径要保守修改：
  - 透明浮层的 HEVC Alpha / ProRes 4444 路径不能因为时间线改造重新发灰。
  - 修改 `TransparentVideoWriter` 或相关 pixel buffer 设置前必须补回归测试或手动验证。
- 写出必须流式：
  - 不允许为了拼接或预览把整段视频帧、大图、CGImage 全部缓存起来。
  - 之前合成视频内存爆过，这条是硬红线。
- `TimelineProject`、layout preset、保存工程都要保持 Codable 向后兼容。
- 预览和导出应继续以同一套时间线映射为准，避免“预览看起来对，导出偏移”。
- 同步 offset 的语义仍是“视频时间 ↔ 运动时间”，不要被运动裁切或片段显示归零语义带偏。

## 建议下一步

### 1. 先做手动 QA

用真实素材确认当前可用性：

1. 打开 App。
2. 导入一个视频和一个 FIT/GPX。
3. 添加第二个运动文件到浮层轨。
4. 拖动浮层片段。
5. 裁剪浮层片段。
6. 保存工程 JSON。
7. 退出 App 后重新打开工程。
8. 验证预览、透明浮层导出、合成视频导出。

这一步比继续写功能更重要，因为现在时间线已经进入“看起来能用，但需要真实工作流打磨”的阶段。

### 2. 更新阶段计划状态

更新 `docs/timeline-phase4-plan.md`：

- 把工程保存/打开标成已完成。
- 把仍然未做的内容明确收敛成：
  - 混合方向/分辨率视频验证。
  - 轨道管理。
  - bookmark 失效恢复。
  - Undo/Redo 覆盖。
  - 时间线手动 QA。

### 3. 做工程打开的错误恢复

优先级较高，因为这是用户能直接遇到的问题：

- bookmark 失效时给清晰提示。
- 允许用户重新定位缺失的视频或运动文件。
- 工程中某个 asset 缺失时，不要让整个工程加载失败。

### 4. 做时间线编辑体验收尾

按最小可用原则，只补用户会立刻感知的问题：

- 拖动和裁剪时的吸附反馈。
- 选中片段后 inspector 显示更明确。
- 片段时间、源文件、裁剪起止点展示。
- 如果需要，补“删除选中片段”快捷入口。

### 5. 再考虑更大的能力

只有当上面稳定后，再考虑：

- 多视频混合方向/分辨率的更完整适配。
- 明确拒绝或支持重叠视频片段。
- 工程包格式，而不是裸 JSON。
- 更完整的 undo/redo。

## 推荐验证命令

常规验证：

```bash
swift test
scripts/build_app_bundle.sh
```

时间线相关测试：

```bash
swift test --filter MediaPoolTests
swift test --filter TimelineVideoWriterTests
swift test --filter OverlayCLITests
```

CLI 检查：

```bash
swift run overlay --help
```

## 接手时先看的文件

- `docs/timeline-phase4-plan.md`
- `Sources/OverlayCore/Timeline/TimelineModel.swift`
- `Sources/OverlayCore/Video/TimelineVideoWriter.swift`
- `Sources/OverlayStudio/Models/StudioModel.swift`
- `Sources/OverlayStudio/Views/ProjectTimelineView.swift`
- `Sources/OverlayStudio/Views/TimelineClipInspectorView.swift`
- `Tests/OverlayStudioTests/MediaPoolTests.swift`
- `Tests/OverlayCoreTests/TimelineVideoWriterTests.swift`
- `Tests/OverlayCLITests/CommandLineOptionsTests.swift`

## 建议接手顺序

1. 先跑 `swift test --filter MediaPoolTests`，确认时间线状态模型没有坏。
2. 打开 `docs/timeline-phase4-plan.md` 和本文档，对齐真实状态。
3. 用真实素材手动跑一次保存、打开、预览、导出。
4. 只修真实 QA 暴露的问题。
5. 再决定是否继续扩大时间线能力。

