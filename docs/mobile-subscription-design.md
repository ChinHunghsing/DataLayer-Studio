# DataLayer Studio 移动端订阅制方案（iPad / iPhone）

| 项目 | 内容 |
| --- | --- |
| 状态 | **已定**（2026-07-07 拍板，进入实施；原「三端 Universal Purchase 统一买断」决策废止） |
| 日期 | 2026-07-07 |
| 适用平台 | iOS / iPadOS（iPad 与 iPhone 为同一 iOS App）；macOS 版**完全不动** |
| 已定参数 | 月付 **$1.99**；年付 **$19.99**（≈10 个月价）；新用户免费试用 7 天；Mac 买断用户送 3 个月订阅码（发码 v1 人工渠道）；Family Sharing 不开启；iOS bundle id `run.libo.datalayer-studio.mobile`；免费层 = 编辑/预览全免费、导出需订阅；macOS 维持买断不动 |
| 关联文档 | `docs/ipad-product-design.md`、`docs/ipad-technical-design.md`、`docs/iphone-product-design.md` |

## 0. 结论摘要

- **必须把 iOS 版做成独立 App record（新 bundle id），不能加入现有 Mac 的 App record（6782545770）。** App Store 的 App 价格是按 App record 设置的、跨平台共享一个价格；同一 record 里做不到「Mac 收费下载 + iOS 免费下载」。
- iOS 版：免费下载；单一订阅组、两档 SKU——**月付 $1.99、年付 $19.99（约 10 个月价，省 2 个月）**；「新用户免费一周」用订阅的**推介优惠（Introductory Offer：7 天免费试用）**实现（两档均配），资格由 Apple 按「每个 Apple 账户 × 每个订阅组一次」自动判定，无需自建新用户识别。
- **Mac 买断用户补偿（已定）**：送 3 个月免费订阅，用 ASC 订阅 **Offer Code** 实现（免费型 / 时长 3 个月），发放机制见 §1.7。
- 免费层建议：**导入/对表/排布/预览全部免费，导出成片需要有效订阅（含试用期）**。转化点放在导出，审核友好（免费 App 有实际可用性）、试用价值感知最强。
- 客户端纯 StoreKit 2 实现（`Transaction.currentEntitlements` + `Transaction.updates`），不引入服务器依赖；App Store Server Notifications V2 仅作运营统计（可选，复用现有 `.env.local` 基建）。
- 布局预设 iCloud 同步**不受拆分 record 影响**：iCloud KVS 标识是 entitlement 层概念，同一开发团队下不同 App 可声明同一标识共享数据。
- **时间窗口红线：在本方案定稿前，绝不能把 iOS platform 添加进现有 App record**——Universal Purchase 挂接是单向操作，一旦挂上就无法拆出独立定价。目前 iOS 未上架、未挂接，拆分零成本。

## 1. 商业模式设计（产品）

### 1.1 三端模式总览

| | macOS | iPad / iPhone（同一 iOS App） |
| --- | --- | --- |
| App record | 现有 6782545770，**不动** | **新建**（新 bundle id） |
| 获取方式 | 付费下载（买断），另有 GitHub 公证版直下渠道 | 免费下载 |
| 解锁模式 | 一次买断全功能（现状 `PurchaseAuthorizationStore` 不变） | 自动续订订阅：月付 $1.99 / 年付 $19.99（≈10 个月价） |
| 新用户优惠 | — | 7 天免费试用（推介优惠，两档均配，自动续订前可随时取消）；Mac 买断用户另有 3 个月 Offer Code（§1.7） |
| 免费能力 | —（买断即全量） | 导入、对表、排布、实时预览全量免费；导出需订阅 |
| iPad/iPhone 互通 | — | 同一 App、同一订阅，天然双端通用 |

两档 SKU 同组同级（服务内容一致，仅计费周期不同）：Paywall 默认高亮年付并标注「相当于 10 个月价」；组内升降级由系统按比例结算，无需自建逻辑。

### 1.2 为什么必须拆分 App record（方案对比）

