# DataLayer Studio 时间线改造交接文档

- 更新时间：2026-07-10
- 提交审阅范围：`093da56ec8eff6a92b1b6c68e1ef740bccbaec56`（含）至 `f2cd534620c5b3cabffad39678581ff6d8084f2c`（含），共 23 个提交
- 当前功能实现基线：`83e8605cba28a1e2213d8910e703af755a8992b6`
- 原交接文档提交：`f2cd534620c5b3cabffad39678581ff6d8084f2c`

## 这份文档的用途

这份文档是下一轮时间线工作的当前事实基线。`docs/timeline-phase4-plan.md` 记录了阶段 4 的原始拆分，但其中“工程保存/打开仍未完成”等状态已经过期；判断真实能力和下一步优先级时，以本文和当前代码为准。

目标仍然是把 DataLayer Studio 从“单视频 + 单运动文件”改造成轻量时间线：

- 一个工程包含多个视频和多个 FIT/GPX。
- 视频片段按时间线顺序拼接。
- 运动数据作为浮层片段放在 overlay track，可移动、裁剪、叠加。
- 预览和导出读取同一个 `TimelineProject`。
- 保持透明 HEVC Alpha / ProRes 4444 的质量和逐帧流式写出，不重新引入透明区域发灰或整段缓存导致的内存问题。

这不是完整 NLE。当前范围不包含画中画、多机位、转场或任意视频重叠混合。

## 23 个提交的演进结论

- `093da56`：新增 `TimelineProject`、`MediaAsset`、`TimelineTrack`、`TimelineClip` 和单源迁移；时间映射为 `sourceIn + (timelineTime - timelineStart)`。
- `c93f968`：加入多视频/多运动文件媒体池，活动源仍兼容旧预览和导出。
- `44d377d`、`5f11833`、`53df9f1`：加入时间线标签、播放头擦洗、视频/浮层同步拖动和导出 in/out 带。
- `3881e79`：建立阶段 4 计划。
- `4802126`、`920f476`、`fcf0659`：浮层按真实运动时长显示、Finder 多选导入、确定性 `single.*` ID 修复拖拽手势，视频片段也可反向拖动调整同步。
- `8ec8a1c`、`ce3b427`：接入 `TimelineVideoWriter`，先保持单源不透明/透明路径等价，再加入多浮层透明导出。
- `8de1dfa`、`5b60439`、`b400811`：时间线成为会话内存储状态，接入多运动文件、多浮层合成导出和自定义片段移动。
- `91e0880`、`a122181`：加入视频顺序追加、左右裁剪，以及连续多视频的合成导出和音轨拼接。
- `9b386c1`：CLI 支持 `--timeline-project` JSON，并禁止和 `--fit`、`--video`、同步参数、布局预设等单源参数混用。
- `4c4cf19`、`abccfa2`：加入片段边缘吸附、片段检查器、片段时间/布局/距离单位编辑。
- `d40bbef`、`4db67e0`：自定义时间线预览读取时间线；运动素材可从媒体池拖到指定 overlay 轨并按落点追加。
- `83e8605`：加入时间线工程 JSON 保存/打开和 security-scoped bookmark。
- `f2cd534`：建立原交接文档，没有代码变化。

结论：阶段 4 的主要功能链路已经接通，下一步不应继续盲目扩功能；应先处理数据丢失风险、统一预览/导出语义、补工程恢复和真实素材 QA。

## 当前真实架构与语义

### 核心模型

- `Sources/OverlayCore/Timeline/TimelineModel.swift`
- `TimelineProject.assets` 保存媒体资产；`tracks` 按自底向上的合成顺序排列。
- `TimelineTrack.Kind` 目前有 `video` 和 `overlay`。
- `TimelineTrack.clip(atTimelineTime:)` 在同轨片段重叠时返回数组中最后一个片段。
- `TimelineClip` 的区间是左闭右开：`timelineStart <= t < timelineEnd`。
- 片段源时间映射为 `sourceIn + (t - timelineStart)`。
- `TimelineProject.duration` 是所有轨道最远的片段结束时间，不只看视频轨。
- 单源迁移使用稳定的 `single.video.*` / `single.overlay.*` ID；这是 SwiftUI 拖拽不中断的必要条件，不要改回随机 ID。
- 浮层单源迁移按运动文件真实剩余时长建片段，可能长于视频。

### App 状态

