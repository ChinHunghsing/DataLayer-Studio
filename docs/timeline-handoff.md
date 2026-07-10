# DataLayer Studio 时间线改造交接文档

- 更新时间：2026-07-10
- 提交审阅范围：`093da56ec8eff6a92b1b6c68e1ef740bccbaec56`（含）至本文档所在提交（含）
- 当前功能实现基线：阶段 7 相对时间线与独立源匹配点
- 原交接文档提交：`f2cd534620c5b3cabffad39678581ff6d8084f2c`
- 阶段 5 状态：时间线可靠性收口已完成并通过全量验证
- 阶段 6 状态：稀疏视频时间线已完成并通过全量验证
- 阶段 7 状态：视频/运动片段自由移动、时间线开头空白和独立源匹配点已完成

## 这份文档的用途

这份文档是下一轮时间线工作的当前事实基线。`docs/timeline-phase4-plan.md` 记录了阶段 4 的原始拆分，但其中“工程保存/打开仍未完成”等状态已经过期；判断真实能力和下一步优先级时，以本文和当前代码为准。

目标仍然是把 DataLayer Studio 从“单视频 + 单运动文件”改造成轻量时间线：

- 一个工程包含多个视频和多个 FIT/GPX。
- 视频片段可分散放在时间线上，开头、片段之间和结尾都允许没有视频。
- 运动数据作为浮层片段放在 overlay track，可移动、裁剪、叠加。
- 预览和导出读取同一个 `TimelineProject`。
- 保持透明 HEVC Alpha / ProRes 4444 的质量和逐帧流式写出，不重新引入透明区域发灰或整段缓存导致的内存问题。

这不是完整 NLE。当前范围不包含画中画、多机位、转场或任意视频重叠混合。

## 提交演进结论

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
- `fa54338`：完成 dirty state、危险操作确认、活动片段统一解析和导出预检等阶段 5 可靠性收口。
- `eeec898`：完成稀疏/无视频时间线、黑色空白画布、视频音频静音空隙和透明浮层空白 Alpha。
- 本文档所在阶段 7 提交：同步改为独立源时间匹配点；视频与运动片段统一自由移动，时间线允许从空白开始。
- `2c5f018`：片段时间改为只读时间码；输出页距离单位与当前选中运动片段的单位统一。
- 当前提交：媒体池“使用中”按时间线实际引用判断；视频支持拖入 V1；空轨可删除；轨道区可纵向滚动；视频片段异步显示缓存音频波形。

结论：阶段 4 的主要功能链路已经接通；阶段 5 已处理静默覆盖、预览/导出片段语义不一致和视频轨无预检三个 P0；阶段 6 把“视频必须连续覆盖导出范围”改为标准剪辑软件的稀疏视频语义；阶段 7 又把源时间同步和片段摆放拆开，所有片段都使用标准的相对时间线位置。下一步转向缺失素材恢复和真实素材 QA。

## 当前真实架构与语义

### 核心模型

- `Sources/OverlayCore/Timeline/TimelineModel.swift`
- `TimelineProject.assets` 保存媒体资产；`tracks` 按自底向上的合成顺序排列。
- `TimelineTrack.Kind` 目前有 `video` 和 `overlay`。
- `TimelineTrack.clip(atTimelineTime:)` 在同轨片段重叠时返回数组中最后一个片段。
- `TimelineClip` 的区间是左闭右开：`timelineStart <= t < timelineEnd`。
- 片段源时间映射为 `sourceIn + (t - timelineStart)`。
- 反向映射为 `timelineStart + (sourceTime - sourceIn)`；`TimelineProject.alignMatchPoint` 用它对齐两个素材源时间，不裁掉任一素材的开头。
- `TimelineProject.duration` 是所有轨道最远的片段结束时间，不只看视频轨。
- `TimelineProject.sourceMatchPoint` 可选保存当前主视频与主运动素材的源时间对应关系；它和片段的 `timelineStart` 独立，旧 JSON 缺字段仍可解码。
- 单源迁移使用稳定的 `single.video.*` / `single.overlay.*` ID；这是 SwiftUI 拖拽不中断的必要条件，不要改回随机 ID。
- 单源迁移始终保留视频和运动素材全长、`sourceIn == 0`；若相对同步会产生负起点，就把这对片段整体右移，而不是裁掉源素材开头。

