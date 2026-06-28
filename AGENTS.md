## 项目约定

- 对外名称统一写 `DataLayer Studio`。
- Git 提交信息必须使用简体中文。
- 完成代码或项目文件修改后，判断是否适合单独提交；适合就 `git commit` 并 `git push`。
- 涉及 CI 配置、CI 脚本、release workflow，或为修复 CI 而做的提交，推送后必须用 `gh run list` / `gh run watch` 确认对应 CI 成功。
- 修改会影响本地 App 可见行为时，完成后运行 `scripts/build_app_bundle.sh`。
- 涉及 App Store Connect、TestFlight、审核、元数据、构建上传时，优先加载 `app-store-connect` skill 并使用已安装的 `asc`/脚本，不默认走网页手工流程。
- App Store / TestFlight 构建号使用 `yyyyMMddNN`，例如 `2026062601`。

## 项目结构

- `Sources/OverlayCore/`：核心库；FIT 解析、遥测序列、时间同步、布局模型、渲染、视频写出都在这里。这里不要依赖 SwiftUI。
- `Sources/OverlayStudio/`：macOS SwiftUI 图形界面；`Views/` 放界面，`Models/` 放状态模型，`Services/` 放外部服务，`Stores/` 放持久化，`Support/` 放本地化和辅助代码。
- `Sources/overlay/`：命令行入口。
- `Tests/OverlayCoreTests/`：核心逻辑、渲染、视频写出测试。
- `Tests/OverlayStudioTests/`：界面模型、设置、服务、本地化测试。
- `Tests/OverlayCLITests/`：命令行参数和布局预设测试。
- `Resources/`：App 资源和权限配置。
- `assets/`：README、营销图、App Store 图片和赞助图片。
- `scripts/`：本地 app bundle 构建、签名、公证、校验脚本。
- `.github/`：CI、issue 模板、PR 模板。

## 常用命令

- 构建调试产物：`swift build`
- 构建 CLI：`swift build -c release --product overlay`
- 构建本地可打开 App：`scripts/build_app_bundle.sh`
- 打开本地 App：`open ".build/DataLayer Studio.app"`
- 查看 CLI 参数：`swift run overlay --help`
- 校验 app bundle：`scripts/verify_app_bundle.sh`
- 校验开源发布准备：`scripts/verify_source_available_readiness.sh`

## 测试命令

- 全量测试：`swift test`
- 只跑某类测试：`swift test --filter OverlayCoreTests.OverlayRendererTests`
- 改 FIT 解析或遥测插值：至少跑 `FITParserTests`、`TelemetrySeriesTests`。
- 改导出、透明通道、合成视频：至少跑 `TransparentVideoWriterTests`、`CompositedVideoWriterTests`、`OverlayRendererTests`。
- 改 UI 状态、导出设置、预设、天气：至少跑相关 `OverlayStudioTests`。
- 改 CLI 参数：跑 `OverlayCLITests`。

## 代码风格

- 用 SwiftPM 和 Swift 5.9 现有写法；不要引入新依赖，除非用户明确要求且现有代码/系统 API 解决不了。
- 优先改共享根因，不在多个调用点复制同一保护逻辑。
- 保持小改动：只动当前需求必须触及的文件；不顺手重构无关代码。
- 新增布局字段必须保持 Codable 向后兼容，旧 preset 不能因为缺字段而加载失败。
- 新增 UI 文案必须同步更新英文、简体中文、繁体中文、日文四套本地化。
- 透明 HEVC/ProRes Alpha 路径要保守修改；不能重新引入透明区域发灰问题。
- 视频写出必须按帧流式处理，禁止把整段视频帧或大图缓存进内存。
- 文件和命令输出里不要使用千分位逗号作为可编辑数值格式。

## 禁止事项

- 不修改 `/Applications/Telemetry Overlay.app` 或任何第三方 app。
- 不提交 `.env.local`、`.apple.env.local`、私钥、证书私钥、provisioning profile、API key、用户视频、FIT、导出视频、`.build/`、`.colameta/`。
- 不在回答、日志或测试输出中打印密钥、signedPayload、App Store 私钥内容。
- 不执行 `git reset --hard`、`git checkout --` 等会丢用户改动的命令，除非用户明确要求。
- 不为了“以后可能用”新增抽象、配置、工厂、协议或依赖。
- 不在未被要求时更改签名、公证、购买校验、App Store 提交状态。

## 完成标准

- 功能改动有最小可运行验证；非平凡逻辑要有测试或更新现有测试。
- `swift test` 能跑就跑；跑不了必须说明原因。
- 影响 GUI 或 app bundle 的改动要重新执行 `scripts/build_app_bundle.sh`。
- 影响导出、签名、公证、TestFlight、App Store 的改动要额外跑对应校验脚本或说明未跑原因。
- 提交前确认 `git status --short`，只提交本次相关文件。
- 最终回复说明：改了什么、跑了什么验证、是否已提交/推送、剩余风险。

## Review 标准

- Review 先列问题，按严重程度排序，附具体文件和行号。
- 优先看：数据丢失、隐私泄露、签名/上架风险、透明 Alpha 回归、内存暴涨、导出错误、旧 preset/CLI 兼容性、缺测试。
- 不把个人风格当问题；只提会导致 bug、维护风险或用户体验回退的点。
- 没发现问题时明确说“未发现阻塞问题”，并列出未覆盖的测试风险。

## App Store Server 数据

- App Store Server API / Server Notification 的 `JWSTransactionDecodedPayload.price` 是 milliunits，展示前必须除以 `1000`。
- `currency` 是 ISO 4217 三字母代码；优先展示为 `金额 CODE（中文货币名称）`。
- 不用 `currency` 推断 storefront；需要地区时读取交易里的 `storefront`。
- 本地 ASC / App Store Server API 变量在 `.env.local`；只读取，不打印。