| 方案 | 做法 | 结论 |
| --- | --- | --- |
| A. 同 record + Universal Purchase（原计划） | iOS 加入 6782545770 | **不可行**：record 只有一个价格，Mac 收费则 iOS 也收费下载；且无法对下载收费的 App 叠加「订阅解锁核心功能」的合理结构 |
| B. 同 record，整体转免费 + Mac 改内购买断 | record 转免费；Mac 用非消耗型 IAP 买断，老用户按 `AppTransaction.originalAppVersion` 豁免 | 可行但**违背「macOS 保持买断制现状」**：要动 Mac 购买路径、老用户豁免逻辑、GitHub 渠道说明，回归风险大 |
| **C. 拆分 record（推荐）** | Mac record 不动；iOS 新建 record、免费 + 订阅 | Mac 零改动零风险；iOS 商业模型完全自由；代价是放弃「一次购买三端」叙事（§1.5） |

**采纳 C。**

### 1.3 免费层与订阅权益

推荐切法（转化点 = 导出）：

- **免费（无订阅）**：导入视频/FIT/GPX、三种对表、全部 21 种组件排布与定制、实时预览、布局预设（含 iCloud 同步）。即：完整体验产品价值，只是带不走成片。
- **订阅（含试用期）**：导出合成成片（全部分辨率/帧率/码率档位，不做二级阉割）、以及后续新增的增值能力默认归入订阅侧。

备选对比（记录否决理由）：

| 备选 | 否决理由 |
| --- | --- |
| 全功能锁（无订阅进不了编辑器） | 免费 App 无可用性，审核风险 + 获客漏斗差，试用前无法感知价值 |
| 导出带水印（免费可导） | 运动创作者对成片水印反感度高，产出物会带着水印在社交平台传播，损品牌 |
| 限制分辨率（免费 720p） | 档位阉割解释成本高，和「导出锁」相比转化并不更好 |

### 1.4 试用设计（新用户免费一周）

- 机制：**月付与年付两个 SKU 均配置推介优惠 → Free Trial → 1 周**。用户点「开始免费试用」即完成订阅（试用期 $0），第 8 天起按所选档位自动续订（$1.99/月或 $19.99/年），期间可随时在系统订阅管理里取消。
- 资格：Apple 自动管控，**每个 Apple 账户在该订阅组只享一次**；卸载重装、换设备不重置。客户端用 `product.subscription.introductoryOffer` + `isEligibleForIntroOffer` 区分显示「免费试用 7 天，之后 ¥X/月」或「¥X/月」。
- 触发时机：**首次点「导出」时弹 Paywall**（价值先行），设置页常驻订阅入口。不做首启强制弹窗。
- 文案红线（审核 3.1 要求）：试用按钮附近必须完整写明「试用 7 天后自动续订 ¥X/月，可随时取消」、恢复购买入口、管理订阅入口、EULA 与隐私政策链接。

### 1.5 对既有决策的影响与用户沟通

- **废止**「已定：付费买断，统一定价，一次购买 Mac / iPad / iPhone 三端使用（Universal Purchase）」。采纳本方案后需同步修订 §6 所列文档。
- Mac 买断用户在 iOS 上**需要另行订阅**。沟通策略：
  - 定位话术：Mac 是「一次买断的专业工作台」，移动端是「按需订阅的随身出片工具」，两条产品线各自定价；
  - 预设 iCloud 同步仍然三端互通（免费能力），Mac 用户不订阅也能在 iPad 上继续调布局、预览，只是导出需订阅；
  - **补偿（已定）**：Mac 买断用户送 3 个月免费订阅（Offer Code），机制与发放见 §1.7。
- App Store 元数据、落地页、README 的「一次购买三端使用」表述在采纳后全部更新。

### 1.6 定价（已定）

- **月付 $1.99 / 年付 $19.99**（美元为基准价；年付 ≈ 10 个月价，Paywall 标注「省 2 个月」）。
- 其他地区价格由 Apple 价格点表按基准价自动换算生成（非待决策项，是 S3 的操作步骤）：建好 SKU 后查看中国区/日本区自动生成的数字，若观感别扭（如非 ¥x8/¥x9 习惯价），在 ASC 里对该地区手动覆盖为邻近价格点即可。
- 已加入 App Store Small Business Program 的话佣金 15%，净收入按此测算。

### 1.7 Mac 买断用户补偿：3 个月 Offer Code（已定）

