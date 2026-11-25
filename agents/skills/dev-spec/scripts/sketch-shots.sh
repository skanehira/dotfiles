#!/bin/sh
# UI_SKETCH.html の全画面を png に撮る (references/ui-sketch.md「5.4 自分で確かめる」)。
# 使い方: sketch-shots.sh <UI_SKETCH.html> <出力ディレクトリ> [--width N (既定 1280)] [--scheme light|dark (既定 light)]
# 全画面が撮れ、ページのエラーが無ければ終了コード 0。1 画面でも失敗すれば 1 で、`FAIL <画面 ID>: <理由>` を出す。
# Playwright は dev-feat-spec の capture-sketch.sh と同じキャッシュを使う (初回だけ入れる)。
set -eu

if [ "$#" -lt 2 ]; then
  echo "usage: sketch-shots.sh <UI_SKETCH.html> <出力ディレクトリ> [--width N] [--scheme light|dark]" >&2
  exit 2
fi

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
html_dir=$(CDPATH='' cd -- "$(dirname -- "$1")" && pwd)
html="$html_dir/$(basename -- "$1")"
[ -f "$html" ] || { echo "not found: $html" >&2; exit 2; }

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

out=$2
shift 2
NODE_PATH="$playwright_home/node_modules" node "$script_dir/sketch-shots.cjs" "$html" "$out" "$@"
