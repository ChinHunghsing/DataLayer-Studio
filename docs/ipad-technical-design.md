# DataLayer Studio for iPad 技术方案文档

| 项目 | 内容 |
| --- | --- |
| 状态 | 提案（未排期，未开工；本文不改动任何现有代码） |
| 日期 | 2026-07-04 |
| 适用平台 | iPadOS（与 iPhone 共用同一 iOS App target；共享架构以本文为准，iPhone 特有差异见 `docs/iphone-technical-design.md`） |
| 最低系统版本 | iOS / iPadOS 26（已定，§2.4；macOS 版维持 13 不变） |
| 商业模式 | 已定：统一定价，一次购买三端使用（Universal Purchase，§9） |
| 关联文档 | `docs/ipad-product-design.md` |

## 0. 结论摘要

- `Sources/OverlayCore`（约 6900 行）**零 AppKit/SwiftUI 依赖**，只用 Foundation、CoreGraphics、CoreText、CoreImage、CoreMedia、CoreVideo、AVFoundation、VideoToolbox、Metal、Darwin——全部在 iOS 上可用。渲染与导出引擎可以不改一行逻辑直接复用（仅需在 `Package.swift` 增加 iOS 平台声明）。
- `Sources/OverlayStudio`（约 12000 行）中平台绑定点**有限且集中**：11 个文件 import AppKit，实际绑定为 5 个 `NSViewRepresentable`、6 处文件面板调用、1 处 NSAlert、2 处 NSWorkspace、2 处 NSPasteboard、1 处 SecCode API、菜单栏 Commands 与 Settings scene。其余（本地化、状态模型主体、天气服务、预设存储、偏好存储、购买校验主体）是平台中立代码。
- 预估共享比例：核心库 100% 复用；GUI 层经「共享层下沉 + 平台服务协议」改造后约 70–80% 复用。
- 主要风险不在渲染正确性，而在**移动端编码器差异**（ProRes 可用性、分辨率上限）与**导出生命周期**（后台挂起、热限制）。两者都有明确缓解手段（§6、§7）。
- 硬阻塞项：无。前置依赖一项：Mac 版 entitlements 中 iCloud KVS 标识当前为空值，跨端预设同步需先在 Mac 端落实（§8）。

## 1. 现状盘点

### 1.1 分层与框架依赖

| Target | 行数 | 依赖框架 | iOS 可用性 |
| --- | --- | --- | --- |
| OverlayCore | ~6900 | Foundation / CoreGraphics / CoreText / CoreImage / CoreMedia / CoreVideo / AVFoundation / VideoToolbox / Metal / Darwin | 全部可用 |
| OverlayStudio | ~12000 | SwiftUI / AppKit / AVFoundation / StoreKit / Security / UserNotifications / OSLog / UniformTypeIdentifiers / QuartzCore | 除 AppKit 与 SecCode API 外全部可用 |
| overlay (CLI) | ~500 | Foundation + OverlayCore | 不适用于 iOS（不移植） |

### 1.2 OverlayCore 兼容性核对（逐模块）

