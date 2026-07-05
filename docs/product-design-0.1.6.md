# DataLayer Studio 产品文档 · 0.1.6 规划基线

> 面向开发团队。第 1–6 章记录 **0.1.5 基线的现状（as-is）**：界面结构、用户可用功能、状态与边界；第 7 章记录团队用的 **设计 Skills 工作流**；第 8 章是 **0.1.6 版本规划**。
>
> 版本上下文：线上最新 tag `v0.1.4`；进行中 `0.1.5`（工作台重构，见 `docs/ui-ue-workbench-plan-0.1.5.md`，阶段 1–4 完成、5–9 待做）；本文规划下一个 `0.1.6`。
>
> 对外名称统一写 **DataLayer Studio**。以下描述均以当前 `Sources/OverlayStudio` 代码为准，不含移动端（另见 `docs/ipad-*`、`docs/iphone-*`）。

---

## 1. 产品定位与目标用户

DataLayer Studio 是一款 **macOS 原生桌面应用**，把运动手表 / 码表的遥测数据（`.fit` / `.gpx`）渲染成可叠加到运动视频上的**数据层（data overlay）**，导出为透明浮层视频或已合成的成片。

核心价值：把「一段运动视频 + 一份活动文件」变成「带专业数据仪表的成片」，全程在本机完成，不上传素材。

三类目标用户，对应三种使用路径：

| 用户 | 诉求 | 主路径 |
| --- | --- | --- |
| 新用户 | 第一次不知道从哪下手 | 导入素材 → 同步 → 裁剪 → 输出 |
| 熟练用户 | 快速出片，重复布局 | 载入预设 → 微调同步 → 导出 |
| 调数据层的用户 | 精细控制单个 gauge 外观 | 选中元素 → Inspector 五分段编辑 |

关键约束（团队红线，来自 `AGENTS.md`）：

- 视频写出**按帧流式**，禁止把整段视频帧或大图缓存进内存。
- 透明 HEVC/ProRes Alpha 路径**保守修改**，不得重新引入透明区域发灰。
- 新增布局字段必须 **Codable 向后兼容**，旧 preset 不能因缺字段加载失败。
- 新增 UI 文案必须**同步四套本地化**：英文、简体中文、繁体中文、日文。
- 不引入新依赖（除非用户明确要求且系统 API 无解）。

---

## 2. 信息架构：三栏工作台（as-is）

主窗口 `ContentView` 是一个三栏 `HStack`，最小尺寸 **1320×760**。标题栏中间显示当前视频文件名；无视频时显示 `.fit` / `.gpx` 文件名；都没有时显示 App 名。

```
┌──────────────┬───────────────────────────────┬────────────────┐
│ 项目面板      │           预览舞台             │   检查器        │
│ SidebarView  │        PreviewCanvasView       │  InspectorView │
│  (330pt)     │  ┌─────────────────────────┐   │   (390pt)      │
│              │  │  播放层 PlayerSurface    │   │  选中头部动作   │
│ · 素材 Source │  │  gauge 可拖拽/缩放/微调  │   │  ─────────────  │
│ · 画布 Canvas │  └─────────────────────────┘   │  五分段设置面板  │
│   - 网格      │  控制条：播放/缩放/适配/全屏     │  · 布局 Frame   │
│   - 预设      │  时间轴（限制在导出区间内）      │  · 内容 Text    │
│   - iCloud   │  ┌─ 底部工作区 BottomWorkspace ┐ │  · 外观 Style   │
│              │  │  [同步] [裁剪] [输出]        │ │  · 字体 Type    │
│              │  └────────────────────────────┘ │  · 数据 Data    │
└──────────────┴───────────────────────────────┴────────────────┘
```

组合关系（源码级，供改结构时定位）：

