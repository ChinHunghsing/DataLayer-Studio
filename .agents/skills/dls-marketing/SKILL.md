---
name: dls-marketing
description: 维护 DataLayer Studio 的 landing-page、README/README.zh-CN、四语言用户手册、App Store/社交宣传图、品牌文案、购买链接、免费版说明和 Cloudflare Pages 部署。更新官网、截图、宣传素材、版本文案、本地化内容或部署 landing-page 时使用。
---

# DataLayer Studio 营销内容

## 品牌与内容一致性

- 对外名称统一为 `DataLayer Studio`；Mac App Store 链接固定为 `https://apps.apple.com/cn/app/datalayer-studio/id6782545770`。
- 涉及下载或导出时，明确区分 Mac App Store 付费完整版与 GitHub Release/自编译/CLI 免费版；免费版导出限 1080p 且带 `Made with DataLayer Studio` 水印，并引导购买完整版。
- 改功能、价格、版本或工作流描述时，检查 `README.md`、`README.zh-CN.md`、`landing-page/`、`docs/user-guide/{en,zh-Hans,zh-Hant,ja}.md` 及对应生成页面，按实际受影响范围同步。
- 新 UI 文案和公开内容保持英文、简中、繁中、日文一致；不要只更新最先看到的一种语言。

## 图片与截图

- 使用当前 App 界面与当前版本素材；先检查已有生成脚本和源图，避免手工复制一套流程。
- 截图保留完整窗口边缘和标题栏，按透明像素边界居中，避免直角阴影、裁切圆角和旧界面残留。
- 落地页展示图按实际 CSS 展示尺寸优化，优先 WebP；不要把原始超大图直接上站。
- App Store 截图的生成与内容一致性归本 skill；上传流程同时使用 `dls-app-store`。

## Cloudflare Pages

正式站点是 `https://datalayer-studio.ligh-t-ouch.com`，项目名 `datalayer-studio`，生产分支 `landing-page`：

```bash
wrangler pages deploy landing-page --project-name=datalayer-studio --branch=landing-page
```

`--branch=main` 只会发布预览环境。部署是外部变更，只在用户要求上线时执行。仅使用 Cloudflare 免费计划/额度；任何可能计费的计划、add-on 或资源必须先获得明确确认。
