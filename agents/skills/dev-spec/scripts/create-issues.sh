#!/bin/sh
# dev-spec のフェーズ 10: ドラフトから GitHub の issue (親と子) を作り、子を親に紐付ける。
# 規則の正本は references/issue-template.md「issue 作成手順」の「スクリプトが行うこと」で、下の節の番号は
# その手順の番号と同じ。何度実行しても同じ結果になる (冪等)。
#
# 使い方: sh create-issues.sh [--keep <番号>]... <ドラフトのディレクトリ>
#   ディレクトリには titles.tsv・parent-<識別子>.md・issue-<連番>.md を置く (フェーズ 9 が書く)
#   カレントディレクトリの GitHub リポジトリに作る (gh repo view で決める)
#   --keep <番号>: 人間が「旧親のまま残す」と決めた tracking の親。突き合わせ・流用・移行の対象から外す
#                  (番号はカンマ区切りでも、--keep を繰り返してもよい)
#
# 終了コード:
#   0 作成と紐付けを終えた。最終報告を標準出力に出す
#   1 使い方の誤り・gh の失敗などで止まった。状態を標準エラーに出す。原因を直して同じコマンドを再実行すると続きから進む
#     既存の issue が上限 (環境変数 ISSUE_LIST_LIMIT、既定 1000 件) 以上あるときも 1 で止まる
#   3 人間の判断が要る。NEEDS_HUMAN: で始まる行を出す。GitHub には何もしていない
#   4 ドラフトの誤り。標準エラーに挙げる。GitHub には何もしていない
#
# POSIX の sh で書く (macOS の sh と Ubuntu の dash で動かすため。bash だけの書き方を使わない)。
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$HERE/lib.sh"

USAGE="使い方: sh create-issues.sh [--keep <番号>]... <ドラフトのディレクトリ>"
KEEP=""
while [ $# -gt 1 ]; do
  case $1 in
    --keep)
      [ $# -ge 3 ] || die 1 "$USAGE"
      for k in $(printf '%s' "$2" | tr ',' ' '); do
        k=${k#\#}
        case $k in '' | *[!0-9]*) die 1 "--keep には issue の番号を渡す: $2" ;; esac
        KEEP="$KEEP $k"
      done
      shift 2
      ;;
    *) die 1 "$USAGE" ;;
  esac
done
[ $# -eq 1 ] || die 1 "$USAGE"
DIR=$(cd "$1" 2>/dev/null && pwd) || die 1 "ドラフトのディレクトリが無い: $1"
TITLES="$DIR/titles.tsv"
NUMBERS="$DIR/numbers.tsv"
[ -f "$TITLES" ] || die 4 "titles.tsv が無い: $DIR"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/create-issues.XXXXXX") || die 1 "一時ディレクトリを作れない"
trap 'rm -rf "$TMP"' EXIT

TAB=$(printf '\t')

# ループの中で呼んでも、ループの入力を読まないようにする
run_gh() { gh "$@" </dev/null; }

title_of() { awk -F '\t' -v f="$1" '$1 == f { print $2; exit }' "$TITLES"; }

# 「対応 UC:」の値から親のキー (基盤 か UC-<番号>) を 1 行ずつ出す
uc_keys() {
  printf '%s\n' "$1" | awk '
    {
      s = $0
      sub(/^[ \t]+/, "", s)
      sub(/[ \t]+$/, "", s)
      if (s == "基盤") { print "基盤"; exit }
      while (match(s, /UC-[0-9]+/)) {
        print substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
      }
    }'
}

uc_line_of() { awk '/^対応 UC:/ { sub(/^対応 UC:[ \t]*/, ""); print; exit }' "$1"; }

# --- 1. ドラフトを確かめる (GitHub には触らない) -------------------------------

for f in "$DIR"/parent-*.md; do [ -f "$f" ] && basename "$f"; done | LC_ALL=C sort >"$TMP/parents.list"
[ -s "$TMP/parents.list" ] || die 4 "parent-*.md が無い: $DIR"

: >"$TMP/errors.txt"
err() { printf '%s\n' "$*" >>"$TMP/errors.txt"; }

# 親のキー: UC-001 → UC-001、UC-004-005 → UC-004 と UC-005、kiban と quick → 基盤
: >"$TMP/parentkeys.tsv"
while IFS= read -r p; do
  [ -n "$(title_of "$p")" ] || err "$p: titles.tsv にタイトルが無い"
  ident=${p#parent-}
  ident=${ident%.md}
  case $ident in
    quick | kiban) printf '基盤\t%s\n' "$p" >>"$TMP/parentkeys.tsv" ;;
    UC-*)
      printf '%s\n' "${ident#UC-}" | tr '-' '\n' | while IFS= read -r num; do
        printf 'UC-%s\t%s\n' "$num" "$p"
      done >>"$TMP/parentkeys.tsv"
      ;;
    *) err "$p: 識別子が UC-<番号>・kiban・quick のどれでもない" ;;
  esac
