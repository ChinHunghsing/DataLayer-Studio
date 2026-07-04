# DataLayer Studio Landing Page

这是 DataLayer Studio 的单页介绍页面，使用纯静态 HTML、CSS 和少量原生 JavaScript。

## 本地预览

直接在浏览器中打开：

```bash
open landing-page/index.html
```

页面素材来自仓库内的 App 图标、README 展示图和 App Store 截图草稿，并以 WebP 放到 `landing-page/assets/` 下，方便单独预览或部署。

如需重新生成多语言图片素材，本机需要安装 ImageMagick，然后运行：

```bash
node landing-page/scripts/generate-localized-assets.mjs
```
