#!/bin/bash
# pptx を PDF 経由で PNG 連番にレンダリングする (視覚 QA 用)
# 使い方: bash render-pptx.sh <deck.pptx> <outdir> [dpi (default 100)]
set -euo pipefail

PPTX="$1"
OUT="$2"
DPI="${3:-100}"

SOFFICE="$(command -v soffice || echo /Applications/LibreOffice.app/Contents/MacOS/soffice)"
if [ ! -x "$SOFFICE" ]; then
  echo "soffice が見つかりません (nix: libreoffice-bin を home.packages に追加)" >&2
  exit 1
fi
if ! command -v pdftoppm >/dev/null; then
  echo "pdftoppm が見つかりません (nix: poppler-utils を home.packages に追加)" >&2
  exit 1
fi

mkdir -p "$OUT"
BASE="$(basename "$PPTX" .pptx)"
"$SOFFICE" --headless --convert-to pdf --outdir "$OUT" "$PPTX" >/dev/null
pdftoppm -png -r "$DPI" "$OUT/$BASE.pdf" "$OUT/$BASE"
ls "$OUT" | grep -c "^$BASE.*\.png$"