### App 状态

- 实际文件是 `Sources/OverlayStudio/Stores/StudioModel.swift`，不是旧文档写的 `Models/StudioModel.swift`。
- `StudioModel.timeline` 是预览和导出的当前时间线状态。
- 初始单源工作流仍由同步输入生成时间线；第一次移动/裁剪任意 `single.*` 片段，或把池中素材加入时间线后进入自定义时间线模式。
- 同步输入保存“视频源时间 ↔ 运动源时间”，并用相对位置对齐主视频/运动片段；手工拖动片段只改自己的 `timelineStart`，不会反写这组源时间。
- 自定义模式下，输出宽高、帧率、距离单位会更新工程设置，不会重建并覆盖多片段结构。
- 活动数据按 `assetID` 缓存在 `activitySeriesByAssetID`，预览和导出据此为每个浮层片段找到各自的 telemetry。
- `hasUnsavedTimelineChanges` 通过当前 `timeline` 与最近保存/打开的 clean snapshot 自动比较；窗口标题使用 macOS document-edited 状态显示未保存标记。
- 自定义时间线切换媒体池活动源、删除被片段引用的素材、打开其他工程和关闭含未保存修改的窗口都会先显示四语言确认，不再静默覆盖。

### UI 已有能力

- 视频/FIT/GPX Finder 导入支持多选；第一个成为活动源，其余异步加入媒体池。
- 媒体池的“加入时间线”按钮：
  - 视频追加到基础视频轨末尾。
  - 运动素材默认在当前播放头位置新建一条 overlay 轨。
- 媒体池“使用中”按素材是否被任意时间线片段引用判断，不再只标记单一活动源；所有被引用的视频和运动素材都会显示该状态。
- 视频和运动素材都可从媒体池拖到同类型现有轨道，按落点时间加入最近可容纳的空隙。
- 时间线显示标尺、视频轨、浮层轨、片段、播放头和导出 in/out 带；轨道总高度超过工作区时可纵向滚动。
- 删除片段后留下的空轨可从轨道头删除，且支持撤销；有片段的轨道不会显示删除入口。
- 视频片段按素材异步抽取并缓存 512 个音频峰值，在片段内部显示音频波形；抽取使用 AVAssetReader 流式解码和 Accelerate 峰值计算，不缓存完整音频。
- 视频和运动数据片段都可自由移动并保留空隙；空隙是合法内容，不会自动 ripple，也不强制任一首片段从 0 开始。
- 同一轨道上的片段不允许重叠：移动、裁剪、检查器编辑和拖放落点都会钳制到最近的可容纳空隙（`TimelineTrack.nonOverlappingStart`/`neighborBounds`）；片段可以精确贴边。旧工程里已有的重叠仍按“最后片段生效”解析。
- 时间线编辑支持撤销/重做（⌘Z/⇧⌘Z，标准编辑菜单）：快照式恢复片段几何、单源迁移标志和选中态；拖动/步进按 0.8 秒窗口合并为一步；打开工程、切换活动源、移除被引用素材会清空撤销栈。
- `single.*` 与池中加入的片段使用同一种拖动逻辑：只修改被拖片段自己的 `timelineStart`；同步标签继续单独编辑源时间匹配点。
- 所有未锁定片段都可左右裁剪；左裁同时修改 `timelineStart`、`sourceIn`、`duration`，右裁修改 `duration`，最短 0.1 秒。
- ⌘B 在播放头处分割所有未锁定片段（两侧源内容连续，左片保留原 ID 和选中态）；⌫ 删除选中片段并保留间隙；⇧⌫ 波纹删除，在所有未锁定轨道上闭合被删时间段，跨段片段自动裁剪或拆分（锁定轨不动）。入口有「时间线」菜单和片段右键菜单，实现在 `Sources/OverlayCore/Timeline/TimelineEditing.swift`。
- 移动和裁剪会吸附到时间线 0 点及其他片段边缘，阈值为当前显示宽度约 6 px；目前没有可见吸附参考线。
- 选中片段后，右侧检查器以只读时间码显示时间线开始、素材入点和时长；位置与裁剪只通过时间线交互修改。运动片段还可设置单片段距离单位和布局，输出页的米/公里选择与当前选中运动片段同步。
- 导出 in/out 带仍是 `StudioModel` 的会话导出范围，不属于 `TimelineProject` 片段几何。