done <"$TMP/parents.list"
cut -f 1 "$TMP/parentkeys.tsv" | sort | uniq -d | while IFS= read -r k; do
  err "対応 UC $k の親のドラフトが 2 つある"
done
cut -f 2 "$TITLES" | sort | uniq -d | while IFS= read -r t; do
  err "titles.tsv に同じタイトルが複数ある: $t"
done
if [ -f "$DIR/parent-quick.md" ]; then MODE=quick; else MODE=uc; fi

graph_rc=0
draft_graph "$DIR" "$TMP/graph.tsv" 2>>"$TMP/errors.txt" || graph_rc=$?
if [ "$graph_rc" -eq 0 ]; then
  [ -s "$TMP/graph.tsv" ] || err "issue-*.md が無い: $DIR"
  if [ -s "$TMP/graph.tsv" ]; then
    awk -F '\t' -v mode=levels -f "$HERE/deps.awk" "$TMP/graph.tsv" >"$TMP/levels.txt" ||
      explain_graph_error "$TMP/levels.txt" 2>>"$TMP/errors.txt"
  fi
fi

# 子 → 親のドラフト
: >"$TMP/childparent.tsv"
if [ -s "$TMP/graph.tsv" ]; then
  cut -f 1 "$TMP/graph.tsv" | while IFS= read -r n; do
    c="issue-$n.md"
    [ -n "$(title_of "$c")" ] || err "$c: titles.tsv にタイトルが無い"
    uc=$(uc_line_of "$DIR/$c")
    if [ -z "$uc" ]; then
      err "$c: 「対応 UC:」の行が無い"
      continue
    fi
    uc_keys "$uc" >"$TMP/keys.txt"
    [ -s "$TMP/keys.txt" ] || { err "$c: 「対応 UC:」の値が 基盤 でも UC-<番号> でもない: $uc"; continue; }
    : >"$TMP/cparents.txt"
    missing=""
    while IFS= read -r k; do
      p=$(awk -F '\t' -v k="$k" '$1 == k { print $2; exit }' "$TMP/parentkeys.tsv")
      if [ -z "$p" ]; then missing="$missing $k"; else echo "$p" >>"$TMP/cparents.txt"; fi
    done <"$TMP/keys.txt"
    if [ -n "$missing" ]; then
      err "$c: 対応 UC (${missing# }) の親のドラフトが無い"
    elif [ "$(sort -u "$TMP/cparents.txt" | wc -l)" -ne 1 ]; then
      err "$c: 対応 UC ($(tr '\n' ' ' <"$TMP/keys.txt" | sed 's/ $//')) が 1 つの親にまとまらない。UC ごとに子を分けるか、統合親を作る"
    else
      printf '%s\t%s\n' "$c" "$(head -n 1 "$TMP/cparents.txt")" >>"$TMP/childparent.tsv"
    fi
  done
fi

if [ -s "$TMP/errors.txt" ]; then
  cat "$TMP/errors.txt" >&2
  exit 4
fi

# 依存の上流から並べた子
awk -F '\t' '{ print "issue-" $2 ".md" }' "$TMP/levels.txt" >"$TMP/children.list"

