#!/usr/bin/env node
// 从 docs/user-guide/*.md 生成 landing-page/user-guide/ 四语言静态页。
// 用法：node landing-page/scripts/build-user-guide.mjs

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const srcDir = join(root, "docs", "user-guide");
const outDir = join(root, "landing-page", "user-guide");

const languages = [
  {
    code: "zh-Hans",
    file: "zh-Hans.md",
    out: "index.html",
    href: "./",
    label: "简体中文",
    short: "简",
    title: "DataLayer Studio 使用手册",
    description: "DataLayer Studio 功能说明与使用手册：多轨时间线、数据组件、天气、导出中心与命令行的完整指南。",
    tocTitle: "目录",
    navGuide: "使用手册",
    navPricing: "购买",
    appStore: "App Store 下载",
    backHome: "返回首页",
    langLabel: "语言",
    homeQuery: "zh-Hans",
  },
  {
    code: "zh-Hant",
    file: "zh-Hant.md",
    out: "zh-hant.html",
    href: "zh-hant.html",
    label: "繁體中文",
    short: "繁",
    title: "DataLayer Studio 使用手冊",
    description: "DataLayer Studio 功能說明與使用手冊：多軌時間線、資料元件、天氣、匯出中心與命令列的完整指南。",
    tocTitle: "目錄",
    navGuide: "使用手冊",
    navPricing: "購買",
    appStore: "App Store 下載",
    backHome: "返回首頁",
    langLabel: "語言",
    homeQuery: "zh-Hant",
  },
  {
    code: "en",
    file: "en.md",
    out: "en.html",
    href: "en.html",
    label: "English",
    short: "EN",
    title: "DataLayer Studio User Guide",
    description: "The complete DataLayer Studio guide: multitrack timeline, data components, weather, the Export Center, and the command line.",
    tocTitle: "Contents",
    navGuide: "User Guide",
    navPricing: "Pricing",
    appStore: "Download on App Store",
    backHome: "Back to home",
    langLabel: "Language",
    homeQuery: "en",
  },
  {
    code: "ja",
    file: "ja.md",
    out: "ja.html",
    href: "ja.html",
    label: "日本語",
    short: "日",
    title: "DataLayer Studio ユーザーガイド",
    description: "DataLayer Studio の完全ガイド：マルチトラックタイムライン、データコンポーネント、天気、書き出しセンター、コマンドライン。",
    tocTitle: "目次",
    navGuide: "ユーザーガイド",
    navPricing: "購入",
    appStore: "App Store でダウンロード",
    backHome: "ホームへ戻る",
    langLabel: "言語",
    homeQuery: "ja",
  },
];

const appStoreURL = "https://apps.apple.com/cn/app/datalayer-studio/id6782545770";
const githubURL = "https://github.com/leeeboo/DataLayer-Studio";
// 分钟级版本号：每次重新生成都会变，确保样式改动后浏览器缓存刷新。
const version = new Date().toISOString().slice(0, 16).replace(/[-:T]/g, "");

const escapeHTML = (text) =>
  text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

const slugify = (text) =>
  text
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s-]/gu, "")
    .replace(/\s+/g, "-");