| 模块 | 关键 API | 结论 |
| --- | --- | --- |
| `FIT/`、`GPX/`、`Activity/` | 纯 Foundation 字节解析 | 直接复用 |
| `Telemetry/`（序列、插值、时间同步） | Foundation | 直接复用 |
| `Rendering/OverlayLayout.swift` | Codable + CGColor | 直接复用；坐标为归一化值，与画幅无关 |
| `Rendering/OverlayRenderer.swift` | CGContext 位图绘制 + CoreText（CTFont/PostScript 字体名） | 直接复用；所用字体（HelveticaNeue、Menlo-Bold、AvenirNextCondensed-Heavy、Futura-CondensedExtraBold）均为 iOS 系统内置，需在 M0 真机核对渲染一致性 |
| `Rendering/OverlayPreviewRenderer.swift` | CIContext(Metal) + CVPixelBufferPool | 直接复用 |
| `Rendering/LayoutPresetStore.swift` | UserDefaults + NSUbiquitousKeyValueStore | 直接复用（iOS 支持 iCloud KVS） |
| `Video/TransparentVideoWriter.swift` | AVAssetWriter + VideoToolbox 压缩属性（StraightAlpha、TargetQualityForAlpha） | API 层面 iOS 13+ 全部可用；真机验证见 §6.3 |
| `Video/CompositedVideoWriter.swift` | AVAssetReader(VideoComposition) + AVAssetWriter + 音轨 mux | 直接复用 |
| `Video/VideoMetadata.swift` | AVURLAsset async load | 直接复用 |
| `Support/OverlayHardwareAcceleration.swift` | MTLCreateSystemDefaultDevice、VTCopyVideoEncoderList、MTLGPUFamily.apple7–10 | 直接复用；`VTCopyVideoEncoderList` 探测逻辑天然处理 iOS 设备间编码器差异 |
| `Support/AppleSiliconRequirement.swift` | `#if !arch(arm64) #error` | iOS 真机与 Apple Silicon Mac 上的模拟器均为 arm64，编译通过；Intel Mac 上的 x86_64 模拟器无法编译（可接受，注明于 CI 约束） |

### 1.3 OverlayStudio 平台绑定点清单

| 位置 | 现状 | iOS 替换 |
| --- | --- | --- |
| `Stores/StudioModel.swift:360,373,580` | NSOpenPanel 选视频/FIT/预设 JSON | `fileImporter` + PhotosPicker + security-scoped 访问（§5） |
| `Stores/StudioModel.swift:386,559` | NSSavePanel 选输出/导出预设 | 先写 App 沙盒，再 `fileMover`/分享（§5.3） |
| `Stores/StudioModel.swift:1748`、`App/OverlayStudioApp.swift:174` | NSWorkspace 在 Finder 显示 | 「在 Files 中显示」（UIDocumentInteraction）或 ShareLink |
| `Stores/StudioModel.swift:1789` | NSAlert 覆盖确认 | SwiftUI `confirmationDialog`（改造后 macOS 也可统一用它） |
| `Stores/StudioModel.swift:1753`、`Views/DebugConsoleView.swift` | NSPasteboard 拷贝路径/日志 | UIPasteboard |
| `Stores/StudioModel.swift:90-91` | `@Published var backgroundImage/overlayImage: NSImage?` | 改为 `CGImage?`（平台中立，SwiftUI `Image(decorative:cgImage:)` 两端可显） |
| `Services/VideoFrameService.swift:22,39` | 返回 NSImage | 返回 CGImage（生成路径本来就是 CGImage） |
| `Support/TextMeasurementCache.swift:25` | NSFont 测宽 | CTFontCreateWithName（一行改动，两端同用） |
| `Views/PlayerSurfaceView.swift:6` | NSViewRepresentable 包 AVPlayerLayer | UIViewRepresentable 等价实现（~40 行） |
| `Views/PreviewTimelineSlider.swift:4` | NSSlider + 方向键帧步进 | UISlider/SwiftUI Slider + 键盘命令（§4） |
| `Views/InspectorSettingsPanel.swift:1708` | NSTextField 步进数字输入 | TextField(数字键盘) + 步进按钮组件 |
| `Views/StudioWindowView.swift:38,116` | 窗口中央标题、live-resize 观察 | iOS 无窗口标题概念→工具栏标题；live-resize→`onGeometryChange` 节流 |
| `Views/PreviewCanvasView.swift:226` | `.onMoveCommand` 方向键微调 | iOS 17 `.onKeyPress` 或 UIKeyCommand（保持同键位） |
| `App/OverlayStudioApp.swift:28-41` | Settings scene + 菜单栏 Commands | 设置 sheet + 工具栏；快捷键用 `.keyboardShortcut`（iPad 硬件键盘同样生效） |
| `App/OverlayStudioApp.swift:61-155` | NSPanel 关于窗口 | 普通 SwiftUI sheet |
| `Support/PurchaseAuthorization.swift:135` | `SecCodeCopySelf` 读签名 entitlement（macOS-only API） | `#if os(macOS)` 保留；iOS 侧仅用收据存在性 + AppTransaction（StoreKit 2 在 iOS 可用） |
| `Views/StudioWindowView.swift:33` | CommandLine 启动参数 | iOS 不适用；入口改为 onOpenURL / 文档类型（§5.4） |

