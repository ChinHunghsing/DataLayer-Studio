# DataLayer Studio 渲染性能优化报告 · 2026-07

> **归档说明（2026-07-16）**：2026-07-07 的性能评审记录，所列 5 项优化均已落地并随 0.2.x/0.3.x 上架。文中"后续待做计划"未再推进，如需重启以当前代码重新评估。

> 面向开发团队。记录 2026-07-07 针对预览与输出（导出）渲染路径的性能评审结论、已落地的 5 项优化及其验证方式，以及后续待做计划。约束前提：**不破坏任何既有功能，输出结果逐像素不变**（透明 Alpha 管线红线尤其不能碰）。

---

## 1. 背景与评审范围

预览与导出共用同一套 CPU CoreGraphics 渲染核心：

- `Sources/OverlayCore/Rendering/OverlayRenderer.swift`：每帧把全部可见元素绘制进 `CVPixelBuffer`。
- `Sources/OverlayCore/Rendering/OverlayPreviewRenderer.swift`：预览封装，含渲染器缓存（`withLayout` 复用）与像素缓冲池。
- `Sources/OverlayCore/Video/TransparentVideoWriter.swift` / `CompositedVideoWriter.swift`：导出写出器，逐帧调用 `OverlayRenderer.render`。
- `Sources/OverlayStudio/Stores/StudioModel.swift`：预览调度（防抖、合并、代际守卫、播放期 5Hz 刷新）。

评审结论：架构底子好（二分采样、路线底图路径缓存、textWidth 缓存、渲染器复用、像素缓冲池、硬件编码器选择、预览合并防抖都已存在），主要优化空间是**每帧常数项开销**。

## 2. 已落地优化（按提交顺序）

每项独立提交，均在提交前跑过对应测试。核心验证手段是测试基建里的 `assertRenderersProduceIdenticalPixels`：**优化前后渲染结果逐像素一致**。

### 2.1 CTLine 缓存（提交 `c19c64d`）

- 问题：`drawText` 每次调用重建 `NSAttributedString` + `CTLineCreateWithAttributedString`。导出 60fps、每帧几十段文本，等于每秒上千次 CoreText 排版，而标签/单位跨帧不变、数值高度重复。
- 改法：仿照既有 `textWidthCache`，增加带上限（8192 条，超限整体清空）的静态 CTLine 缓存，key 为 `(字体名+字号百分位, 文本, 色彩空间名+颜色分量)`，锁保护，跨渲染器实例共享。
- 位置：`OverlayRenderer.drawText` / `cachedTextLine`，key 类型 `TextLineKey` / `TextColorKey`。
- 测试：`testTextLineCacheRendersIdenticalPixelsColdAndWarm`（冷/热缓存逐像素一致）、`testTextLineCacheIsSharedAcrossRendererInstances`。

### 2.2 指标文案每帧只算一次（提交 `5b56a3b`）

- 问题：`render()` 里对齐宽度计算（`alignedMetricTileWidth`）与绘制循环各调一次 `metricContent`，同一帧全部指标元素的字符串格式化执行两遍。
- 改法：每帧先按可见元素索引构建一份文案表 `metricContentsByVisibleIndex`，宽度对齐与绘制共用。按索引（而非 element.id）建表，重复 id 场景行为也与旧实现一致；顺带移除只剩单一用途的 `metricElements` 存储属性。
- 测试：既有 `testMetricTilesShareAlignedWidthWhenOneValueNeedsMoreSpace` 覆盖对齐行为。

### 2.3 `withLayout` 复用已裁剪序列（提交 `5ad5892`）

- 问题：`withLayout`（布局变更时复用渲染器）路径仍执行 `series.trimmed(by:)`。裁剪激活时该函数 O(n) 重建全部样本（逐条 rebase 约 30 个字段的结构体），拖拽元素的每个 tick 都整段拷贝上万条样本。
- 改法：`reusing` 构造器在 `previous.config.activityTrim == config.activityTrim && previous.sourceSeries == series` 时直接复用上一实例的已裁剪 `series`（数组共享 COW 存储，比较为 O(1)），否则保持原逻辑。
- 测试：`testWithLayoutRendersSameAsFreshRendererWhenTrimIsActive`（裁剪激活下 `withLayout` 与全新渲染器逐像素一致）。

### 2.4 路线进度路径按帧缓存（提交 `9bea5e0`）