### 预览与导出

- 时间线预览按当前时间选择视频片段，并按 overlay 轨顺序合成浮层；只要相对排布不能由旧的 0 起点播放器等价表示，就自动走时间线预览。
- 同步标签显示和“把当前帧设为运动开始”读取播放头下片段的源视频时间，不把时间线绝对位置误当成视频源时间；播放头位于开头空白或其他视频素材时不可设置当前主视频的同步点。
- `TimelineProject.activeClips(kind:atTimelineTime:)` 是预览和 writer 共用的活动片段解析器；同一轨重叠时统一为数组中最后一个片段生效，多轨仍按自底向上顺序合成。
- 自定义时间线播放通过共享 `AVPlayer` 播放由 `TimelineVideoCompositionBuilder` 组装的 `AVMutableComposition`（视频+音频按片段几何摆放、空隙为空段），播放流畅且有声音；擦洗用 `player.seek`，叠加层单独渲染。时间线编辑按视频几何签名防抖 250ms 重建播放器；无视频片段或素材不可读时回退到浮层时钟 + 逐帧抽图。
- `Sources/OverlayCore/Video/TimelineVideoWriter.swift` 是透明浮层和合成视频的统一入口。
- 单浮层透明导出继续委托原 `TransparentVideoWriter`，保护既有 Alpha 路径。
- 多浮层透明导出逐帧渲染和合成，不缓存整段视频。
- 普通合成视频允许导出范围内没有视频：有数据时透明数据层叠在黑色画布上，无数据时输出纯黑帧；只有浮层导出始终保持 Alpha 透明，空白帧也是全透明。
- 视频片段可分散排列；writer 按样本时间戳流式取帧，空隙写黑帧，视频音频保持在对应片段区间，空隙静音。
- 同一视频轨的片段仍不能重叠，片段也不能超出源视频可用时长。
- 多视频通过 `AVMutableComposition` 组合；目前只取第一段视频的 `preferredTransform` 作为组合轨 transform。
- 启用的 overlay 轨按 `TimelineProject.tracks` 自底向上合成；禁用轨不导出。
- `Sources/OverlayCore/Timeline/TimelineExportValidation.swift` 提供 App、CLI 和 writer 共用的导出预检；视频空隙和没有视频都合法，overlap、源范围越界、缺少 asset/telemetry 仍会在编码前返回明确错误。

### 工程保存/打开与 CLI

