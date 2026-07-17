// HTML スライドの全可視テキストが pptx に編集可能テキストとして含まれるかの網羅照合。
// 移植漏れ・意図しない改変を機械検出する (デッキ非依存)。
//
// 使い方: playwright をインストールした作業ディレクトリで
//   node verify-content.mjs <deck.pptx> <slides.html> [slides2.html ...]
// 終了コード: 0 = 全一致 / 1 = 欠落あり (欠落行を出力)
import { execFileSync } from "node:child_process";
import path from "node:path";
import { chromium } from "playwright";

const [pptxPath, ...htmlPaths] = process.argv.slice(2);
if (!pptxPath || htmlPaths.length === 0) {
  console.error("usage: node verify-content.mjs <deck.pptx> <slides.html>...");
  process.exit(2);
}

const norm = (s) => s.replace(/\s+/g, " ").trim();

// pptx の段落ごとの結合テキスト (<a:p> 内の <a:t> を連結)
function pptxParagraphs(file) {
  let xml;
  try {
    xml = execFileSync("unzip", ["-p", file, "ppt/slides/slide*.xml"], {
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
    });
  } catch {
    console.error(`✗ ${file} を pptx として読めません (存在しないか壊れている)`);
    process.exit(2);
  }
  return [...xml.matchAll(/<a:p>[\s\S]*?<\/a:p>/g)].map((p) =>
    norm(
      [...p[0].matchAll(/<a:t>([^<]*)<\/a:t>/g)]
        .map((m) => m[1])
        .join("")
        .replace(/&amp;/g, "&")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'"),
    ),
  );
}

const paras = pptxParagraphs(pptxPath);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });

let missingTotal = 0;
for (const htmlPath of htmlPaths) {
  await page.goto(`file://${path.resolve(htmlPath)}`, {
    waitUntil: "networkidle",
  });
  const htmlLines = await page.evaluate(() =>
    [...document.querySelectorAll(".slide")].flatMap((s) => {
      // display:none のスライドは innerText の改行が落ちて連結されるため、
      // 可視化 (active 付与) してから読む
      s.classList.add("active");
      return s.innerText.split(/[\n\t]+/);
    }),
  );
  const missing = [];
  for (const raw of htmlLines) {
    const line = norm(raw);
    if (line.length < 2) continue;
    if (!paras.some((p) => p.includes(line))) missing.push(line);
  }
  if (missing.length) {
    console.error(`✗ ${htmlPath}: ${missing.length} 行が pptx に見つからない`);
    for (const m of missing) console.error(`  - ${m}`);
  } else {
    console.log(`✓ ${htmlPath}: 全可視テキストが pptx に含まれる`);
  }
  missingTotal += missing.length;
}

await browser.close();
process.exit(missingTotal ? 1 : 0);