### 1.4 打包现状

仓库没有 Xcode 工程：macOS `.app` 由 `scripts/build_app_bundle.sh` 用 SwiftPM 产物手工组装。**iOS 无法用这条路**（iOS App 必须经 Xcode 工程/`xcodebuild` 构建、签名、打 ipa）。这是 iOS 版最大的一次性基建投入，见 §2.2。

## 2. 目标架构

### 2.1 单一 iOS App，两种 idiom

iPhone 与 iPad 交付为**同一个 iOS App target**（universal），UI 按 size class 分流；不是两个 App。本文与 iPhone 文档按平台拆分是设计视角，工程上共享同一代码基。

### 2.2 工程结构提案

```
Overlay/
├── Package.swift                  # 现有 SwiftPM 包：加 .iOS 平台声明
├── Sources/
│   ├── OverlayCore/               # 不动
│   ├── OverlayStudioKit/          # 新：平台中立共享层（从 OverlayStudio 下沉）
│   ├── OverlayStudio/             # macOS 壳（瘦身后保留 AppKit 桥接与 mac 入口）
│   └── OverlayTouch/              # 新：iOS 界面层（SwiftUI，iPad/iPhone idiom 分流）
├── App/
│   └── DataLayerStudio.xcodeproj  # 新：仅含 iOS app shell target，依赖本地 SwiftPM 包
└── scripts/build_app_bundle.sh    # macOS 流程不变
```

- Xcode 工程只做「壳」：Info.plist、entitlements、资产目录、签名配置，代码全部来自本地 SwiftPM 包，最大限度减少 .xcodeproj 噪声。可选用 xcodegen/Tuist 生成工程以保持声明式，团队规模小可直接提交 .xcodeproj，二选一即可。
- macOS 构建与发布流程完全不变（`swift build` + 脚本），互不影响。

### 2.3 target 划分与依赖方向

```
OverlayCore ← OverlayStudioKit ← OverlayStudio (macOS)
                              ← OverlayTouch  (iOS)
```

OverlayStudioKit 禁止 import AppKit/UIKit（照搬 OverlayCore「不依赖 SwiftUI」的约定，允许 SwiftUI 但禁平台 UI 框架，或干脆两者都禁、视图全留在壳层——建议后者，界限更清晰）。

### 2.4 Package.swift 与系统版本

- **最低系统版本（已定）：iOS / iPadOS 26**；macOS 版最低版本维持 13 不变。
- 声明方式：`platforms: [.macOS(.v13), .iOS("26.0")]`——用字符串形式可保持 `swift-tools-version: 5.9` 不动（枚举 `.v26` 需要更高工具链的 PackageDescription）；若同期把工具链统一升到 Xcode 26 随附版本，也可改用枚举形式，二选一。
- 取 26 的收益：
  - 设备下限抬到 A12 Bionic（iPadOS 26：iPad 第 8 代 / mini 5 / Air 3 / Pro 3 代及以上）与 A13（iOS 26：iPhone 11 / SE 第 2 代及以上），全系具备成熟 HEVC 硬编，A10 级设备（iPad 第 7 代）的编码器顾虑直接消除；
  - 单一系统大版本，无需为 17/18 的 SwiftUI 行为差异做分支；`@Observable`、`.onKeyPress`、`ContentUnavailableView` 等全量可用；
  - UI 直接按 iOS 26 原生控件与系统外观（Liquid Glass 体系）实现，无旧外观适配层。
- 代价：放弃无法升级到 26 的机型（iPhone XS/XR、iPad 第 7 代等，终止于 iOS/iPadOS 18）。本产品对编码性能敏感、目标用户为视频创作人群，设备普遍较新，可接受。
- 以 Xcode 26 / iOS 26 SDK 构建。

## 3. 共享层抽取（对现有代码的重构范围）