- App 菜单已有“打开时间线工程”和“保存时间线工程”；保存是每次弹出面板的 Save As 行为。
- 工程格式是直接编码的 `TimelineProject` JSON，不是工程包，也没有独立 schema/version 字段。
- `MediaAsset.bookmarkData` 保存 security-scoped bookmark；旧 JSON 缺该可选字段仍可解码。
- 打开工程时会先应用 JSON，再异步加载各媒体资产。
- 当前 JSON 保存：素材、轨道、片段、输出宽高/帧率、工程距离单位、片段布局/单位，以及可选的主视频/运动源时间匹配点。
- 当前 JSON 不保存：导出 in/out、activity trim、导出模式、codec、bitrate、输出路径、当前播放头和 UI 选择状态；重新打开后导出范围重置为完整时间线。
- CLI 用 `overlay --timeline-project project.json --output output.mov ...` 导出，直接读取 JSON 中的文件 URL，不使用 App 的 bookmark 恢复交互。
- CLI 当前默认导出 `project.duration` 全长，不读取 App 会话里的导出 in/out。
- CLI 在解析运动文件后会运行与 App/writer 相同的时间线预检，无效工程不会进入编码器。
- 单源 CLI 的普通合成模式也允许省略 `--video`，此时按完整运动时长输出黑底数据视频。
- 单源 CLI 的普通合成模式有视频时也使用迁移后的 `project.duration`，源匹配点造成的前置空白/运动数据和两份素材完整时长不会被旧的视频时长截掉。

## 已完成并有自动测试覆盖的主路径

- 单源迁移时间映射、真实浮层时长、稳定 ID、Codable 往返、吸附候选。
- 媒体池去重和活动源切换。
- 多运动文件加入新轨或指定 overlay 轨。
- 多视频/多运动素材的“使用中”状态、视频/运动素材拖入对应轨道和空轨删除。
- 波形峰值归一化，以及真实 AAC 视频的本机流式抽取验证。
- 自定义片段移动、裁剪、检查器时间/布局/距离单位编辑。
- `single.*` 视频/运动片段独立移动、开头空白、源时间匹配点相对对齐和工程恢复。
- 自定义时间线 JSON round trip。
- 单源时间线合成视频与旧 writer 的基础输出等价检查。
- 单浮层透明导出冒烟测试。
- 多浮层透明/不透明合成冒烟测试。
- 连续两段视频和音轨顺序导出测试。
- CLI 时间线工程参数、冲突参数和 JSON 读取测试。
- dirty state、危险操作确认和窗口关闭一次性授权测试。
- 同轨重叠浮层“最后片段生效”的模型与实际 writer 输出测试。
- App/CLI 允许视频 gap、继续拒绝 overlap 的共享预检测试。
- 开头/结尾黑帧、中间稀疏视频、片段音频静音空隙、完全无视频的黑底数据合成测试。
- 单浮层不覆盖整个导出范围时，空白区仍保持透明 Alpha 的实际写出测试。

验证状态：

- `swift test`：347 个测试全部通过，0 failure。
- `swift test --filter MediaPoolTests`：40 个测试全部通过。
- `swift test --filter AudioWaveformLoaderTests`：2 个测试全部通过；另用本地真实 AAC 视频验证了流式峰值抽取。
- `swift test --filter TimelineModelTests`：20 个测试全部通过。
- `swift test --filter TimelineVideoWriterTests`：10 个测试全部通过，包含稀疏视频、黑帧、音频静音区间和透明空白帧的真实写出检查。
- `swift test --filter OverlayCLITests`：22 个测试全部通过。
- `swift test --filter LocalizationTests`：15 个 macOS 本地化测试全部通过。
- `swift test --filter StudioModelTests`：65 个 macOS 状态模型测试全部通过。
- `scripts/build_app_bundle.sh` 成功生成 `.build/DataLayer Studio.app`。
- `scripts/verify_app_bundle.sh` 验证通过。

注意：硬件编码器相关测试允许在不可用机器上 skip；“测试通过”不等于已经验证多浮层 Alpha 的真实视觉质量或混合方向视频。

## 阶段 5/6 完成项与后续问题

### P0（已完成）：防止用户时间线被静默覆盖

当前行为：

- 从媒体池切换自定义时间线的活动源前，明确提示会替换为单源时间线。
- 删除被时间线引用的非活动素材前，明确提示会删除所有引用片段。
- 打开其他工程或关闭窗口时，如有未保存时间线修改会先确认。
- 保存成功和工程打开成功会更新 clean snapshot；后续时间线几何或工程输出设置变化会自动重新标记 dirty。
- 相关状态行为由 `MediaPoolTests` 覆盖。