- 实际文件是 `Sources/OverlayStudio/Stores/StudioModel.swift`，不是旧文档写的 `Models/StudioModel.swift`。
- `StudioModel.timeline` 是预览和导出的当前时间线状态。
- 初始单源工作流仍由旧字段迁移生成时间线；第一次把池中素材“加入时间线”后进入自定义时间线模式。
- 自定义模式下，输出宽高、帧率、距离单位会更新工程设置，不会重建并覆盖多片段结构。
- 活动数据按 `assetID` 缓存在 `activitySeriesByAssetID`，预览和导出据此为每个浮层片段找到各自的 telemetry。

### UI 已有能力

- 视频/FIT/GPX Finder 导入支持多选；第一个成为活动源，其余异步加入媒体池。
- 媒体池的“加入时间线”按钮：
  - 视频追加到基础视频轨末尾。
  - 运动素材默认在当前播放头位置新建一条 overlay 轨。
- 运动素材可从媒体池拖到现有 overlay 轨，按落点时间追加到该轨。
- 时间线显示标尺、视频轨、浮层轨、片段、播放头和导出 in/out 带。
- `single.*` 片段拖动仍修改全局视频/运动同步；池中加入的自定义片段移动只修改自己的 `timelineStart`。
- 自定义片段可左右裁剪；左裁同时修改 `timelineStart`、`sourceIn`、`duration`，右裁修改 `duration`，最短 0.1 秒。
- 移动和裁剪会吸附到时间线 0 点及其他片段边缘，阈值为当前显示宽度约 6 px；目前没有可见吸附参考线。
- 自定义时间线中，选中片段后右侧检查器可编辑时间线开始、素材入点、时长；运动片段还可设置单片段距离单位和布局。纯单源迁移模式下这些字段只读。
- 导出 in/out 带仍是 `StudioModel` 的会话导出范围，不属于 `TimelineProject` 片段几何。

### 预览与导出

- 自定义时间线预览按当前时间选择视频片段，并按 overlay 轨顺序合成浮层。
- 自定义时间线播放不再直接使用 `AVPlayer`，而是用定时器推进并逐帧提取视频画面；当前没有连续视频音频预览，需要单独确认产品预期和性能。
- `Sources/OverlayCore/Video/TimelineVideoWriter.swift` 是透明浮层和合成视频的统一入口。
- 单浮层透明导出继续委托原 `TransparentVideoWriter`，保护既有 Alpha 路径。
- 多浮层透明导出逐帧渲染和合成，不缓存整段视频。
- 合成视频导出要求导出范围被启用的视频片段连续覆盖：
  - 起点必须落在视频片段内。
  - 片段之间不能留空。
  - 片段不能重叠。
  - 片段不能超出源视频可用时长。
- 多视频通过 `AVMutableComposition` 顺序拼接；目前只取第一段视频的 `preferredTransform` 作为组合轨 transform。
- 启用的 overlay 轨按 `TimelineProject.tracks` 自底向上合成；禁用轨不导出。

### 工程保存/打开与 CLI

- App 菜单已有“打开时间线工程”和“保存时间线工程”；保存是每次弹出面板的 Save As 行为。
- 工程格式是直接编码的 `TimelineProject` JSON，不是工程包，也没有独立 schema/version 字段。
- `MediaAsset.bookmarkData` 保存 security-scoped bookmark；旧 JSON 缺该可选字段仍可解码。
- 打开工程时会先应用 JSON，再异步加载各媒体资产。
- 当前 JSON 保存：素材、轨道、片段、输出宽高/帧率、工程距离单位以及片段布局/单位。
- 当前 JSON 不保存：导出 in/out、activity trim、导出模式、codec、bitrate、输出路径、当前播放头和 UI 选择状态；重新打开后导出范围重置为完整时间线。
- CLI 用 `overlay --timeline-project project.json --output output.mov ...` 导出，直接读取 JSON 中的文件 URL，不使用 App 的 bookmark 恢复交互。
- CLI 当前默认导出 `project.duration` 全长，不读取 App 会话里的导出 in/out。

## 已完成并有自动测试覆盖的主路径

- 单源迁移时间映射、真实浮层时长、稳定 ID、Codable 往返、吸附候选。
- 媒体池去重和活动源切换。
- 多运动文件加入新轨或指定 overlay 轨。
- 自定义片段移动、裁剪、检查器时间/布局/距离单位编辑。
- 自定义时间线 JSON round trip。
- 单源时间线合成视频与旧 writer 的基础输出等价检查。
- 单浮层透明导出冒烟测试。
- 多浮层透明/不透明合成冒烟测试。
- 连续两段视频和音轨顺序导出测试。
- CLI 时间线工程参数、冲突参数和 JSON 读取测试。

