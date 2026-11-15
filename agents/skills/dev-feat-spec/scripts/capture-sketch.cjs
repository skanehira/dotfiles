#!/usr/bin/env node
// UI_SKETCH.html の 1 画面をヘッドレスの Chromium で開き、その画面の要素だけを撮る。
// 画面は `#screen=<id>` で開き、スケッチが描いた画面の ID を `data-sketch-screen` に出す取り決め
// (references/sketch-capture.md「スケッチの口」) に頼る。ボタンを押して状態を作る方式にしないのは、
// スケッチのボタンには処理が無いことが多く、押しても状態が変わらないまま撮れてしまうため。
const { chromium } = require("playwright");

const [html, screen, out, widthArg] = process.argv.slice(2);
if (!html || !screen || !out) {
  console.error("usage: capture-sketch.cjs <UI_SKETCH.html の絶対パス> <画面 ID> <出力 png> [幅]");
  process.exit(2);
}

(async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: Number(widthArg || 1280), height: 800 },
    });
    const errors = [];
    page.on("pageerror", (error) => errors.push(String(error).split("\n")[0]));
    await page.goto(`file://${html}#screen=${encodeURIComponent(screen)}`);
    // 描いた画面の ID で待つ。知らない ID をスケッチが既定の画面に落としても、ここで時間切れになる。
    const target = page.locator(`[data-sketch-screen="${screen}"]`);
    await target.waitFor({ state: "visible", timeout: 30000 });
    await page.evaluate(() => (document.fonts ? document.fonts.ready : null));
    if (errors.length > 0) {
      console.error(`page error: ${errors.join(" / ")}`);
      process.exitCode = 1;
      return;
    }
    await target.screenshot({ path: out });
    console.log(out);
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(String(error).split("\n")[0]);
  process.exit(1);
});