- ASC 配置：订阅 Offer Code → 免费型（Free）→ 时长 3 个月 → 资格勾选新订阅者/已流失订阅者（覆盖 Mac 用户首次领取与回流）；月付 SKU 上配置即可（3 个月免费后按 $1.99/月续订，可随时取消）。
- 兑换路径：App 内 `presentOfferCodeRedeemSheet`（iOS 16+）+ App Store「兑换代码」通用入口。
- 发放机制（**已定：v1 人工，2026-07-07**）：一次性码（one-time use）分批生成；Mac App 在购买校验通过（`PurchaseAuthorizationStore.state == .allowed` 且有收据）时显示「领取 iOS 3 个月订阅」入口，引导邮件/表单申请，人工核对后发码。启动成本为零。
  - 远期备选（量大再评估，届时另行确认）：Cloudflare Worker 自动发码——Mac App 提交 `AppTransaction` JWS，Worker 用 App Store Server API 验签后从 KV 码池发码（复用 `.env.local` 凭据；启用前按项目约定确认 Cloudflare 免费额度）。
- 注意：Offer Code 有配额（每 App 每季度上限 150,000 个），一次性码有有效期（生成后约 6 个月），按季度小批量滚动生成；**不用公开自定义码**（会泄漏被任意兑换）。
- GitHub 直下版 Mac 用户无收据、无法在线核验，走人工渠道个案处理（量极小）。

## 2. 用户体验（产品）

### 2.1 Paywall

- 用系统 `SubscriptionStoreView`（iOS 17+，本项目最低 26）实现，视觉跟随 App 深色气质做轻定制；两档 SKU 并列，默认高亮年付（标注「相当于 10 个月价 · 省 2 个月」）。
- 内容：权益列表（导出全档位成片 + 后续增值项）、试用条款全文、价格与周期、恢复购买、管理订阅、**兑换代码入口（Offer Code，供 Mac 用户领取的 3 个月码）**、EULA/隐私链接。
- 入口：① 无有效订阅时点「导出」→ paywall sheet；② 设置页「订阅」分区常驻。

### 2.2 订阅状态的 UI 表达

- 设置页显示当前状态：试用中（剩余天数）/ 已订阅（下次续订日）/ 未订阅 / 宽限期（提示更新支付方式）。
- 到期降级：编辑器不锁、工程不丢，仅导出按钮回到「需订阅」态——沿用「禁用即说明原因」原则，按钮下内联一行说明 + 直达 paywall。
- 导出中订阅过期（跨天长导出边界）：**当次导出不中断**，完成后再降级。

### 2.3 恢复与管理

- 「恢复购买」= `AppStore.sync()` 后重扫 entitlements（换设备/重装场景）。
- 「管理订阅」= `AppStore.showManageSubscriptions(in:)`（取消、改支付方式都在系统层完成）。
- 退款走 Apple 标准流程，App 内不做客服通道，FAQ 链接落地页。

### 2.4 新增文案（四语言，`TouchLocalization.swift`）

关键 key（en/zh-Hans/zh-Hant/ja 四表同步，测试拦截漏改）：`paywall.title`、`paywall.feature.export`、`paywall.trial.cta`（免费试用 7 天）、`paywall.trial.terms`（试用后自动续订说明）、`paywall.subscribe.cta`、`paywall.restore`、`paywall.manage`、`paywall.eula` / `paywall.privacy`、`subscription.state.trial` / `.active` / `.gracePeriod` / `.none`、`status.exportNeedsSubscription`。

## 3. 技术方案

### 3.1 App Store Connect 配置（一次性）

1. 新建 iOS bundle id：**已定 `run.libo.datalayer-studio.mobile`**（正式壳工程用它；现有 `…overlaytouchhost` 仅是模拟器调试壳 id，不上架）。
2. ASC 新建 App record（platform iOS，免费），四语言元数据；`asc` 工作流 platform 参数用 `IOS`，构建号沿用 `yyyyMMddNN`。
3. 创建订阅组（如 `DataLayer Studio Mobile`）→ 组内两个自动续订 SKU：月付 $1.99（1 个月）与年付 $19.99（1 年）→ 两档均配置推介优惠：Free Trial / 1 周 / 所有地区。
   - product id 建议 `run.libo.datalayerstudio.mobile.monthly` / `…yearly`（**内购 product id 只允许字母数字、句点、下划线，不能带连字符**，故与 bundle id 写法不同）。
   - 月付 SKU 另配 Offer Code（免费 3 个月，§1.7）。
4. 订阅需签署最新付费应用协议（Mac 已收费，银行/税务信息已在，确认协议版本即可）。
5. Billing Grace Period 建议开启（账单问题宽限，减少误伤流失）。
6. 隐私标签与 `PrivacyInfo.xcprivacy` 同现状（不收集数据；订阅交易由 Apple 处理，不新增采集）。
7. Family Sharing 对订阅**不开启（已定，2026-07-07）**——开启后不可关闭，留作后续增长手段；S3 配置时确认两个 SKU 均保持关闭。

