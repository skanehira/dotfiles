#!/bin/sh
# ドラフトの子 issue の依存の段数と、実行バッチ数・下限を出す (dev-spec のフェーズ 9 のドラフトチェック)。
#
# 使い方: sh dep-depth.sh [--serial] <ドラフトのディレクトリ>
#   --serial: dev-impl が並列実行を許さないプロジェクト。閾値の判定をしないと行に添える
#
# 出力の 1 行目: 依存段数: L0..L<k> (<k+1> 段、実行バッチ <b> / 下限 <m>)
#   実行バッチ <b> は、各段を 3 件ずつに分けて流したときのバッチ数の和、下限 <m> は ceil(子の件数 / 3)
# 2 行目以降: 段ごとの子 (L<段>: issue-<連番> ...)
#
# 終了コード: 0 計算できた / 1 使い方の誤り・ドラフトが無い / 2 ドラフトに無い連番への依存
#             3 依存の循環 / 4 依存の行の形の誤り
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$HERE/lib.sh"

serial=0
if [ "${1:-}" = "--serial" ]; then
  serial=1
  shift
fi
[ $# -eq 1 ] || die 1 "使い方: sh dep-depth.sh [--serial] <ドラフトのディレクトリ>"
DIR=$1

TMP=$(mktemp -d "${TMPDIR:-/tmp}/dep-depth.XXXXXX") || die 1 "一時ディレクトリを作れない"
trap 'rm -rf "$TMP"' EXIT

draft_graph "$DIR" "$TMP/graph.tsv" || exit $?
[ -s "$TMP/graph.tsv" ] || die 1 "issue-*.md が無い: $DIR"

awk -F '\t' -v mode=levels -f "$HERE/deps.awk" "$TMP/graph.tsv" >"$TMP/levels.txt"
rc=$?
if [ "$rc" -ne 0 ]; then
  explain_graph_error "$TMP/levels.txt"
  exit "$rc"
fi

awk -F '\t' -v serial="$serial" '
  BEGIN { k = 0; total = 0 }
  {
    lv = $3 + 0
    cnt[lv]++
    members[lv] = members[lv] (members[lv] == "" ? "" : " ") "issue-" $2
    if (lv > k) k = lv
    total++
  }
  END {
    b = 0
    for (i = 0; i <= k; i++) b += int((cnt[i] + 2) / 3)
    m = int((total + 2) / 3)
    note = serial ? " (並列前提を満たさないため閾値判定なし)" : ""
    printf "依存段数: L0..L%d (%d 段、実行バッチ %d / 下限 %d)%s\n", k, k + 1, b, m, note
    for (i = 0; i <= k; i++) printf "L%d: %s\n", i, members[i]
  }
' "$TMP/levels.txt"
