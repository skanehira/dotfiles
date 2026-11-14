#!/bin/sh
# dev-impl の Step 1: issue の着手順を計算する。規則の正本は SKILL.md「Step 1: issue の収集と着手順」。
#
# 使い方:
#   sh next-issues.sh collect <スナップショット> [issue 番号...]
#       GitHub から issue を集めてスナップショットに書き、着手順を出す。番号 (先頭の # は付けても付けなくてもよい)
#       を渡すと、その issue と、まだ終わっていない依存先だけを対象にする。対象にならない番号は標準エラーに出す
#   sh next-issues.sh mark <スナップショット> <番号> <started|closed|parked>
#       着手した (started)・merge して close した (closed)・needs-human に駐車した (parked) ことを
#       スナップショットに書き、着手順を出し直す。started と parked の issue は start に出さず、依存元を待たせる。
#       GitHub は読み直さない (run の途中で ready が付いた issue は拾わない)
#   sh next-issues.sh order <スナップショット>
#       スナップショットから着手順を出す
#
# 着手順の出力 (タブ区切り):
#   start<TAB>番号<TAB>実効スコア   着手できる issue。前回から再開する issue (in-progress か、issue-<番号> のブランチが
#                                   手元か origin に残るもの) が先、続いて実効スコアの高い順、
#                                   同じなら番号の小さい順。実効スコアは U (緊急枠)・数値・- (スコア無し)
#   wait<TAB>番号<TAB>依存先        close されていない依存先が残る issue (依存先はカンマ区切り)
#   cycle<TAB>番号                  依存が循環している issue。着手しない
#   unknown<TAB>番号<TAB>依存先     どこにも無い issue に依存している issue。着手しない
#   badline<TAB>番号<TAB>行         「Depends on」で始まるのに読めない行 (1 行に複数並べたなど) がある open の issue。着手しない
#
# 対象: open で ready か in-progress が付き、needs-human と tracking が付かず、読めない依存の行が無い issue。
#   番号を渡したときは、その issue と、まだ終わっていない依存先だけ。
# 実効スコア: 自分と、自分に直接・間接に依存する対象 issue の「## 優先度」のスコア (緊急枠は U) の最大値。
#
# 終了コード: 0 出せた / 1 使い方の誤り・gh の失敗・issue が上限 (環境変数 ISSUE_LIST_LIMIT、既定 1000 件) 以上ある
#
# POSIX の sh で書く (macOS の sh と Ubuntu の dash で動かすため。bash だけの書き方を使わない)。
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SPEC="$HERE/../../dev-spec/scripts"
# shellcheck source=../../dev-spec/scripts/lib.sh
. "$SPEC/lib.sh"

