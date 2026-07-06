## 项目约定

- 对外名称统一写 `DataLayer Studio`。
- 官方 App Store URL：`https://apps.apple.com/cn/app/datalayer-studio/id6782545770`。
- Git 提交信息必须使用简体中文。
- 每次做修改前和提交前，都要先确认本地仓库已同步到远端最新 Git 版本；多人协作时至少执行 `git fetch` 并检查当前分支与上游分支没有落后。
- 完成代码或项目文件修改后，判断是否适合单独提交；适合就 `git commit` 并 `git push`。
- 涉及 CI 配置、CI 脚本、release workflow，或为修复 CI 而做的提交，推送后必须用 `gh run list` / `gh run watch` 确认对应 CI 成功。
- 修改会影响本地 App 可见行为时，完成后运行 `scripts/build_app_bundle.sh`。
- 支持 iOS、iPadOS 或任何其他平台时，必须保证 macOS 端既有功能、视觉表现、导出结果和构建/发布流程不回退；改共享层或平台条件编译后，至少跑 macOS 相关测试与 `scripts/build_app_bundle.sh`，必要时补充预览/渲染/导出对比验证。
- 移动端界面默认方向：iPadOS 按横屏优先开发与验收，iPhone 按竖屏优先开发与验收；除非用户明确要求，不要反过来设默认布局。
- iPadOS 开发与真机测试流程见 `docs/ipados-development-testing.md`；涉及真机签名、临时 Xcode 壳、`assets/resourses/` 本地素材时按该文档执行，不提交临时工程、设备素材或签名文件。
- 涉及 App Store Connect、TestFlight、审核、元数据、构建上传时，优先加载 `app-store-connect` skill 并使用已安装的 `asc`/脚本，不默认走网页手工流程。
- 发内部 TestFlight 时不要对内部组调用 `asc builds add-groups`；该接口只适合外部组。用 `asc builds build-beta-detail view` 确认 `Internal State = IN_BETA_TESTING` 即完成。
- App Store / TestFlight 构建号使用 `yyyyMMddNN`，例如 `2026062601`。
- TestFlight 流程：先 `git fetch` 并确认不落后；用 `asc doctor` 确认认证正常；先运行 `asc versions list --app 6782545770 --platform MAC_OS --output table` 查看 App Store Connect App Store 版本，再运行 `asc testflight pre-release list --app 6782545770 --platform MAC_OS --output table --paginate` 查看 TestFlight 线上 train，并把要发布的线上 train 作为 `<版本号>`，不要从脚本默认值、git tag、文档或记忆推断版本；用 `asc builds list --app 6782545770 --platform MAC_OS --version <版本号>` 查同版本最新构建号；显式传 `APP_VERSION=<版本号> APP_BUILD=<yyyyMMddNN>` 运行 `scripts/build_app_bundle.sh`；用 `.apple.env.local` 中的签名配置执行 `scripts/package_app_store_pkg.sh`；用 `asc builds upload --app 6782545770 --pkg <pkg> --version <版本号> --build-number <构建号> --wait` 上传；如果 ASC 提示构建号不够高，递增当天 NN 后重新构建和打包；内部 TestFlight 不要对内部组调用 `asc builds add-groups`，最后用 `asc builds build-beta-detail view --app 6782545770 --build-number <构建号> --version <版本号> --platform MAC_OS` 确认 `Internal State = IN_BETA_TESTING`；外部 TestFlight 只对外部组调用 `asc builds add-groups`，必要时补充 What to Test 并确认 Beta Review/外部分发状态。
- App Store 截图更新流程：先用 `asc versions list --app 6782545770 --platform MAC_OS --output table` 确认目标 `<版本号>`、`<version-id>` 和状态；截图目录使用 `assets/appstore/v<版本号>/<locale>/desktop@2x/`，macOS 桌面截图按 `APP_DESKTOP` 上传，优先用 2880x1800 的 `@2x` 图，不要同时上传 `desktop` 和 `desktop@2x` 两套以免重复；每个语言先跑 `asc screenshots validate --path assets/appstore/v<版本号>/<locale>/desktop@2x --device-type APP_DESKTOP --output table`；通过后用对应的 `<version-localization-id>` 执行 `asc screenshots upload --version-localization <version-localization-id> --path assets/appstore/v<版本号>/<locale>/desktop@2x --device-type APP_DESKTOP --replace --output table`；上传后用 `asc screenshots list --version-localization <version-localization-id> --output table` 确认每个语言截图数量正确且状态为 `COMPLETE`。
- App Store 审核提交流程：提交前加载 `app-store-review` 和 `app-store-optimization` skill；确认工作区已同步且目标构建已经处理完成并绑定到 `<version-id>`；运行 `asc validate --app 6782545770 --version-id <version-id> --platform MAC_OS --output table` 和 `asc review doctor --app 6782545770 --output table`，必须没有 blocking、errors、warnings；`release.type_manual`、`privacy.publish_state.unverified` 这类 info 不等于阻塞，但要确认 ASC 后台实际信息正确；用 `asc review details-for-version --version-id <version-id> --output table` 检查审核联系人、电话、邮箱、demo/notes；先跑 `asc review submit --app 6782545770 --version-id <version-id> --build <build-id> --platform MAC_OS --dry-run --output table`，确认 `wouldSubmit=true` 且 build 正确；正式提交用 `asc review submit --app 6782545770 --version-id <version-id> --build <build-id> --platform MAC_OS --confirm --output table`；提交后用 `asc review status --app 6782545770 --output table` 和 `asc versions view --version-id <version-id> --include-build --include-submission --output json --pretty` 确认进入 `WAITING_FOR_REVIEW` 或后续审核状态。
- ASC 命令需要访问 Keychain；如果沙箱里出现 `One or more parameters passed ... (-50)`，不要改项目参数，改在沙箱外执行同一条 `asc` 命令。
- GitHub Release 流程：先 `git fetch --tags` 并确认当前分支不落后、工作区干净、目标 tag 不存在；先让 `main` 的 CI 通过，再创建 `vX.Y.Z` tag 并 `git push origin vX.Y.Z`。
- `v*` tag 会触发 `.github/workflows/release.yml`：运行测试、构建、签名、公证，并创建/更新 GitHub Release，上传 zip 和 sha256。发布后必须用 `gh run list` / `gh run watch` 确认 release workflow 成功，再用 `gh release view <tag>` 核对资产；Release 正文必须包含 Highlights 和 `Full commit list since <上一版本>`，commit 列表用 `git log --oneline <上一tag>..<当前tag>` 生成，自动生成内容太短时发布后用 `gh release edit <tag> --notes-file <file>` 补齐。
- GitHub Release 资产必须做下载后验证：下载 zip、核对 sha256、解压后运行 `codesign --verify --deep --strict`、`xcrun stapler validate`、`spctl -a -vv -t exec`，三者都通过才算“用户可直接运行”。
- 在 Codex 沙箱内运行 `codesign` / `stapler` / `spctl` 可能对已签名公证的 GitHub 下载包给出假阴性（例如 `invalid signature`、`kLSDataUnavailableErr`、`internal error in Code Signing subsystem`）；Release 资产验证必须脱沙箱执行这三条命令，只有脱沙箱仍失败才修签名或重打包。
- release workflow 失败时，先修复并推送新提交，确认 `main` CI 通过后再处理 tag；不要无原因覆盖或移动已发布 tag。