- `ContentView` → `SidebarView` / `PreviewCanvasView` / `InspectorView`。
- `PreviewCanvasView` → `PlayerSurfaceView`（视频帧 + 浮层图）、`PreviewControlsPanel`（播放/缩放/适配/全屏 + `PreviewTimelineSlider`）、`BottomWorkspaceView`（底部工作区）。
- `BottomWorkspaceView` → `WorkspaceTab`（同步/裁剪/输出）+ 同步页复用 `SidebarSyncSection`。
- `InspectorView` → `InspectorSelectionHeader`（选中元素头部）+ `InspectorSettingsPanel`（五分段）。
- **全屏预览**是独立模式：`PreviewCanvasView(isFullscreen: true)`，Esc 退出。
- **导出进度与结果**是模态 sheet（`ExportStatusSheet`），不占用主界面。

---

## 3. 用户可用功能清单（as-is 功能盘点）

### 3.1 素材导入（项目面板 · 素材 Source）
- **源视频**：`⌘O` 或点击选择。可选——不选视频时走 FIT/GPX-only 透明浮层路径。
- **活动文件**：`⌘F`，支持 `.fit` 与 `.gpx`。
- 加载状态行：loading / loaded / error，失败可 **Retry**。
- CLI 启动参数：`--video <path>`、`--fit <path>`、`--offset <seconds>`（`StudioLaunchOptions`）。

### 3.2 数据层元素目录（22+ 种 gauge）
遥测/运动动态字段共 22 个 `component.*`，加上天气、GPS 路线、时间日期等，按渲染形态分四类（基准尺寸见 `ComponentBaseSize`）：

- **标准指标块**（160×74）：配速 pace、心率 heartRate、踏频 cadence、卡路里 calories、步幅 strideLength、功率 power、垂直振幅、触地时间/占比/平衡、垂直比、呼吸频率、步速损失%、形态功率、空气功率、腿部弹性刚度、距离 distance。
- **仪表盘**（speed 420×238）：速度，带刻度 tick、gauge min/max、小数位。
- **地图/进度**：GPS 路线（route 382×238）、顶部进度条（topProgress 1650×58，含起点/实时/终点距离与终点标签）。
- **信息块**：天气（weather 136×76，图标 + 温湿度）、时间和日期（timeDate 300×118）。

### 3.3 同步（底部工作区 · 同步 tab）
把视频时间对齐到活动时间。三种模式（`SyncMode`）：

| 模式 | 文案 | 场景 |
| --- | --- | --- |
| `syncPoint` | 匹配点 | 视频和活动里能找到同一瞬间 |
| `fitStart` | 视频起点 | 录像开始时活动已进行一段（输入视频 00:00 对应的活动用时） |
| `offset` | 手动 | 高级：直接给正负偏移（时/分/秒/毫秒 + 正负号） |

- **标记运动开始**（`⌘⇧S`）：把当前播放头这一帧设为活动 00:00。
- 实时映射提示：`视频 %@ = 运动 %@`、`运动开始前 %@`。
- 无视频时显示「无需同步」，直接用活动时间。

### 3.4 裁剪（底部工作区 · 裁剪 tab）
- 导出范围：整段 / 当前为开始 / 当前为结束。
- 显示开始、结束、时长。
- 预览播放头被限制在导出区间内。

### 3.5 输出 / 导出（底部工作区 · 输出 tab）
- **两种导出类型**：透明浮层 / 合成视频（FIT/GPX-only 时合成视频禁用）。
- **编码**：HEVC/H.265 with alpha、Apple ProRes 4444（浮层）；HEVC/H.265、H.264（合成）。导出类型与编码不匹配会拦截。
- **分辨率**：源视频 / 7 档预设（含竖屏）/ 自定义宽高（2–16384、偶数）。
- **帧率**：源视频 / 8 档预设（23.976–60）/ 自定义（1–240）。
- **码率**：kbps（1–1,000,000，含「对本机过大」保护）。
- **距离单位**：米 / 公里。
- **目标**：固定另存路径，或「导出时询问」。
- **导出摘要**：类型/编码/分辨率/帧率/范围/时长/码率/预估大小/目标。
- 导出按钮：导出浮层 / 导出视频（`⌘E`）；不可用时在按钮附近显示不可执行原因。
- **导出中**：进度 + 预计剩余 + 取消（`⌘.`，二次确认）。
- **完成**：结果 sheet 显示文件名、用时、在访达中显示 / 打开文件；失败或取消给对应文案；完成后发系统通知，点通知直达 Finder。