USAGE="使い方: sh next-issues.sh collect <スナップショット> [番号...] / mark <スナップショット> <番号> <started|closed|parked> / order <スナップショット>"
[ $# -ge 2 ] || die 1 "$USAGE"
CMD=$1
SNAP=$2
shift 2

TMP=$(mktemp -d "${TMPDIR:-/tmp}/next-issues.XXXXXX") || die 1 "一時ディレクトリを作れない"
trap 'rm -rf "$TMP"' EXIT

# スナップショットの列: 番号 / 状態 (target・open・closed) / スコア / 依存先 / 再開 (1|0) / 読めない依存の行
print_order() {
  [ -f "$SNAP" ] || die 1 "スナップショットが無い: $SNAP"
  awk -F '\t' -v mode=order -f "$SPEC/deps.awk" "$SNAP" >"$TMP/order.txt" || die 1 "着手順を計算できない"
  awk -F '\t' '
    FILENAME == ARGV[1] {
      if ($5 == "1") resume[$1] = 1
      if ($6 != "") bad[++nb] = $1 "\t" $6
      next
    }
    $1 == "start" && ($2 in resume) { print; next }
    $1 == "start" { starts[++ns] = $0; next }
    { others[++no] = $0 }
    END {
      for (i = 1; i <= ns; i++) print starts[i]
      for (i = 1; i <= no; i++) print others[i]
      for (i = 1; i <= nb; i++) print "badline\t" bad[i]
    }
  ' "$SNAP" "$TMP/order.txt"
}

case $CMD in
  collect)
    ARGS=""
    for a in "$@"; do
      a=${a#\#}
      case $a in '' | *[!0-9]*) die 1 "issue の番号は数で渡す: $a" ;; esac
      ARGS="$ARGS $a"
    done
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner </dev/null) || die 1 "GitHub のリポジトリを決められない"
    LIMIT=${ISSUE_LIST_LIMIT:-1000}
    case $LIMIT in '' | *[!0-9]* | 0*) die 1 "ISSUE_LIST_LIMIT には 1 以上の数を渡す: $LIMIT" ;; esac
    # 1 行に: 番号 / 状態 (OPEN|CLOSED) / ラベル (カンマ区切り) / 本文 (@tsv なので改行は \n の 2 文字)
    gh issue list --repo "$REPO" --state all --limit "$LIMIT" --json number,state,labels,body \
      --jq '.[] | [(.number | tostring), .state, ([.labels[].name] | join(",")), (.body // "")] | @tsv' \
      </dev/null >"$TMP/raw.tsv" || die 1 "issue の一覧を取れない"
    [ "$(wc -l <"$TMP/raw.tsv")" -lt "$LIMIT" ] || die 1 "issue が $LIMIT 件以上あり、取りこぼす。環境変数 ISSUE_LIST_LIMIT を $LIMIT より大きくして再実行する"
    # 前回の run が残した issue-<番号> のブランチ (手元か origin)。その issue は再開として先に回す
    git for-each-ref --format='%(refname)' refs/heads/ refs/remotes/origin/ 2>/dev/null |
      sed -n -e 's#^refs/heads/issue-\([0-9][0-9]*\)$#\1#p' -e 's#^refs/remotes/origin/issue-\([0-9][0-9]*\)$#\1#p' |
      sort -u | tr '\n' ' ' >"$TMP/branches.txt"
    awk -F '\t' -v args="$ARGS" -v branches="$(cat "$TMP/branches.txt")" '
      BEGIN {
        nbr = split(branches, br, " ")
        for (i = 1; i <= nbr; i++) has_branch[br[i] + 0] = 1
      }
      {
        num = $1 + 0
        ids[++cnt] = num
        st[num] = $2
        lab = "," $3 ","
        n = split($4, lines, /\\n/)
        deps = ""; score = ""; bad = ""; insec = 0
        for (i = 1; i <= n; i++) {
          line = lines[i]
          sub(/\\r$/, "", line)
          if (line ~ /^## /) insec = (line ~ /^## 優先度[ \t]*$/)
          if (insec && line ~ /^緊急枠 \(/) score = "U"
          else if (insec && score != "U" && line ~ /^スコア [0-9]+(\.[0-9]+)?/) {
            s = line
            sub(/^スコア /, "", s)
            sub(/[^0-9.].*$/, "", s)
            score = s
          }
          if (line ~ /^Depends on/) {
            if (line ~ /^Depends on #[0-9]+[ \t]*$/) {
              d = line
              sub(/^Depends on #/, "", d)
              sub(/[ \t]*$/, "", d)
              deps = deps (deps == "" ? "" : ",") d
            } else if (bad == "" && $2 == "OPEN") bad = line
          }
        }
        sc[num] = score; dp[num] = deps; bd[num] = bad
        inprog[num] = (lab ~ /,in-progress,/)
        eligible[num] = ($2 == "OPEN" && (lab ~ /,ready,/ || lab ~ /,in-progress,/) && lab !~ /,needs-human,/ && lab !~ /,tracking,/ && bad == "")
      }
      END {
        if (args == "") {
          for (i = 1; i <= cnt; i++) if (eligible[ids[i]]) target[ids[i]] = 1
        } else {
          q = split(args, queue, " ")
          for (h = 1; h <= q; h++) asked[queue[h] + 0] = 1
          for (h = 1; h <= q; h++) {
            x = queue[h] + 0
            if (seen[x]++ || !eligible[x]) continue
            target[x] = 1
            k = split(dp[x], ds, ",")
            for (j = 1; j <= k; j++) {
              d = ds[j] + 0
              if (st[d] == "OPEN" && !seen[d]) queue[++q] = d
            }
          }
        }
        for (x in asked) {
          if (!(x in target)) printf "#%d は対象にならない (open で ready か in-progress が付き、needs-human と tracking が付いていない issue だけが対象)\n", x | "cat 1>&2"
        }
        for (i = 1; i <= cnt; i++) {
          x = ids[i]
          if (st[x] == "CLOSED") s = "closed"
          else if (x in target) s = "target"
          else s = "open"
          printf "%d\t%s\t%s\t%s\t%d\t%s\n", x, s, sc[x], dp[x], (s == "target" && (inprog[x] || (x in has_branch))), bd[x]
        }
      }
    ' "$TMP/raw.tsv" >"$SNAP" || die 1 "スナップショットを書けない: $SNAP"
    print_order
    ;;
  mark)
    [ $# -eq 2 ] || die 1 "$USAGE"
    case $2 in started | closed | parked) ;; *) die 1 "$USAGE" ;; esac
    [ -f "$SNAP" ] || die 1 "スナップショットが無い: $SNAP"
    awk -F '\t' -v n="$1" '$1 == n { found = 1 } END { exit !found }' "$SNAP" || die 1 "スナップショットに #$1 が無い"
    awk -F '\t' -v OFS='\t' -v n="$1" -v how="$2" '
      $1 == n { $2 = (how == "closed" ? "closed" : "open"); $5 = 0 }
      { print }
    ' "$SNAP" >"$TMP/snap.tsv" && cat "$TMP/snap.tsv" >"$SNAP"
    print_order
    ;;
  order)
    [ $# -eq 0 ] || die 1 "$USAGE"
    print_order
    ;;
  *)
    die 1 "$USAGE"
    ;;
esac
