# 0.3.3 版本交接文档

> **归档说明（2026-07-16）**：本文交接的 0.3.3 发布已完成——App Store 版本 0.3.3 已上架（`READY_FOR_DISTRIBUTION`，2026-07-16 经 `asc` 实查），第三节所列 ASC 剩余工作不再成立。**唯一未完成事项：GitHub Release v0.3.3 截至归档时尚未发布（最新 tag 为 v0.3.2）**，如需补发按 `AGENTS.md` 的 GitHub Release 流程执行。第二节末尾的体验债务（复制片段可见反馈、完整视觉令牌、controlSize 分层）仍然有效。以下正文为 2026-07-15 的历史状态，仅供追溯。

> 写给接手 0.3.3 发布的智能体。开工前先读根目录 `AGENTS.md`（全部流程约定都在那里），再读本文档。
> 本文档描述的是 2026-07-15 的状态；按 AGENTS.md 约定，若仓库现状与本文不符，以当前可验证事实为准。

## 一、0.3.3 是什么

0.3.3 是 0.3.2（2026-07-13 上架）之后的编辑体验补丁版，无新增大功能。定位：

- 空白片段编辑能力（选择、删除、定点粘贴）与常驻虚线样式
- 播放头位置与天气数据持久化进 `.dlsproj` 工程
- 距离单位切换相关三个缺陷修复
- 0.3.2 发版审核遗留的五项清理（见下节）

范围已冻结。明确不做：不动 `OverlayCore` 渲染/写出管线与透明 Alpha 路径、不动购买/签名逻辑、不做移动端内容、controlSize 分层继续推迟。

## 二、开发状态：0.3.3 范围已完成，仍有已知体验债务

### v0.3.2 之后合入 main 的功能与修复（发布说明素材）

- 空白片段编辑：时间线空白区可选择、删除、定点粘贴（`1aea5c0`）
- 空白片段常驻虚线样式与标识（`7982f6b`）
- 播放头与天气持久化进工程文件（`1aea5c0`）
- 自动对表片段不再显示特殊标线与徽章（`f087569`）
- 移除画布选中元素黄色框（`3de26d7`）
- 修复：距离仪表切换单位不生效（`f09e39b`）、首次加载后单位切换不刷新预览（`5b36a1c`）、默认距离面板未绑定活动片段（`4e411e9`）

### 0.3.2 审核遗留五项处理状态（2026-07-15）

1. **播放头吸附怪癖**：拖离起点后拖回，起点在本次拖动内不再吸附。修复方式：起点排除只在播放头未离开起点时生效，一旦拖出吸附阈值即解除（`ProjectTimelineView.playheadScrubEscapesStart` + `playheadScrubHasEscapedStart` 状态）。测试：`testProjectTimelinePlayheadScrubSnapsBackToStartAfterEscapingIt`。
2. **setStatus 出口**：`setStatus`/`setStatusAndToast` 现在统一写入应用内调试控制台（新增 `DebugLogCategory.status`，四语言 `debug.category.status` 已补）；同步写入系统日志时消息使用 private 隐私级别，不公开文件路径和错误详情。15 处无就地出口的用户级消息升级为 toast（预设保存/导入导出错误、工程保存/加载错误、媒体重链接结果、手动录制时间、导出前置校验失败等）。仍有一项已知体验债务：复制时间线片段只写状态，没有用户可见 toast。
3. **内置导出预设 name 双份**：`ExportPreset.builtIn` 不再硬编码英文名（`name: ""`），显示名统一走 `localizedNameKey`/`displayName(localize:)`，唯一来源是 `Localization.swift` 的 `exportPreset.builtin.*`。用户预设 Codable 结构未变，向后兼容。测试：`testBuiltInExportPresetNamesComeFromLocalizationOnly`。
4. **ShellStyle 死令牌**：删除无调用方的 `fontXS/fontSmall/fontBody/fontTitle` 与 `panelFill`。这只是清理死代码，不代表 4.9 的完整视觉令牌与 `controlSize` 分层已经实现；两项均继续作为后续体验债务。
5. **重复保护逻辑**：时间线吸附阈值 `isSnappingEnabled ? Double(6 / laneWidth) * duration : 0` 在 5 处重复（3 处漏了 `laneWidth > 0` 防护），收敛为 `ProjectTimelineView.snapThreshold(laneWidth:duration:)`。

### 已完成的验证

- 全量 `swift test`：524 项全部通过（2026-07-15）
- 系统日志隐私修复后 `swift test --filter StudioModelTests`：108 项全部通过（2026-07-15）
- `scripts/build_app_bundle.sh` 构建成功
- 建议接手后人工走查一次：时间线标尺拖动播放头（离开吸附点→拖回能重新吸附）、导出中心内置预设四语言名称、导出前置校验失败的 toast。

## 三、App Store Connect 当前状态与剩余工作

以下状态已于 2026-07-15 通过 `asc` 实查：

1. **ASC 版本**：macOS 0.3.3 已创建，状态为 `PREPARE_FOR_SUBMISSION`，version id 为 `2550366f-e8fe-48c7-b78b-a90a5596ec9d`；尚未绑定 App Store 审核构建，也未提交审核。
2. **元数据与截图**：`en-US`、`zh-Hans`、`zh-Hant`、`ja` 的描述、关键词、宣传文本与 What's New 已填写；每语言 3 张 `APP_DESKTOP` 截图均为 `COMPLETE`。本地素材位于 `assets/appstore/v0.3.3/`，当前主工作区无未提交截图。
3. **内部 TestFlight**：0.3.3 构建 `2026071502` 已上传且为 `VALID`，`Internal State = IN_BETA_TESTING`；该构建包含系统日志隐私修复。`2026071501` 为上一内部构建。
4. **App Store 审核构建**：`2026071502` 已可用，但尚未绑定到 0.3.3 App Store 版本；提审前绑定该构建并完成发布前检查。
5. **提审**：按 `AGENTS.md` 审核流程执行；发布方式确认 `AFTER_APPROVAL`，完成 validate、review doctor、dry-run、正式提交并确认进入 `WAITING_FOR_REVIEW` 或后续状态。
6. **GitHub Release**：尚未发布 v0.3.3。main CI 通过后打 tag，确认 release workflow 成功并完成下载资产验证。

## 四、注意事项与坑

- `asc`、`codesign`、`swift build` 在沙箱内会报 Keychain/TLS/权限假错误，脱沙箱重跑同一条命令即可，不要改项目配置（AGENTS.md 有明文约定）。
- 0.3.2 版式的原始截图在 `assets/screenshots_raw/v0.3.2/`，2026-07-15 曾被误覆盖后已还原，不要再动。
- `docs/archive/ux-overhaul-0.3-plan.md` 第 230 行附近记录了当前遗留：复制片段的可见反馈、完整视觉令牌与 `controlSize` 分层尚未完成，均不阻塞 0.3.3 的既定修复范围。
- 播放头交互如再报问题，吸附核心都在 `ProjectTimelineView.swift`：候选生成 `snapResult`、阈值 `snapThreshold`、起点排除 `playheadScrubEscapesStart`。
- 新增 UI 文案必须同步四语言（`Localization.swift`），`LocalizationTests` 会检查 key 缺失。