### 3.6 布局预设与 iCloud（项目面板 · 画布 Canvas）
- 保存当前布局为命名预设；列表可**载入 / 设为默认 / 删除**（均二次确认）。
- 预设 **JSON 导入 / 导出**（跨机迁移）。
- **iCloud 同步**状态（`LayoutPresetSyncStatus`）：仅本地 / 已就绪 / 已请求上传 / 收到 iCloud 更新。

### 3.7 天气（数据层元素 · 天气 gauge 的数据分区）
- OpenWeather **One Call 4.0** key，只存本机；每个活动文件的天气结果本地缓存，避免重复消耗额度。
- 天气图标：自动 / 晴 / 多云 / 雨 / 雪 / 雷暴 / 雾 / 风。
- 「刷新天气」重新拉取并更新预览；缺 key / 缺活动文件 / key 无 One Call 权限有对应错误文案与引导链接。

### 3.8 画布网格
- 显示网格、拖动时吸附、可配置列数/行数。

### 3.9 预览控制
- 播放/暂停（Space）、缩放（`⌘+` / `⌘-` / `⌘0`）、适配、全屏（`⌘⇧F`）、刷新预览（`⌘R`）。
- 直接在画布拖拽/缩放 gauge，方向键微调选中元素。
- 时间轴显示预览时间与「运动开始」标记。

### 3.10 检查器（右栏，仅编辑当前选中 gauge）
- **头部动作**：显示第几/共几层、添加、显示/隐藏、复制、层级前后移动、删除。
- **五分段**：布局 Frame / 内容 Text / 外观 Style / 字体 Type / 数据 Data。
- 空状态引导「选择或添加一个 gauge」；隐藏元素在顶部有「已隐藏」提示与「显示」动作。
- 完整撤销/重做：移动、编辑、添加、删除、复制、图层重排、套用预设。

### 3.11 设置 / 系统面
- **语言**：跟随系统 / 简体 / 繁体 / English / 日本語（菜单与设置均可切，立即生效）。
- **外观**：跟随系统 / 浅色 / 深色。
- **购买校验**（`PurchaseAuthorizationGate`）：校验 App Store 收据，支持恢复购买、重试，缺收据/未验证/恢复失败有分别文案。
- **调试控制台**（`⌘⇧D`）：分类（输入/天气/预览/导出）、搜索、复制当前结果、清空。

### 3.12 菜单与快捷键总表
| 菜单 | 动作 | 快捷键 |
| --- | --- | --- |
| 文件 | 打开视频 / 打开运动文件 / 导出浮层 / 取消导出 | `⌘O` / `⌘F` / `⌘E` / `⌘.` |
| 排列 | 上移一层 / 下移一层 | `⌘⌥↑` / `⌘⌥↓` |
| 预览 | 刷新 / 播放暂停 / 标记运动开始 / 放大 / 缩小 / 重置缩放 / 全屏 | `⌘R` / `Space` / `⌘⇧S` / `⌘+` / `⌘-` / `⌘0` / `⌘⇧F` |
| 语言 | 五语言切换 | — |
| 调试 | 控制台 / 复制日志 / 清空日志 | `⌘⇧D` |
| 画布 | 方向键微调选中元素 | `方向键` |

---

## 4. 关键状态与边界（state machine）

`StudioModel` 是单一状态源。团队改交互时，优先改这里的**共享根因**，不要在多个调用点复制保护逻辑。

- **可预览 `canPreview`**：有活动文件即可（视频可选）。
- **可导出 `canExport`**：活动文件 + 输出设置全部在合法区间 + 目标合法；合成视频还要求有源视频。不可导出时把原因放到按钮附近，不只藏在 tooltip。
- **导出中 `isExporting`**：锁定打开/导出/播放/标记等命令；进度 + ETA + 可取消。
- **导出结果**：成功（`lastExportedURL`）/ 失败（`lastExportErrorMessage`）/ 取消（`lastExportWasCancelled`）三态，走同一 sheet。
- **加载失败**：`videoLoadFailure` / `fitLoadFailure` 保留 Retry。
- **空状态**：无选中元素、隐藏元素、无预设、无天气 key 各有对应文案。