### 3.2 客户端架构（StoreKit 2，无服务器依赖）

新增 `Sources/OverlayTouch/Stores/MobileSubscriptionStore.swift`（`@MainActor ObservableObject`；StoreKit 2 API macOS 12+ 同样可编译，模型保持平台中立以便 macOS 上跑单测）：

```
状态机 EntitlementState: .unknown → .subscribed(expiry:, inTrial:) | .gracePeriod | .notSubscribed
职责：
- start(): 读 Transaction.currentEntitlements 建立初始状态；挂 Transaction.updates 长驻监听（续订/退款/撤销实时生效）
- products(): Product.products(for: [monthlyID, yearlyID])；isEligibleForIntroOffer 决定 CTA 文案
- purchase(): product.purchase() → 校验 VerificationResult → transaction.finish()
- restore(): AppStore.sync() + 重扫
- 离线容忍：最近一次已验证的到期时间戳存 UserDefaults；无网时按缓存到期时间 + 一天容差判定，避免离线闪锁
```

授权判定只信 StoreKit 2 本地验签（JWS 由系统校验），不自建收据服务器。

### 3.3 工程接入点

- **门只设一处**：`TouchStudioModel.export()` 入口检查注入的 `SubscriptionEntitlementProviding`（协议），无权益时置 `status.exportNeedsSubscription` 并由 UI 弹 paywall；模型内不 import StoreKit，保持可测性（fake provider 注入）。
- `TouchExportSection` 导出按钮态与 paywall sheet；设置页加订阅分区。
- macOS 侧零改动：`PurchaseAuthorizationStore`（AppTransaction 收据校验、GitHub 直下版无收据放行）原样保留。
- 免费功能不加任何检查——不在 21 个组件、预设、预览路径上埋权益判断，避免权益逻辑扩散。

### 3.4 iCloud 预设同步跨 record

两个 App 声明**同一个** `com.apple.developer.ubiquity-kvstore-identifier = $(TeamIdentifierPrefix)run.libo.datalayer-studio`（同一团队即可共享 KVS）。原有前置项不变且更关键：**Mac 版需先发小更新把该标识从空值落实为显式值**，iOS 正式壳对齐同一标识。`LayoutPresetStore` 代码无需改动。

### 3.5 测试策略

- 单测（macOS，`OverlayTouchTests`）：fake entitlement provider 驱动导出门（无权益→状态文案 / 有权益→放行）、状态机转移、离线缓存容差；paywall 文案四语言键位对齐。
- StoreKit 本地测试：**依赖 Xcode 工程**（`.storekit` 配置文件 + Xcode scheme / `SKTestSession`），SwiftPM 手工组装的模拟器壳做不了——因此**正式 Xcode 壳工程从「发布前置」提前为本方案的实施前置**。`.storekit` 里配好月订 + 7 天试用，本地验证购买/试用/续订/退款/撤销全路径（Xcode 可加速时间流逝模拟续订周期）。
- Sandbox / TestFlight：沙盒账户走真实 ASC 配置验证推介优惠资格显示、宽限期；TestFlight 内订阅自动走沙盒。
- 验收清单：试用开始→到期自动转正扣费（沙盒加速）；试用中取消→到期降级；月↔年组内升降级按比例结算；Offer Code 兑换 3 个月→到期转正；恢复购买跨设备；iPad/iPhone 同账户互通；导出中过期不中断；离线启动不闪锁。

### 3.6 服务器侧（可选，不阻塞 v1）

App Store Server Notifications V2 订阅事件（`SUBSCRIBED` / `DID_RENEW` / `EXPIRED` / `GRACE_PERIOD_EXPIRED` 等）接入现有 server 基建做运营看板；沿用既有规则：`price` 为 milliunits（展示除以 1000）、`currency` 只做展示、地区读 `storefront`。解锁判定永不依赖服务器。

### 3.7 审核合规清单（Guideline 3.1）

- 免费层有真实可用性（编辑/预览全量），App 不是「空壳 + 付费墙」；
- 试用与订阅条款在购买点完整展示（价格、周期、自动续订、取消方式）；
- 恢复购买与管理订阅入口可达；EULA（可用 Apple 标准 EULA）与隐私政策链接在 App 内与元数据同时提供；
- 订阅在用户所有 iOS 设备可用（同一 App 天然满足）；
- 天气功能用户自备 OpenWeather key 的既有注意事项不变。

