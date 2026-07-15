# DataLayer Studio Landing Page Design

## 目标

这个页面不是营销模板，也不是功能清单。它要在 10 秒内让跑步视频创作者明白三件事：

- DataLayer Studio 把视频和 FIT/GPX 运动文件变成可编辑的数据层。
- 输出可以是透明 Alpha 浮层，也可以是已叠加好的成片。
- 这是一个专业 macOS 工具，适合剪辑工作流，不是玩具滤镜。

## 受众

- 跑步、骑行、训练视频创作者。
- 用 DaVinci Resolve、Final Cut Pro、Premiere 剪辑的人。
- 关心时间同步、透明通道、码率、帧率、布局预设的人。

## 页面气质

- 专业、克制、技术可信。
- 深色界面可以保留，但不要做成泛泛的霓虹科技页。
- 视觉重点应该来自真实视频画面、真实 app 截图、轨迹线和数据层，而不是装饰光效。

## 核心叙事

1. 导入：视频 + FIT/GPX。
2. 对齐：毫秒级同步运动时间和视频时间。
3. 编排：拖动、缩放、设置每个 gauge。
4. 输出：透明浮层或最终视频。

首页文案和视觉都围绕这四步，不再扩散到无关能力。

## 推荐页面结构

### Header

- 左侧品牌名。
- 中间导航最多保留：功能、工作流、输出、购买。
- 右侧：语言、GitHub 图标按钮、App Store 下载。
- GitHub 图标按钮必须视觉居中，按钮宽高固定。

### Hero

- 标题直接说产品结果，不写抽象价值观。
- 第一屏必须出现真实 app 截图或真实导出效果。
- Hero 的主图优先用真实 app 截图；如果要更有广告感，用截图外框和背景强化，不要替换成假 UI。
- 第一屏事实标签保留三项即可：macOS 13+、FIT/GPX、透明 MOV / 成片。

### Workflow

- 用四步替代泛泛三步：导入、同步、编排、输出。
- 每步一行标题 + 一行说明。
- 图标要小，不抢文字和截图。

### Showcase

- 用真实导出画面说明“数据层让观众读懂运动”。
- 保留切换：前后对比、数据标注、编辑界面。
- 图片必须 WebP，宽度按实际展示尺寸生成，避免大图硬塞。

### Output

- 明确区分两个输出：
  - 透明 Alpha 浮层：给剪辑软件上层轨道。
  - 合成视频：直接得到带数据层的成片，保留音频。
- 不要把编码器细节放到首页主文案里，除非作为小字事实。

### Pricing

- 一次买断，价格以 App Store 为准。
- 购买区只保留 App Store 和 GitHub 两个动作。
- 上线初期展示“刚刚上线 · 早鸟价”：Hero 顶部金色胶囊徽标（点击滚动到购买区）+ 购买区早鸟价面板，四语言价格与营销海报一致（¥68 / NT$320 / $9.99 / ¥1500）。金色是全页唯一暖色，只允许用在早鸟视觉上。
- 除早鸟价外不做其他价格牌，不写“限时”“订阅对比”，不虚构划线原价。

## 视觉系统

### 色彩

- 背景：深色偏蓝黑，保留轻微网格。
- 主色：蓝色用于动作和同步状态。
- 数据强调色：配速蓝、心率红、步频绿、距离黄可以少量出现。
- 不要让整页只有蓝色。真实截图里的运动画面要承担主要色彩变化。

### 字体

- 页面字体沿用系统/现有 Noto 系列。
- 中文标题可以继续用宋体方向，但字号和行高要更克制。
- 不用花哨 web font，避免多语言加载和渲染不稳定。

### 间距

- 页面整体比传统 marketing page 更紧凑。
- 区块之间留白以内容分组为准，不做大段空屏。
- 主要断点：桌面、平板、手机；不要为少数宽度写特殊布局。

## 图片策略

真实截图优先级高于 imagegen。

必须用真实素材：

- app 主界面截图。
- 导出效果截图。
- App Store 截图。
- GitHub / App Store 标识。

可以用 imagegen 的素材：

- 背景运动场景的抽象化纹理。
- Hero 背后的柔和路线轨迹光带。
- App 截图外层的宣传图背景。
- 非产品截图的海报概念图。

不适合 imagegen：

- app UI 截图。
- App Store 页面。
- 任何含有真实按钮、菜单、价格、系统窗口文字的图。

## Imagegen 方向

如果要生成视觉背景，使用这种方向：

```text
Use case: ads-marketing
Asset type: landing page background texture
Primary request: Create a restrained premium background for a macOS running telemetry video tool.
Scene/backdrop: dark blue-black editorial backdrop with subtle grid, faint irregular GPS route line, soft depth, no fake UI.
Subject: abstract motion-data layer, route curve, transparent video editing atmosphere.
Style: professional, flat-modern, premium software launch page, low contrast, not neon, not cyberpunk.
Avoid: mock app screens, readable text, logos, QR codes, people, heavy glow, purple gradients, bokeh blobs.
```

如果要生成宣传海报背景，使用这种方向：

```text
Use case: ads-marketing
Asset type: App Store / social promo background
Primary request: Create a premium 3:4 poster background for DataLayer Studio, leaving a large safe area for a real app screenshot.
Scene/backdrop: dark technical canvas, subtle GPS route curve, measured grid, quiet depth, App Store-ready polish.
Subject: abstract data overlay production workflow, not a fake interface.
Style: high-end macOS productivity software, crisp, restrained, modern.
Avoid: generated UI, text, fake screenshots, excessive glow, stock-photo runners.
```

## 多语言规则

- 文案必须同时支持简体中文、繁体中文、英文、日文。
- 不同语言下按钮和标题长度不同，布局不能依赖固定字数。
- App 截图用对应语言版本；没有对应语言截图时宁可用中性截图，不要用 AI 生成假文字。

## 不做

- 不加视频背景。
- 不加复杂滚动动画。
- 不加第三方前端框架。
- 不做假 dashboard 数字。
- 不把部署流程写进 README。

## 下一轮改造清单

1. 把 Workflow 改成四步，并和首页宣传图底部四格能力保持一致。
2. 收紧 Hero 和各 section 的纵向留白，适配 1440×900、1920×1080、MacBook 13/14 寸。
3. 重新整理 Output 区，让透明浮层和合成视频并列表达。
4. 检查所有多语言图片尺寸，优先转 WebP，避免超过实际展示尺寸太多。
5. 保持 Header 动作区固定、稳定、视觉居中。
