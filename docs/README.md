# docs 目录索引

> 最后整理：2026-07-16（当时线上版本 macOS 0.3.3，已上架）。
> 流程约定一律以根目录 `AGENTS.md` 为准；本目录只放产品、技术与使用文档。
> 若文档内容与仓库现状冲突，以当前可验证事实为准。

## 现行文档

### 用户文档

- [user-guide-zh-CN.md](user-guide-zh-CN.md) — 功能说明与完整使用手册（适用 0.3.x 界面）。
- [quick-export-guide-zh-CN.md](quick-export-guide-zh-CN.md) — 快速上手：导出第一条数据浮层。

### iOS / iPadOS（ios/）

- [ios/ipados-development-testing.md](ios/ipados-development-testing.md) — iPadOS 开发与真机测试流程（`AGENTS.md` 引用，改移动端前必读）。
- [ios/mobile-subscription-design.md](ios/mobile-subscription-design.md) — 移动端商业模式与订阅红线（`AGENTS.md` 引用）。
- [ios/ipad-product-design.md](ios/ipad-product-design.md) / [ios/ipad-technical-design.md](ios/ipad-technical-design.md) — iPad 版产品与技术设计（v1 已合入 main，实施中）。
- [ios/iphone-product-design.md](ios/iphone-product-design.md) / [ios/iphone-technical-design.md](ios/iphone-technical-design.md) — iPhone 版产品与技术设计（提案，未开工）。

### 算法专题（描述现行实现）

- [startup-pace-catchup-smoothing.md](startup-pace-catchup-smoothing.md) — 起跑与活动结尾的配速平滑（`TelemetrySeries.swift` 现行行为）。
- [motion-resumption-pace-smoothing.md](motion-resumption-pace-smoothing.md) — 组间休息后奔跑恢复点的配速修正（前文的中段推广）。

### 本地文件（不入库）

- `ios/ios-handover.md` — 本地交接笔记，已被 `.gitignore` 忽略，只存在于开发机。

## 归档（archive/）

已完成里程碑的历史记录，只供追溯，不再反映当前状态；每篇开头有归档说明。

- [archive/handoff-0.3.3.md](archive/handoff-0.3.3.md) — 0.3.3 发布交接（已上架；GitHub Release v0.3.3 归档时未发布）。
- [archive/ux-overhaul-0.3-plan.md](archive/ux-overhaul-0.3-plan.md) — 0.3「Studio Reset」界面重构方案（0.3.0–0.3.3 已全部实施）。
- [archive/timeline-handoff.md](archive/timeline-handoff.md) — 时间线改造交接（阶段 4–9 已收口）。
- [archive/qa-0.2.3-transparent-and-longform.md](archive/qa-0.2.3-transparent-and-longform.md) — 0.2.3 透明边缘与 4K 长片 QA 记录（红线回归基线）。
- [archive/render-performance-optimization.md](archive/render-performance-optimization.md) — 2026-07 渲染性能优化报告（5 项优化已落地）。

## 维护约定

- 新的版本交接、一次性 QA 记录、已执行完的方案，完结后移入 `archive/` 并在开头加归档说明。
- 移动文档时同步修正其它文档和代码注释里的路径引用（`grep -rn "docs/<文件名>"`）。
- 本索引在增删文档时同步更新。
