# DataLayer Studio 0.2.3 版本规划

- 制定日期：2026-07-11
- 版本主题：**自动对表 + 工程体验收口**
- 基线：0.2.2（时间线里程碑阶段 4–9.7 已收口，见 `docs/timeline-handoff.md`）

## 背景

0.2.2 完成了时间线改造的最终验收：多视频/多 FIT、多轨叠加、稀疏时间线、工程保存/恢复、素材 relink、撤销/重做全部落地。时间线交接文档的结论是基础时间线不再扩张范围，0.2.3 转入新里程碑：把「对表」这一最难的上手步骤自动化，并补齐工程保存体验和发布质量缺口。

## 范围

### A. 自动对表（主打特性）

按视频文件 creation time 与 FIT/GPX 活动 UTC 起点，在导入时自动把片段摆到时间线的正确相对位置，用户只需核对微调。

- 依据：2026-07-11 真实素材验收时，三段视频起点 `0/2434/2483` 秒、运动片段 `622` 秒就是人工按 creation time 算出摆放的；把这个计算自动化即可。
- 行为约定：
  - 视频缺 creation time 元数据、或推算出的相对位置明显不合理（相隔超过 24 小时）时，回退到现有的「末尾顺延」行为并给出状态提示，不静默摆错。
  - 导入顺序不影响结果：新素材的拍摄时间早于当前时间线 0 点时，现有内容整体右移（相对位置全部保持，手动导出范围与播放头随移），新素材落到 0 点；存在含片段的锁定轨道时不整体移动，回退末尾顺延并提示。
  - 自动摆放结果必须可撤销（纳入现有时间线 Undo/Redo）。
- 触点：导入落位逻辑（`StudioModel` 时间线追加路径）、`TimelineProject` 片段几何；不改 writer、不改透明路径。
- 测试：新增落位计算单元测试（含无 creation time、时区/UTC 换算、跨天异常回退）；`MediaPoolTests` 补导入落位断言。

### B. 工程保存体验收口

- ⌘S 覆盖保存到当前工程路径；无路径时等同另存为。
- ⌘⇧S 另存为（现有 Save As 面板行为迁移到这里）。
- 「文件 ▸ 最近打开的工程」菜单（security-scoped bookmark 恢复）。
- 窗口标题显示工程名（配合现有 document-edited 未保存标记）。
- 测试：`MediaPoolTests`/`StudioModelTests` 补覆盖保存、路径记忆与 dirty state 交互。

### C. 质量与缺陷修复（本版必做）

| # | 项目 | 说明 |
|---|------|------|
| C1 | 「完成时间线」错字 | `renderScope.singleClip` 与 `help.renderScope` 的 zh-Hans/zh-Hant 应为「完整时间线／完整時間線」；随工作区未提交改动一并修正提交 |
| C2 | 多浮层透明边缘 QA | ✅ 2026-07-12 完成，结论：通过。见 `docs/qa-0.2.3-transparent-and-longform.md` |
| C3 | 4K 长片压力回归 | ✅ 2026-07-12 完成，结论：通过（121.5 分钟 4K/29.97 全程导出，内存零增长）。见 `docs/qa-0.2.3-transparent-and-longform.md` |
| C4 | 窗口标题/状态显示原始 FIT 文件名 | ✅ 2026-07-12 完成。窗口标题与加载状态改显示「活动日期 + 运动类型」（如「2026-06-23 跑步」）；FIT session sport（field 5）与 GPX `<type>` 解析为 `TelemetrySport`，经 `ParsedActivity` 与 series 并行返回（不塞进热值类型 `TelemetrySeries`）；文件名仍保留在素材池与调试日志。四语言 sport 文案齐 |
| C5 | 天气 Key 引导 | ✅ 2026-07-12 完成。缺 Key 提示与检查器指引补充「无 Key 怎么办」：免费注册 → 订阅 One Call 4.0（含每日免费额度）→ My API keys 复制 → 新 Key 需等待生效；四语言同步 |
| C6 | CLI 应用内入口提示 | ❌ 用户 2026-07-12 决定不做 |

### D. 顺延候选（余量充足才做）

- 内置布局模板（比赛/训练/极简三套，FIT 载入即呈现）——独立性好，可整体平移到 0.2.4。
- CLI 支持导出 in/out 参数（当前只能全长导出，与 App 行为不一致）。
- 瞬时消息与持久状态分离（toast 通道）。

## 非目标（明确不做）

- 转场、画中画、多机位、音频轨——交接文档明确不混回基础时间线范围。
- 发送到剪辑软件（FCPXML/DaVinci）——留给 0.3.x。
- 移动端（独立 App record，独立排期）；iPad 版评审遗留 4 项观察（loadProducts 不重试、isEligibleForIntroOffer 不刷新、activeDrag 悬挂、进度条微抖）在移动端自己的迭代里处理。

## 遗留缺陷队列（本版不做，继续排队）

- **移动端预览渲染并发隐患（做 C4 时发现，移动端排期修）**：`TouchStudioModel.refreshOverlayOnly` / `StudioModel` 把非 Sendable 的 COW 值类型（`OverlayLayout`、`TelemetrySeries`）捕获进 `Task.detached` 渲染任务，主 actor 同时就地改这些值（`updateElement`、`elements.append`），COW 唯一性检查存在数据竞争，会破坏堆内存。平时时序上不触发；但**任何改变 `TelemetrySeries` 内存布局的改动都会稳定复现**（在干净 main 上仅加一个占位字段即 6/6 崩溃，栈在 `OverlayRenderer` 渲染路径）。因此 C4 特意把 sport 放在 `ParsedActivity` 里、不加进 `TelemetrySeries`，规避而非修复。根治需要移动端把渲染任务改成读取真正隔离的快照（或串行化 + 隔离），且需真机验证，属移动端范围。试过实例级/进程级 render 锁与 `layout.sanitized` 均只让崩溃转移、不能根治，勿再走加锁老路。
- 冷启动 Inspector 预选字段聚焦空值态（UX 评审 P3，需先复核时间线改造后是否仍存在）。
- 「复制/清空调试日志」菜单无快捷键；Debug Console 类别选择器拥挤。
- README 展示图与官网素材仍是旧同步 UI，需要一轮整体更新（可与 0.2.3 发布同步做营销素材，不占开发范围）。
- 真实相机素材矩阵（混合方向/分辨率/帧率/编码）继续在发布验收中扩大。

## 验收标准

1. 自动对表：真实素材（`assets/resourses/multi/`）导入后自动落位与 2026-07-11 人工计算结果一致；无 creation time 素材回退顺延且有提示；自动摆放可撤销。
2. 保存体验：⌘S/⌘⇧S/最近工程全链路真机验证；旧工程 JSON 加载不回退。
3. C2/C3 两项 QA 有结论记录（通过或列出问题）。
4. 全量 `swift test` 绿；`scripts/build_app_bundle.sh` + `scripts/verify_app_bundle.sh` 通过。
5. 新文案四语言（en/zh-Hans/zh-Hant/ja）同步；Codable 向后兼容（旧 preset、schema 1/2 工程可加载）。

## 发布检查清单

- 工作区遗留改动（撤销/重做菜单路由、导出体积估算音频开销、渲染范围改名含 C1 错字修正）先收尾提交，再开工新特性。
- 仓库根目录 `DataLayer-Studio-AppStore.pkg` 为 0.2.2 打包遗留，移走或删除，勿提交。
- 构建号沿用 `yyyyMMddNN`；TestFlight 与审核流程按 AGENTS.md 既定步骤执行。
