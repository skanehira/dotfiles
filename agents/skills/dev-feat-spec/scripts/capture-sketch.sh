#!/bin/sh
# UI_SKETCH.html の 1 画面を png に撮る (references/sketch-capture.md「撮る」)。
# 使い方: capture-sketch.sh <UI_SKETCH.html> <画面 ID> <出力 png> [--width N (既定 1280)] [--highlight <key>]
# Playwright は初回だけキャッシュに入れる。Chromium は ~/Library/Caches/ms-playwright (Linux は ~/.cache/ms-playwright) を使う。
set -eu

if [ "$#" -lt 3 ]; then
  echo "usage: capture-sketch.sh <UI_SKETCH.html> <画面 ID> <出力 png> [--width N] [--highlight <key>]" >&2
  exit 2
fi

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
html_dir=$(CDPATH='' cd -- "$(dirname -- "$1")" && pwd)
html="$html_dir/$(basename -- "$1")"
[ -f "$html" ] || { echo "not found: $html" >&2; exit 2; }

# utility-nvim-ui-capture と同じ版にそろえ、ダウンロード済みの Chromium を共有する
playwright_version=1.65.1
playwright_home="${XDG_CACHE_HOME:-$HOME/.cache}/dev-feat-spec/playwright"
if [ ! -f "$playwright_home/node_modules/playwright/package.json" ]; then
  echo "installing Playwright $playwright_version into $playwright_home (one-time)" >&2
  mkdir -p "$playwright_home"
  (cd "$playwright_home" && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-audit --no-fund "playwright@$playwright_version" >/dev/null) || {
    echo "failed to install Playwright" >&2
    exit 1
  }
fi

screen=$2
out=$3
shift 3
NODE_PATH="$playwright_home/node_modules" node "$script_dir/capture-sketch.cjs" "$html" "$screen" "$out" "$@" || {
  status=$?
  echo "capture failed. Chromium が無ければ: npx playwright@$playwright_version install chromium" >&2
  exit "$status"
}