尚未加入完整 Undo/Redo；用户确认执行的替换/删除仍不可撤销。

### P0（已完成）：统一同轨重叠浮层的预览/导出语义

规则已经收口为：

- 每条启用轨在同一时刻最多提供一个活动片段。
- 同轨重叠时，轨道 `clips` 数组中最后一个命中的片段生效。
- 不同 overlay 轨的活动片段继续按工程轨道顺序叠加。
- 预览、透明导出和合成视频导出都调用 `TimelineProject.activeClips`。

`TimelineModelTests` 验证解析顺序，`TimelineVideoWriterTests` 用“前片段可见、后片段空布局”的实际输出验证 writer 只渲染后片段。

### P0（已完成）：视频轨无效结构在编码前预检

视频片段可以自由移动和裁剪；真正无效的结构会在编码前被一致拒绝：

- `TimelineProject.firstExportValidationIssue` 供 App、CLI 和 writer 共用。
- App 输出面板会在导出前显示本地化的 overlap、源范围越界、缺素材/telemetry 提示并禁用导出。
- CLI 在 writer 启动前返回 `Timeline error`。
- writer 自身仍执行同一预检，防止绕过 UI/CLI 调用。

当前没有把错误直接画在时间线片段上，也没有 ripple 编辑；这是后续 UX 增强，不再是静默失败风险。

### 阶段 6（已完成）：稀疏视频时间线

- `TimelineProject.duration` 继续由所有轨最晚结束的片段决定，通常是完整运动浮层。
- 视频不需要从 0 开始，也不需要连续覆盖导出范围；没有视频片段的工程也可导出普通合成视频。
- App 预览在无视频时保留数据浮层并使用黑色画布；完全空白区也显示黑色画布。
- 普通合成 writer 只保留当前/下一张源样本，按输出帧时间选择视频或黑帧，仍是逐帧流式处理。
- 视频音频按片段的时间线位置组合，前后和片段间空隙静音。
- 单浮层只有在覆盖完整导出范围时才委托旧透明 writer；否则走活动片段解析，保证无数据区间全透明。
- 同轨视频 overlap 仍是错误；当前没有引入多视频轨、画中画、转场或 ripple 编辑。

### 阶段 7（已完成）：源时间同步与相对时间线解耦

- 同步标签继续输入“视频素材的什么时候对应运动数据的什么时候”，不改成时间线绝对时间输入。
- 匹配点持久化在可选的 `TimelineProject.sourceMatchPoint`；片段移动不会修改匹配点，保存/打开工程后两者分别恢复。
- 同步值变化时，主视频源匹配点和主运动源匹配点落在同一个时间线时刻；如果会得到负起点，两片段一起右移到非负区间。
- 正偏移不再通过增加运动片段 `sourceIn` 丢弃运动开头；两个素材始终以完整源时长进入初始时间线。
- 视频片段与运动片段，包括 `single.*`，都能单独横向拖动；所有片段都能放到 0 秒之后，因此整条时间线可以从黑色空白开始。
- 第一次编辑单源片段后，预览切到时间线驱动；同步标签的当前时间读取片段源时间，避免“时间线 45 秒”被误认为“视频 45 秒”。
- 未手工设置导出 in/out 时，时间线移动或同步导致总时长变化会继续保持默认全时间线导出；用户手工设定过范围后不自动覆盖。

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
- 横屏 + 竖屏、不同分辨率、不同帧率视频连续或稀疏组合。
- 多视频边界无错帧/重复帧，视频空隙黑帧和音频静音位置准确。
- 长视频、多轨预览和导出内存稳定。
- 自定义时间线定时器预览的播放流畅度、拖动响应和无音频行为。
- 保存、退出 App、重新打开、重新授权素材后的预览与两种导出。

