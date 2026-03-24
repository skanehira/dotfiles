#!/bin/bash
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "Usage: $(basename "$0") <input.html> [output.pdf]" >&2
  exit 1
fi

INPUT_HTML="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTPUT_PDF="${2:-${INPUT_HTML%.html}.pdf}"
if [ $# -ge 2 ]; then
  OUTPUT_PDF="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
fi

if [ ! -f "$INPUT_HTML" ]; then
  echo "Error: $INPUT_HTML not found" >&2
  exit 1
fi

# 共有キャッシュにplaywright-coreをインストール（初回のみ）
SLIDE_PDF_CACHE="$HOME/.cache/slide-pdf"
if [ ! -d "$SLIDE_PDF_CACHE/node_modules/playwright-core" ]; then
  echo "Installing playwright-core..."
  npm install --prefix "$SLIDE_PDF_CACHE" playwright-core >/dev/null 2>&1
  npx --prefix "$SLIDE_PDF_CACHE" playwright-core install chromium >/dev/null 2>&1
fi

# PDF生成
NODE_PATH="$SLIDE_PDF_CACHE/node_modules" node -e "
const { chromium } = require('playwright-core');
(async () => {
  try {
    const browser = await chromium.launch();
    const page = await browser.newPage();
    await page.goto('file://${INPUT_HTML}');
    await page.waitForLoadState('networkidle');
    // Mermaid等の非同期描画をポーリングで待機（最大2秒）
    await page.waitForFunction(() => {
      const containers = document.querySelectorAll('[class*=\"mermaid\"]');
      if (containers.length === 0) return true;
      return Array.from(containers).every(el => el.querySelector('svg'));
    }, { timeout: 2000 }).catch(() => {
      console.error('警告: Mermaid描画の待機がタイムアウトしました。描画なしで続行します。');
    });
    // 全スライドを印刷レイアウトに強制変換
    // (JSが付与したインラインスタイルをDOMレベルで上書き)
    await page.evaluate(() => {
      document.body.style.overflow = 'visible';
      document.body.style.background = '#fff';
      const container = document.getElementById('slide-container');
      if (container) {
        container.style.position = 'relative';
        container.style.width = 'auto';
        container.style.height = 'auto';
        container.style.overflow = 'visible';
      }
      const nav = document.getElementById('slide-nav');
      if (nav) nav.style.display = 'none';
      document.querySelectorAll('.slide').forEach(s => {
        s.classList.remove('active');
        s.style.display = 'block';
        s.style.position = 'relative';
        s.style.top = 'auto';
        s.style.left = 'auto';
        s.style.transform = 'none';
        s.style.pageBreakAfter = 'always';
        s.style.pageBreakInside = 'avoid';
        s.style.marginBottom = '0';
      });
    });
    await page.pdf({
      path: '${OUTPUT_PDF}',
      width: '1920px',
      height: '1080px',
      printBackground: true
    });
    await browser.close();
    console.log('PDF出力完了: ${OUTPUT_PDF}');
  } catch (err) {
    console.error('PDF出力エラー:', err.message);
    process.exit(1);
  }
})();
"
