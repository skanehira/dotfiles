#!/bin/bash
# Keynoteでpptxを開き、全スライドをPNG画像としてエクスポートする(視覚確認用)。
#
# 使い方: export_slides.sh <pptxの絶対パス> <出力先ディレクトリ>
#
# 実装上の注意:
# - Keynoteのpptxインポートは非同期のため、AppleScriptの `open` の戻り値は
#   信用できない(ドキュメントが開いていても missing value を返すことがある)。
#   戻り値は使わず、open後に `count of documents` をポーリングして開くのを待つ。
# - 失敗時にKeynoteをquit/killして再起動するリトライは行わない。
#   動作中のKeynoteを殺すと、次回起動時にバージョン案内やウィンドウ復元などの
#   モーダルダイアログが出てAppleEventが恒久的にブロックされる悪循環になる。
#   Keynoteは起動したまま使い回すのが安全。
set -euo pipefail

SRC="$1"
OUT_DIR="$2"

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.png 2>/dev/null || true

# 名前("Keynote")ではなくBundle IDで本家Keynote(com.apple.iWork.Keynote)を指定する。
# 名前解決は曖昧で、CFBundleNameが同じ"Keynote"の別アプリが存在すると
# tell application "Keynote" がそちらに解決され、pptxを開けずタイムアウトする。
KEYNOTE_ID="com.apple.iWork.Keynote"

run_export() {
  osascript <<EOF
set srcPath to "$SRC"
set outDir to "$OUT_DIR"
tell application id "$KEYNOTE_ID"
    activate
    -- 戻り値は使わない(pptxインポートでは missing value になることがある)
    open POSIX file srcPath
end tell
-- ドキュメントが開くまで最大30秒ポーリング
set docReady to false
repeat 30 times
    tell application id "$KEYNOTE_ID"
        if (count of documents) > 0 then
            set docReady to true
            exit repeat
        end if
    end tell
    delay 1
end repeat
if not docReady then error "NO_DOCUMENT"
tell application id "$KEYNOTE_ID"
    set theDoc to front document
    export theDoc as slide images to (POSIX file outDir) with properties {image format:PNG}
    close theDoc saving no
end tell
EOF
}

# 失敗時の切り分け: モーダルダイアログでブロックされているのか、
# 単にドキュメントを開けなかったのかをウィンドウ一覧から判別して報告する。
report_failure() {
  local windows
  windows=$(osascript -e 'tell application "System Events" to tell process "Keynote" to get name of every window' 2>/dev/null || echo "")
  if [ -n "$windows" ]; then
    echo "エクスポートに失敗しました。Keynoteに以下のウィンドウが残っています: $windows" >&2
    echo "モーダルダイアログ(バージョン案内・ウィンドウ復元・エラー等)の場合は" >&2
    echo "手動で閉じてから、もう一度このスクリプトを実行してください。" >&2
  else
    echo "エクスポートに失敗しました。ダイアログは検出されていません。" >&2
    echo "Keynoteがドキュメントを開けていない可能性があります(ファイルパス・形式を確認)。" >&2
    echo "Keynoteはquit/killせず、そのまま再実行してください。" >&2
  fi
}

if ! run_export; then
  report_failure
  exit 1
fi

count=$(ls "$OUT_DIR"/*.png 2>/dev/null | wc -l | tr -d ' ')
echo "exported $count PNG files to $OUT_DIR"