const inline = (text) => {
  let out = escapeHTML(text);
  out = out.replace(/`([^`]+)`/g, (_, code) => `<code>${code}</code>`);
  out = out.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  out = out.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '<a href="$2">$1</a>');
  return out;
};

function markdownToHTML(md) {
  const lines = md.split("\n");
  const html = [];
  const toc = [];
  let paragraph = [];
  let list = null; // { type: "ul"|"ol"|"check", items: [] }
  let code = null; // { lang, lines }
  let table = null; // { header, rows }
  let skippingTOC = false; // 网页版侧栏已有目录，跳过 Markdown 里的目录章节
  const tocHeadings = new Set(["目录", "目錄", "contents", "目次"]);

  const flushParagraph = () => {
    if (paragraph.length > 0) {
      html.push(`<p>${paragraph.map(inline).join("<br>")}</p>`);
      paragraph = [];
    }
  };

  const flushList = () => {
    if (!list) return;
    if (list.type === "check") {
      html.push(`<ul class="checklist">${list.items.map((i) => `<li>${inline(i)}</li>`).join("")}</ul>`);
    } else {
      const tag = list.type;
      html.push(`<${tag}>${list.items.map((i) => `<li>${inline(i)}</li>`).join("")}</${tag}>`);
    }
    list = null;
  };

  const flushTable = () => {
    if (!table) return;
    const head = `<thead><tr>${table.header.map((c) => `<th>${inline(c)}</th>`).join("")}</tr></thead>`;
    const body = `<tbody>${table.rows
      .map((row) => `<tr>${row.map((c) => `<td>${inline(c)}</td>`).join("")}</tr>`)
      .join("")}</tbody>`;
    html.push(`<div class="table-scroll"><table>${head}${body}</table></div>`);
    table = null;
  };

  const flushAll = () => {
    flushParagraph();
    flushList();
    flushTable();
  };

  const splitRow = (line) =>
    line
      .replace(/^\|/, "")
      .replace(/\|\s*$/, "")
      .split("|")
      .map((c) => c.trim());

  for (const raw of lines) {
    const line = raw.replace(/\s+$/, "");

    if (code) {
      if (line.startsWith("```")) {
        html.push(`<pre><code>${escapeHTML(code.lines.join("\n"))}</code></pre>`);
        code = null;
      } else {
        code.lines.push(raw);
      }
      continue;
    }

    if (line.startsWith("```")) {
      flushAll();
      code = { lang: line.slice(3).trim(), lines: [] };
      continue;
    }

    if (line.startsWith("|")) {
      flushParagraph();
      flushList();
      const cells = splitRow(line);
      if (!table) {
        table = { header: cells, rows: [], sawSeparator: false };
      } else if (!table.sawSeparator && cells.every((c) => /^:?-{3,}:?$/.test(c))) {
        table.sawSeparator = true;
      } else {
        table.rows.push(cells);
      }
      continue;
    }
    flushTable();

    const heading = line.match(/^(#{1,3})\s+(.*)$/);
    if (heading) {
      flushAll();
      const level = heading[1].length;
      const text = heading[2].trim();
      if (level === 2 && tocHeadings.has(text.toLowerCase())) {
        skippingTOC = true;
        continue;
      }
      skippingTOC = false;
      const id = slugify(text);
      if (level === 1) {
        html.push(`<h1>${inline(text)}</h1>`);
      } else {
        if (level === 2) toc.push({ id, text });
        html.push(`<h${level} id="${id}">${inline(text)}</h${level}>`);
      }
      continue;
    }

    if (skippingTOC) continue;

    if (/^---+$/.test(line)) {
      flushAll();
      html.push("<hr>");
      continue;
    }

    const check = line.match(/^- \[[ x]\]\s+(.*)$/);
    if (check) {
      flushParagraph();
      flushTable();
      if (!list || list.type !== "check") {
        flushList();
        list = { type: "check", items: [] };
      }
      list.items.push(check[1]);
      continue;
    }

    const bullet = line.match(/^- (.*)$/);
    if (bullet) {
      flushParagraph();
      flushTable();
      if (!list || list.type !== "ul") {
        flushList();
        list = { type: "ul", items: [] };
      }
      list.items.push(bullet[1]);
      continue;
    }

    const ordered = line.match(/^\d+\.\s+(.*)$/);
    if (ordered) {
      flushParagraph();
      flushTable();
      if (!list || list.type !== "ol") {
        flushList();
        list = { type: "ol", items: [] };
      }
      list.items.push(ordered[1]);
      continue;
    }

    if (line.trim() === "") {
      flushAll();
      continue;
    }

    flushList();
    paragraph.push(line.trim());
  }

  flushAll();
  return { body: html.join("\n"), toc };
}

const githubIcon = `<svg class="github-mark" aria-hidden="true" viewBox="0 0 24 24"><path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12z"></path></svg>`;

