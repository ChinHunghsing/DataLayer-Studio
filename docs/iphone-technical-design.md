# DataLayer Studio for iPhone 技术方案文档

| 项目 | 内容 |
| --- | --- |
| 状态 | 提案（未排期，未开工；本文不改动任何现有代码） |
| 日期 | 2026-07-04 |
| 适用平台 | iOS / iPhone（与 iPad 共用同一 iOS App target） |
| 关联文档 | `docs/iphone-product-design.md`、`docs/ipad-technical-design.md`（共享架构以该文档为准，本文只展开 iPhone 特有部分） |

## 0. 结论摘要

- 可行性与 iPad 版同源：核心渲染/导出引擎（`Sources/OverlayCore`）零 AppKit 依赖，iOS 直接复用；平台绑定点清单、共享层抽取（OverlayStudioKit）、文件访问、iCloud 预设同步、购买校验、CI/发布方案见 `docs/ipad-technical-design.md` §1–§5、§8–§13，本文不重复。
- iPhone 特有的技术工作集中在五处：**相册直读管线**（PHAsset → AVAsset，避免大视频落盘拷贝）、**自动对齐**（视频创建时间 × FIT 绝对时间，新共享能力）、**compact 界面层**（sheet 化检查器与竖屏画布手势）、**更严格的导出生命周期**（热/电/锁屏 + 可选 Live Activity）、**内置竖版模板资产管线**。
- 硬阻塞项：无。最大的不确定性是自动对齐依赖的视频时间元数据质量（§3.2），需真实素材库验证并设计兜底。

## 1. 与共享架构的关系

```
OverlayCore（不动） ← OverlayStudioKit（共享层，iPad 文档 §3） ← OverlayTouch（iOS 壳）
                                                                  ├── iPad idiom（regular）
                                                                  └── iPhone idiom（compact）
```

- idiom 分流依据 **size class**（`horizontalSizeClass == .compact` 走 iPhone 布局），不用 `UIDevice.userInterfaceIdiom`——这样 iPad Slide Over/分屏的 compact 场景自动获得 iPhone 布局，一举两得。
- `StudioSessionModel`、平台服务协议、导出生命周期模块（`ExportRuntimeGuarding`）、文件访问（security-scoped + bookmark）、Info.plist/entitlements/隐私清单等完全共享，见 iPad 技术文档 §3–§7。
- 渲染一致性是硬约束：iPhone 上任何「轻编辑」都只是 UI 裁剪，写回的仍是完整 `OverlayLayout`，三端像素级一致。

## 2. 界面层技术要点（compact idiom）

### 2.1 结构

- `NavigationStack` + 主编辑页（画布 + 底部工具条）+ 半高 sheet（`presentationDetents([.medium, .large])`）承载模板/组件/对齐/设置四个面板；sheet 弹出时画布保持可见可交互（`presentationBackgroundInteraction(.enabled(upThrough: .medium))`）。
- 三步向导用独立 NavigationStack 页面序列，完成后落到主编辑页；素材齐备时向导可跳过。
- 轻量检查器不是新造设置系统：复用共享检查器的绑定与分区实现，按「iPhone 白名单」过滤暴露分区/条目（白名单在 idiom 层声明，共享层不感知），保证同一状态写路径、无双份逻辑。

### 2.2 画布手势（与 iPad 的差异）

| 手势 | iPad | iPhone |
| --- | --- | --- |
| 双指捏合 | 缩放画布 | 缩放**选中组件**（`frame.scale`，沿用 0.1–4 clamp）；未选中时缩放画布 |
| 双击 | 适配 ↔ 100% | 同 |
| 单指拖动 | 移动组件/平移画布 | 同；小屏下组件选中热区放大系数更大 |

- 拖动跟手性沿用现成机制：gauge 拖动期间预览渲染降采样（现有 `gaugeDragMaximumPreviewRenderDimension = 1600`）在 iPhone 分辨率下天然足够。
- 时间轴滑杆用 SwiftUI Slider + 帧步进按钮（共享组件，替代 macOS 的 NSSlider 桥接）。

## 3. iPhone 特有技术模块

### 3.1 相册直读管线（主导入路径）

现有写入器与元数据加载以 **URL** 为输入（`CompositedVideoWriter(outputURL:sourceVideoURL:…)`、`VideoMetadata.load(from:)` 内部构造 `AVURLAsset`）。相册素材若走「导出成文件再用 URL」，4K 长视频要在沙盒里复制数百 MB 至数 GB，首次体验不可接受。方案：

