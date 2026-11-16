#!/usr/bin/env node
// UI_SKETCH.html の 1 画面をヘッドレスの Chromium で開き、その画面の要素だけを撮る。
// 画面は `#screen=<id>` で開き、スケッチが描いた画面の ID を `data-sketch-screen` に出す取り決め
// (references/sketch-capture.md「スケッチの口」) に頼る。ボタンを押して状態を作る方式にしないのは、
// スケッチのボタンには処理が無いことが多く、押しても状態が変わらないまま撮れてしまうため。
//
// `--highlight <key>` を渡すと、`data-sketch-change="<key>:<説明>"` の要素に枠と説明のラベルを重ねて撮る。
// 枠はスケッチの CSS ではなく撮影のときだけ重ねる。スケッチに枠を描くと、次の設計 PR の変更前の画像にも
// 前の変更の枠が写るため。key で絞るのも同じ理由で、残った前の印には枠を付けない。
const { chromium } = require("playwright");

function parseArgs(argv) {
  const positional = [];
  const options = { width: 1280, highlight: null };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--width") options.width = Number(argv[(i += 1)]);
    else if (argv[i] === "--highlight") options.highlight = argv[(i += 1)];
    else positional.push(argv[i]);
  }
  return { positional, options };
}

const { positional, options } = parseArgs(process.argv.slice(2));
const [html, screen, out] = positional;
if (!html || !screen || !out || !options.width || options.highlight === undefined) {
  console.error(
    "usage: capture-sketch.cjs <UI_SKETCH.html の絶対パス> <画面 ID> <出力 png> [--width N] [--highlight <key>]",
  );
  process.exit(2);
}

/** 印の付いた要素に枠とラベルを重ね、重ねた数を返す (ブラウザの中で動く)。 */
function drawHighlights({ screen, key }) {
  const root = document.querySelector(`[data-sketch-screen="${screen}"]`);
  const prefix = `${key}:`;
  // モーダルの背景の下に隠れた要素 (中心に別の要素が重なっているもの) には枠を付けない。
  // 付けると、見えていない要素の枠がモーダルの上に浮いて写る。
  // elementFromPoint は表示領域の外では null を返すので、測る前にその要素まで動かす。
  const visibleOnTop = (el) => {
    el.scrollIntoView({ block: "center", inline: "center" });
    const r = el.getBoundingClientRect();
    const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    return hit !== null && (el === hit || el.contains(hit));
  };
  const targets = [...root.querySelectorAll("[data-sketch-change]")].filter(
    (el) => el.getAttribute("data-sketch-change").startsWith(prefix) && visibleOnTop(el),
  );
  const color = "#e11d48";
  for (const el of targets) {
    const label = el.getAttribute("data-sketch-change").slice(prefix.length);
    const r = el.getBoundingClientRect();
    const box = document.createElement("div");
    Object.assign(box.style, {
      position: "absolute",
      left: `${r.left + scrollX - 4}px`,
      top: `${r.top + scrollY - 4}px`,
      width: `${r.width + 8}px`,
      height: `${r.height + 8}px`,
      border: `3px solid ${color}`,
      borderRadius: "6px",
      pointerEvents: "none",
      zIndex: "2147483647",
      boxSizing: "border-box",
    });
    document.body.appendChild(box);
    if (label === "") continue;
    const tag = document.createElement("div");
    tag.textContent = label;
    Object.assign(tag.style, {
      position: "absolute",
      background: color,
      color: "#fff",
      font: "bold 12px/1.4 sans-serif",
      padding: "2px 6px",
      borderRadius: "4px",
      whiteSpace: "nowrap",
      pointerEvents: "none",
      zIndex: "2147483647",
    });
    document.body.appendChild(tag);
    // ラベルは枠の上辺にまたがせて右端に寄せる。枠の真上に置くと、左上にあることの多い見出しや
    // 項目名に重なって読めなくなるため。画面の上端からはみ出すときだけ枠の下辺に置く。
    const straddle = r.top - 4 - tag.offsetHeight / 2;
    // 測る前にスクロールしているので、画面の位置もここで測り直す (表示領域の座標で比べるため)
    const rootTop = root.getBoundingClientRect().top;
    const top = straddle >= rootTop ? straddle : r.bottom + 4 - tag.offsetHeight / 2;
    tag.style.top = `${top + scrollY}px`;
    tag.style.left = `${r.right + scrollX + 4 - tag.offsetWidth - 8}px`;
  }
  return targets.length;
}

(async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: options.width, height: 800 } });
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
    if (options.highlight !== null) {
      const count = await page.evaluate(drawHighlights, { screen, key: options.highlight });
      // 印の付け忘れや key の打ち間違いで、枠の無い画像を「枠つき」として出さない
      if (count === 0) {
        console.error(`no element with data-sketch-change="${options.highlight}:..." in ${screen}`);
        process.exitCode = 1;
        return;
      }
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