验证状态：

- 本次交接更新重新运行 `swift test`：299 个测试全部通过，0 failure。
- 功能基线提交记录的 `swift test --filter MediaPoolTests` 通过。
- 功能基线提交记录的 `scripts/build_app_bundle.sh` 通过；本次只有 Markdown 文档变化，没有重复构建 App bundle。

注意：硬件编码器相关测试允许在不可用机器上 skip；“测试通过”不等于已经验证多浮层 Alpha 的真实视觉质量或混合方向视频。

## 下一步必须先处理的问题

### P0：防止用户时间线被静默覆盖

当前从媒体池点击另一个视频或运动素材，会把 `timelineUsesSingleSourceMigration` 重新设为 `true` 并重建单源时间线。用户已有的自定义多片段时间线会被直接替换，没有 dirty state、确认、自动保存或 Undo。打开另一个工程、移除仍被时间线引用的非活动素材也没有未保存改动保护。

下一步应先：

1. 明确“点击媒体池行”在自定义时间线中的产品语义，不能继续无提示重建工程。
2. 增加工程 dirty state。
3. 在打开工程、切换为单源、移除被引用素材、关闭窗口前处理未保存修改。
4. 为这一行为补 `MediaPoolTests`/状态模型测试，防止数据丢失回归。

### P0：统一同轨重叠浮层的预览/导出语义

当前存在确定的不一致：

- 预览调用 `TimelineTrack.clip(atTimelineTime:)`，同一 overlay 轨重叠时只取最后一个片段。
- `TimelineVideoWriter` 会 flatten 启用轨的所有 overlay clip，再把同一时刻命中的片段全部合成。

因此，同轨重叠时可能出现“预览一层、导出两层”。下一步必须选定一种规则并让预览、透明导出、合成视频导出共用同一个片段解析器；同时增加同轨重叠测试。

### P0：视频轨编辑可以制造直到导出才暴露的无效工程

自定义视频片段可以自由移动和裁剪，但 writer 拒绝导出范围内的视频空洞、重叠和越过源时长。UI 当前没有预检或即时错误提示。

下一步应增加共享的 `TimelineProject` 校验/导出预检，并决定：

- 视频片段是否始终保持 ripple/顺序相接；或
- 允许自由移动，但在时间线上明确显示空洞/重叠错误，并在导出前给可操作提示。

不要在 App 与 CLI 各复制一套校验规则。

### P1：工程打开的缺失素材恢复

当前 bookmark stale 标记被读取但没有处理；bookmark 解析失败会退回 JSON 中的旧 URL。后台视频元数据/FIT 解析失败时基本静默，工程仍会显示“已加载”，之后预览可能缺层、导出才报缺 telemetry 或不可读视频。

需要：

- 打开时收集每个 asset 的 resolved / stale / missing / unreadable 状态。
- 允许逐个重新定位视频和 FIT/GPX，并把新 URL/bookmark 写回工程。
- 单个 asset 缺失时保留其片段和工程其余内容，不让整个工程不可用。
- 在预览、时间线和导出预检中显示同一个缺失素材状态。

### P1：真实素材和视觉回归矩阵

自动测试还不能证明以下场景可交付：

- HEVC Alpha 与 ProRes 4444 的多浮层结果放在深色/浅色背景时边缘不灰。
- 横屏 + 竖屏、不同分辨率、不同帧率视频连续拼接。
- 多视频边界无黑帧/重复帧，音频连续且时间正确。
- 长视频、多轨预览和导出内存稳定。
- 自定义时间线定时器预览的播放流畅度、拖动响应和无音频行为。
- 保存、退出 App、重新打开、重新授权素材后的预览与两种导出。

混合方向尤其要谨慎：组合轨目前只使用第一段视频的 transform，不能把它写成“已经支持”。

### P2：编辑体验和轨道管理

- 增加“删除选中片段”及确认/Undo；目前只能通过移除媒体池素材间接删除其所有片段。
- 明确轨道新增、删除、重命名、启用、锁定的 UI；模型字段存在不代表交互完整。
- 支持片段跨 overlay 轨移动，或明确只允许在原轨横向移动。
- 增加可见吸附线/吸附反馈；当前只有数值吸附。
- 决定移动片段时是片段左边缘吸附，还是左右边缘都参与吸附。
- 补完整 Undo/Redo；当前不要承诺时间线编辑可撤销。

### P2：工程格式收口

先决定轻量 JSON 是否就是正式格式，再考虑：