# --- 2. 既存の issue と突き合わせる (まだ何も変えない) ---------------------------

REPO=$(run_gh repo view --json nameWithOwner -q .nameWithOwner) ||
  die 1 "GitHub のリポジトリを決められない (git リポジトリでない・GitHub のリモートが無い・gh が未認証)。リポジトリを用意してから再実行する"

LIMIT=${ISSUE_LIST_LIMIT:-1000}
case $LIMIT in '' | *[!0-9]* | 0*) die 1 "ISSUE_LIST_LIMIT には 1 以上の数を渡す: $LIMIT" ;; esac
# 1 行に: 番号 / 状態 (OPEN|CLOSED) / ラベル (カンマ区切り) / 本文に「対応 UC:」行があれば uc、無ければ - / タイトル
run_gh issue list --repo "$REPO" --state all --limit "$LIMIT" --json number,title,state,labels,body \
  --jq '.[] | [(.number | tostring), .state, ([.labels[].name] | join(",")), (if ((.body // "") | test("(?m)^対応 UC:")) then "uc" else "-" end), .title] | @tsv' \
  >"$TMP/existing_raw.tsv" || die 1 "既存の issue の一覧を取れない"
# gh は新しい順に返す。報告の順を決めるため番号の昇順に並べる
sort -t "$TAB" -k1,1n "$TMP/existing_raw.tsv" >"$TMP/existing.tsv"
[ "$(wc -l <"$TMP/existing.tsv")" -lt "$LIMIT" ] || die 1 "既存の issue が $LIMIT 件以上あり、取りこぼす。環境変数 ISSUE_LIST_LIMIT を $LIMIT より大きくして再実行する"

existing_by_title() { awk -F '\t' -v t="$1" '$5 == t { print $1 }' "$TMP/existing.tsv"; }
state_of() { awk -F '\t' -v n="$1" '$1 == n { print $2; exit }' "$TMP/existing.tsv"; }

# ドラフト → 既存の番号 (タイトルの完全一致)
: >"$TMP/matched.tsv"
: >"$TMP/needs_human.txt"
cat "$TMP/parents.list" "$TMP/children.list" | while IFS= read -r f; do
  t=$(title_of "$f")
  existing_by_title "$t" >"$TMP/hits.txt"
  case $(wc -l <"$TMP/hits.txt" | tr -d ' ') in
    0) ;;
    1) printf '%s\t%s\n' "$f" "$(cat "$TMP/hits.txt")" >>"$TMP/matched.tsv" ;;
    *) printf 'NEEDS_HUMAN: 同じタイトルの issue が複数あり、どれに当たるか決められない: %s (%s)\n' "$t" "$(sed 's/^/#/' "$TMP/hits.txt" | tr '\n' ' ' | sed 's/ $//; s/ / \/ /g')" >>"$TMP/needs_human.txt" ;;
  esac
done
matched_num() { awk -F '\t' -v f="$1" '$1 == f { print $2; exit }' "$TMP/matched.tsv"; }

# tracking の親のうち、どの親のドラフトとも一致せず、--keep で残すと決めたものでもない open の親。
# closed の親は、終わった別の作業の親なので、流用も移行もしない
cut -f 2 "$TMP/matched.tsv" >"$TMP/matched_nums.txt"
for k in $KEEP; do echo "$k"; done >>"$TMP/matched_nums.txt"
awk -F '\t' 'FILENAME == ARGV[1] { m[$1] = 1; next } $2 == "OPEN" && ("," $3 ",") ~ /,tracking,/ && !($1 in m) { print $1 "\t" $5 }' \
  "$TMP/matched_nums.txt" "$TMP/existing.tsv" >"$TMP/stray_parents.tsv"
grep " トラッキング$" "$TMP/stray_parents.tsv" >"$TMP/old_parents.tsv" || true
grep -v " トラッキング$" "$TMP/stray_parents.tsv" >"$TMP/other_parents.tsv" || true

list_issues() { sed "s/^\([0-9]*\)${TAB}/#\1 /" "$1" | awk '{ s = s (NR > 1 ? " / " : "") $0 } END { print s }'; }

