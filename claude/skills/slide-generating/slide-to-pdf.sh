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
