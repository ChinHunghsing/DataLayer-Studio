---
name: dls-timeline
description: 维护 DataLayer Studio 的 TimelineProject、媒体池、片段/轨道编辑、Undo/Redo、预览、工程保存恢复、离线重链、CLI 时间线参数和时间线导出预检。修改 Sources/OverlayCore/Timeline、StudioModel、ProjectTimelineView、MediaPoolTests、TimelineModelTests，或排查选择状态、吸附、裁剪、同步、工程兼容和预览/导出不一致时使用。
---

# DataLayer Studio 时间线

## 事实来源

先读当前代码与测试；`docs/archive/timeline-handoff.md` 只用于理解历史语义，文中的“下一步”和旧路径不是当前事实。

## 核心语义

- `StudioModel.timeline` 是会话内单一时间线状态；预览与导出共享 `TimelineProject.activeClips`，预检共享 `firstExportValidationIssue`。
- 片段区间左闭右开；源时间为 `sourceIn + (timelineTime - timelineStart)`。
- 轨道数组自底向上合成；同轨历史重叠取数组中最后一个命中片段。空白、稀疏视频和无视频工程都是合法状态。
- 同轨新编辑不允许重叠；复用 `nonOverlappingStart`、`neighborBounds` 和既有吸附 helper，不复制保护逻辑。
- `single.*` 和媒体 ID 必须稳定；异步导入完成顺序不能改变 Finder 选择顺序或片段落位。
- 移动、裁剪、分割、删除、换轨、轨道状态、重链和被引用素材变更保持既有 Undo/Redo 与锁轨语义。

## 工程与状态防线

- 新字段保持 Codable 向后兼容；旧 schema 可迁移，未来 schema 明确拒绝。不可改变 `.dlsproj` / `.dlspreset` 后缀语义。
- 离线重链按稳定 asset ID 更新 URL、bookmark 和元数据，不重建片段引用或几何。
- 工程持久化字段、clean snapshot、窗口 dirty 标记必须同步；避免保存后仍脏或状态变化未标脏。
- 全量替换时间线、删除被引用素材、打开其他工程和关闭未保存工程保留确认；普通可撤销编辑不增加确认。
- 选中项、活动片段、检查器编辑上下文和预览刷新必须从同一次模型变更更新。历史上距离单位、默认面板和首次载入曾因上下文或刷新缺失失效。
- 用户可见错误走现有 status/toast 出口；系统日志对路径和错误详情使用隐私级别。

## 验证路由

模型或工程格式：

```bash
swift test --filter TimelineModelTests
swift test --filter MediaPoolTests
```

`StudioModel`、检查器或预览状态再跑相关 `OverlayStudioTests`；改变 writer 可见片段解析、视频轨覆盖、空白或音频语义时，同时加载 `dls-export` 并跑 `TimelineVideoWriterTests`。