## 4. 实施计划

| 阶段 | 内容 | 出口标准 | 粗估 |
| --- | --- | --- | --- |
| S0 决策定稿 | ✅ 已完成（2026-07-07）：拆 record、导出锁免费层、$1.99 月 / $19.99 年、送 3 个月码、bundle id `.mobile`；§6 文档已修订 | 本文档状态已改「已定」 | — |
| S1 正式 Xcode 壳 | ✅ 已完成（2026-07-07）：`App/DataLayerStudioMobile.xcodeproj`（universal target，bundle id `.mobile`）、KVS entitlements（模拟器/真机双验证）、`.storekit` 两档 SKU+7 天试用并挂入共享 scheme；App ID 已随自动签名注册。PrivacyInfo 留到 S2 随订阅代码补 | 模拟器构建启动通过；真机签名构建通过 | — |
| S2 订阅模块 | MobileSubscriptionStore + 导出门 + paywall + 设置分区 + 四语言文案 + 单测 | §3.5 验收清单本地全绿 | 3–5 天 |
| S3 ASC 配置与联调 | 新 record、订阅组/两档 SKU/试用、Offer Code 首批码、CN/JP 价格点核对、沙盒验证 | 沙盒全路径通过（含兑换码） | 1–2 天 |
| S4 Mac KVS 小版本 | Mac 版落实 KVS 显式标识并发布 | 三端预设同步联调通过 | 1 天 + 审核周期 |
| S5 TestFlight → 提审 | 内测 + 元数据 + 审核 | 上架 | 1–2 周（含审核） |

依赖关系：S1 是 S2/S3 的前置；S4 可并行；整体在 iPad 功能补齐（检查器等）之外独立推进，互不阻塞。

## 5. 风险登记

| 风险 | 概率 | 影响 | 缓解 |
| --- | --- | --- | --- |
| 用户对「Mac 买断 ≠ iOS 免订阅」不满 | 中 | 中 | §1.5 话术前置到商店描述与落地页；预设同步免费保留三端协同价值；Offer Code 补偿备选 |
| 订阅疲劳导致差评 | 中 | 中 | 免费层足够完整；只一档月付、条款清晰；到期不锁编辑不丢数据 |
| 审核认定免费层可用性不足 | 低 | 中 | 编辑/预览全免费的切法即为此设计；审核备注说明免费能力清单 |
| 误把 iOS 挂进现有 record（不可逆） | 低 | 高 | 本文档红线 + 操作时用新 bundle id，任何人不得对 6782545770 执行加 iOS platform |
| 试用资格误解（重装无二次试用） | 中 | 低 | Paywall 按 eligibility 动态文案，不对不合格用户展示「免费试用」按钮 |
| 离线/退款边界状态错乱 | 低 | 中 | §3.2 缓存容差 + Transaction.updates 撤销即时处理 + §3.5 验收清单覆盖 |

## 6. 采纳后需同步修订的文档

- `docs/ipad-product-design.md`：头表商业模式行、§1 分工表加商业模式行、§7 发布前置中“购买校验门（Universal Purchase）”改为本方案订阅门。
- `docs/ipad-technical-design.md`：§8-6 发布前置（bundle id、Universal Purchase 注意段整段替换）、风险表。
- `docs/iphone-product-design.md` / `docs/iphone-technical-design.md`：头表商业模式行、§10/§9 商业化段。
- `AGENTS.md`：iOS 的 ASC 流程补充（新 App record id、platform IOS、订阅 SKU 约定）——待 S3 配置完成后回填实际 id。
- 落地页与 README 的「一次购买三端使用」表述。

## 7. 已拍板决策与剩余开放问题

已拍板（2026-07-07）：① 月付 $1.99；② 免费层按 §1.3 推荐（导出锁）；③ Mac 买断用户送 3 个月 Offer Code，**发码 v1 走人工渠道**（§1.7）；④ bundle id `run.libo.datalayer-studio.mobile`；⑤ 年付与月付同期上线，定价 $19.99（≈10 个月价）；⑥ **Family Sharing 不开启**（§3.1-7）。

无剩余开放问题。备忘两条非决策事项：CN/JP 地区价在 S3 建 SKU 时按价格点核对观感（§1.6）；发码自动化为远期备选，按人工渠道申请量再评估（§1.7）。
