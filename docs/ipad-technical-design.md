# DataLayer Studio for iPad 技术方案文档

| 项目 | 内容 |
| --- | --- |
| 状态 | **实施中**（本文描述已落地架构与剩余技术工作，由 2026-07-04 提案版重写） |
| 日期 | 2026-07-06 |
| 适用平台 | iPadOS（与 iPhone 共用同一 iOS App target；iPhone 差异见 `docs/iphone-technical-design.md`） |
| 最低系统版本 | iOS / iPadOS 26（`Package.swift` 已声明 `.iOS("26.0")`；macOS 维持 13） |
| 对应提交 | `4220ee2`、`7ff081b`（main） |
| 关联文档 | `docs/ipad-product-design.md`、`docs/ipados-development-testing.md` |

## 0. 现状摘要

- **已定决策：iPad 只导出合成成片**。iOS 侧只使用 `CompositedVideoWriter`（HEVC/H.264），`TransparentVideoWriter` 与 HEVC-alpha/ProRes 路径保留在核心库、仅供 macOS/CLI 使用。
- `Sources/OverlayCore`（渲染/解析/写出引擎）如提案预期 **100% 复用，未改一行逻辑**；唯一改动是一处编码器兼容性修复（§4.2），macOS 行为不变。
- iPad 界面与会话模型落在新 target `Sources/OverlayTouch`（约 4200 行）；**原提案的 P1「StudioModel 拆分下沉」没有做**，iPad 会话模型独立实现（差异与代价见 §2.3）。
- 日常开发用模拟器闭环：SwiftPM executable 壳 + `scripts/build_touch_sim_app.sh` 一键构建安装启动，导入→对表→排布→导出全链路已在 iPad Pro 13-inch (M5) 模拟器验证。
- 仓库仍是纯 SwiftPM，没有 Xcode 工程；真机验证用 `/tmp` 临时壳（见开发测试文档），正式发布壳是遗留项（§8）。

## 1. 已落地架构

### 1.1 Target 结构与依赖

```
OverlayCore ← OverlayStudioKit ← OverlayStudio     (macOS 壳，不变)
                              ← OverlayTouch      (iOS 界面层 + 会话模型)
                                   ← OverlayTouchHost (模拟器调试壳, executable)
Tests/OverlayTouchTests  (依赖 OverlayTouch，在 macOS 上运行)
```

- `OverlayStudioKit` 目前只沉了 `TextMeasurementCache`、`VideoFrameService` 两个平台中立文件（`package` 可见性）。
- `OverlayTouch` 必须在 macOS 上编译通过（`swift build` 构建全部 target）：iOS 专属代码用**整文件 `#if os(iOS)`** 门控；模型层平台中立（`ObservableObject`，不用 `@Observable`，因包声明 macOS 13），因此模型单测直接在 macOS 跑。
- `OverlayTouchHost` 在 macOS 下退化为一条提示的 CLI，保证全量构建不断。

### 1.2 OverlayTouch 文件职责

| 文件 | 职责 |
| --- | --- |
| `Models/TouchStudioModel.swift`（~1340 行） | 会话模型：素材载入（含 security-scoped 生命周期）、对表（三模式 → `TelemetryTimeSync`）、播放与时间轴、浮层预览渲染调度（合并/节流/拖动降采样 1600px/上限 3200px）、布局编辑 + 100 级快照撤销、预设 CRUD + iCloud KVS 观察、导出参数校验与执行（进度/ETA/取消）、偏好持久化、热状态监控 |
| `Models/TouchModels.swift` | 枚举、分辨率/帧率预设表、组件基础尺寸、`TouchExportRuntimeGuarding` 协议 |
| `Support/TouchLocalization.swift` | 四语言字典（en/zh-Hans/zh-Hant/ja）+ 组件图标映射；`tables` 为 internal 供键位对齐测试 |
| `Support/TouchPlatformServices.swift` | UIKit 门控：导出中屏幕常亮 + `beginBackgroundTask` 收尾窗口；`PHPhotoLibrary` 存片 |
| `Views/TouchEditorRootView.swift` | 根视图：regular 三栏 / compact sheet、工具栏、设置 sheet、onOpenURL、模拟器调试环境变量入口 |
| `Views/TouchSourcesPanel.swift` | 素材导入（fileImporter + PhotosPicker/Transferable 拷贝）、对表、预设 |
| `Views/TouchExportSection.swift` | 导出设置/进度/结果卡片（ShareLink、存照片） |
| `Views/TouchCanvasView.swift` | 画布（AVPlayerLayer + 浮层 CGImage 叠加、触控选中/拖动、粗估命中热区 ≥44pt）+ 时间轴 |
| `Views/TouchInspectorPanel.swift` | 添加组件 + 选中组件设置子集 |
| `OverlayTouchRootView.swift` | 对外入口：iOS → 编辑器；macOS → P0 诊断视图 |