1. 共享层引入视频源抽象：`VideoSource = fileURL(ScopedFileReference) | photoLibrary(PHAsset)`，统一解析为 `AVAsset` 供预览（AVPlayer、AVAssetImageGenerator 本就接受 AVAsset）。
2. 核心库**新增接受 `AVAsset` 的初始化重载**（`CompositedVideoWriter`、`VideoMetadata`；`AVAssetReader(asset:)` 内部实现不变），保留 URL 版本以维持 CLI 与 macOS 兼容——这是本方案对 OverlayCore 唯一的功能性新增，属加法不改行为。
3. PHAsset → `PHImageManager.requestAVAsset(forVideo:options:)`，`deliveryMode = .highQualityFormat`、`isNetworkAccessAllowed = true`（iCloud 照片库素材带下载进度回调，UI 呈现）。
4. 慢动作视频返回 `AVComposition`：预览与 AVAssetReader 均可直接消费（自然带变速效果）；对纯浮层导出无影响（浮层导出根本不读源视频，仅用其尺寸/帧率/时长——这也意味着 iPhone 可支持「只有 FIT、没有视频」的浮层导出，产品上作为隐藏能力保留）。
5. 生命周期：PHAsset 的 AVAsset 不涉及 security-scoped 访问；但导出进行中要持有强引用并处理照片库对象失效（用户删除素材）→ 中断并给可读错误。

### 3.2 自动对齐（新共享能力，iPhone 首发）

- 输入：视频创建时间（优先 `AVAsset.creationDate`（QuickTime 元数据，含时区），相册素材回退 `PHAsset.creationDate`）与 FIT 绝对时间（`TelemetrySeries` 样本已带 `date`）。
- 计算：`fitSyncTime = 视频创建时刻 − FIT 起始时刻`（换算到 FIT 已历时间），产出现有 `TelemetryTimeSync(videoSyncTime: 0, fitSyncTime:)`——落在既有同步模型内，无新模型。
- 已知精度陷阱（需样本库实测）：相机时钟漂移、创建时间记录的是「开始拍摄」还是「写文件」、跨时区、剪辑过的视频元数据丢失。因此定位为**给初值**，UI 必须跟「对齐确认 + 帧微调」页，兜底进入手动三模式（共享实现）。
- 该模块放 OverlayStudioKit，iPad/Mac 后续直接受益。

### 3.3 导出生命周期（在 iPad 文档 §7 基础上加严）

- iPhone 单手/移动场景下切走概率远高于 iPad，中断提示与「一键重来」的可达性要求更高（完成/中断状态用全屏卡片而非状态栏文字）。
- 热策略：iPhone 散热差，`thermalState == .serious` 时在进度条下方常驻提示；`.critical` 时暂停确认（继续/取消）——暂停实现为取消+保留参数一键重来（AVAssetWriter 无真暂停）。
- 低电量模式（`isLowPowerModeEnabled`）导出前提示可能变慢，不阻断。
- Live Activity（可选，产品开放问题 #4）：ActivityKit 展示导出进度于锁屏/灵动岛；进度更新节流到 ≥1%/次且 ≤1 次/秒（预算限制）；App 挂起时写出会中断，Activity 状态要能表达「已中断，回到 App 重试」，避免锁屏上进度假死。**注意：Live Activity 不延长后台执行时间，不能当后台导出方案。**

### 3.4 内置竖版模板资产管线

- 模板即 `LayoutPreset` JSON（已 Codable），由设计在 iPad/Mac 版内排布后导出（现有预设导出功能即生产工具）。
- 以 bundle 资源随 App 分发，启动时经 `LayoutPresetState` 解码 + `sanitized` 载入为只读「内置模板」区，**不写入** UserDefaults/iCloud KVS（不占 1MB 配额、不污染用户预设；「另存为我的预设」时才复制进用户存储）。
- 模板按画幅标注（16:9 / 9:16 / 1:1，加在模板元数据而非 LayoutPreset 模型——避免动共享 Codable 模型；用文件名约定或独立清单 JSON），编辑页按当前视频宽高比排序推荐。
- 竖版分辨率预设补充 1080×1920、2160×3840（现 `OutputResolutionPreset.fixed` 均为横版；「跟随源」已可用，此项是 UI 层预设清单扩充）。

