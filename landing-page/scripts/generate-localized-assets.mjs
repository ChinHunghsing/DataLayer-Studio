import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const landingRoot = resolve(scriptDir, "..");
const repoRoot = resolve(landingRoot, "..");
const landingAssets = join(landingRoot, "assets");
const tempDir = mkdtempSync(join(tmpdir(), "datalayer-localized-assets-"));

const fontPath = "/System/Library/Fonts/Supplemental/Arial Unicode.ttf";
let activeTextRuns = null;
const appIcon = join(landingAssets, "app-icon.png");
const comparisonSource = join(landingAssets, "data-layer-comparison.webp");
const metricsSource = join(landingAssets, "data-layer-metrics.webp");

const sourceLocalePath = (language, filename) => {
  const folder = language === "en" ? "en-US" : language;
  return join(repoRoot, "assets", "appstore", "v0.1.2", folder, "desktop", filename);
};

const languages = {
  "zh-Hans": {
    appStore: {
      subtitle: "FIT 视频数据叠加层",
      info: [
        ["年龄限制指定", "9+", "岁"],
        ["类别", "照片 / 视频", ""],
        ["开发者", "LIGHTOUCH K.K.", ""],
        ["语言", "ZH", "+ 3 种语言"],
        ["大小", "7.5", "MB"],
      ],
      whatsNew: "更新",
      update: ["增加合成视频导出，改善暂停后的实际时间显示，并更新 App Store 截图。"],
      versionHistory: "版本历史",
      version: "版本 0.1.3",
      time: "5小时前",
      preview: "预览",
      platform: "Mac",
      body: [
        "0.1.3 中，除了透明 Alpha 叠加层，也可以导出合成完成的视频。",
        "让跑步影片变成清晰、易读、带数据层的训练记录。",
        "DataLayer Studio 面向跑者、教练和内容创作者，把运动数据精准同步到真实视频，并输出可编辑的透明叠加层或完成视频。",
      ],
      more: "更多",
      website: "网站",
      support: "支持",
    },
  },
  "zh-Hant": {
    appStore: {
      subtitle: "FIT 影片資料疊加層",
      info: [
        ["年齡分級", "9+", "歲"],
        ["類別", "照片 / 影片", ""],
        ["開發者", "LIGHTOUCH K.K.", ""],
        ["語言", "ZH", "+ 3 種語言"],
        ["大小", "7.5", "MB"],
      ],
      whatsNew: "更新項目",
      update: ["加入合成影片輸出，改善暫停後的實際時間顯示，並更新 App Store 截圖。"],
      versionHistory: "版本記錄",
      version: "版本 0.1.3",
      time: "5 小時前",
      preview: "預覽",
      platform: "Mac",
      body: [
        "0.1.3 中，除了透明 Alpha 疊加層，也可以輸出合成完成的影片。",
        "讓跑步影片成為清楚、好讀、帶有資料層的訓練紀錄。",
        "DataLayer Studio 面向跑者、教練和內容創作者，把運動資料精準同步到真實影片，並輸出可編輯的透明疊加層或完成影片。",
      ],
      more: "更多",
      website: "網站",
      support: "支援",
    },
    comparison: {
      title: "資料層讓運動畫面更豐富",
      subtitle: "同一段影片，對比原始畫面與疊加運動資料後的效果。",
      noLayer: "無資料層",
      withLayer: "資料層開啟",
      onlyVideo: "只有畫面",
      quote: "從「看到畫面」到「讀懂運動」",
      chips: ["配速", "心率", "軌跡", "天氣"],
      note: "即時資料直接疊加到影片，訓練故事更完整。",
    },
    metrics: {
      title: "資料層展示完整運動資訊",
      subtitle: "路線、距離、配速、心率、天氣和時間，直接標註到影片畫面。",
      labels: {
        distance: "距離進度",
        route: "路線軌跡",
        weather: "天氣環境",
        metrics: "運動指標",
        time: "時間日期",
      },
    },
  },
  en: {
    appStore: {
      subtitle: "FIT video data overlay",
      info: [
        ["Age Rating", "9+", ""],
        ["Category", "Photo & Video", ""],
        ["Developer", "LIGHTOUCH K.K.", ""],
        ["Language", "EN", "+ 3 languages"],
        ["Size", "7.5", "MB"],
      ],
      whatsNew: "What's New",
      update: ["Added composited video export, improved real-time display after pause, and refreshed App Store screenshots."],
      versionHistory: "Version History",
      version: "Version 0.1.3",
      time: "5h ago",
      preview: "Preview",
      platform: "Mac",
      body: [
        "In 0.1.3, DataLayer Studio can export finished composited video in addition to transparent Alpha overlays.",
        "Turn running footage into clear, readable video with data layers.",
        "DataLayer Studio helps runners, coaches, and creators sync activity data to real footage and export editable transparent overlays or finished videos.",
      ],
      more: "More",
      website: "Website",
      support: "Support",
    },
    comparison: {
      title: "Data Layers Make Runs Readable",
      subtitle: "Compare raw footage with the same scene after activity data is overlaid.",
      noLayer: "No data layer",
      withLayer: "Data layer on",
      onlyVideo: "Only the scene",
      quote: "From seeing the scene to reading the run",
      chips: ["Pace", "Heart rate", "Route", "Weather"],
      note: "Live data goes directly onto video, completing the training story.",
    },
    metrics: {
      title: "Show Complete Activity Context",
      subtitle: "Route, distance, pace, heart rate, weather, and time are annotated directly on video.",
      labels: {
        distance: "Distance progress",
        route: "Route track",
        weather: "Weather",
        metrics: "Activity metrics",
        time: "Time & date",
      },
    },
  },
  ja: {
    appStore: {
      subtitle: "FIT 動画データオーバーレイ",
      info: [
        ["年齢制限指定", "9+", "歳"],
        ["カテゴリ", "写真 / ビデオ", ""],
        ["デベロッパ", "LIGHTOUCH K.K.", ""],
        ["言語", "JA", "+ 3 言語"],
        ["サイズ", "7.5", "MB"],
      ],
      whatsNew: "アップデート",
      update: ["合成済み動画の書き出しを追加し、一時停止後の実時刻表示を改善。App Store スクリーンショットも更新しました。"],
      versionHistory: "バージョン履歴",
      version: "バージョン 0.1.3",
      time: "5時間前",
      preview: "プレビュー",
      platform: "Mac",
      body: [
        "0.1.3 では、透明 Alpha オーバーレイに加えて、データを合成済みの完成動画も書き出せます。",
        "ランニング映像を、見やすいデータレイヤー付きの動画に。",
        "DataLayer Studio は、ランナー、コーチ、動画クリエイターが運動データを実際の映像と正確に同期し、読みやすいゲージを配置して、透明な Alpha オーバーレイまたは完成動画を書き出せる macOS アプリです。",
      ],
      more: "さらに表示",
      website: "Webサイト",
      support: "サポート",
    },
    comparison: {
      title: "データレイヤーで走りを読みやすく",
      subtitle: "同じ動画で、元映像と運動データを重ねた後の見え方を比較。",
      noLayer: "データなし",
      withLayer: "データレイヤー ON",
      onlyVideo: "映像だけ",
      quote: "「見る映像」から「読める運動」へ",
      chips: ["ペース", "心拍", "ルート", "天気"],
      note: "リアルタイムデータを動画に直接重ね、トレーニングの物語を補完します。",
    },
    metrics: {
      title: "運動情報をすべて表示",
      subtitle: "ルート、距離、ペース、心拍、天気、時刻を動画に直接表示。",
      labels: {
        distance: "距離の進捗",
        route: "ルート軌跡",
        weather: "天気",
        metrics: "運動指標",
        time: "時刻と日付",
      },
    },
  },
};

