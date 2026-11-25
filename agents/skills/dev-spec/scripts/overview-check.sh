#!/bin/sh
# 人が読む概要 (OVERVIEW.md と、機能設計書の「何を作るか」節) の長さ・語・網羅を検査する。
#
# 使い方: sh overview-check.sh <docs/design のディレクトリ> [機能設計書...]
#   機能設計書を省略すると全件を検査し、OVERVIEW.md が無ければ問題にする。
#   渡すとその機能設計書だけを検査する。OVERVIEW.md は、あれば全体を検査する。
#
# 出力: 問題 1 件につき 1 行。問題が無ければ何も出さない
# 終了コード: 0 問題なし / 1 問題あり / 2 使い方の誤り
#
# 長さはバイトで数える (mawk は文字数を数えられない。日本語は 1 文字 3 バイト)。リンクの先は数えない。
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$HERE/lib.sh"

MAX_LINE=450
MAX_SECTION_ROWS=40
MAX_SECTION_BYTES=4000
MAX_OVERVIEW_ROWS=150
MAX_OVERVIEW_BYTES=16000

[ $# -ge 1 ] && [ -d "$1" ] || die 2 "使い方: sh overview-check.sh <docs/design のディレクトリ> [機能設計書...]"
DIR=$1
shift
OVERVIEW=$DIR/OVERVIEW.md

check_links() {
  for path in "$DIR"/features/*.md; do
    [ -f "$path" ] || continue
    name=${path##*/}
    grep -Fq -e "](./features/$name)" -e "](./features/$name#" \
      -e "](features/$name)" -e "](features/$name#" "$OVERVIEW" ||
      printf '%s: features/%s への参照が無い\n' "$OVERVIEW" "$name"
  done
  awk '{
    while (match($0, /\]\((\.\/)?features\/[^)#]+\.md/)) {
      link = substr($0, RSTART, RLENGTH)
      $0 = substr($0, RSTART + RLENGTH)
      sub(/^.*features\//, "", link)
      print link
    }
  }' "$OVERVIEW" | sort -u | while IFS= read -r name; do
    [ -f "$DIR/features/$name" ] || printf '%s: features/%s が無い\n' "$OVERVIEW" "$name"
  done
}

problems() {
  if [ -f "$OVERVIEW" ]; then
    check_text "$OVERVIEW" "" "$MAX_OVERVIEW_ROWS" "$MAX_OVERVIEW_BYTES" "$MAX_LINE"
    check_links
  elif [ $# -eq 0 ]; then
    printf '%s: 無い\n' "$OVERVIEW"
  fi
  if [ $# -eq 0 ]; then
    set -- "$DIR"/features/*.md
    if [ ! -f "$1" ]; then
      printf '%s/features: 機能設計書が無い\n' "$DIR"
      return
    fi
  fi
  for path in "$@"; do
    if [ -f "$path" ]; then
      check_text "$path" "何を作るか" "$MAX_SECTION_ROWS" "$MAX_SECTION_BYTES" "$MAX_LINE"
    else
      printf '%s: 無い\n' "$path"
    fi
  done
}

found=$(problems "$@")
[ -z "$found" ] && exit 0
printf '%s\n' "$found"
exit 1