设计要求：以上每个「不可用/失败/空」状态都要让用户知道**下一步能做什么**，四语言文案都要具体，不能只暴露底层错误。

---

## 5. 现状约束与非目标（0.1.5 已明确「暂不做」）

以下在 0.1.5 计划里被显式排除，0.1.6 **默认延续排除**，除非有新证据推翻：

- 不做 onboarding、help center、全局 toast 系统、wizard。
- 不新增全局 Inspector 状态模型、不重做 Inspector 导航、不做全属性批量编辑。
- 不把同步/裁剪/输出拆成独立窗口，导出设置不回左栏。
- 不做完整快捷键设置页、不做自定义快捷键、不把 Debug 命令搬进主界面。
- 不改最小窗口尺寸（除非验证发现 1320×760 确实不够）。
- 不做移动端适配（移动端走独立文档与路线）。

---

## 6. 0.1.5 剩余摊子（承接到 0.1.6 的基线）

`ui-ue-workbench-plan-0.1.5.md` 阶段 1–4 完成，阶段 5–9 是未完成的可用性收尾：

- **阶段 5 Inspector 二次打磨**：五分段默认展开与顺序、折叠摘要降噪、高频动作前置。
- **阶段 6 底部工作区流程提示**：同步/裁剪/输出之间不靠猜；导出不可用原因前置到按钮旁。
- **阶段 7 快捷操作可发现性**：已注册快捷键在 tooltip 统一显示，命令只注册一次。
- **阶段 8 状态/空态/错误恢复**：失败给可执行下一步，四语言文案具体化。
- **阶段 9 小窗口/多语言/无障碍**：四语言长文本不破版，小窗口 action group 收进菜单，补 a11y label。

> 0.1.6 规划以「假设 0.1.5 已把阶段 5–6 落地、阶段 7–9 部分落地」为前提；实际开工前先核对 0.1.5 分支真实进度再锁定范围。

---

## 7. 设计 Skills 工作流（团队怎么用）

本项目用 Claude 设计类 skill 做 UI/UE 迭代。原则：**按问题类型用最小组合，不一次开满**；每轮改动前后各跑一次轻量 `critique`。

| Skill | 用途 | 使用时机 |
| --- | --- | --- |
| `critique` | UI/UE 审核、发现阻塞问题并量化 | 每轮 UI 改动前后 |
| `shape` | 把模糊问题收束成小范围设计 brief | 新增交互前（尤其 Inspector / 快捷流） |
| `layout` | 间距、密度、视觉层级 | 底部工作区、Inspector 二次打磨 |
| `clarify` | 文案、错误、空状态、提示 | 同步/导出/权限/天气/空态四语言文案 |
| `adapt` | 小窗口、长文本、多语言适配 | 四语言落地后与小窗口验证 |
| `polish` | 最终一致性和细节检查 | 每个阶段收尾 |
| `typeset` | 字体层级、字号、可读性 | Inspector 字体分段、导出摘要密度 |
| `swiftui-expert-skill` | macOS 结构、commands、Inspector、split layout、状态/焦点/无障碍 | 改窗口结构、菜单、快捷键、出现焦点/a11y 问题时 |
| `swiftui-performance` | 渲染/滚动/body 求值/内存 | 预览刷新卡顿、导出内存、视图更新过多时 |

说明与修正：

- 0.1.5 计划表里的 `build-macos-apps:swiftui-patterns` **当前技能列表中不存在**；macOS 结构/commands/Inspector/split layout 的需求改用 **`swiftui-expert-skill`**，性能相关用 `swiftui-performance`。
- 更主观的视觉风格升级（`impeccable` / `delight` / `bolder` 等）本轮**不启用**，避免偏离既有产品约定与品牌方向；确需做时先补项目设计上下文再评估。

Skills 只是加速审查与打磨，**不替代**第 1 章红线和第 8 章验证；skill 产出的结论仍要落到 `StudioModel` 共享根因与四语言文案。

---

## 8. 0.1.6 版本计划（收敛版）

### 8.1 版本主题
**「少猜、少滚、少报错」**。0.1.6 不做新工作台、不做新系统，只把 0.1.5 主路径的最后摩擦点补平。