- schema/version 与迁移策略。
- 是否保存导出 in/out、activity trim 和导出设置。
- 是否记录相对路径或升级为工程包。
- CLI 在文件移动后的定位策略。

在这些需求明确前，不要为了“以后可能用”提前新增抽象层。

## 建议的下一轮执行顺序

1. 先补复现测试：自定义时间线被媒体池切换覆盖、同轨浮层重叠预览/导出不一致、视频 gap/overlap 预检。
2. 修复数据丢失入口，并加入 dirty state/未保存修改保护。
3. 抽出预览与 writer 共用的“某时刻活动片段解析”和工程校验规则。
4. 做缺失素材/relink 流程。
5. 用 `assets/resourses/` 的本地真实素材跑完整 QA；该目录和产物不得提交。
6. 只修 QA 暴露的问题，验证透明 Alpha、混合视频和长时内存。
7. 稳定后再做删除片段、轨道管理、跨轨移动、Undo/Redo 和工程格式升级。
8. 同步更新 `docs/timeline-phase4-plan.md`，并清理 `ProjectTimelineView` 顶部仍写“只读/后续再编辑”的过期注释。

## 手动 QA 清单

### 基础工作流

1. 多选导入两个视频和两个 FIT/GPX。
2. 用“加入时间线”把第二个视频追加到 V1。
3. 把第二个运动文件拖到已有 overlay 轨，再用按钮新建另一条 overlay 轨。
4. 移动和裁剪自定义片段，检查吸附、检查器数值和预览同步。
5. 拖动 `single.*` 视频/浮层片段，确认“同步”标签仍双向一致。
6. 调整导出 in/out，确认播放头和预览范围 clamp 正确。
7. 分别导出透明浮层和合成视频。

### 工程恢复

1. 保存 JSON，退出 App，再打开工程。
2. 确认媒体池、轨道、片段几何、片段布局/单位恢复。
3. 确认导出 in/out 等未持久化会重置，避免误判为 bug 修复完成。
4. 移动或重命名一个素材后重新打开，记录当前失败表现，作为 relink 实现验收基线。

### 导出质量

1. 多浮层透明视频分别覆盖深色、浅色和彩色背景检查 Alpha。
2. 横屏/竖屏、不同分辨率、不同帧率视频两两组合。
3. 在片段边界前后逐帧检查画面和音频。
4. 运行长素材，观察内存不能随时长持续增长。

## 推荐验证命令

```bash
swift test --filter TimelineModelTests
swift test --filter MediaPoolTests
swift test --filter TimelineVideoWriterTests
swift test --filter OverlayCLITests
swift test
scripts/build_app_bundle.sh
swift run overlay --help
```

改透明或合成写出时，额外重点跑：

```bash
swift test --filter TransparentVideoWriterTests
swift test --filter CompositedVideoWriterTests
swift test --filter OverlayRendererTests
```

## 接手时先看的文件

- `docs/timeline-handoff.md`
- `docs/timeline-phase4-plan.md`（状态有过期内容，只作阶段拆分参考）
- `Sources/OverlayCore/Timeline/TimelineModel.swift`
- `Sources/OverlayCore/Video/TimelineVideoWriter.swift`
- `Sources/OverlayCore/Video/CompositedVideoWriter.swift`
- `Sources/OverlayCore/Video/TransparentVideoWriter.swift`
- `Sources/OverlayStudio/Stores/StudioModel.swift`
- `Sources/OverlayStudio/Views/ProjectTimelineView.swift`
- `Sources/OverlayStudio/Views/TimelineClipInspectorView.swift`
- `Sources/OverlayStudio/Views/TimelineDragPayload.swift`
- `Sources/overlay/main.swift`
- `Tests/OverlayStudioTests/MediaPoolTests.swift`
- `Tests/OverlayCoreTests/TimelineModelTests.swift`
- `Tests/OverlayCoreTests/TimelineVideoWriterTests.swift`
- `Tests/OverlayCLITests/CommandLineOptionsTests.swift`

## 不可突破的边界

- 透明 Alpha 路径保守修改；任何像素缓冲或颜色空间变化都要有自动测试和深浅背景手动验证。
- 所有写出按帧流式处理，禁止缓存整段视频帧、大图或 CGImage。
- `TimelineProject`、工程 JSON 和布局 preset 保持 Codable 向后兼容。
- 预览、App 导出和 CLI 必须共用同一时间映射、片段选择和校验语义。
- 支持新平台或改共享层时，macOS 既有预览、导出、构建和发布流程不得回退。