原则：**先下沉、后移植**。macOS 版先完成下沉重构并回归（`swift test` + 手测），再开 iOS 壳，避免双线漂移。

### 3.1 可直接搬入 OverlayStudioKit（近零改动）

| 文件 | 改动 |
| --- | --- |
| `Support/Localization.swift`（2101 行，字典本地化） | 无 |
| `Models/StudioModels.swift`、`Support/NumberTextFormatter.swift`、`Support/PreviewCommandActions.swift`、`Support/AppAppearanceSelection.swift` | 无/极小 |
| `Stores/StudioPreferenceStore.swift` | 无（UserDefaults） |
| `Services/OpenWeatherService.swift` | 无（URLSession + SecItem 钥匙串，iOS 同 API） |
| `Support/PurchaseAuthorization.swift` | `AppStoreSigningInfo.currentApplicationIdentifier()` 加 `#if os(macOS)`，iOS 返回 nil（收据存在性判断已足够触发校验） |
| `Support/TextMeasurementCache.swift` | NSFont → CTFont（一处） |

### 3.2 StudioModel 拆分（重构主体，2177 行）

拆为：

1. **`StudioSessionModel`（下沉到 OverlayStudioKit）**：素材/元数据/遥测状态、对表、布局与选中、预设、导出参数与校验、导出执行（TransparentVideoWriter/CompositedVideoWriter 调度、进度、ETA、取消）、预览渲染调度、天气、调试日志、撤销。`backgroundImage`/`overlayImage` 改为 `CGImage?`；AVPlayer 保留（跨平台可用）。
2. **平台服务协议（壳层实现注入）**：

```swift
protocol MediaPicking      { func pickVideo() async -> PickedMedia?; func pickActivityFile() async -> URL?; ... }
protocol OutputDelivering  { func deliver(_ url: URL, mode: OverlayExportMode) async -> DeliveryResult }  // Finder 显示 / Files 移动 / 分享 / 存相册
protocol SystemServicing   { func copyToPasteboard(_ s: String); func confirmOverwrite(_ name: String) async -> Bool }
protocol ExportRuntimeGuarding { func exportDidStart(); func exportDidEnd() }  // mac: 空实现；iOS: idle timer/后台任务/热监控（§7）
```

macOS 壳的实现即现有 NSPanel/NSWorkspace/NSAlert/NSPasteboard 代码平移；行为不变。

3. **文件访问语义变化**：`setVideo(_:)`/`setFIT(_:)` 增加 security-scoped 生命周期管理（§5.2）。macOS 沙盒下同样受益（当前依赖面板隐式授权，无书签持久化）。

### 3.3 视图层复用评估

| 视图 | 结论 |
| --- | --- |
| InspectorView / InspectorSettingsPanel / InspectorSelectionHeader（~2800 行） | 主体为纯 SwiftUI（Form/Picker/Slider/ColorPicker），除 SteppableNumericTextField 桥接外可共享；建议随 idiom 包一层容器（mac/iPad 右栏、iPhone sheet） |
| SidebarView / SidebarControls / SidebarSyncSection（~1500 行） | 同上，面板调用改走协议后可共享 |
| PreviewCanvasView（1121 行） | 手势/选中/网格逻辑可共享；`.onMoveCommand`、悬停部分按平台条件编译 |
| PreviewControlsPanel、PurchaseAuthorizationGate、SettingsView、DebugConsoleView | 小改后共享 |
| PlayerSurfaceView、PreviewTimelineSlider、StudioWindowView、OverlayStudioApp | 按平台各自实现（合计 ~700 行，iOS 侧重写等量代码） |

## 4. 平台替换映射总表