sub_issues_of() {
  run_gh api --paginate "repos/$REPO/issues/$1/sub_issues?per_page=100" --jq '.[].number' ||
    die 1 "#$1 の子の一覧を取れない"
}

MIGRATE=""
if [ "$MODE" = quick ]; then
  if [ -z "$(matched_num parent-quick.md)" ]; then
    case $(wc -l <"$TMP/old_parents.tsv" | tr -d ' ') in
      0) ;;
      1) printf 'parent-quick.md\t%s\n' "$(cut -f 1 "$TMP/old_parents.tsv")" >>"$TMP/matched.tsv" ;;
      *) printf 'NEEDS_HUMAN: 「<タスク名> トラッキング」の親が複数ある。どれを流用するかを選ぶ: %s\n' "$(list_issues "$TMP/old_parents.tsv")" >>"$TMP/needs_human.txt" ;;
    esac
  fi
else
  case $(wc -l <"$TMP/old_parents.tsv" | tr -d ' ') in
    0) ;;
    1) MIGRATE=$(cut -f 1 "$TMP/old_parents.tsv") ;;
    *) printf 'NEEDS_HUMAN: 旧構成の「<タスク名> トラッキング」の親が複数ある。どれから移行するかを選ぶ: %s\n' "$(list_issues "$TMP/old_parents.tsv")" >>"$TMP/needs_human.txt" ;;
  esac
  : >"$TMP/stray_with_children.txt"
  while IFS="$TAB" read -r n t; do
    sub_issues_of "$n" >"$TMP/subs.txt"
    [ -s "$TMP/subs.txt" ] &&
      printf '#%s %s (子: %s)\n' "$n" "$t" "$(sed 's/^/#/' "$TMP/subs.txt" | tr '\n' ' ' | sed 's/ $//')" >>"$TMP/stray_with_children.txt"
  done <"$TMP/other_parents.tsv"
  if [ -s "$TMP/stray_with_children.txt" ]; then
    printf 'NEEDS_HUMAN: どの親のドラフトとも一致しない tracking の親が子を持つ。どの新しい親へ貼り替えるか、旧親のまま残すかを決める: %s\n' \
      "$(awk '{ s = s (NR > 1 ? " / " : "") $0 } END { print s }' "$TMP/stray_with_children.txt")" >>"$TMP/needs_human.txt"
  fi
fi

if [ -s "$TMP/needs_human.txt" ]; then
  cat "$TMP/needs_human.txt"
  exit 3
fi

# --- 3. ラベルを用意する -----------------------------------------------------

run_gh label create ready --repo "$REPO" --force --color 0E8A16 --description "着手可能" >/dev/null || die 1 "ラベル ready を作れない"
run_gh label create in-progress --repo "$REPO" --force --color 1D76DB --description "dev-impl が実装中" >/dev/null || die 1 "ラベル in-progress を作れない"
run_gh label create needs-human --repo "$REPO" --force --color D93F0B --description "人間の判断待ちで駐車中" >/dev/null || die 1 "ラベル needs-human を作れない"
run_gh label create tracking --repo "$REPO" --force --color 5319E7 --description "親 issue (トラッキング)。実装対象ではない" >/dev/null || die 1 "ラベル tracking を作れない"

: >"$NUMBERS"
: >"$TMP/created.txt"
: >"$TMP/states.tsv"
number_of() { awk -F '\t' -v f="$1" '$1 == f { print $2; exit }' "$NUMBERS"; }

