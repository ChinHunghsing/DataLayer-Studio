# DataLayer Studio 项目约定

## 不可变约束

- 对外名称统一为 `DataLayer Studio`；Mac App Store：`https://apps.apple.com/cn/app/datalayer-studio/id6782545770`。
- Mac App Store 是付费完整版。GitHub Release、自编译与 CLI 为免费版：编辑/预览完整，导出限 1080p 且带 `Made with DataLayer Studio` 水印；限制由 `OverlayCore.ExportEntitlement` 和三个 writer 兜底，不得移除或绕过。
- 修改前和提交前先 `git fetch`，确认当前分支不落后上游；仓库、提交历史、项目文档或外部实查与记忆冲突时，以当前可验证事实为准。
- Git 提交信息使用简体中文。适合独立提交的改动完成验证后提交并推送；CI/release 改动推送后必须确认对应 GitHub Actions 成功。
- 不提交或输出 `.env.local`、`.apple.env.local`、私钥、证书/profile、API key、signedPayload、用户视频/FIT、导出物、`.build/`、`.colameta/`。
- 不执行会丢用户改动的命令；不修改第三方 App；未被要求时不更改签名、公证、购买校验或商店提交状态。
- Cloudflare 仅用免费计划/额度；任何可能计费的能力必须先获得用户确认。

## 项目专属 Skills

按任务加载仓库内 skill，详细流程只在触发时进入上下文：

- `.agents/skills/dls-telemetry`：FIT/GPX、遥测、配速、距离、暂停与锚点。
- `.agents/skills/dls-timeline`：时间线、媒体池、工程格式、Undo/Redo、预览一致性。
- `.agents/skills/dls-export`：writer、Alpha、合成、内存、时长与导出权益。
- `.agents/skills/dls-ios`：OverlayTouch、iPad/iPhone、StoreKit、模拟器/真机与 macOS 回归。
- `.agents/skills/dls-app-store`：ASC、TestFlight、截图、签名打包与提审。
- `.agents/skills/dls-github-release`：tag、release workflow、Release 正文与下载资产验收。
- `.agents/skills/dls-marketing`：官网、README、用户手册、宣传图、四语言与 Pages 部署。

## 代码边界

- `Sources/OverlayCore/`：平台中立核心；不得依赖 SwiftUI。
- `Sources/OverlayStudioKit/`：macOS/iOS 共享层；不得 import AppKit/UIKit。
- `Sources/OverlayStudio/`：macOS SwiftUI App；状态集中在 `Stores/`，界面放 `Views/`。
- `Sources/OverlayTouch/` 与 `Sources/OverlayTouchHost/`：iOS UI 和 SwiftPM 调试壳；正式壳在 `App/DataLayerStudioMobile.xcodeproj`。
- `Sources/overlay/`：CLI；测试按 `OverlayCoreTests`、`OverlayStudioTests`、`OverlayCLITests`、`OverlayTouchTests` 对应。
- 本地真实素材仅放已忽略的 `assets/resourses/`，不进 Git。

## 开发规则

- 使用 SwiftPM / Swift 5.9 现有写法；先复用现有 helper、系统 API 与依赖，不为单次需求新增抽象或依赖。
- 修共享根因，完整检查调用者；只改需求必需文件，不顺手重构。
- 新增 Codable 字段保持旧 preset/工程兼容；新增 UI 文案同步英文、简中、繁中、日文。
- 视频写出逐帧流式处理；透明 HEVC/ProRes Alpha 不得回退；可编辑数值不使用千分位逗号。
- 支持新平台不得回退 macOS；iPad 横屏优先、iPhone 竖屏优先。

## 验证与交付

- 非平凡逻辑补最小回归测试；先跑相关 filter，能跑时再跑 `swift test`。
- 影响 App 可见行为运行 `scripts/build_app_bundle.sh`；涉及共享层/跨平台时按对应 skill 补 macOS 与 iOS 回归。
- 提交前再次确认同步状态与 `git status --short`，只提交本次文件。
- 最终回复说明改动、验证、提交/推送状态和剩余风险。
- Review 先按严重程度列具体文件/行号；优先检查数据丢失、隐私、签名/上架、Alpha、内存、导出和旧工程/CLI 兼容。无问题时输出 `✅OK`，并说明未覆盖测试风险。
