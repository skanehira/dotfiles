#!/bin/sh
# 子 issue の本文で、人が読む「ゴール」節の長さと語、実装用の節の折りたたみを検査する。
#
# 使い方: sh issue-check.sh <本文のファイル>...
# 出力: 問題 1 件につき 1 行。問題が無ければ何も出さない
# 終了コード: 0 問題なし / 1 問題あり / 2 使い方の誤り
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$HERE/lib.sh"

MAX_LINE=300
MAX_ROWS=25
MAX_BYTES=2500

[ $# -ge 1 ] || die 2 "使い方: sh issue-check.sh <本文のファイル>..."
for path in "$@"; do
  [ -f "$path" ] || die 2 "無い: $path"
done

# 折りたたみの印は見出しではないので、節の終わりを印で切る
goal_of() {
  awk '{ line = $0; sub(/[ \t\r]+$/, "", line) } line == "<details>" { exit } { print }' "$1"
}

check_shape() {
  awk -v file="$1" '
    { sub(/[ \t\r]+$/, "") }
    match($0, /^[ \t]*(```+|~~~+)/) {
      mark = substr($0, RSTART, RLENGTH)
      sub(/^[ \t]*/, "", mark)
      if (fence == "") { fence = mark; next }
      if (substr(mark, 1, 1) == substr(fence, 1, 1) && length(mark) >= length(fence)) { fence = ""; next }
    }
    fence != "" { next }
    $0 != "" && !started {
      started = 1
      if ($0 != "## ゴール") printf "%s: 「ゴール」節で始まっていない\n", file
    }
    after_open {
      if ($0 !~ /^<summary>.*<\/summary>$/) printf "%s: <details> の次に <summary> が無い\n", file
      after_open = 0
    }
    after_summary && $0 != "" {
      printf "%s: <summary> の次に空行が無い (中の Markdown が表示されない)\n", file
    }
    after_close && $0 != "" {
      printf "%s: </details> の次に空行が無い (次の Markdown が表示されない)\n", file
    }
    { after_summary = (open && $0 ~ /<\/summary>$/); after_close = 0 }
    $0 == "<details>" { open = 1; opens++; section = ""; after_open = 1 }
    $0 == "</details>" { open = 0; closes++; section = ""; after_close = 1 }
    /^## / {
      section = substr($0, 4)
      if (open) order = order "・" section
      else if (section == "優先度") { if (!closes) early = 1 }
      else if (section != "ゴール")
        printf "%s:%d: 折りたたみの外に書いてよい見出しは「ゴール」と「優先度」だけ\n", file, NR
    }
    section == "ゴール" && /^(対応 UC|担う受け入れ基準):/ {
      printf "%s:%d: 「対応 UC」「担う受け入れ基準」は「設計」節に書く\n", file, NR
    }
    section == "ゴール" && /^\*\*いま困っていること\*\*:/ { has_trouble = 1 }
    section == "ゴール" && /^\*\*こうなる\*\*:/ { has_change = 1 }
    section == "ゴール" && /^\*\*変わらないこと\*\*:/ { has_keep = 1 }
    section == "設計" && /^対応 UC:/ { has_usecase = 1 }
    END {
      if (!has_trouble) printf "%s: 「ゴール」に「いま困っていること」が無い\n", file
      if (!has_change) printf "%s: 「ゴール」に「こうなる」が無い\n", file
      if (!has_keep) printf "%s: 「ゴール」に「変わらないこと」が無い\n", file
      if (opens != 1 || closes != 1) {
        printf "%s: 折りたたみは 1 つだけにする (<details> と </details> を 1 回ずつ)\n", file
        exit
      }
      if (early || index(order, "・優先度")) printf "%s: 「優先度」は折りたたみの後に書く\n", file
      sub(/・優先度/, "", order)
      if (index(order, "・設計") && !has_usecase) printf "%s: 「設計」に「対応 UC」が無い\n", file
      if (order != "・設計・DoD・非スコープ・依存")
        printf "%s: 実装用の節が 設計・DoD・非スコープ・依存 の順に揃っていない\n", file
    }
  ' "$1"
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/issue-check.XXXXXX") || die 2 "一時ディレクトリを作れない"
trap 'rm -rf "${TMP:?}"' EXIT

problems() {
  for path in "$@"; do
    goal_of "$path" >"$TMP/goal.md"
    check_text "$TMP/goal.md" "ゴール" "$MAX_ROWS" "$MAX_BYTES" "$MAX_LINE" |
      awk -v from="$TMP/goal.md" -v to="$path" '{ print to substr($0, length(from) + 1) }'
    check_shape "$path"
  done
}

found=$(problems "$@")
[ -z "$found" ] && exit 0
printf '%s\n' "$found"
exit 1