| 桌面能力 | iOS 实现 | 备注 |
| --- | --- | --- |
| NSOpenPanel（视频） | `fileImporter`(UTType.movie 等) + PhotosPicker 双入口 | 照片图库路径见 iPhone 技术文档 §3.1（iPad 同样适用） |
| NSOpenPanel（FIT/GPX/JSON） | `fileImporter`（自定义 UTType，§5.4） | |
| NSSavePanel | 导出写沙盒临时/文档目录 → `fileMover` 或分享 | 现有「先写临时文件再原子安装」机制原样保留 |
| 菜单栏 Commands | 工具栏 + 上下文菜单 + `.keyboardShortcut` | 键位与 Mac 相同 |
| Settings scene | 设置 sheet | |
| `.onMoveCommand` | `.onKeyPress`（iOS 17+） | 方向键微调保留 |
| NSAlert | `confirmationDialog` | |
| NSWorkspace reveal | Files 显示 / ShareLink | |
| NSPasteboard | UIPasteboard | |
| UNUserNotificationCenter | 同 API 直接复用 | 点击通知的处理从 NSWorkspace 改为 App 内定位 |
| AVPlayerLayer host (NSView) | 同构 UIView 版本 | `AVPlayerViewController` 不适用（画布需自绘浮层叠加） |
| 窗口 min 尺寸 1320×760 | 移除；按 size class 自适应 | ContentView 三栏固定宽 380/390 改自适应 |

## 5. 文件访问与数据流

### 5.1 导入入口

1. `fileImporter`：视频（`.movie/.video/.mpeg4Movie/.quickTimeMovie`，与现 allowedContentTypes 一致）、活动文件（fit/gpx）、预设 JSON。
2. 照片图库：PhotosPicker → PHAsset 直读 AVAsset（免拷贝路径，详见 iPhone 技术文档 §3.1，iPad 复用）。
3. 拖拽：`onDrop`（UTType.movie + 自定义 fit/gpx 类型）。
4. 「用 DataLayer Studio 打开」：`onOpenURL` + 文档类型声明，接管来自邮件/IM/Garmin Connect 分享的 FIT。

### 5.2 security-scoped 访问（新增能力，现代码空缺）

- 现状：macOS 版依赖 NSOpenPanel 的会话内隐式授权，全仓库无 `startAccessingSecurityScopedResource`/书签。iOS 上文档选择器返回的 URL **必须**配对调用 start/stop 访问，跨启动复用必须存 bookmark。
- 方案：`StudioSessionModel` 内引入 `ScopedFileReference`（URL + 是否 scoped + bookmark 数据），在 setVideo/setFIT 时 start，替换素材/退出时 stop；「最近使用」列表基于 bookmark（v1.x 可选）。macOS 端同结构（`bookmarkData(options: .withSecurityScope)`），一并修掉「重启后失去访问权」的隐患。
- 导出读源视频（合成模式）贯穿整个写出过程，scoped 访问必须覆盖 AVAssetReader 全生命周期。

### 5.3 输出去向

- 写出流程不变：临时目录写 `DataLayerStudio-<pid>-…` → 校验 → 原子安装。安装目标改为 App 文档目录（`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` 使其在 Files 可见）。
- 完成后提供：移动到用户位置（`fileMover`）/ ShareLink / 合成模式存入照片库（`PHPhotoLibrary`，权限用 add-only 级别）。
- 残留清理：`removeStaleTemporaryOutputs` 的 pid 存活探测（`kill(pid,0)`）在 iOS 单进程模型下依然正确，可复用。

### 5.4 Info.plist / entitlements 清单（iOS target）

- `UTImportedTypeDeclarations`：`com.garmin.fit`（conform `public.data`，扩展名 fit）、`com.topografix.gpx`（conform `public.xml`，扩展名 gpx，业界通用标识）。
- `CFBundleDocumentTypes`：上述两类 + movie（Viewer/Editor 角色）。
- `UIFileSharingEnabled`、`LSSupportsOpeningDocumentsInPlace` = YES。
- `NSPhotoLibraryAddUsageDescription`（保存合成视频）；读取走 PhotosPicker 无需权限文案。
- entitlements：iCloud KVS（标识与 Mac 对齐，§8）。iOS 无需 network-client（默认允许出网）与 App Sandbox 声明。
- **`PrivacyInfo.xcprivacy`（iOS 提审强制）**：声明 UserDefaults 等 required-reason API 用途；无追踪、无第三方 SDK，清单很短但不能缺。

## 6. 媒体管线差异（iOS）