混合方向尤其要谨慎：组合轨目前只使用第一段视频的 transform，不能把它写成“已经支持”。

### P2：编辑体验和轨道管理

- 删除选中片段（⌫ 留隙 / ⇧⌫ 波纹删除）和空轨删除已实现，并纳入 Undo/Redo；目前没有删除确认。
- 空轨删除已有入口；轨道新增、重命名、启用、锁定仍没有完整 UI，模型字段存在不代表交互完整。
- 支持片段跨 overlay 轨移动，或明确只允许在原轨横向移动。
- 增加可见吸附线/吸附反馈；当前只有数值吸附。
- 决定移动片段时是片段左边缘吸附，还是左右边缘都参与吸附。
- 继续扩大 Undo/Redo 覆盖面；当前片段移动、裁剪、分割、删除、加入和空轨删除已可撤销，媒体源替换/移除仍是确认后清空撤销栈。

### P2：工程格式收口

先决定轻量 JSON 是否就是正式格式，再考虑：

- schema/version 与迁移策略。
- 是否保存导出 in/out、activity trim 和导出设置。
- 是否记录相对路径或升级为工程包。
- CLI 在文件移动后的定位策略。

在这些需求明确前，不要为了“以后可能用”提前新增抽象层。

## 建议的下一轮执行顺序

1. 做缺失素材/relink 流程，把 bookmark stale / missing / unreadable 变成逐 asset 状态和重新定位入口。
2. 用 `assets/resourses/` 的本地真实素材跑完整 QA；该目录和产物不得提交。
3. 只修 QA 暴露的问题，验证透明 Alpha、混合视频、片段边界音频和长时内存。
4. 评估长视频波形生成、纵向多轨滚动和合成播放器的性能。
5. 稳定后再做轨道重命名/启用/锁定、跨轨移动、可见吸附反馈和工程格式升级。

## 手动 QA 清单

### 基础工作流

1. 多选导入两个视频和两个 FIT/GPX。
2. 用“加入时间线”把两个视频放入 V1，再移动成开头、中间和结尾都有空隙的分散片段。
3. 把第二个视频拖到 V1，把第二个运动文件拖到已有 overlay 轨，再用按钮新建另一条 overlay 轨。
4. 删除一个片段使轨道变空，确认轨道头出现删除入口；创建足够多的 overlay 轨，确认轨道区可纵向滚动。
5. 确认时间线上的每个视频片段都显示波形，无音频的视频不显示伪波形，多个片段复用同一素材时不会重复长时间加载。
6. 分别移动和裁剪视频、运动数据片段，检查吸附、检查器只读时间码和预览源时间。
7. 把 `single.*` 视频和运动片段都拖到 0 秒之后，确认开头是空白黑画布，且“同步”标签中的源匹配时间不被拖动修改。
8. 修改同步标签的“视频时间/运动时间”，确认两素材对应源时刻重新落在同一个时间线位置，同时保留完整素材开头。
9. 调整导出 in/out，确认播放头和预览范围 clamp 正确。
10. 分别导出透明浮层和合成视频。

### 工程恢复

1. 保存 JSON，退出 App，再打开工程。
2. 确认媒体池、轨道、片段几何、片段布局/单位恢复。
3. 确认导出 in/out 等未持久化会重置，避免误判为 bug 修复完成。
4. 移动或重命名一个素材后重新打开，记录当前失败表现，作为 relink 实现验收基线。

### 导出质量

1. 多浮层透明视频分别覆盖深色、浅色和彩色背景检查 Alpha。
2. 横屏/竖屏、不同分辨率、不同帧率视频两两组合。
3. 在片段边界前后逐帧检查画面和音频，并确认视频空隙为黑帧/静音、浮层仍继续显示。
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
- `Sources/OverlayStudio/Services/AudioWaveformLoader.swift`
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