function renderPage(lang, converted) {
  const alternates = languages
    .map((l) => `<link rel="alternate" hreflang="${l.code}" href="https://datalayer-studio.ligh-t-ouch.com/user-guide/${l.out === "index.html" ? "" : l.out}">`)
    .join("\n    ");

  const switcher = languages
    .map((l) => {
      const current = l.code === lang.code ? ' aria-current="page" class="lang-link is-active"' : ' class="lang-link"';
      const href = l.code === lang.code ? l.href : `${l.href}?sel=1`;
      return `<a${current} href="${href}" lang="${l.code}" hreflang="${l.code}">${l.label}</a>`;
    })
    .join("\n          ");

  const tocItems = converted.toc
    .map((item) => `<li><a href="#${item.id}">${escapeHTML(item.text)}</a></li>`)
    .join("\n            ");

  const redirect =
    lang.code === "zh-Hans"
      ? `<script>
      (function () {
        try {
          var pages = { "zh-Hans": "", "zh-Hant": "zh-hant.html", en: "en.html", ja: "ja.html" };
          var params = new URLSearchParams(location.search);
          if (params.get("sel") === "1") { localStorage.setItem("dlsGuideLang", "zh-Hans"); return; }
          var explicit = params.get("lang");
          var stored = localStorage.getItem("dlsGuideLang");
          var target = null;
          if (explicit && pages[explicit] !== undefined) target = explicit;
          else if (stored && pages[stored] !== undefined) target = stored;
          else {
            var langs = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language];
            for (var i = 0; i < langs.length; i++) {
              var v = String(langs[i] || "").toLowerCase();
              if (v.startsWith("ja")) { target = "ja"; break; }
              if (v.startsWith("en")) { target = "en"; break; }
              if (v.startsWith("zh")) {
                target = /hant|tw|hk|mo/.test(v) ? "zh-Hant" : "zh-Hans";
                break;
              }
            }
          }
          if (target && target !== "zh-Hans") location.replace(pages[target] + location.hash);
        } catch (e) {}
      })();
    </script>`
      : `<script>
      (function () {
        try {
          if (new URLSearchParams(location.search).get("sel") === "1") {
            localStorage.setItem("dlsGuideLang", "${lang.code}");
          }
        } catch (e) {}
      })();
    </script>`;

  return `<!doctype html>
<html lang="${lang.code}">
  <head>
    <!-- Google tag (gtag.js) -->
    <script async src="https://www.googletagmanager.com/gtag/js?id=G-9GGBXK8CEN"></script>
    <script>
      window.dataLayer = window.dataLayer || [];
      function gtag(){dataLayer.push(arguments);}
      gtag('js', new Date());
      gtag('config', 'G-9GGBXK8CEN');
    </script>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${lang.title}</title>
    <meta name="description" content="${lang.description}">
    <meta name="theme-color" content="#061018">
    <link rel="canonical" href="https://datalayer-studio.ligh-t-ouch.com/user-guide/${lang.out === "index.html" ? "" : lang.out}">
    ${alternates}
    <link rel="icon" href="../assets/app-icon.png">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link
      href="https://fonts.googleapis.com/css2?family=Noto+Sans:wght@400;500;700&family=Noto+Sans+JP:wght@400;500;700&family=Noto+Sans+SC:wght@400;500;700&family=Noto+Sans+TC:wght@400;500;700&family=Noto+Serif:wght@700&family=Noto+Serif+JP:wght@700&family=Noto+Serif+SC:wght@700&family=Noto+Serif+TC:wght@700&display=swap"
      rel="stylesheet"
    >
    <link rel="stylesheet" href="../styles.css?v=${version}-guide">
    <link rel="stylesheet" href="styles.css?v=${version}">
    ${redirect}
  </head>
  <body class="user-guide-page">
    <header class="site-header">
      <a class="brand" href="../?lang=${lang.homeQuery}" aria-label="${lang.backHome}">
        <img src="../assets/app-icon.png" alt="" width="32" height="32">
        <span>DataLayer Studio</span>
      </a>
      <nav class="site-nav" aria-label="Navigation">
        <a href="${lang.href}" aria-current="page">${lang.navGuide}</a>
        <a href="../?lang=${lang.homeQuery}#pricing">${lang.navPricing}</a>
      </nav>
      <div class="header-actions">
        <a class="button secondary header-cta guide-github" href="${githubURL}" target="_blank" rel="noreferrer">
          ${githubIcon}
          <span>GitHub</span>
        </a>
        <a class="button primary header-cta" href="${appStoreURL}" target="_blank" rel="noreferrer">
          <span>${lang.appStore}</span>
        </a>
      </div>
    </header>

    <main class="guide-shell section-shell">
      <aside class="guide-side">
        <nav class="lang-switch" aria-label="${lang.langLabel}">
          ${switcher}
        </nav>
        <nav class="guide-toc" aria-label="${lang.tocTitle}">
          <p class="guide-toc-title">${lang.tocTitle}</p>
          <ol>
            ${tocItems}
          </ol>
        </nav>
      </aside>
      <article class="guide-doc">
${converted.body}
      </article>
    </main>

    <footer class="site-footer section-shell">
      <span>DataLayer Studio</span>
      <a href="${appStoreURL}">App Store</a>
      <a href="${githubURL}" target="_blank" rel="noreferrer">${githubIcon}<span>GitHub</span></a>
      <span>© 2026 DataLayer Studio contributors.</span>
    </footer>
  </body>
</html>
`;
}

mkdirSync(outDir, { recursive: true });

for (const lang of languages) {
  const md = readFileSync(join(srcDir, lang.file), "utf8");
  const converted = markdownToHTML(md);
  const page = renderPage(lang, converted);
  writeFileSync(join(outDir, lang.out), page);
  console.log(`✓ ${lang.out} (${converted.toc.length} sections)`);
}