create_issue() { # $1: ドラフト $2: ラベル
  url=$(run_gh issue create --repo "$REPO" --title "$(title_of "$1")" --body-file "$DIR/$1" --label "$2") ||
    die 1 "$1 の issue を作れなかった。作成済みの番号は $NUMBERS にある。同じコマンドを再実行すると、続きから作る"
  created=${url##*/}
  printf '%s\t%s\n' "$1" "$created" >>"$NUMBERS"
  printf '%s\n' "$1" >>"$TMP/created.txt"
  printf '%s\tOPEN\n' "$created" >>"$TMP/states.tsv"
}

# --- 4. 親を用意する ---------------------------------------------------------

while IFS= read -r p; do
  n=$(matched_num "$p")
  if [ -n "$n" ]; then
    printf '%s\t%s\n' "$p" "$n" >>"$NUMBERS"
    printf '%s\t%s\n' "$n" "$(state_of "$n")" >>"$TMP/states.tsv"
  else
    create_issue "$p" tracking
  fi
done <"$TMP/parents.list"

# --- 5. 子を依存の上流から用意する (作る直前に依存を番号に置き換える) -----------

replace_dependencies() { # $1: ドラフト
  awk -F '\t' '
    FILENAME == ARGV[1] { num[$1] = $2; next }
    /^Depends on issue-[0-9]+[ \t]*$/ {
      k = $0
      sub(/^Depends on issue-/, "", k)
      sub(/[ \t]*$/, "", k)
      f = "issue-" k ".md"
      if (f in num) { print "Depends on #" num[f]; next }
    }
    { print }
  ' "$NUMBERS" "$DIR/$1" >"$TMP/replaced.md" && cat "$TMP/replaced.md" >"$DIR/$1"
}

while IFS= read -r c; do
  replace_dependencies "$c"
  n=$(matched_num "$c")
  if [ -n "$n" ]; then
    printf '%s\t%s\n' "$c" "$n" >>"$NUMBERS"
    printf '%s\t%s\n' "$n" "$(state_of "$n")" >>"$TMP/states.tsv"
  else
    create_issue "$c" ready
  fi
done <"$TMP/children.list"

if grep -n '^Depends on issue-[0-9]' "$DIR"/issue-*.md >"$TMP/left.txt"; then
  cat "$TMP/left.txt" >&2
  die 1 "番号に置き換えられなかった依存が残っている (上の行)"
fi

# --- 6. 既存の issue の本文を、依存を置き換えた後のドラフトと比べる -------------

# 比べる前に、CR と末尾の空行を落とす。GitHub は本文を末尾の改行も含めて保存し、gh -q はさらに改行を
# 1 つ足して出す。Web の画面で編集された本文は CRLF になり、末尾の改行の数も変わる
normalize_body() {
  tr -d '\r' | awk '{ l[NR] = $0 } END { n = NR; while (n > 0 && l[n] == "") n--; for (i = 1; i <= n; i++) print l[i] }'
}

: >"$TMP/closed_mismatch.txt"
child_updated=0
child_unchanged=0
while IFS="$TAB" read -r f n; do
  grep -Fxq "$f" "$TMP/created.txt" && continue
  run_gh issue view "$n" --repo "$REPO" --json body -q .body >"$TMP/raw.md" || die 1 "#$n の本文を取れない"
  normalize_body <"$TMP/raw.md" >"$TMP/current.md"
  normalize_body <"$DIR/$f" >"$TMP/draft.md"
  if cmp -s "$TMP/current.md" "$TMP/draft.md"; then
    case $f in issue-*) child_unchanged=$((child_unchanged + 1)) ;; esac
  elif [ "$(state_of "$n")" = CLOSED ]; then
    echo "#$n" >>"$TMP/closed_mismatch.txt"
    case $f in issue-*) child_unchanged=$((child_unchanged + 1)) ;; esac
  else
    run_gh issue edit "$n" --repo "$REPO" --body-file "$DIR/$f" >/dev/null || die 1 "#$n の本文を貼り直せない"
    case $f in issue-*) child_updated=$((child_updated + 1)) ;; esac
  fi
done <"$NUMBERS"

# --- 7. 旧構成から移行する・8. 子を親に紐付ける ---------------------------------

parent_num_for_keys() { # 標準入力のキーから親の番号を出す。1 つにまとまらなければ何も出さない
  while IFS= read -r k; do
    pf=$(awk -F '\t' -v k="$k" '$1 == k { print $2; exit }' "$TMP/parentkeys.tsv")
    [ -n "$pf" ] && number_of "$pf"
    [ -n "$pf" ] || echo "?"
  done | sort -u >"$TMP/pnums.txt"
  if [ "$(wc -l <"$TMP/pnums.txt" | tr -d ' ')" -eq 1 ] && ! grep -qx '?' "$TMP/pnums.txt"; then
    cat "$TMP/pnums.txt"
  fi
}

