# DataLayer Studio 30 秒产品宣传片

这是一个可继续编辑的 Remotion 项目，主体动画由 Remotion 生成，素材标准化、原创音轨合成和最终封装由 FFmpeg 完成。

## 成片规格

- 时长：30 秒
- 分辨率：1920 × 1080
- 帧率：30 fps
- 视频：H.264 / yuv420p
- 音频：AAC / 48 kHz
- 最终文件：`../output/promo-30s-16x9.mp4`

## 素材使用情况

- `assets/marketing/video/AppIcon.png`：官方 App 图标
- `assets/marketing/video/无数据层跑步视频.mp4`：开场前后对比
- `assets/marketing/video/有数据层跑步视频.mp4`：开场和最终效果展示
- `assets/marketing/video/app操作录屏.mov`：三项核心功能的真实操作画面
- `landing-page/assets/app-editor-714.webp`：官网真实软件界面截图
- `landing-page/assets/app-components-714.webp`、`app-export-714.webp`：保留为后续镜头替换素材

素材中没有独立音乐或音效文件。`scripts/prepare-assets.sh` 使用 FFmpeg 合成了原创、克制的电子氛围音乐和轻量转场提示音，没有使用第三方受版权保护音乐。`assets/marketing/爆炸气泡.png` 与目标风格不符，未使用。

## 修改文案和价格

编辑 `src/config.ts`。常用字段：

- `productName`：产品名称
- `tagline` / `taglineZh`：英文与中文卖点
- `hook`：开场文案
- `features`：三项主要功能
- `priceLabel` / `price`：价格信息
- `website`：购买网址
- `cta`：行动号召

## 安装

```bash
cd marketing-video
npm install
```

需要本机已安装 `ffmpeg` 和 `ffprobe`。

## 预览

```bash
npm run preview
```

命令会先准备代理素材，再启动 Remotion Studio。打开 `Promo30s` 即可逐帧预览和修改。

## 重新导出

```bash
npm run render
```

流程会：

1. 用 FFmpeg 将原始 4K/60fps 素材标准化为适合 Remotion 的代理素材。
2. 用 Remotion 渲染 `output/promo-30s-16x9.remotion.mp4`。
3. 用 FFmpeg 控制响度、清理元数据并输出 `output/promo-30s-16x9.mp4`。

## 时间结构

- 0–3 秒：跑步视频前后对比
- 3–8 秒：产品名称与核心价值
- 8–13 秒：FIT / GPX 导入与时间同步
- 13–18 秒：动态数据组件与自定义布局
- 18–23 秒：透明数据层导出与剪辑软件工作流
- 23–27 秒：最终效果展示
- 27–30 秒：Logo、早鸟价格和官网

## 验证

```bash
npm run typecheck
ffprobe ../output/promo-30s-16x9.mp4
ffmpeg -v error -i ../output/promo-30s-16x9.mp4 -f null -
```