主路径固定为：

`导入素材 → 同步时间 → 裁剪范围 → 选择输出类型 → 导出`

### 8.2 本轮只做三件事

**P0 · 主路径提示与导出可用性**
- 底部工作区只补轻量提示：当前步骤在做什么、下一步能做什么。
- 导出按钮旁常驻显示不可导出的原因：缺活动文件、合成视频缺源视频、编码与类型不匹配、输出参数越界、目标路径不可写。
- 素材加载后默认进入「同步」页的行为只复核，不重新设计。
- 不做 wizard、不做 onboarding、不做全局 toast。
- 验证：相关 `OverlayStudioTests` + `scripts/build_app_bundle.sh` 后手测导入、同步、裁剪、两种导出类型。

**P1 · Inspector 降噪**
- 复核五分段默认展开顺序，只让高频区默认展开。
- 折叠摘要只保留必要信息：隐藏状态、X/Y、大小、核心颜色；删掉无决策价值的摘要。
- 小窗口下头部动作挤不下时进菜单，不挤压标题。
- 不改 Inspector 架构，不新增全局 Inspector 状态模型。
- 验证：选中/隐藏/复制/删除/层级移动手测 + Inspector 相关 `OverlayStudioTests`。

**P1 · 错误恢复与导出可靠性**
- 加载、天气、预设、导出失败文案改成「原因 + 下一步」。
- 复核导出取消后的半成品清理和临时文件清理。
- 复核导出摘要里的时长、码率、预估大小，保证数字可读且无千分位逗号。
- 不重写 writer；透明 Alpha 路径只在测试证明必须改时才动。
- 验证：`TransparentVideoWriterTests`、`CompositedVideoWriterTests`、`OverlayRendererTests`，防透明发灰、内存暴涨、合成视频回归。

### 8.3 明确不进 0.1.6
- 不做 onboarding、help center、全局 toast、wizard。
- 不做自定义快捷键页。
- 不改三栏结构、不拆独立窗口、不改最小窗口尺寸。
- 不做完整 iCloud 体验重设计，只修明显状态文案问题。
- 不做移动端适配。
- 不启用主观视觉风格升级 skill。

### 8.4 提交切分
1. 主路径提示与导出不可用原因。
2. Inspector 降噪与小窗口动作菜单。
3. 错误恢复文案与导出可靠性复核。

### 8.5 完成标准
1. 新增文案英/简/繁/日齐全。
2. 非平凡逻辑有测试或更新现有测试。
3. 影响 GUI 的改动运行 `scripts/build_app_bundle.sh`。
4. 影响导出的改动跑 writer/renderer 相关测试。
5. 每个提交只含对应阶段文件，提交前 `git fetch` 并确认不落后。

---

## 附录 A · 源码定位速查
| 关注点 | 文件 |
| --- | --- |
| 三栏布局、导出 sheet | `Views/ContentView.swift` |
| 窗口标题、启动参数 | `Views/StudioWindowView.swift` |
| 项目面板（素材/画布/预设） | `Views/SidebarView.swift`、`Views/SidebarControls.swift` |
| 预览舞台 / 控制条 / 时间轴 | `Views/PreviewCanvasView.swift`、`Views/PreviewControlsPanel.swift`、`Views/PreviewTimelineSlider.swift` |
| 底部工作区（同步/裁剪/输出） | `Views/BottomWorkspaceView.swift`、`Views/SidebarSyncSection.swift` |
| 检查器 | `Views/InspectorView.swift`、`Views/InspectorSelectionHeader.swift`、`Views/InspectorSettingsPanel.swift` |
| 状态机 / 能力判定 | `Stores/StudioModel.swift` |
| 数据模型（同步模式/分辨率/帧率/尺寸） | `Models/StudioModels.swift` |
| 菜单与快捷键 | `App/OverlayStudioApp.swift` |
| 四语言文案 | `Support/Localization.swift` |
| 天气服务 / 视频帧 | `Services/OpenWeatherService.swift`、`Services/VideoFrameService.swift` |
| 购买校验 | `Views/PurchaseAuthorizationGate.swift`、`Support/PurchaseAuthorization.swift` |
