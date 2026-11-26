#!/bin/sh
# 機能設計書の「実装の配置」の表を集め、実装先ファイルごとに作る機能設計書がちょうど 1 本かを検査する。
#
# 使い方: sh placement-check.sh <docs/design のディレクトリ>
#   リポジトリの最上位で実行する。作る機能設計書が無いファイルは、リポジトリに既にあれば問題にしない。
#
# 出力: 問題 1 件につき 1 行。問題が無ければ何も出さない
# 終了コード: 0 問題なし / 1 問題あり / 2 使い方の誤り
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$HERE/lib.sh"

[ $# -eq 1 ] && [ -d "$1/features" ] || die 2 "使い方: sh placement-check.sh <docs/design のディレクトリ>"
DIR=$1

rows() {
  awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function problem(msg) { printf "PROB\t%s\n", msg }
    function record(path, kind) { printf "REC\t%s\t%s\t%s\n", path, kind, FILENAME }
    FNR == 1 { inside = 0 }
    /^## / { inside = ($0 ~ /^## 実装の配置[ \t]*$/); tables = 0; in_table = 0; next }
    !inside { next }
    !/^\|/ { in_table = 0; next }
    !in_table {
      in_table = 1; tables++; fcol = 0; kcol = 0
      n = split($0, c, "|")
      for (i = 2; i < n; i++) {
        if (trim(c[i]) == "実装先ファイル") fcol = i
        if (trim(c[i]) == "作る / 足す") kcol = i
      }
      if (tables == 1 && !fcol) problem(FILENAME ": 「実装の配置」の表に「実装先ファイル」の列が無い")
      else if (fcol && !kcol) problem(FILENAME ": 「実装の配置」の表に「作る / 足す」の列が無い")
      next
    }
    $0 ~ /^\|[ \t:|-]+$/ || !fcol || !kcol { next }
    {
      split($0, c, "|")
      where = FILENAME ":" FNR
      kind = trim(c[kcol])
      if (kind != "作る" && kind != "足す") {
        problem(where ": 「作る / 足す」の値が「作る」「足す」のどちらでもない (" kind ")")
        next
      }
      cell = c[fcol]
      if (cell !~ /`[^`]+`/) {
        problem(where ": 「実装先ファイル」のパスをバッククォートで囲んでいない")
        next
      }
      while (match(cell, /`[^`]+`/)) {
        path = substr(cell, RSTART + 1, RLENGTH - 2)
        cell = substr(cell, RSTART + RLENGTH)
        if (path ~ /\/$/) problem(where ": 「実装先ファイル」にディレクトリを書いている (" path ")")
        else if (path ~ /^\.\//) record(substr(path, 3), kind)
        else if (path ~ /\//) record(path, kind)
        else printf "BARE\t%s\t%s\t%s\t%s\n", where, path, kind, FILENAME
      }
    }
  ' "$DIR"/features/*.md | while IFS= read -r line; do
    case $line in
      BARE*)
        IFS='	' read -r _ where path kind doc <<END
$line
END
        if [ -e "$path" ]; then
          printf 'REC\t%s\t%s\t%s\n' "$path" "$kind" "$doc"
        else
          printf 'PROB\t%s: 「実装先ファイル」が最上位からのファイルのパスでない (%s)\n' "$where" "$path"
        fi
        ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
}

owners() {
  grep '^REC	' | sort -u | awk -F '\t' '
    function flush() {
      if (path == "") return
      if (makers >= 2) printf "MANY\t%s\t%d\t%s\n", path, makers, maker_docs
      else if (makers == 0) printf "NONE\t%s\t0\t%s\n", path, adder_docs
    }
    { row_path = $2; kind = $3; doc = $4 }
    row_path != path { flush(); path = row_path; makers = 0; maker_docs = ""; adder_docs = ""; last_maker = ""; last_adder = "" }
    kind == "作る" && doc != last_maker { maker_docs = maker_docs (makers++ ? ", " : "") doc; last_maker = doc }
    kind == "足す" && doc != last_adder { adder_docs = adder_docs (last_adder != "" ? ", " : "") doc; last_adder = doc }
    END { flush() }
  '
}

problems() {
  all=$(rows)
  printf '%s\n' "$all" | sed -n 's/^PROB	//p'
  printf '%s\n' "$all" | owners | while IFS='	' read -r kind path count docs; do
    case $kind in
      MANY) printf '%s: 作る機能設計書が %s 本ある (%s)\n' "$path" "$count" "$docs" ;;
      NONE) [ -e "$path" ] || printf '%s: 作る機能設計書が無い (足す: %s)\n' "$path" "$docs" ;;
    esac
  done
}

found=$(problems)
[ -z "$found" ] && exit 0
printf '%s\n' "$found"
exit 1