### 1.3 复用与重复情况

- 直接复用（零改动）：FIT/GPX 解析、`TelemetrySeries`、`TelemetryTimeSync`、`OverlayLayout` 及全部渲染、`OverlayPreviewRenderer`、`CompositedVideoWriter`、`LayoutPresetStore`、`OverlayHardwareProfile`。
- 有意的重复（与 macOS `StudioModel` 各有一份，均为百行量级）：对表模式换算、导出编排/进度 ETA、预设持久化包装、素材加载状态机。收敛计划见 §2.3。

## 2. 与原提案的差异（重要）

### 2.1 仅成片导出（产品决策）

`TouchStudioModel.exportMode` 是常量 `.video`；导出面板无模式切换；编码选项仅 HEVC/H.264（`availableCodecs` 按 `exportMode == .video` 过滤，ProRes 属浮层模式自然排除）。原提案中的 HEVC-alpha 真机金样、透明通道对比验证、ProRes 显隐策略**对 iPad 侧全部不再适用**（macOS 侧照旧）。若未来恢复浮层导出，参照 `7ff081b` 提交中删除的 overlay 分支。

### 2.2 未做 P1「共享层下沉」

原提案要求「先下沉、后移植」（拆分 2400 行 StudioModel 到 OverlayStudioKit）。实际实施选择了**先独立实现 iPad 模型**：拆分的 macOS 回退风险远大于收益，且会阻塞 iPad 出可用版本。代价是 §1.3 所列的编排重复。

**收敛路线（建议在检查器补齐之后做）**：以 `TouchStudioModel` 为蓝本反向抽取（它已经是平台中立的），把对表/导出编排/预设持久化逐块移入 OverlayStudioKit，macOS `StudioModel` 与 `TouchStudioModel` 分别改为薄壳。原提案 §1.3 的 AppKit 绑定点清单仍然有效，做下沉时从 git 历史（2026-07-04 版本文档）取用。

### 2.3 工程形态：暂无 Xcode 工程

提案中的 `App/DataLayerStudio.xcodeproj` 尚未建。当前：模拟器用 SwiftPM 壳 + 脚本组装 .app（Info.plist 内嵌在脚本里生成，含 fit/gpx UTI、四语言 `CFBundleLocalizations`、`UIFileSharingEnabled`、照片写入权限文案）；真机用 `/tmp` 临时 Xcode 壳。正式发布壳（签名、entitlements、`PrivacyInfo.xcprivacy`、universal target）是发布前置项（§8）。

## 3. 文件访问与数据流（已实现）

- 导入：`fileImporter`（movie 系 UTType + `.data`/`.item` 兜底，FIT/GPX 同样走 data/item 兜底以兼容 Files 动态类型）+ PhotosPicker（`FileRepresentation` 拷贝到临时目录）+ `onOpenURL`（文档类型声明支持「用 DataLayer Studio 打开」）。拖拽 onDrop 未做。
- security-scoped：视频 URL 的访问权由模型持有（`ScopedResourceAccess`，替换/析构时释放，覆盖导出全程读取）；活动文件在解析期间临时持有。应用容器内文件 `startAccessing` 返回 false 属正常，不视为错误。跨启动 bookmark（「最近使用」）未做。
- 输出：核心库「临时文件写出 → 校验 → 原子安装」不变；安装目标为 App Documents（Files 可见），文件名自动去重（`-2`/`-3` 后缀），因此**没有覆盖确认流程**。完成后 ShareLink 分享 / `PHPhotoLibrary` 存入照片（add-only 权限）。
- 残留清理：`removeStaleTemporaryOutputs` 的 pid 探测在 iOS 单进程模型下直接复用。

## 4. 媒体管线（已实现）

### 4.1 预览

AVPlayer 播放 + `OverlayPreviewRenderer` 浮层 CGImage 双层结构；播放中按 0.2s 节流刷新浮层；scrub 走 `player.seek`（带容差）+ 合并渲染；组件拖动中渲染尺寸降采样到 1600px。渲染尺寸随画布几何 × displayScale，上限 3200px。

### 4.2 编码器兼容性（本次实施的关键教训）

`kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality` 在软件编码环境（iOS 模拟器）会让 `AVAssetWriterInput` 初始化**抛 ObjC 异常直接崩进程**（Swift 无法 catch）。两个写出器已改为仅在 `hardwareProfile.canUseHardwareEncoder(for: codec)` 为真时附加该属性；Apple Silicon Mac 上探测必有硬编，设置字典不变。**今后给写出器新增 VT compression property 必须考虑无硬编环境并沿用此门控写法。**

### 4.3 模拟器与真机

模拟器无硬件编码器：HEVC/H.264 走软件编码，速度慢但可完整验证导出链路与产物正确性（已抽帧核验组件烧入、音轨保留）。真机硬编的性能/热基准未测（§8）。

