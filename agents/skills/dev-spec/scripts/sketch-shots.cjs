#!/usr/bin/env node
// UI_SKETCH.html の全画面をヘッドレスの Chromium で開き、1 画面ずつ png に撮る。
// 画面の一覧はスケッチの `window.SKETCH_SCREENS` から読み、`#screen=<id>` で開く
// (references/ui-sketch.md「5.1 骨組みの作成」の口)。一覧をスケッチの側に持たせるのは、
// 撮る側が ID を渡す方式だと、渡し忘れた画面が誰にも見られないまま残るため。
const { chromium } = require("playwright");
const path = require("node:path");
const fs = require("node:fs");

function parseArgs(argv) {
  const positional = [];
  const options = { width: 1280, scheme: "light" };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--width") options.width = Number(argv[(i += 1)]);
    else if (argv[i] === "--scheme") options.scheme = argv[(i += 1)];
    else positional.push(argv[i]);
  }
  return { positional, options };
}

const { positional, options } = parseArgs(process.argv.slice(2));
const [html, outDir] = positional;
if (!html || !outDir || !options.width || !["light", "dark"].includes(options.scheme)) {
  console.error("usage: sketch-shots.cjs <UI_SKETCH.html の絶対パス> <出力ディレクトリ> [--width N] [--scheme light|dark]");
  process.exit(2);
}

/** 1 画面を開いて撮り、失敗の理由を返す (成功なら null)。 */
async function shoot(browser, screen) {
  const page = await browser.newPage({
    viewport: { width: screen.width ?? options.width, height: 900 },
    colorScheme: options.scheme,
  });
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error).split("\n")[0]));
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text().split("\n")[0]);
  });
  try {
    await page.goto(`file://${html}#screen=${encodeURIComponent(screen.id)}`);
    // 描いた画面の ID で待つ。一覧にあるのに描けない ID は、既定の画面に落ちてもここで時間切れになる。
    await page.locator(`[data-sketch-screen="${screen.id}"]`).first().waitFor({ state: "visible", timeout: 15000 });
    await page.evaluate(() => (document.fonts ? document.fonts.ready : null));
    if (errors.length > 0) return `page error: ${errors.join(" / ")}`;
    const out = path.join(outDir, `${options.scheme}-${screen.id}.png`);
    await page.screenshot({ path: out, fullPage: true });
    console.log(out);
    return null;
  } catch (error) {
    return String(error).split("\n")[0];
  } finally {
    await page.close();
  }
}

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch();
  try {
    const probe = await browser.newPage();
    await probe.goto(`file://${html}`);
    const listed = await probe
      .waitForFunction(() => Array.isArray(window.SKETCH_SCREENS) && window.SKETCH_SCREENS, null, { timeout: 30000 })
      .then((handle) => handle.jsonValue())
      .catch(() => null);
    await probe.close();
    if (!listed || listed.length === 0) {
      console.error("FAIL: window.SKETCH_SCREENS が無いか空です (ui-sketch.md 5.1 の口を作る)");
      process.exitCode = 1;
      return;
    }
    const screens = listed.map((item) => (typeof item === "string" ? { id: item } : item));
    let failed = 0;
    for (const screen of screens) {
      const reason = await shoot(browser, screen);
      if (reason !== null) {
        failed += 1;
        console.error(`FAIL ${screen.id}: ${reason}`);
      }
    }
    console.log(`captured ${screens.length - failed} / ${screens.length} (${options.scheme})`);
    if (failed > 0) process.exitCode = 1;
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(String(error).split("\n")[0]);
  process.exit(1);
});