issue_id() { run_gh api "repos/$REPO/issues/$1" --jq .id || die 1 "#$1 の id を取れない"; }

current_state() { awk -F '\t' -v n="$1" '$1 == n { s = $2 } END { print s }' "$TMP/states.tsv"; }

link() { # $1: 子 $2: 親 [$3: replace]
  if [ "$(current_state "$2")" = CLOSED ]; then
    run_gh issue reopen "$2" --repo "$REPO" --comment "issue が追加されたため再オープンする" >/dev/null || die 1 "#$2 を reopen できない"
    printf '%s\tOPEN\n' "$2" >>"$TMP/states.tsv"
  fi
  id=$(issue_id "$1") || exit 1
  if [ "${3:-}" = replace ]; then
    run_gh api "repos/$REPO/issues/$2/sub_issues" -F sub_issue_id="$id" -F replace_parent=true >/dev/null
  else
    run_gh api "repos/$REPO/issues/$2/sub_issues" -F sub_issue_id="$id" >/dev/null
  fi || die 1 "#$1 を親 #$2 に紐付けられなかった。作成済みの番号は numbers.tsv にある。同じコマンドを再実行すると、続きから紐付ける"
}

body_keys() { # $1: issue の番号。本文の「対応 UC:」のキーを出す
  run_gh issue view "$1" --repo "$REPO" --json body -q .body >"$TMP/raw.md" || die 1 "#$1 の本文を取れない"
  uc=$(tr -d '\r' <"$TMP/raw.md" | awk '/^対応 UC:/ { sub(/^対応 UC:[ \t]*/, ""); print; exit }')
  [ -n "$uc" ] && uc_keys "$uc"
  return 0
}

: >"$TMP/unknown_uc.txt"
relinked=0
OLD_CLOSED=""
if [ -n "$MIGRATE" ]; then
  sub_issues_of "$MIGRATE" >"$TMP/old_children.txt"
  while IFS= read -r c; do
    body_keys "$c" >"$TMP/bkeys.txt"
    p=$(parent_num_for_keys <"$TMP/bkeys.txt")
    if [ -n "$p" ]; then
      link "$c" "$p" replace
      relinked=$((relinked + 1))
    else
      echo "#$c" >>"$TMP/unknown_uc.txt"
    fi
  done <"$TMP/old_children.txt"
  sub_issues_of "$MIGRATE" >"$TMP/old_children.txt"
  if [ ! -s "$TMP/old_children.txt" ]; then
    run_gh issue close "$MIGRATE" --repo "$REPO" --comment "ユースケース単位のトラッキング issue へ移行したため close する" >/dev/null ||
      die 1 "旧親 #$MIGRATE を close できない"
    OLD_CLOSED=$MIGRATE
  fi
fi

# 親ごとに、紐付け済みの子 (子<TAB>親)
: >"$TMP/linked.tsv"
cut -f 2 "$TMP/childparent.tsv" | sort -u >"$TMP/used_parents.txt"
while IFS= read -r pf; do
  p=$(number_of "$pf")
  sub_issues_of "$p" >"$TMP/subs.txt"
  sed "s/\$/${TAB}$p/" "$TMP/subs.txt" >>"$TMP/linked.tsv"
done <"$TMP/used_parents.txt"

# 子の今の親の番号を $TMP/cur.txt に書く (親が無ければ空)
current_parent() {
  : >"$TMP/cur.txt"
  if run_gh api "repos/$REPO/issues/$1/parent" --jq .number >"$TMP/cur.txt" 2>"$TMP/parent_err.txt"; then
    return 0
  fi
  : >"$TMP/cur.txt"
  grep -q 'HTTP 404' "$TMP/parent_err.txt" || die 1 "#$1 の親を確かめられない: $(cat "$TMP/parent_err.txt")"
}