## 5. 导出生命周期（已实现 v1 策略）

`TouchExportRuntimeGuarding` 协议 + UIKit 实现：导出中 `isIdleTimerDisabled = true`；退后台 `beginBackgroundTask` 争取收尾窗口，超时由系统回调结束任务（写出靠取消回调终止，不做断点续导）；`ProcessInfo.thermalState` ≥ serious 时导出 UI 显示提示。UI 上有「导出期间请保持 App 在前台」说明。真机中断路径（来电/锁屏/切走）未手测。

## 6. 预设 iCloud 同步（已实现，有前置项）

- iOS 侧用 `LayoutPresetStore.load()`（不需要 macOS 的旧域迁移 `loadIncludingSharedAppDomains`）；`didChangeExternallyNotification` 观察与同步状态显示已接。
- **前置项未解**：Mac 版 `Resources/AppStore.entitlements` 的 `com.apple.developer.ubiquity-kvstore-identifier` 仍为空值。跨端同步要求 Mac 与 iOS 使用同一显式 KVS 标识，需先发一个 Mac 版小更新落实，iOS 正式壳对齐。

## 7. 测试与验证（现状）

- `Tests/OverlayTouchTests`（macOS 运行，`swift test --filter OverlayTouchTests`）：模型行为 9 项（导出就绪/区间钳位/元素增删复制层级/撤销重做/预设 CRUD/遥测可用性过滤，用临时 GPX 走真实解析路径）+ 本地化 5 项（四表键位对齐、语言解析、格式化）。
- 模拟器 E2E：`scripts/build_touch_sim_app.sh --run` + `TOUCH_AUTOLOAD_VIDEO/FIT`、`TOUCH_AUTOEXPORT`（任意非空值）、`TOUCH_AUTOEXPORT_MAX_SECONDS` 环境变量自动载入样本并导出（仅 `targetEnvironment(simulator)` 编译，正式包无此行为）；产物从 `simctl get_app_container … data` 的 Documents 取出核验。
- macOS 回归基线：全量 `swift test` + `scripts/build_app_bundle.sh` + `scripts/verify_app_bundle.sh`，v1 合入时全绿。
- CI 未加 iOS job（§8）。

## 8. 剩余技术工作（建议顺序）

1. **真机验证**：/tmp 壳装真机（流程见开发测试文档 §5），跑合成 HEVC 硬编导出，产出性能/热基准表；手测导出中退后台/来电中断。
2. **检查器补齐 + 运动数据裁切 UI**：纯 OverlayTouch 内工作，无共享层风险。
3. **CI 增加 iOS 编译信号**：至少把 `swift build --target OverlayTouch`（iphonesimulator triple）加进 CI，防止 macOS 侧改动悄悄弄断 iOS 编译。
4. **M3 平台特性**：onDrop 拖拽、多 Scene、键盘全键位（方向键微调 / ⌥⌘↑↓ / ⌘±）、Pencil/指针悬停、画布捏合缩放与网格吸附。
5. **P1 共享层下沉**（择机）：按 §2.3 路线收敛双份编排。
6. **发布前置**：正式 Xcode 壳工程（bundle id `run.libo.datalayer-studio`，同一 App record 加 iOS platform，Universal Purchase 单向挂接注意事项见下）；购买校验门（StoreKit 2 `AppTransaction` 复用，`SecCodeCopySelf` 已属 macOS-only 路径）；`PrivacyInfo.xcprivacy`；Mac 端 iCloud KVS 标识（§6）；天气；无障碍/四语言验收；App Store 素材（iPad 13/11 英寸截图，构建号 `yyyyMMddNN`）。

Universal Purchase 注意：挂接是单向操作，之后不能拆回独立 SKU；调价作用于三端同一价格。

## 9. 风险登记（更新）

| 风险 | 概率 | 影响 | 缓解 |
| --- | --- | --- | --- |
| 双份编排随功能迭代漂移（iPad 模型 vs Mac StudioModel） | 中 | 中 | 改对表/导出语义时两边同改并跑双端测试；尽早排期 P1 下沉 |
| 真机硬编行为与模拟器软编差异（性能/属性支持） | 中 | 中 | §8-1 真机基准前置；新增 VT 属性沿用 §4.2 门控 |
| 导出中挂起/热限制导致失败率上升 | 中 | 中 | 生命周期模块已接；真机中断手测补上 |
| CI 无 iOS 信号，iOS 编译被无意弄断 | 高（当前状态） | 低-中 | §8-3 尽快加编译 job |
| iCloud KVS 标识依赖 Mac 版先行发版 | 确定 | 低 | 作为独立小版本提前发 |
| 画布粗估热区在极端自定义下偏差大 | 低 | 低 | 精确边界待与 macOS 实现一起下沉共享 |