const escapeXml = (value) => String(value)
  .replace(/&/g, "&amp;")
  .replace(/</g, "&lt;")
  .replace(/>/g, "&gt;")
  .replace(/"/g, "&quot;");

const fileHref = (filePath) => resolve(filePath);

const magick = (args) => {
  const result = spawnSync("magick", args, { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`magick ${args.join(" ")}\n${result.stderr}`);
  }
};

const renderSvg = (name, svg, outputPath) => {
  const svgPath = join(tempDir, `${name}.svg`);
  const basePath = join(tempDir, `${name}-base.png`);
  writeFileSync(svgPath, svg);
  magick([svgPath, basePath]);

  const textRuns = activeTextRuns ?? [];
  if (textRuns.length === 0) {
    magick([basePath, "-depth", "8", "-strip", outputPath]);
    return;
  }

  const draw = textRuns.map((run) => {
    const commands = [
      `fill '${run.fill}'`,
      `fill-opacity ${run.opacity}`,
      `font-size ${run.size}`,
      `text-anchor ${run.anchor}`,
      `text ${run.x},${run.y} ${quoteDrawText(run.content)}`,
    ];
    return commands.join(" ");
  }).join("\n");

  magick([basePath, "-font", fontPath, "-draw", draw, "-depth", "8", "-strip", outputPath]);
};

const captureText = () => {
  activeTextRuns = [];
};

const releaseText = () => {
  const textRuns = activeTextRuns ?? [];
  activeTextRuns = null;
  return textRuns;
};

const line = (x1, y1, x2, y2, opacity = 0.18) =>
  `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="#76d7ff" stroke-opacity="${opacity}" stroke-width="1"/>`;

const text = (content, x, y, {
  size = 24,
  fill = "#f2f8fb",
  weight = 700,
  anchor = "start",
  opacity = 1,
  spacing = 0,
} = {}) =>
  {
    if (activeTextRuns) {
      activeTextRuns.push({ content, x, y, size, fill, weight, anchor, opacity, spacing });
    }
    return "";
  };

const quoteDrawText = (value) => `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`;

const paragraph = (lines, x, y, lineHeight, options = {}) =>
  lines.map((item, index) => text(item, x, y + index * lineHeight, options)).join("\n");

const pill = (label, cx, cy, width, {
  height = 36,
  size = 18,
  fill = "#f2f8fb",
  stroke = "#62d7ff",
  background = "#071923",
  backgroundOpacity = 0.9,
  weight = 700,
} = {}) => `
  <rect x="${cx - width / 2}" y="${cy - height / 2}" width="${width}" height="${height}" rx="${height / 2}" fill="${background}" fill-opacity="${backgroundOpacity}" stroke="${stroke}" stroke-opacity="0.85" stroke-width="1.2"/>
  ${text(label, cx, cy + size * 0.34, { size, fill, weight, anchor: "middle" })}
`;

const baseBackground = () => {
  const vertical = [120, 300, 480, 660, 840, 1020, 1200, 1380].map((x) => line(x, 0, x, 900)).join("\n");
  const horizontal = [120, 260, 400, 540, 680, 820].map((y) => line(0, y, 1440, y)).join("\n");
  return `
    <rect width="1440" height="900" fill="#06141e"/>
    ${vertical}
    ${horizontal}
    <path d="M90 835 C170 490 300 235 600 230 C860 226 910 77 1085 93 C1190 104 1265 142 1385 195" fill="none" stroke="#126c85" stroke-width="8" stroke-opacity="0.62"/>
    <path d="M345 246 C446 185 535 190 610 232" fill="none" stroke="#126c85" stroke-width="7" stroke-opacity="0.48"/>
  `;
};

const generateAppShowcase = (language) => {
  const source = sourceLocalePath(language, "01-preview-overlay.png");
  const output = join(landingAssets, `app-showcase-${language}.webp`);
  magick([
    source,
    "-crop",
    "1090x684+175+200",
    "+repage",
    "-resize",
    "1800x1129!",
    output,
  ]);
};

const generateComparison = (language, copy, crops) => {
  const output = join(landingAssets, `data-layer-comparison-${language}.webp`);
  const titleSize = language === "en" ? 43 : 46;
  const subtitleSize = language === "en" ? 22 : 21;
  const quoteSize = language === "en" ? 28 : 30;
  const chipWidths = language === "en" ? [135, 135, 135, 135] : [135, 135, 135, 135];

  captureText();
  const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="900" viewBox="0 0 1440 900">
  ${baseBackground()}
  ${text(copy.title, 78, 94, { size: titleSize, weight: 800 })}
  ${text(copy.subtitle, 78, 145, { size: subtitleSize, fill: "#b8c8d2", weight: 600 })}
  <rect x="79" y="166" width="181" height="6" rx="3" fill="#62d7ff"/>

  ${pill(copy.noLayer, 143, 268, language === "en" ? 168 : 136, { height: 34, size: language === "en" ? 16 : 18 })}
  ${pill(copy.withLayer, 817, 268, language === "en" ? 176 : language === "ja" ? 188 : 166, { height: 34, size: language === "en" ? 16 : 18 })}

  <image href="${fileHref(crops.plain)}" x="75" y="295" width="630" height="354"/>
  <image href="${fileHref(crops.overlay)}" x="735" y="295" width="630" height="354"/>
  <circle cx="720" cy="472" r="23" fill="#071923" stroke="#62d7ff" stroke-width="4"/>
  ${text("→", 720, 487, { size: 46, fill: "#62d7ff", weight: 800, anchor: "middle" })}

  ${pill(copy.onlyVideo, 170, 705, language === "en" ? 180 : 160, { height: 36, size: language === "en" ? 16 : 17 })}
  ${text(copy.quote, 78, 809, { size: quoteSize, weight: 800 })}

  ${copy.chips.map((label, index) => {
    const x = 822 + index * 151;
    const fill = index === 1 ? "#ff7284" : index === 2 ? "#74f1a4" : "#62d7ff";
    return pill(label, x, 706, chipWidths[index], { height: 36, size: language === "en" ? 16 : 18, fill, stroke: "#62d7ff" });
  }).join("\n")}
  ${text(copy.note, 755, 800, { size: language === "en" ? 18 : 19, fill: "#b8c8d2", weight: 600 })}
</svg>`;

  renderSvg(`comparison-${language}`, svg, output);
  releaseText();
};

const generateMetrics = (language, copy) => {
  const output = join(landingAssets, `data-layer-metrics-${language}.webp`);
  const titleSize = language === "en" ? 45 : 46;
  const labelSize = language === "en" ? 21 : 23;
  const labelWidths = {
    distance: language === "en" ? 235 : 196,
    route: language === "en" ? 190 : 198,
    weather: 198,
    metrics: language === "en" ? 220 : 198,
    time: 198,
  };

  captureText();
  const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="900" viewBox="0 0 1440 900">
  <image href="${fileHref(metricsSource)}" x="0" y="0" width="1440" height="900"/>
  <rect x="58" y="48" width="${language === "en" ? 775 : 710}" height="124" fill="#06141e"/>
  ${text(copy.title, 78, 96, { size: titleSize, weight: 800 })}
  ${text(copy.subtitle, 78, 144, { size: language === "en" ? 20 : 21, fill: "#b8c8d2", weight: 600 })}
  <rect x="79" y="166" width="181" height="6" rx="3" fill="#62d7ff"/>

  ${pill(copy.labels.distance, 616, 316, labelWidths.distance, { height: 42, size: labelSize, backgroundOpacity: 1 })}
  ${pill(copy.labels.route, 247, 445, labelWidths.route, { height: 42, size: labelSize, backgroundOpacity: 1 })}
  ${pill(copy.labels.weather, 1084, 633, labelWidths.weather, { height: 42, size: labelSize, backgroundOpacity: 1 })}
  ${pill(copy.labels.metrics, 403, 765, labelWidths.metrics, { height: 42, size: labelSize, backgroundOpacity: 1 })}
  ${pill(copy.labels.time, 1084, 848, labelWidths.time, { height: 42, size: labelSize, backgroundOpacity: 1 })}
</svg>`;

  renderSvg(`metrics-${language}`, svg, output);
  releaseText();
};

const generateAppStore = (language, copy) => {
  const output = join(landingAssets, `app-store-${language}.webp`);
  const previewOne = sourceLocalePath(language, "01-preview-overlay.png");
  const previewTwo = sourceLocalePath(language, "02-arrange-gauges.png");
  const infoCellWidth = 2256 / 5;

  captureText();
  const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="2256" height="1932" viewBox="0 0 2256 1932">
  <rect width="2256" height="1932" fill="#f7f8f9"/>
  <image href="${fileHref(appIcon)}" x="78" y="58" width="160" height="160"/>
  ${text("DataLayer Studio", 300, 98, { size: 52, fill: "#1f2428", weight: 800 })}
  ${text(copy.subtitle, 300, 145, { size: 31, fill: "#888c90", weight: 700 })}
  <path d="M365 195v44M342 218l23 23 23-23M336 250h58" fill="none" stroke="#0a84ff" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>

  <line x1="78" y1="280" x2="2178" y2="280" stroke="#d8dadd" stroke-width="2"/>
  ${copy.info.map(([label, value, detail], index) => {
    const center = infoCellWidth * index + infoCellWidth / 2;
    return `
      ${text(label, center, 335, { size: 22, fill: "#b0b3b6", weight: 800, anchor: "middle" })}
      ${text(value, center, 389, { size: value.length > 5 ? 25 : 42, fill: "#85888c", weight: 800, anchor: "middle" })}
      ${detail ? text(detail, center, 434, { size: 23, fill: "#85888c", weight: 600, anchor: "middle" }) : ""}
    `;
  }).join("\n")}
  <line x1="78" y1="462" x2="2178" y2="462" stroke="#d8dadd" stroke-width="2"/>

  ${text(copy.whatsNew, 82, 560, { size: 44, fill: "#202326", weight: 800 })}
  ${paragraph(copy.update, 82, 640, 38, { size: 27, fill: "#303438", weight: 700 })}
  ${text(copy.versionHistory, 1982, 560, { size: 28, fill: "#0a84ff", weight: 800, anchor: "middle" })}
  ${text(copy.time, 2082, 640, { size: 26, fill: "#8c8f92", weight: 600, anchor: "middle" })}
  ${text(copy.version, 2082, 680, { size: 24, fill: "#8c8f92", weight: 600, anchor: "middle" })}
  <line x1="78" y1="725" x2="2178" y2="725" stroke="#d8dadd" stroke-width="2"/>

  ${text(copy.preview, 82, 805, { size: 44, fill: "#202326", weight: 800 })}
  <clipPath id="preview-one"><rect x="78" y="852" width="1020" height="638" rx="10"/></clipPath>
  <clipPath id="preview-two"><rect x="1158" y="852" width="1020" height="638" rx="10"/></clipPath>
  <rect x="78" y="852" width="1020" height="638" rx="10" fill="#06141e"/>
  <rect x="1158" y="852" width="1020" height="638" rx="10" fill="#06141e"/>
  <image href="${fileHref(previewOne)}" x="78" y="852" width="1020" height="638" clip-path="url(#preview-one)"/>
  <image href="${fileHref(previewTwo)}" x="1158" y="852" width="1020" height="638" clip-path="url(#preview-two)"/>
  ${text("▭  " + copy.platform, 82, 1565, { size: 28, fill: "#85888c", weight: 700 })}

  ${paragraph(copy.body, 82, 1690, 45, { size: 29, fill: "#303438", weight: 650 })}
  ${text(copy.more, 1688, 1824, { size: 29, fill: "#0a84ff", weight: 800 })}
  ${text("LIGHTOUCH K.K.", 1970, 1690, { size: 27, fill: "#0a84ff", weight: 800 })}
  ${text(copy.website, 1970, 1754, { size: 29, fill: "#8c8f92", weight: 700 })}
  ${text(copy.support, 1970, 1810, { size: 29, fill: "#8c8f92", weight: 700 })}
</svg>`;

  renderSvg(`app-store-${language}`, svg, output);
  releaseText();
};

mkdirSync(landingAssets, { recursive: true });

const comparisonPlainCrop = join(tempDir, "comparison-plain.png");
const comparisonOverlayCrop = join(tempDir, "comparison-overlay.png");
magick([comparisonSource, "-crop", "630x354+75+295", "+repage", comparisonPlainCrop]);
magick([comparisonSource, "-crop", "630x354+735+295", "+repage", comparisonOverlayCrop]);

for (const language of ["zh-Hant", "en", "ja"]) {
  generateAppShowcase(language);
  generateComparison(language, languages[language].comparison, {
    plain: comparisonPlainCrop,
    overlay: comparisonOverlayCrop,
  });
  generateMetrics(language, languages[language].metrics);
}

for (const language of Object.keys(languages)) {
  generateAppStore(language, languages[language].appStore);
}

console.log("Generated localized landing-page assets.");