## 项目结构

- `Sources/OverlayCore/`：核心库；FIT 解析、遥测序列、时间同步、布局模型、渲染、视频写出都在这里。这里不要依赖 SwiftUI。
- `Sources/OverlayStudio/`：macOS SwiftUI 图形界面；`Views/` 放界面，`Models/` 放状态模型，`Services/` 放外部服务，`Stores/` 放持久化，`Support/` 放本地化和辅助代码。
- `Sources/OverlayStudioKit/`：平台中立共享层（禁止 import AppKit/UIKit），macOS 与 iOS 共用。
- `Sources/OverlayTouch/`：iPadOS/iOS 界面层；iOS 专属代码用 `#if os(iOS)` 门控，macOS 构建必须始终通过；新增文案走 `TouchLocalization.swift` 四语言字典。
- `Sources/OverlayTouchHost/`：iOS 模拟器调试 App 壳（SwiftPM executable）；配套脚本 `scripts/build_touch_sim_app.sh`，流程见 `docs/ipados-development-testing.md`。
- `Sources/overlay/`：命令行入口。
- `Tests/OverlayCoreTests/`：核心逻辑、渲染、视频写出测试。
- `Tests/OverlayStudioTests/`：界面模型、设置、服务、本地化测试。
- `Tests/OverlayCLITests/`：命令行参数和布局预设测试。
- `Tests/OverlayTouchTests/`：iPad 会话模型与四语言文案测试（在 macOS 上运行）。
- `Resources/`：App 资源和权限配置。
- `assets/`：README、营销图、App Store 图片和赞助图片。
- `assets/resourses/`：本地验证素材目录，已被 `.gitignore` 忽略；可放一组视频与配套 FIT，当前这组 FIT 的开表时间是视频开始后第 49 秒。此目录只用于本机调试，不提交到 Git。
- `docs/`：产品、技术和本地开发测试文档；iPadOS 真机流程见 `docs/ipados-development-testing.md`。
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
- 改 `OverlayTouch`：跑 `OverlayTouchTests`，并按 `docs/ipados-development-testing.md` 跑一次 iPhoneOS/模拟器编译；改到共享层还要跑 macOS 回归。

## 代码风格

- 用 SwiftPM 和 Swift 5.9 现有写法；不要引入新依赖，除非用户明确要求且现有代码/系统 API 解决不了。
- 优先改共享根因，不在多个调用点复制同一保护逻辑。
- 保持小改动：只动当前需求必须触及的文件；不顺手重构无关代码。
- 新增布局字段必须保持 Codable 向后兼容，旧 preset 不能因为缺字段而加载失败。
- 新增 UI 文案必须同步更新英文、简体中文、繁体中文、日文四套本地化。
- 透明 HEVC/ProRes Alpha 路径要保守修改；不能重新引入透明区域发灰问题。
- 视频写出必须按帧流式处理，禁止把整段视频帧或大图缓存进内存。
- 文件和命令输出里不要使用千分位逗号作为可编辑数值格式。
- 前端/落地页左右展示图必须按实际展示尺寸优化分辨率，优先转成 WebP。
- 落地页正式站点是 `https://datalayer-studio.ligh-t-ouch.com`，Cloudflare Pages 项目是 `datalayer-studio`，生产分支是 `landing-page`；上线用 `wrangler pages deploy landing-page --project-name=datalayer-studio --branch=landing-page`，不要用 `--branch=main`，那只会发预览环境。
- 使用 Cloudflare 时只允许使用免费计划/免费额度内可用的功能；启用任何付费计划、付费 add-on、超额计费或可能产生账单的资源前，必须先明确告知并获得用户确认。

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
