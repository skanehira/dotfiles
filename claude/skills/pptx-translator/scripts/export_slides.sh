#!/bin/bash
# Keynoteでpptxを開き、全スライドをPNG画像としてエクスポートする(視覚確認用)。
# まれにAppleEventがタイムアウトすることがあるため、失敗時はKeynoteを強制終了して1回だけ再試行する。
#
# 使い方: export_slides.sh <pptxの絶対パス> <出力先ディレクトリ>
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
    set theDoc to open POSIX file srcPath
    delay 2
    export theDoc as slide images to (POSIX file outDir) with properties {image format:PNG}
    close theDoc saving no
end tell
EOF
}

# 注意: 失敗時にKeynoteをquit/killして再起動するリトライは行わない。
# 動作中のKeynoteを殺すと、次回起動時にバージョン案内やウィンドウ復元などの
# モーダルダイアログが出てAppleEventが恒久的にブロックされる悪循環になる。
# Keynoteは起動したまま使い回すのが安全。
if ! run_export; then
  echo "エクスポートに失敗しました。Keynoteがモーダルダイアログ" >&2
  echo "(バージョン案内・ウィンドウ復元・エラー等)でブロックされている可能性があります。" >&2
  echo "画面上のダイアログを手動で閉じてから、もう一度このスクリプトを実行してください。" >&2
  exit 1
fi

count=$(ls "$OUT_DIR"/*.png 2>/dev/null | wc -l | tr -d ' ')
echo "exported $count PNG files to $OUT_DIR"
