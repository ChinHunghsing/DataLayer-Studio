---
name: dls-github-release
description: 发布和验证 DataLayer Studio 的 GitHub Release，包括 main CI、v* tag、release workflow、Release notes、免费版声明、zip/sha256 资产、Developer ID 签名与公证下载验收。用户要求创建、补发、修复或核验 GitHub Release，或修改 .github/workflows/release.yml、签名公证脚本时使用。
---

# DataLayer Studio GitHub Release

## 发布前

- 正式发布属于外部变更，只在用户明确要求时打 tag、推送或改 Release。
- `git fetch --tags` 后确认当前分支不落后、工作区干净、目标 tag 不存在，并先确认 `main` CI 成功。
- 工作区有用户无关改动时，从 `origin/main` 在 `/private/tmp` 创建 clean worktree 操作，避免污染或误提交。
- 不无原因覆盖或移动已发布 tag。workflow 失败先修复并推送，确认 `main` CI 通过后再处理 tag。

## 发布与正文

创建 `vX.Y.Z` 并推送会触发 `.github/workflows/release.yml`，它运行测试、构建、Developer ID 签名、公证并上传 zip 与 sha256。推送后必须用 `gh run list` / `gh run watch` 等到 release workflow 成功，再用 `gh release view <tag>` 核对资产。

Release 正文必须包含：

- `Highlights`。
- `Full commit list since <上一版本>`，由 `git log --oneline <上一tag>..<当前tag>` 生成；每条 hash 链接到 GitHub commit 页面。
- 明确说明这是免费版：导出限 1080p 且带 `Made with DataLayer Studio` 水印。
- Mac App Store 完整版购买链接 `https://apps.apple.com/cn/app/datalayer-studio/id6782545770`。

自动正文过短时用 `gh release edit <tag> --notes-file <file>` 补齐。

## 下载资产验收

从 Release 重新下载 zip 和 sha256，核对摘要，解压后在沙箱外运行：

```bash
codesign --verify --deep --strict <app>
xcrun stapler validate <app>
spctl -a -vv -t exec <app>
```

三项都通过才算用户可直接运行。沙箱内的 `invalid signature`、`kLSDataUnavailableErr` 或 Code Signing internal error 常是假阴性；只有脱沙箱复现才修改签名或重打包。
