#!/usr/bin/env bash
# Numbers 実機で xlsx のセル計算値を読み取る検証スクリプト (saas-pricing-design スキル同梱)
#
# openpyxl 生成の xlsx は計算結果キャッシュを持たないため、数式が Numbers に
# 取り込めないと値 0 に置換される。実際に Numbers で開いて計算値を読むのが唯一の互換検証。
#
# Usage:
#   verify_numbers.sh <xlsx path> <シート名:セル> [<シート名:セル>...]
# Example:
#   verify_numbers.sh docs/料金プラン.xlsx "料金プラン:B50" "料金プラン:B55" "インフラ詳細:B22"
#
# 出力: "シート名:セル=値" を 1 行ずつ。0.0 / missing value が出たら数式の取り込み失敗を疑う
#       (references/excel-recipe.md の Numbers 互換ルールを確認)

set -euo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: $0 <xlsx path> <シート名:セル> [<シート名:セル>...]" >&2
    exit 1
fi

XLSX_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
shift

# シートごとにセルをまとめる AppleScript を生成
SCRIPT="tell application \"Numbers\"
    set doc to open POSIX file \"${XLSX_PATH}\"
    delay 3
    set out to \"\"
    tell doc
"
for target in "$@"; do
    sheet="${target%%:*}"
    cell="${target##*:}"
    SCRIPT+="        tell sheet \"${sheet}\"
            tell table 1
                try
                    set v to value of cell \"${cell}\"
                    set out to out & \"${sheet}:${cell}=\" & (v as string) & linefeed
                on error
                    set out to out & \"${sheet}:${cell}=ERROR\" & linefeed
                end try
            end tell
        end tell
"
done
SCRIPT+="    end tell
    close doc without saving
    return out
end tell"

osascript -e "$SCRIPT"