- 问题：路线元素"已走过"进度段每帧从最多 900 个路线点重建 CGPath，而相邻帧的 `elapsedCount`（进度点数）通常不变（1Hz 重采样 + 900 点降采样意味着一小时活动约 4 秒才变化一次）。
- 改法：按元素缓存最近一条进度路径，`elapsedCount` 或 `fitRect` 变化即重建。**按值比较而非增量追加**——预览时间可以回退，增量方案不安全。实例级缓存加锁（预览任务取消是协作式的，同一渲染器实例可能被并发渲染，先例是 `fontCache`）。
- 测试：`testRouteProgressPathCacheRendersIdenticalPixelsAcrossRepeatedFrames`（先渲 45s 再渲 30s 触发失效/命中，与全新渲染器逐像素一致）。

### 2.5 透明导出循环按帧释放（提交 `da832bd`）

- 问题：`TransparentVideoWriter` 的 `requestMediaDataWhenReady` 单次回调内连续写出大量帧，中间产生的 CF/CI 自动释放对象要到回调结束才释放，长时 4K 导出抬高内存峰值。`CompositedVideoWriter` 同构循环早已有 `autoreleasepool`。
- 改法：循环体包一层 `try autoreleasepool { ... }`，与合成导出路径写法对齐。不触碰像素与编码参数。
- 测试：`TransparentVideoWriterTests` + `CompositedVideoWriterTests` 全过（30 个）。

### 2.6 收尾验证

- 全量 `swift test`：257 个测试全部通过（2026-07-07）。
- `scripts/build_app_bundle.sh` 构建签名成功。
- 未做量化基准：本轮全部是消除重复计算/重复分配的确定性收益，正确性由逐像素测试保证；量化对比见第 4 节计划。

## 3. 未落地的候选优化（按建议顺序）

评审时识别、本轮未做的项，实施前都应先用 Instruments（Time Profiler）确认收益：

1. **格式描述复用**（`TransparentVideoWriter.appendPixelBuffer`）：每帧为同池同格式的 buffer 重建 `CMVideoFormatDescription`，可首帧创建后复用。收益小；改的是导出追加路径，改后必须全跑两个 writer 测试。
2. **Calendar 缓存**（`OverlayRenderer.formatClockAndCalendarDate`）：`Calendar.current` 每帧查询，存 `static let` 即可；可进一步按整秒缓存格式化结果。仅 timeDate 元素受益，零风险。
3. **scrub 期间降采样渲染**（`StudioModel`）：gauge 拖拽已降到 1600px（`gaugeDragMaximumPreviewRenderDimension`），时间轴 scrub 与播放期间仍按全尺寸（上限 3200px）渲染。扩展降采样能明显降 CPU，但 scrub 瞬间清晰度下降是**可见的产品折衷，需产品拍板后再做**。
4. **静态内容分层缓存**（大改，暂不建议）：面板背景、标签、路线底图渲染一次成层，逐帧只重绘动态值。理论收益最大，但直接触及透明 HEVC/ProRes Alpha 合成路径（红线：不能重新引入透明区域发灰），需要金样逐像素对比验证。只有在 Instruments 证明常数项优化不够时再评估。

## 4. 后续计划

- [ ] 用 `assets/resourses/` 本地素材做一次真实透明导出（HEVC alpha + ProRes 4444），肉眼核对半透明区域无发灰，并记录导出耗时作为基准。
- [ ] 用 Instruments Time Profiler 对导出与预览各采一次样，确认剩余热点排序，再决定是否做第 3 节第 1、2 项。
- [ ] 第 3 节第 3 项（scrub 降采样）交产品决策。
- [ ] 若仍需大幅提速，再评估第 3 节第 4 项（分层缓存），前置条件：金样对比测试基建。

## 5. 回归风险与守护

- 所有渲染优化的守护测试都在 `Tests/OverlayCoreTests/OverlayRendererTests.swift`，以逐像素一致为准绳；新增渲染路径缓存时**必须**配套同类测试。
- CTLine / 路线进度路径缓存均有界（8192 条 / 每路线元素 1 条），不会随导出时长增长。
- 缓存 key 的设计前提：文本颜色统一由 `CGColor(red:green:blue:alpha:)` 构造（`OverlayColor.cgColor` 与 `Colors` 常量），key 已含色彩空间名防碰撞；若未来引入其他色彩空间的文本颜色，此前提仍成立。
