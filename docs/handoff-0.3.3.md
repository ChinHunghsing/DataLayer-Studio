# 0.3.3 版本交接文档

> 写给接手 0.3.3 发布的智能体。开工前先读根目录 `AGENTS.md`（全部流程约定都在那里），再读本文档。
> 本文档描述的是 2026-07-15 的状态；按 AGENTS.md 约定，若仓库现状与本文不符，以当前可验证事实为准。

## 一、0.3.3 是什么

0.3.3 是 0.3.2（2026-07-13 上架）之后的编辑体验补丁版，无新增大功能。定位：

- 空白片段编辑能力（选择、删除、定点粘贴）与常驻虚线样式
- 播放头位置与天气数据持久化进 `.dlsproj` 工程
- 距离单位切换相关三个缺陷修复
- 0.3.2 发版审核遗留的五项清理（见下节）

范围已冻结。明确不做：不动 `OverlayCore` 渲染/写出管线与透明 Alpha 路径、不动购买/签名逻辑、不做移动端内容、controlSize 分层继续推迟。

## 二、开发状态：已全部完成

### v0.3.2 之后合入 main 的功能与修复（发布说明素材）

- 空白片段编辑：时间线空白区可选择、删除、定点粘贴（`1aea5c0`）
- 空白片段常驻虚线样式与标识（`7982f6b`）
- 播放头与天气持久化进工程文件（`1aea5c0`）
- 自动对表片段不再显示特殊标线与徽章（`f087569`）
- 移除画布选中元素黄色框（`3de26d7`）
- 修复：距离仪表切换单位不生效（`f09e39b`）、首次加载后单位切换不刷新预览（`5b36a1c`）、默认距离面板未绑定活动片段（`4e411e9`）

### 0.3.2 审核遗留五项清理（2026-07-15 完成）

1. **播放头吸附怪癖**：拖离起点后拖回，起点在本次拖动内不再吸附。修复方式：起点排除只在播放头未离开起点时生效，一旦拖出吸附阈值即解除（`ProjectTimelineView.playheadScrubEscapesStart` + `playheadScrubHasEscapedStart` 状态）。测试：`testProjectTimelinePlayheadScrubSnapsBackToStartAfterEscapingIt`。
2. **setStatus 出口**：`setStatus`/`setStatusAndToast` 现在统一写入调试控制台（新增 `DebugLogCategory.status`，四语言 `debug.category.status` 已补）。15 处无就地出口的用户级消息升级为 toast（预设保存/导入导出错误、工程保存/加载错误、媒体重链接结果、手动录制时间、导出前置校验失败等）。保持沉默的原则：有就地出口（天气 `weatherRefreshMessage`、导出 sheet 三态、素材库失败行）或结果自明（片段分割/删除、拖放上轨）的不弹 toast。
3. **内置导出预设 name 双份**：`ExportPreset.builtIn` 不再硬编码英文名（`name: ""`），显示名统一走 `localizedNameKey`/`displayName(localize:)`，唯一来源是 `Localization.swift` 的 `exportPreset.builtin.*`。用户预设 Codable 结构未变，向后兼容。测试：`testBuiltInExportPresetNamesComeFromLocalizationOnly`。
4. **ShellStyle 死令牌**：删除无调用方的 `fontXS/fontSmall/fontBody/fontTitle` 与 `panelFill`。需要时再随真实调用点重新引入。
5. **重复保护逻辑**：时间线吸附阈值 `isSnappingEnabled ? Double(6 / laneWidth) * duration : 0` 在 5 处重复（3 处漏了 `laneWidth > 0` 防护），收敛为 `ProjectTimelineView.snapThreshold(laneWidth:duration:)`。

### 已完成的验证

- 全量 `swift test`：524 项全部通过（2026-07-15）
- `scripts/build_app_bundle.sh` 构建成功
- 建议接手后人工走查一次：时间线标尺拖动播放头（离开吸附点→拖回能重新吸附）、导出中心内置预设四语言名称、导出前置校验失败的 toast。

## 三、剩余工作：发布流程

代码已冻结，剩下的全是发布操作。严格按 `AGENTS.md` 的流程约定执行，此处只列顺序和 0.3.3 特有信息：

1. **确认截图就绪**：`assets/appstore/v0.3.3/`（四语言 `desktop@2x` 各 3 张，2880×1800）。⚠️ 2026-07-15 下午有另一方在本机重新生成这批截图（工作区有未提交修改），接手时先 `git status` 确认这批文件已被制作方提交或确认状态，**不要替他们提交或还原**。
2. **What's New 四语言文案**：尚未撰写。围绕第二节的功能与修复写（空白片段编辑、工程状态持久化、单位切换修复、播放头吸附修复）。可用 `asc-whats-new-writer` skill。
3. **TestFlight**：按 AGENTS.md 的 TestFlight 流程逐条执行。版本号必须从 ASC 线上 train 确认（不要从本文推断）；构建号 `yyyyMMddNN`。当前 ASC 尚无 0.3.3 版本记录，train 需要先创建/确认。
4. **ASC 创建 0.3.3 版本并上传截图**：按 AGENTS.md 截图流程，每语言先 `validate` 再按 `<version-localization-id>` 上传 `desktop@2x`，只传 @2x，最后确认 `COMPLETE`。
5. **提审**：按 AGENTS.md 审核提交流程（加载 `app-store-review`/`app-store-optimization` skill，`release-type` 确认 `AFTER_APPROVAL`，validate → review doctor → dry-run → confirm → 确认 `WAITING_FOR_REVIEW`）。
6. **GitHub Release**：main CI 通过后打 `v0.3.3` tag 推送，`gh run watch` 确认 release workflow 成功，正文含 Highlights 与 `git log --oneline v0.3.2..v0.3.3` 完整列表，资产做脱沙箱三项验证（sha256 / codesign / stapler / spctl）。

## 四、注意事项与坑

- `asc`、`codesign`、`swift build` 在沙箱内会报 Keychain/TLS/权限假错误，脱沙箱重跑同一条命令即可，不要改项目配置（AGENTS.md 有明文约定）。
- 0.3.2 版式的原始截图在 `assets/screenshots_raw/v0.3.2/`，2026-07-15 曾被误覆盖后已还原，不要再动。
- `docs/ux-overhaul-0.3-plan.md` 第 230 行附近记录了 0.3.2 审核遗留清单，本次五项完成后该清单已清空；0.3 重构（0.3.0/0.3.1/0.3.2 三步）至此收尾。
- 播放头交互如再报问题，吸附核心都在 `ProjectTimelineView.swift`：候选生成 `snapResult`、阈值 `snapThreshold`、起点排除 `playheadScrubEscapesStart`。
- 新增 UI 文案必须同步四语言（`Localization.swift`），`LocalizationTests` 会检查 key 缺失。