### 3.5 导出参数的 iPhone 侧默认

- 产物类型默认「成片（HEVC）」；浮层（HEVC-alpha）收进次要位置；ProRes 4444 仅在 `OverlayHardwareProfile` 探测到硬件编码器（iPhone 13 Pro 起的 Pro 机型）时出现在高级选项。
- 画质档位映射：1080p / 4K / 跟随源 → 现有宽高/码率参数（码率沿用「跟随源码率」逻辑，高级里可改）；帧率默认跟随源。
- 上限钳位随 iPad 文档 §6.2 的设备矩阵结论，iPhone 侧 UI 默认不提供超过 4K 的档位。

## 4. 性能与内存预算（iPhone 修正值）

| 项 | 评估 |
| --- | --- |
| 导出峰值内存 | 流式管线下 1080p < 100MB、4K < 300MB 量级（BGRA 帧 33MB × 池深 ~6 + 编码器内部）；对 4GB RAM 设备（iPhone XS 级）安全余量充足；**保持「禁止整段缓存帧」红线** |
| 预览 | iPhone 视图尺寸小，预览渲染负载低于 iPad；AVAssetImageGenerator scrub 不变 |
| 4K HEVC-alpha 导出速度 | A 系设备低于 M 系 iPad，P0 基准表需覆盖至少一台非 Pro A 系机型；导出页的预估耗时区间用该表标定 |
| 电量 | 长导出属高功耗场景，纳入 M4 实测（30 分钟素材导出的电量消耗），必要时在文案中管理预期 |

## 5. 测试策略（增量）

- 模拟器矩阵：iPhone SE（最小屏）/ 标准 6.1 英寸 / Pro Max，compact 布局与 sheet 交互 UI 测试；写出用例的编码器限制同 iPad 文档 §11（模拟器无硬编，真机验收）。
- 自动对齐：构造元数据样本库（正常/缺创建时间/跨时区/剪辑过/慢动作）做表驱动单测。
- 相册管线：iCloud 未下载素材、下载中取消、导出中素材被删除三条异常路径。
- 竖版模板：9:16/1:1 画幅下全组件渲染快照测试（补充现有 OverlayRendererTests 的横版基线）。
- 真机热测：连续两次 4K 导出观察 thermalState 阶梯与提示触发。

## 6. 工作量粗估（在 iPad 计划 P0–P1 完成的前提上）

| 项 | 粗估 |
| --- | --- |
| 相册直读 + AVAsset 重载（含核心库加法与测试） | 4–6 天 |
| 三步向导 + 自动对齐（含样本库与兜底 UI） | 1–1.5 周 |
| compact 编辑页（画布手势差异、四 sheet、轻量检查器白名单） | 2–3 周 |
| 竖版模板资产管线 + 设计联动 | 3–5 天（工程侧） |
| 导出页 + 生命周期加严（Live Activity 另计 3–4 天） | 1 周 |
| 测试/无障碍/本地化/发布 | 1–1.5 周 |
| 合计 | 约 6–8 周单人全职（与 iPad UI 有约 30% 可并行复用） |

## 7. 风险登记（iPhone 特有）

| 风险 | 概率 | 影响 | 缓解 |
| --- | --- | --- | --- |
| 视频时间元数据质量差导致自动对齐口碑翻车 | 高 | 高（主打卖点） | 定位为「初值 + 确认页」；样本库驱动开发；失败路径直接给手动模式，不硬撑 |
| 相册 iCloud 素材下载慢/失败打断首次体验 | 中 | 中 | 下载进度 UI + 可取消 + 建议 Wi-Fi 文案 |
| 轻量检查器白名单取舍不当（功能不够用/太复杂各打五十） | 中 | 中 | TestFlight 数据迭代；白名单做成配置便于调整 |
| 竖版模板设计资源不到位拖累 v1 | 中 | 高（竖屏是主场景） | 模板生产用现有 Mac 版工具链，提前于 M2 启动设计 |
| 导出中切走比例高造成成功率指标难看 | 高 | 中 | 中断可解释 + 一键重来 + （可选）Live Activity 降低「切走看进度」动机；指标口径把「中断后重试成功」计入成功 |
| Sheet 叠画布的交互在小屏拥挤 | 中 | 中 | medium detent 高度调优；画布最小可视高度约束；早期可用性测试 |