### 6.1 编码器能力矩阵与策略

| 编码 | macOS 现状 | iOS/iPadOS | 策略 |
| --- | --- | --- | --- |
| H.264 / HEVC | 硬编（探测选择） | 全部支持设备硬编 | 不变 |
| HEVC-alpha | 硬编+系统支持 | 系统支持成熟；最低版本 26 的设备下限（A12/A13）起均具硬编 | 不变；M0 真机金样验证 |
| ProRes 4444 | 总可用（软编兜底） | 仅 ProRes 硬件机型可靠（iPhone 13 Pro+ 的 Pro 系、M1+ iPad）；其余设备不保证 | 复用 `OverlayHardwareProfile` 探测：无硬编时 UI 隐藏 ProRes 选项并注明「此设备不支持」，默认引导 HEVC-alpha。**与 macOS 的行为差异点，需要产品文案** |

### 6.2 分辨率与码率钳位

当前校验上限宽 16384px、码率 1000000 kbps 是桌面取向。移动端硬编上限依设备（HEVC 一般 8K、H.264 一般 4K），建议：iOS UI 预设最高 4K（3840×2160）+ 自定义上限 7680，超出编码器能力时依赖现有 `cannotStartWriter/unsupportedEncoder` 错误路径给可读提示；M0 阶段用设备矩阵实测定案（`OverlayVideoError` 文案已可承载）。核心库校验逻辑不动（保持 CLI/macOS 兼容），钳位放在 iOS 侧参数层。

### 6.3 透明通道保守原则（延续仓库红线）

HEVC-alpha 路径（unpremultiply → StraightAlpha 编码属性 → CVBuffer alpha attachment）**一行不改**。iOS 验收增加金样流程：真机导出固定布局浮层 → FCP iPad / Mac FCP 双端叠加检查透明区域无发灰 → 与 macOS 版同参数导出做像素抽样比对。

### 6.4 预览

AVPlayer + 浮层 CGImage 双层结构、scrub 用 AVAssetImageGenerator、拖动 gauge 降采样（上限 1600px）等机制全部可直接复用；iPad 屏幕像素密度高但预览渲染尺寸本来就按视图尺寸计算，无需特调。

## 7. 导出生命周期（iOS 特有，新增模块）

iOS 与 macOS 的最大运行时差异：**App 退到后台会被挂起，AVAssetWriter 编码无法在挂起中继续**。v1 策略（简单、可解释）：

1. 前台导出：导出中 `UIApplication.isIdleTimerDisabled = true`（结束/取消/出错时恢复）。
2. 退后台：`beginBackgroundTask` 争取收尾窗口（约 30 秒）；窗口内完不成则主动取消写出、清理临时文件，回前台时提示「导出因切换应用被中断」并允许一键重来。**不做**断点续导（AVAssetWriter 无法恢复半成品会话，成本/收益不成立）。
3. 热监控：订阅 `ProcessInfo.thermalStateDidChangeNotification`，`serious` 起在导出 UI 显示提示并写入调试日志（沿用 debug console 通道）；不自动降速（编码器由系统调度）。
4. 远期（不进 v1）：Live Activity 展示导出进度（详见 iPhone 技术文档 §3.5）；BGProcessingTask 不适合用户主动等待的导出场景，不采用。

以上封装为 §3.2 的 `ExportRuntimeGuarding` 协议 iOS 实现，macOS 实现为空操作。

## 8. 预设 iCloud 同步

- 机制复用：`LayoutPresetStore` 的 NSUbiquitousKeyValueStore 读写与 `didChangeExternallyNotification` 监听在 iOS 完全同构，`StudioModel` 中的观察代码平移即可。
- **前置依赖**：`Resources/AppStore.entitlements` 中 `com.apple.developer.ubiquity-kvstore-identifier` 当前为空字符串。跨端同步要求 Mac 与 iOS 使用**同一个显式 KVS 标识**（如 `$(TeamIdentifierPrefix)run.libo.datalayer-studio`）。需要先出一个 Mac 版更新落实该标识（涉及正式签名验证，属于独立小改动），iOS 版对齐。
- 容量核对:KVS 总量 1MB、单 key 1MB，而全部预设序列化在**一个 key** 下。单预设 JSON 实测量级为几 KB（默认布局 8 元素），几十个预设内安全；接近上限时的降级（本地保留 + 同步状态显示失败原因）列入 v1.x，当前风险低。
- UserDefaults 迁移域（`run.libo.overlay-studio` 旧域回填）是 macOS 历史包袱，iOS 端不需要 `loadIncludingSharedAppDomains`，直接用 `load()`。