: >"$TMP/other_parent.txt"
while IFS= read -r c; do
  n=$(number_of "$c")
  p=$(number_of "$(awk -F '\t' -v c="$c" '$1 == c { print $2; exit }' "$TMP/childparent.tsv")")
  grep -Fxq "$n$TAB$p" "$TMP/linked.tsv" && continue
  current_parent "$n"
  cur=$(cat "$TMP/cur.txt")
  if [ -z "$cur" ]; then
    link "$n" "$p"
  elif [ "$cur" != "$p" ]; then
    echo "#$n (親 #$cur)" >>"$TMP/other_parent.txt"
  fi
done <"$TMP/children.list"

# ドラフトに無い既存の子: 親が無ければ、本文の「対応 UC」で紐付ける
cut -f 2 "$NUMBERS" >"$TMP/ours.txt"
awk -F '\t' 'FILENAME == ARGV[1] { m[$1] = 1; next } $2 == "OPEN" && $4 == "uc" && ("," $3 ",") !~ /,tracking,/ && !($1 in m) { print $1 "\t" $2 "\t" $5 }' \
  "$TMP/ours.txt" "$TMP/existing.tsv" >"$TMP/strays.tsv"
: >"$TMP/unmatched_open.txt"
while IFS="$TAB" read -r n _ t; do
  echo "#$n $t" >>"$TMP/unmatched_open.txt"
  current_parent "$n"
  [ -s "$TMP/cur.txt" ] && continue
  body_keys "$n" >"$TMP/bkeys.txt"
  p=$(parent_num_for_keys <"$TMP/bkeys.txt")
  if [ -n "$p" ]; then link "$n" "$p"; else echo "#$n" >>"$TMP/unknown_uc.txt"; fi
done <"$TMP/strays.tsv"

# --- 9. 最終報告 -------------------------------------------------------------

joined() { tr '\n' ' ' <"$1" | sed 's/ $//'; }

parents_new=$(grep -c '^parent-' "$TMP/created.txt")
parents_total=$(wc -l <"$TMP/parents.list" | tr -d ' ')
printf '親 issue: 新規 %s / 既存 %s\n' "$parents_new" $((parents_total - parents_new))
while IFS= read -r p; do
  printf '  #%s %s\n' "$(number_of "$p")" "$(title_of "$p")"
done <"$TMP/parents.list"
printf '子 issue: 新規 %s / 本文更新 %s / 変更なし %s\n' "$(grep -c '^issue-' "$TMP/created.txt")" "$child_updated" "$child_unchanged"
if [ -n "$MIGRATE" ]; then
  if [ -n "$OLD_CLOSED" ]; then
    printf '旧構成からの移行: 貼り替え %s 件、close した旧親 #%s\n' "$relinked" "$OLD_CLOSED"
  else
    printf '旧構成からの移行: 貼り替え %s 件。旧親 #%s には子が残るので open のまま\n' "$relinked" "$MIGRATE"
  fi
fi
sort -u "$TMP/unknown_uc.txt" >"$TMP/unknown_uc_sorted.txt"
[ -s "$TMP/unknown_uc_sorted.txt" ] && printf '対応 UC 不明で紐付けなかった子: %s\n' "$(joined "$TMP/unknown_uc_sorted.txt")"
[ -s "$TMP/other_parent.txt" ] && printf '別の親に付いているので紐付けを変えなかった子: %s\n' "$(awk '{ s = s (NR > 1 ? " / " : "") $0 } END { print s }' "$TMP/other_parent.txt")"
[ -s "$TMP/closed_mismatch.txt" ] && printf 'closed だが本文が現ドラフトと違う issue: %s\n' "$(joined "$TMP/closed_mismatch.txt")"
[ -s "$TMP/unmatched_open.txt" ] &&
  printf 'どのドラフトとも一致しない open の既存の子 (close するかを人間に確認する): %s\n' \
    "$(awk '{ s = s (NR > 1 ? " / " : "") $0 } END { print s }' "$TMP/unmatched_open.txt")"
exit 0
