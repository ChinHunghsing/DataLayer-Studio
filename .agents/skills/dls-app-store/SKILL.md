---
name: dls-app-store
description: 操作 DataLayer Studio 的 App Store Connect、macOS TestFlight、App Store 构建、签名打包、provisioning profile、四语言截图、元数据、审核提交与 App Store Server 数据。用户要求上传构建、发内外测、更新商店截图、提审、上线，或修改 scripts/package_app_store_pkg.sh 和相关发布配置时使用。
---

# DataLayer Studio App Store

## 授权与事实来源

- 同时加载通用 `app-store-connect` skill；提审再加载 `app-store-review` 与 `app-store-optimization`。
- App ID 为 `6782545770`，平台为 `MAC_OS`，构建号为 `yyyyMMddNN`。
- 版本、train、构建、截图和审核状态只信 `asc` 当前查询，不从脚本默认值、tag、文档或记忆推断。
- 查询可以直接执行；上传、分发、替换截图和正式提交只在用户明确要求对应外部变更时执行。
- 不输出 `.env.local`、`.apple.env.local`、私钥、profile 内容、signedPayload 或任何 secret。

## TestFlight

1. `git fetch`，确认当前分支不落后；运行 `asc doctor`。
2. 运行：

```bash
asc versions list --app 6782545770 --platform MAC_OS --output table
asc testflight pre-release list --app 6782545770 --platform MAC_OS --output table --paginate
asc builds list --app 6782545770 --platform MAC_OS --version <版本号>
```

3. 取线上 train，显式传 `APP_VERSION=<版本号> APP_BUILD=<yyyyMMddNN>` 运行 `scripts/build_app_bundle.sh`。
4. 用 `.apple.env.local` 的签名配置运行 `scripts/package_app_store_pkg.sh`，再执行：

```bash
asc builds upload --app 6782545770 --pkg <pkg> --version <版本号> --build-number <构建号> --wait
```

5. 构建号过低时递增当日 NN，重新构建和打包。内部组不要调用 `asc builds add-groups`；运行下列命令确认 `Internal State = IN_BETA_TESTING`。只有外部组使用 `add-groups`，并检查 What to Test、Beta Review 和外部分发状态。

```bash
asc builds build-beta-detail view --app 6782545770 --build-number <构建号> --version <版本号> --platform MAC_OS
```

## 签名与 profile

- `.apple.env.local` 缺 `APP_STORE_PROVISIONING_PROFILE` 时，用 `asc profiles list --paginate` 找 ACTIVE 的 Mac App Store profile，下载后 `asc profiles inspect`，确认 bundle 与 capabilities，再显式传路径给打包脚本；已存在则优先复用并 inspect。
- `asc` Keychain 的 `(-50)`、Swift/Clang cache、codesign/stapler/spctl 异常先脱沙箱重跑同一命令，不先改项目参数、签名或 entitlement。

## 商店截图

1. 用 `asc versions list` 确认 `<版本号>`、`<version-id>` 与状态。
2. 每语言仅使用 `assets/appstore/v<版本号>/<locale>/desktop@2x/` 的 2880×1800 图，设备类型 `APP_DESKTOP`；不要同时上传 `desktop` 和 `desktop@2x`。
3. 每语言依次运行并确认数量与 `COMPLETE`：

```bash
asc screenshots validate --path assets/appstore/v<版本号>/<locale>/desktop@2x --device-type APP_DESKTOP --output table
asc screenshots upload --version-localization <version-localization-id> --path assets/appstore/v<版本号>/<locale>/desktop@2x --device-type APP_DESKTOP --replace --output table
asc screenshots list --version-localization <version-localization-id> --output table
```

## 提审

默认审核通过后自动发布。确认目标构建已处理并绑定版本后依次运行：

```bash
asc versions update --version-id <version-id> --release-type AFTER_APPROVAL
asc validate --app 6782545770 --version-id <version-id> --platform MAC_OS --output table
asc review doctor --app 6782545770 --output table
asc review details-for-version --version-id <version-id> --output table
asc review submit --app 6782545770 --version-id <version-id> --build <build-id> --platform MAC_OS --dry-run --output table
asc review submit --app 6782545770 --version-id <version-id> --build <build-id> --platform MAC_OS --confirm --output table
```

validate/doctor 必须无 blocking、errors、warnings；`privacy.publish_state.unverified` 一类 info 需核对后台但不自动视为阻塞。正式提交后用 `asc review status` 和 `asc versions view --include-build --include-submission` 确认进入 `WAITING_FOR_REVIEW` 或后续状态。

## Server 数据

`JWSTransactionDecodedPayload.price` 是 milliunits，展示前除以 `1000`；`currency` 是 ISO 4217，只用于金额显示，地区读取 `storefront`。