## 9. 购买与授权

- **商业模式（已定）：付费买断 + Universal Purchase，统一定价，一次购买 Mac / iPad / iPhone 三端使用。**
- 工程落地：iOS target 使用与 Mac 相同的 bundle identifier `run.libo.datalayer-studio`，在 ASC 现有 App record（App ID 6782545770）下新增 iOS platform；已购 Mac 版的用户在 iOS 端以同一 Apple 账户直接解锁，无迁移动作。entitlements 中的 iCloud KVS 标识同步对齐（§8）。
- 注意事项：Universal Purchase 挂接是单向操作，之后不能再拆回独立 SKU；调价作用于三端同一价格；macOS 与 iOS 平台在同一 App record 下各自维护版本元数据与截图。
- StoreKit 2 `AppTransaction.shared` / `AppStore.sync()` 在 iOS 可用，`PurchaseAuthorizationStore` 状态机与 Gate 视图直接复用；同一 App record 下 AppTransaction 校验逻辑三端一致。
- `SecCodeCopySelf` 读取签名 entitlement 是 macOS-only，加 `#if os(macOS)`；iOS 判定「需要校验」只看收据存在性即可（App Store 安装必有收据；本地开发无收据 → 直接放行，与现逻辑一致）。

## 10. 性能与内存预算

| 项 | 量级 | 评估 |
| --- | --- | --- |
| 导出帧缓冲（BGRA） | 1080p ≈ 8.3MB/帧；4K ≈ 33MB/帧 | 写出管线按帧流式、池化（浮层池 2 + adaptor 池），峰值 < 200MB，远低于 iPad jetsam 限额；**保持「禁止整段缓存」红线** |
| 预览渲染 | 视图尺寸上限 3200px、拖动降采样 1600px | 直接复用 |
| 文本测宽缓存 | 上限 4096/16384 条 | 直接复用 |
| 路线路径缓存 | 布局变更时增量复用 | 直接复用 |
| 长导出 CPU/GPU | M 系 iPad ≈ 入门 Mac；A 系设备实测 | M0 输出基准表（1080p/4K × HEVC-alpha/HEVC 每分钟素材耗时） |

## 11. 测试策略

- **单元测试**：`OverlayCoreTests`、`OverlayStudioTests`（迁移到 OverlayStudioKit 后）增加 iOS Simulator destination 跑一遍。注意：模拟器缺硬件编码器，HEVC-alpha/ProRes 写出用例需按能力探测跳过（现有 `OverlayHardwareAccelerationTests` 已是探测式写法，写出类用例补 capability guard），完整写出验证放真机计划。
- **金样与互通**：§6.3 的透明通道金样；FCP iPad、LumaFusion、DaVinci Resolve iPad 导入验收各一条用例。
- **文件访问**：bookmark 恢复、scoped 生命周期（导出中源文件访问不失效）单测 + UI 测试。
- **生命周期**：导出中退后台/来电/锁屏的中断-恢复手测脚本；热压测（连续导出 30 分钟素材）。
- **无障碍/本地化**：沿用 `LocalizationTests` 四语言键校验；VoiceOver 手测清单。

## 12. CI 与发布

- CI 增加 job：`xcodebuild build test -destination 'platform=iOS Simulator,name=iPad Pro (13-inch)'`（Apple Silicon runner，规避 §1.2 arm64 断言）。macOS job 不变。
- TestFlight/App Store：沿用 `asc` 工作流，platform 参数 IOS；构建号沿用 `yyyyMMddNN`；截图与元数据四语言。
- GitHub Release 不发 iOS 产物（无旁加载分发），README 注明 iOS 仅 App Store 渠道。

