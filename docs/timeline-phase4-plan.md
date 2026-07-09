# 时间线 · 阶段 4 执行计划（权威数据源 + 合成器）

> 状态：**阶段 4.1-4.3 已完成（单源导出入口改由时间线驱动）**；**4.6 的核心透明多浮层写出已完成**。当前实现仍保守复用既有单源写出器；多视频、权威 timeline 存储模型、UI 中真正添加/编辑多片段仍未完成。
> 本文档给未来会话一份可直接照做的分步执行计划，确保每一步都能完整落地、CI 绿、可安全停下。

## 目标（对应用户原始四点需求里尚未实现的部分）

1. 一个项目多个视频（顺序拼接成一条时间轴）。
2. 一个项目多个 FIT，每个 FIT = 一段浮层片段，可放在不同轨道 / 不同时间位置。
3. 片段可裁剪时长、拖拽位置、多轨叠加合成。
4. 预览与导出都从「时间线」这一权威数据源读取并合成。

前三点是「单源可安全映射」阶段做不到的根因：它们要求时间线从**派生视图**变成**存储的权威模型**，并要求一个能编排多片段、多轨、多源的**合成器**。

## 现有架构（阶段 4 要改的锚点）

- 核心渲染原语：`OverlayRenderer.render(videoTime:into:)`（`Sources/OverlayCore/Rendering/OverlayRenderer.swift:83`）——按单个时间点把**一层浮层**渲染进一个 `CVPixelBuffer`。**可每片段复用**，是阶段 4 的基石。
- 单源导出器：
  - `CompositedVideoWriter`（`Sources/OverlayCore/Video/CompositedVideoWriter.swift`）——不透明合成：读源视频帧，逐帧 `videoTime = exportStartTime + presentationTime`，`renderer.render(videoTime:into:overlayBuffer)`，叠加后写出。按帧流式、`frameIndex` 递进、不缓存整段。
  - `TransparentVideoWriter`（`Sources/OverlayCore/Video/TransparentVideoWriter.swift`）——透明 HEVC/ProRes Alpha 路径，**保守区域，不能重新引入透明发灰**。
- 导出入口：`StudioModel.export()`（`Sources/OverlayStudio/Stores/StudioModel.swift:1934`），按 mode 选 Transparent(1990)/Composited(2013)。
- 时间线模型：`TimelineProject` / `TimelineTrack` / `TimelineClip` / `MediaAsset`（`Sources/OverlayCore/Timeline/TimelineModel.swift`）。`TimelineClip.sourceTime(atTimelineTime:) = sourceIn + (t − timelineStart)`。
- 时间线目前是**派生**的：`StudioModel.currentTimelineProject`（`:1204`）每次从活动视频/FIT + `timeSync` + `layout` 用 `TimelineProject.migratingSingleSource(...)` 现算，不存储、不被预览/导出读取。
- 只读时间线视图：`ProjectTimelineView`（`Sources/OverlayStudio/Views/ProjectTimelineView.swift`），已支持：拖浮层片段→改同步、in/out 带→导出范围、播放头擦洗。

## 红线（每一步都不能破）

- 透明 Alpha 不发灰；`TransparentVideoWriter` 逻辑保守迁移，不重写像素混合细节。
- 逐帧流式，禁止把整段视频帧或大图缓存进内存。
- 向后兼容：旧 preset / 旧工程能加载；新增 Codable 字段给默认值，缺字段不报错。
- macOS 端既有功能、视觉、导出结果、构建/发布流程不回退。
- 不为「以后可能用」加抽象（AGENTS.md 禁止事项）——每一步都要落到一个**当次就在工作**的能力上，不做纯脚手架提交。

## 分步路线（每步独立 CI 绿、可停）

### 步骤 4.1　TimelineVideoWriter：单视频 + 单浮层，金样对齐
**状态：已完成。** `TimelineVideoWriter` 已新增，单视频 + 单浮层路径会从 `TimelineProject` 的片段几何推导同步关系，再分派到既有 `CompositedVideoWriter`。`TimelineVideoWriterTests` 覆盖了与旧合成 writer 的单源输出等价、缺少 telemetry、缺少视频片段等情况。

**做**：新建 `Sources/OverlayCore/Video/TimelineVideoWriter.swift`。输入一个 `TimelineProject`（此时只含 1 视频轨 1 浮层轨、各 1 片段）+ 输出配置，逐帧：
- 用视频轨当前片段定位源视频帧（`TimelineClip.sourceTime`）。
- 用浮层轨当前片段的 `sourceIn`/`timelineStart` 算出该片段的 activity elapsed，复用 `OverlayRenderer.render(videoTime:into:)`（每片段一个 renderer 实例）。
- 叠加、写出。透明路径先不动（4.1 只做不透明 `CompositedVideoWriter` 等价物）。

**验收**：新写一个 `TimelineVideoWriterTests`，对同一单源用「旧 `CompositedVideoWriter`」和「新 `TimelineVideoWriter`（由 `migratingSingleSource` 生成的工程）」各导出，逐帧/关键帧像素对比一致（金样）。**此步不接线到 UI/导出入口**——但它不是脚手架：它有独立测试证明其正确，是后续步的受测基座。若判定「未接线=脚手架」有顾虑，可与 4.2 合并为一个提交。