## 13. 安全与隐私

- 权限最小集：照片库仅 add-only（保存成片）+ Picker 免权限读取；无定位（GPS 数据来自 FIT 文件而非设备）；无麦克风/相机。
- OpenWeather key 继续存钥匙串（SecItem 同 API）；不打印、不入日志（沿用 redacted 摘要）。
- 隐私清单 `PrivacyInfo.xcprivacy`（§5.4）；App 隐私标签与 Mac 版一致（不收集数据）。

## 14. 分阶段实施计划

| 阶段 | 内容 | 出口标准 | 粗估 |
| --- | --- | --- | --- |
| P0 验证 spike | Package.swift 加 iOS 平台；建最小 Xcode 壳；真机（1 台 M 系 iPad + 1 台下限档 A12 机型，如 iPad 第 8 代）跑 OverlayCore 导出 1080p HEVC-alpha + 合成 HEVC；FCP iPad 验收 | 金样通过，得出编码器/性能基准表 | 2–3 天 |
| P1 共享层下沉 | 建 OverlayStudioKit；StudioModel 拆分 + 平台协议；NSImage→CGImage；macOS 全量回归（swift test + build_app_bundle.sh + 手测） | macOS 版行为零变化 | 1.5–2 周 |
| P2 iPad UI | OverlayTouch：三栏自适应布局、画布触控手势、检查器/侧栏容器、文件导入导出、导出生命周期模块 | 产品文档 M1+M2 场景走通 | 3–4 周 |
| P3 平台特性 | 拖拽、多窗口、键盘全键位、Pencil/指针、文档类型、通知、预设同步联调（含 Mac entitlement 前置项） | 产品文档 M3 验收 | 1.5–2 周 |
| P4 发布 | 无障碍/本地化验收、性能与热测试、隐私清单、TestFlight 内测 → 提审 | 上架 | 1–2 周 |

合计约 8–11 周单人全职量级（不含 iPhone idiom 层，那部分见 iPhone 技术文档 §6）。

## 15. 风险登记

| 风险 | 概率 | 影响 | 缓解 |
| --- | --- | --- | --- |
| HEVC-alpha 在部分 A 系设备行为差异（灰边/编码失败） | 低–中（最低版本 26 已把下限收敛到 A12/A13） | 高（核心卖点） | P0 金样前置；探测式降级到 ProRes（有硬编时）或提示换设备 |
| ProRes 在非 ProRes 机型不可用引发用户困惑 | 高 | 中 | UI 显隐 + 文案；产品文档已注明与 Mac 行为差异 |
| 导出中挂起/热限制导致失败率上升 | 中 | 中 | §7 生命周期模块 + 中断可解释可重试；导出前时长提示 |
| StudioModel 拆分引入 macOS 回归 | 中 | 高 | P1 独立合入 + 全量测试 + app bundle 手测清单；拆分期间冻结其他 GUI 需求 |
| iCloud KVS 标识对齐需 Mac 版先行发版 | 确定 | 低 | 作为独立小版本提前发；iOS 首版可先行（同步功能标记「等待 Mac 更新」） |
| 模拟器不能覆盖编码路径，CI 信号弱 | 确定 | 中 | 真机验收清单制度化（发布前必跑） |
| 三栏 UI 在 compact 尺寸退化体验差 | 中 | 中 | 产品文档 §6.2 的 sheet 方案 + Stage Manager 最小尺寸验收 |

## 16. 附录：AppKit import 文件全集（重构对照）

`OverlayStudioApp.swift`、`StudioModel.swift`、`OverlayCoreExtensions.swift`、`TextMeasurementCache.swift`、`VideoFrameService.swift`、`StudioWindowView.swift`、`InspectorSettingsPanel.swift`、`PlayerSurfaceView.swift`、`PreviewTimelineSlider.swift`、`PreviewCanvasView.swift`、`DebugConsoleView.swift`——共 11 个文件；绑定点明细见 §1.3。