### 步骤 4.2　导出切到 TimelineVideoWriter（不透明路径）
**状态：已完成。** `StudioModel.export()` 的合成视频分支已改为使用 `currentTimelineProject` + `TimelineVideoWriter`；实际编码和混合仍复用旧 `CompositedVideoWriter`，降低回归风险。

**做**：`StudioModel.export()` 的不透明分支改为：用 `currentTimelineProject`（仍是派生的单源工程）驱动 `TimelineVideoWriter`。透明分支暂留旧 `TransparentVideoWriter`。
**验收**：真机导出单源视频，与改动前逐帧一致；跑 `CompositedVideoWriterTests` + 新 `TimelineVideoWriterTests` + 真机金样对比。

### 步骤 4.3　透明路径纳入 TimelineVideoWriter
**状态：已完成。** `StudioModel.export()` 的透明浮层分支已改为使用 `TimelineVideoWriter`；底层仍调用原 `TransparentVideoWriter`，没有重写 HEVC Alpha / ProRes Alpha 像素路径。`TimelineVideoWriterTests` 增加透明模式冒烟测试，`TransparentVideoWriterTests` 继续作为 Alpha 回归保护。

**做**：把透明 HEVC/ProRes Alpha 输出并入 `TimelineVideoWriter`（或让它内部按 codec 分派到既有透明混合代码，**逐字迁移像素混合，不改算法**）。
**验收**：`TransparentVideoWriterTests` 全绿；真机导出透明片段，放到深色/浅色背景确认**不发灰**、边缘正确。这一步单独提交、单独验证透明回归。

### 步骤 4.4　时间线变权威存储模型
**做**：`StudioModel` 增 `@Published var timeline: TimelineProject`。首次由 `migratingSingleSource` 建立；换源/改同步/改布局/改导出范围时**写回**这个存储模型（把现有 `setActivitySyncZeroVideoTime`、`setExportTrim*` 等改为编辑 `timeline` 的片段几何/工程属性）。`currentTimelineProject` 改为返回存储的 `timeline`。预览与导出改为读 `timeline`。持久化：`timeline` 进工程存档，做 Codable 向后兼容（旧档无 timeline 字段→用旧字段迁移生成）。
**验收**：这是最容易回退的一步——旧工程加载、同步/导出范围/布局与改动前完全一致；`swift test` 全量 + 真机回归（三标签、预览、导出金样）。**建议整段做完再提交，不半开工。**

### 步骤 4.5　多视频顺序拼接
**做**：素材池拖第二个视频到视频轨→追加为第二个视频片段（顺序拼接成一条视频时间轴）。`TimelineVideoWriter` 已按片段定位源，天然支持跨片段切换源视频。
**验收**：两段不同分辨率/帧率视频拼接导出正确；片段边界无错帧；内存不涨（仍逐帧）。

### 步骤 4.6　多浮层片段 / 多轨叠加
**状态：部分完成。** `TimelineVideoWriter` 已支持透明浮层模式下多个 overlay clip / 多 overlay track 按轨道顺序逐帧叠加，单浮层仍走原 `TransparentVideoWriter` 路径以保护 HEVC Alpha。尚未完成：`StudioModel` 权威 timeline 存储、素材池拖 FIT 生成新浮层片段、预览与 UI 编辑多片段。

**做**：素材池拖 FIT 到浮层轨→生成浮层片段（每段可选布局、默认继承项目）；支持多条浮层轨，`TimelineVideoWriter` 逐帧对「该时刻所有启用轨的浮层片段」自底向上依次 `render` 叠加。
**验收**：两个 FIT 双轨叠加预览=导出；透明叠加不发灰；逐帧流式内存稳定。

### 步骤 4.7　片段编辑收口 + CLI/测试/回归
**做**：片段裁剪时长（拉边=改 `duration`/`sourceIn`，真正的几何裁剪，此时才语义正确）、拖拽位置、吸附；片段检查器（改单段布局/距离单位）。CLI 若暴露时间线导出则补参数与 `OverlayCLITests`。
**验收**：全量 `swift test`、`scripts/build_app_bundle.sh`、CLI 测试、真机综合回归。

## 每步的固定收尾清单

1. `swift build` + `swift build -c release`（release 更严）。
2. 相关测试：改渲染/导出→`TimelineVideoWriterTests`/`CompositedVideoWriterTests`/`TransparentVideoWriterTests`/`OverlayRendererTests`；改 UI 状态→`OverlayStudioTests`；改 CLI→`OverlayCLITests`。
3. `scripts/build_app_bundle.sh` 重建，真机验证（认 `/Overlay/.build/...` 进程，pkill 用完整路径，别误杀 `/Applications` 的 App Store 版）。
4. 简体中文提交、推送、`gh run watch` 确认 CI 绿。
5. 更新记忆 `timeline-feature-progress`。

## 里程碑现状（阶段 4 之前，已可用）

- 素材池：多视频 / 多 FIT 导入、去重、活动项高亮、导入更多。
- 时间线（只读渲染）：标尺 + V/O 轨 + 片段块 + 红播放头。
- 拖浮层片段 → 改同步（写回 match-point 同步）。
- in/out 高亮带 → 导出范围（与「截剪」标签双向一致，预览自动 clamp）。
- 播放头擦洗预览。

单源可安全映射的编辑已全部落地；再往前必须走本文档的阶段 4。
