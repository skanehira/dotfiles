#!/bin/sh
# create-issues.sh のテスト。偽の gh (tests/fake/gh) を PATH の先頭に置いて動かす
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../create-issues.sh"
# shellcheck source=assert.sh
. "$HERE/assert.sh"

# --- 準備の部品 ---------------------------------------------------------------

setup() {
  export GH_FAKE_DIR="$T/gh"
  mkdir -p "$GH_FAKE_DIR" "$T/d"
  : >"$GH_FAKE_DIR/calls.log"
  : >"$T/d/titles.tsv"
  PATH="$HERE/fake:$PATH"
  export PATH
  unset GH_FAKE_FAIL_LINK
}

# 親のドラフト。使い方: parent <識別子> <タイトル>
parent() {
  printf '## 設計\ndocs/design/DESIGN.md 参照\n' >"$T/d/parent-$1.md"
  printf 'parent-%s.md\t%s\n' "$1" "$2" >>"$T/d/titles.tsv"
}

# 子のドラフト。使い方: child <連番> <タイトル> <対応 UC の値> [依存先の連番...]
child() {
  n=$1
  title=$2
  uc=$3
  shift 3
  {
    printf '## ゴール\n%s を作る\n\n<details>\n<summary>実装用</summary>\n\n## 設計\n対応 UC: %s\n\n## 依存\n' "$title" "$uc"
    if [ $# -eq 0 ]; then
      printf '依存なし\n'
    else
      for d in "$@"; do printf 'Depends on issue-%s\n' "$d"; done
    fi
    printf '\n</details>\n'
  } >"$T/d/issue-$n.md"
  printf 'issue-%s.md\t%s\n' "$n" "$title" >>"$T/d/titles.tsv"
}

# 既存の issue。使い方: existing <番号> <OPEN|CLOSED> <ラベル> <タイトル> <本文> [親の番号]
existing() {
  dir="$GH_FAKE_DIR/issues/$1"
  mkdir -p "$dir"
  echo "$2" >"$dir/state"
  printf '%s' "$3" >"$dir/labels"
  printf '%s' "$4" >"$dir/title"
  printf '%s' "$5" >"$dir/body"
  [ $# -ge 6 ] && echo "$6" >"$dir/parent"
  next=$(cat "$GH_FAKE_DIR/next" 2>/dev/null || echo 1)
  [ "$next" -le "$1" ] && echo $(($1 + 1)) >"$GH_FAKE_DIR/next"
  return 0
}

run() {
  # 本物の gh で GitHub に issue を作らないよう、偽物を指していなければ止める
  if [ "$(command -v gh)" != "$HERE/fake/gh" ]; then
    echo "gh が偽物を指していない: $(command -v gh)。テストを止める" >&2
    exit 99
  fi
  ${SH:-sh} "$SCRIPT" "$@" "$T/d" >"$T/out.txt" 2>"$T/err.txt"
  echo $? >"$T/rc.txt"
}

calls_without_labels() {
  grep -v '^label ' "$GH_FAKE_DIR/calls.log" >"$T/calls.txt" || true
}

parent_of() { cat "$GH_FAKE_DIR/issues/$1/parent" 2>/dev/null; }

# --- 新規作成 ----------------------------------------------------------------

# クイックモード: 親を先に作り、子を依存の上流から作り、依存を番号に置き換え、全部を親に紐付ける
test_quick_mode_creates_parent_then_children_in_dependency_order() {
  setup
  parent quick '単語カード トラッキング'
  child 1 '学習モードを実装する' '基盤' 2
  child 2 '雛形を整備する' '基盤'
  child 3 '一覧を実装する' '基盤' 2 1
  run
  assert_eq 0 "$(cat "$T/rc.txt")"
  calls_without_labels
  printf '%s\n' \
    'create #1 単語カード トラッキング [tracking]' \
    'create #2 雛形を整備する [ready]' \
    'create #3 学習モードを実装する [ready]' \
    'create #4 一覧を実装する [ready]' \
    'link #2 -> #1' 'link #3 -> #1' 'link #4 -> #1' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/calls.txt"
  assert_file_contains_line "$GH_FAKE_DIR/issues/3/body" 'Depends on #2'
  assert_file_contains_line "$GH_FAKE_DIR/issues/4/body" 'Depends on #2'
  assert_file_contains_line "$GH_FAKE_DIR/issues/4/body" 'Depends on #3'
  assert_file_contains_line "$T/out.txt" '子 issue: 新規 3 / 本文更新 0 / 変更なし 0'
}

# 4 種のラベルを用意する
test_prepares_four_labels() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤'
  run
  grep '^label ' "$GH_FAKE_DIR/calls.log" >"$T/labels.txt"
  printf 'label ready\nlabel in-progress\nlabel needs-human\nlabel tracking\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/labels.txt"
}

# 番号と連番の対応を numbers.tsv に残す
test_writes_numbers_tsv() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤'
  run
  printf 'parent-quick.md\t1\nissue-1.md\t2\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/d/numbers.tsv"
}

# UC ごとの親: 子は「対応 UC」行の UC の親に紐付く。統合親は覆う UC の子を受け持つ
test_uc_mode_links_children_to_their_uc_parents() {
  setup
  parent UC-001 'UC-001: 登録する'
  parent UC-002-003 'UC-002 / UC-003: 探す と 並べる'
  parent kiban '基盤: UC に属さない共通実装'
  child 1 '基盤を作る' '基盤'
  child 2 '登録を作る' 'UC-001: 登録する' 1
  child 3 '探して並べる' 'UC-002: 探す, UC-003: 並べる' 1
  run
  assert_eq 0 "$(cat "$T/rc.txt")"
  # 親は parent-*.md の名前の順 (UC-001, UC-002-003, kiban) に #1・#2・#3
  assert_eq 3 "$(parent_of 4)"
  assert_eq 1 "$(parent_of 5)"
  assert_eq 2 "$(parent_of 6)"
}

# --- 再実行 (冪等) -----------------------------------------------------------

# 2 回目は何も作らず、何も書き換えず、何も紐付けない
test_second_run_changes_nothing() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤'
  child 2 'B' '基盤' 1
  run
  : >"$GH_FAKE_DIR/calls.log"
  run
  assert_eq 0 "$(cat "$T/rc.txt")"
  calls_without_labels
  : >"$T/empty.txt"
  assert_file_eq "$T/empty.txt" "$T/calls.txt"
  assert_file_contains_line "$T/out.txt" '子 issue: 新規 0 / 本文更新 0 / 変更なし 2'
}

# 前回が子の作成の途中で止まっていたら、残りの子を作って全部を紐付ける
test_resumes_after_partial_creation() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤'
  child 2 'B' '基盤' 1
  existing 1 OPEN tracking 'T トラッキング' "$(cat "$T/d/parent-quick.md")"
  existing 2 OPEN ready 'A' "$(cat "$T/d/issue-1.md")"
  run
  assert_eq 0 "$(cat "$T/rc.txt")"
  calls_without_labels
  printf '%s\n' 'create #3 B [ready]' 'link #2 -> #1' 'link #3 -> #1' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/calls.txt"
  assert_file_contains_line "$GH_FAKE_DIR/issues/3/body" 'Depends on #2'
}

# --- 既存の issue の本文 ------------------------------------------------------

# タイトルが一致した open の issue は、本文が違えば貼り直す
test_updates_body_of_matching_open_issue() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤'
  existing 1 OPEN tracking 'T トラッキング' "$(cat "$T/d/parent-quick.md")"
  existing 2 OPEN ready 'A' '古い本文' 1
  run
  calls_without_labels
  printf 'edit #2\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/calls.txt"
  assert_file_contains_line "$T/out.txt" '子 issue: 新規 0 / 本文更新 1 / 変更なし 0'
}

# closed の issue は、本文が違っても書き換えず、番号を報告する
test_reports_closed_issue_with_different_body() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤'
  existing 1 OPEN tracking 'T トラッキング' "$(cat "$T/d/parent-quick.md")"
  existing 2 CLOSED ready 'A' '古い本文' 1
  run
  calls_without_labels
  : >"$T/empty.txt"
  assert_file_eq "$T/empty.txt" "$T/calls.txt"
  assert_file_contains_line "$T/out.txt" 'closed だが本文が現ドラフトと違う issue: #2'
}

# --- 既存の、ドラフトに無い子 -------------------------------------------------

# どのドラフトとも一致しない open の既存の子は報告し、親が無ければ本文の「対応 UC」で紐付ける
test_reports_and_links_unmatched_existing_child() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤'
  existing 7 OPEN ready '消えた作業' "$(printf '## ゴール\n対応 UC: 基盤\n')"
  run
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" 'どのドラフトとも一致しない open の既存の子 (close するかを人間に確認する): #7 消えた作業'
  assert_eq 8 "$(parent_of 7)"
}

# 本文の「対応 UC」に当たる親が無い子は紐付けず、報告する
test_reports_child_whose_uc_has_no_parent() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤'
  existing 7 OPEN ready '別の作業' "$(printf '## ゴール\n対応 UC: UC-009: どこか\n')"
  run
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_eq '' "$(parent_of 7)"
  assert_file_contains_line "$T/out.txt" '対応 UC 不明で紐付けなかった子: #7'
}

# --- クイックモードの親の流用 ------------------------------------------------

# 既存の「<タスク名> トラッキング」が 1 件なら、タイトルが違っても流用して本文を貼り直す
test_quick_mode_reuses_single_existing_tracking_parent() {
  setup
  parent quick '新しい名前 トラッキング'
  child 1 'A' '基盤'
  existing 5 OPEN tracking '古い名前 トラッキング' '古い本文'
  run
  assert_eq 0 "$(cat "$T/rc.txt")"
  calls_without_labels
  printf '%s\n' 'create #6 A [ready]' 'edit #5' 'link #6 -> #5' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/calls.txt"
}

# 既存の「<タスク名> トラッキング」が 2 件以上なら、何もせずに人間に選ばせる (終了コード 3)
test_quick_mode_with_two_tracking_parents_needs_human() {
  setup
  parent quick '新しい名前 トラッキング'
  child 1 'A' '基盤'
  existing 5 OPEN tracking '古い名前 トラッキング' 'x'
  existing 6 OPEN tracking 'もう一つ トラッキング' 'y'
  run
  assert_eq 3 "$(cat "$T/rc.txt")"
  : >"$T/empty.txt"
  assert_file_eq "$T/empty.txt" "$GH_FAKE_DIR/calls.log"
  assert_file_contains_line "$T/out.txt" 'NEEDS_HUMAN: 「<タスク名> トラッキング」の親が複数ある。どれを流用するかを選ぶ: #5 古い名前 トラッキング / #6 もう一つ トラッキング'
}

# --- UC ごとの親の判断と移行 -------------------------------------------------

# どの親のドラフトとも一致しない tracking の親が子を持つなら、何もせずに人間に聞く (終了コード 3)
test_uc_mode_unmatched_tracking_parent_with_children_needs_human() {
  setup
  parent UC-001 'UC-001: 登録する'
  child 1 'A' 'UC-001: 登録する'
  existing 3 OPEN tracking 'UC-001: 登録をする' 'x'
  existing 4 OPEN ready 'B' "$(printf '対応 UC: UC-001: 登録をする\n')" 3
  run
  assert_eq 3 "$(cat "$T/rc.txt")"
  : >"$T/empty.txt"
  assert_file_eq "$T/empty.txt" "$GH_FAKE_DIR/calls.log"
  assert_file_contains_line "$T/out.txt" 'NEEDS_HUMAN: どの親のドラフトとも一致しない tracking の親が子を持つ。どの新しい親へ貼り替えるか、旧親のまま残すかを決める: #3 UC-001: 登録をする (子: #4)'
}

# 旧構成 (「<タスク名> トラッキング」の単一親) からの移行: 子を UC の親へ貼り替え、空になった旧親を close する
test_migrates_old_single_parent_and_closes_it() {
  setup
  parent UC-001 'UC-001: 登録する'
  child 1 'A' 'UC-001: 登録する'
  existing 1 OPEN tracking '旧 トラッキング' 'x'
  existing 2 OPEN ready 'A' "$(cat "$T/d/issue-1.md")" 1
  run
  assert_eq 0 "$(cat "$T/rc.txt")"
  calls_without_labels
  printf '%s\n' 'create #3 UC-001: 登録する [tracking]' 'relink #2 -> #3' 'close #1' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/calls.txt"
  assert_file_contains_line "$T/out.txt" '旧構成からの移行: 貼り替え 1 件、close した旧親 #1'
}

# 「対応 UC」行の無い旧親の子は貼り替えずに残し、旧親は close しない
test_migration_keeps_children_without_uc_line() {
  setup
  parent UC-001 'UC-001: 登録する'
  child 1 'A' 'UC-001: 登録する'
  existing 1 OPEN tracking '旧 トラッキング' 'x'
  existing 2 OPEN ready '古い子' '対応 UC の無い本文' 1
  run
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_eq 1 "$(parent_of 2)"
  assert_file_lacks_line "$GH_FAKE_DIR/calls.log" 'close #1'
  assert_file_contains_line "$T/out.txt" '対応 UC 不明で紐付けなかった子: #2'
}

# closed の親に新しい子を紐付けるときは、先に reopen する
test_reopens_closed_parent_before_linking_new_child() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤'
  existing 1 CLOSED tracking 'T トラッキング' "$(cat "$T/d/parent-quick.md")"
  run
  calls_without_labels
  printf '%s\n' 'create #2 A [ready]' 'reopen #1' 'link #2 -> #1' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/calls.txt"
}

# --- ドラフトの誤り (何も呼ばずに終了コード 4) ---------------------------------

test_draft_without_title_exits_4() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤'
  printf '## ゴール\n対応 UC: 基盤\n' >"$T/d/issue-2.md"
  run
  assert_eq 4 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/err.txt" 'issue-2.md: titles.tsv にタイトルが無い'
  : >"$T/empty.txt"
  assert_file_eq "$T/empty.txt" "$GH_FAKE_DIR/calls.log"
}

test_child_without_uc_line_exits_4() {
  setup
  parent quick 'T トラッキング'
  printf '## ゴール\nUC の行が無い\n' >"$T/d/issue-1.md"
  printf 'issue-1.md\tA\n' >>"$T/d/titles.tsv"
  run
  assert_eq 4 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/err.txt" 'issue-1.md: 「対応 UC:」の行が無い'
}

test_child_whose_uc_has_no_parent_draft_exits_4() {
  setup
  parent UC-001 'UC-001: 登録する'
  child 1 'A' 'UC-002: 探す'
  run
  assert_eq 4 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/err.txt" 'issue-1.md: 対応 UC (UC-002) の親のドラフトが無い'
}

test_child_spanning_two_parents_exits_4() {
  setup
  parent UC-001 'UC-001: 登録する'
  parent UC-002 'UC-002: 探す'
  child 1 'A' 'UC-001: 登録する, UC-002: 探す'
  run
  assert_eq 4 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/err.txt" 'issue-1.md: 対応 UC (UC-001 UC-002) が 1 つの親にまとまらない。UC ごとに子を分けるか、統合親を作る'
}

test_dependency_cycle_exits_4() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤' 2
  child 2 'B' '基盤' 1
  run
  assert_eq 4 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/err.txt" '依存が循環している: issue-1.md issue-2.md'
  : >"$T/empty.txt"
  assert_file_eq "$T/empty.txt" "$GH_FAKE_DIR/calls.log"
}

# 既存の issue が上限の件数に達したら、取りこぼすので止まる。上限は ISSUE_LIST_LIMIT で上げられる
test_issue_list_limit_is_configurable() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤'
  existing 7 OPEN ready 'x' 'x'
  existing 8 OPEN ready 'y' 'y'
  export ISSUE_LIST_LIMIT=2
  run
  assert_eq 1 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/err.txt" '既存の issue が 2 件以上あり、取りこぼす。環境変数 ISSUE_LIST_LIMIT を 2 より大きくして再実行する'
  export ISSUE_LIST_LIMIT=3
  run
  assert_eq 0 "$(cat "$T/rc.txt")"
  unset ISSUE_LIST_LIMIT
}

# --- 失敗 --------------------------------------------------------------------

# 紐付けに失敗したら、作った番号と紐付けられなかった組を出して終了コード 1
test_link_failure_exits_1_with_state() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤'
  GH_FAKE_FAIL_LINK=1
  export GH_FAKE_FAIL_LINK
  run
  assert_eq 1 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/err.txt" '#2 を親 #1 に紐付けられなかった。作成済みの番号は numbers.tsv にある。同じコマンドを再実行すると、続きから紐付ける'
}

# --- レビューで見つかった場面 ------------------------------------------------

# closed の「<タスク名> トラッキング」は流用しない (終わった別タスクの親に、新しい子を付けない)
test_quick_mode_does_not_reuse_closed_tracking_parent() {
  setup
  parent quick 'B タスク トラッキング'
  child 1 'X' '基盤'
  existing 1 CLOSED tracking 'A タスク トラッキング' '古い本文'
  run
  assert_eq 0 "$(cat "$T/rc.txt")"
  calls_without_labels
  printf '%s\n' 'create #2 B タスク トラッキング [tracking]' 'create #3 X [ready]' 'link #3 -> #2' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/calls.txt"
}

# 移行で close した旧親は、再実行で close し直さない
test_rerun_after_migration_does_not_close_again() {
  setup
  parent UC-001 'UC-001: 登録する'
  child 1 'A' 'UC-001: 登録する'
  existing 1 OPEN tracking '旧 トラッキング' 'x'
  existing 2 OPEN ready 'A' "$(cat "$T/d/issue-1.md")" 1
  run
  : >"$GH_FAKE_DIR/calls.log"
  run
  assert_eq 0 "$(cat "$T/rc.txt")"
  calls_without_labels
  : >"$T/empty.txt"
  assert_file_eq "$T/empty.txt" "$T/calls.txt"
  assert_file_lacks_line "$T/out.txt" '旧構成からの移行: 貼り替え 0 件、close した旧親 #1'
}

# --keep で残すと決めた親は突き合わせから外し、その親に付いている子は紐付けを変えずに報告する
test_keep_option_leaves_parent_and_reports_its_children() {
  setup
  parent UC-001 'UC-001: 登録する'
  child 1 'A' 'UC-001: 登録する'
  existing 3 OPEN tracking 'UC-001: 登録をする' 'x'
  existing 4 OPEN ready 'A' "$(cat "$T/d/issue-1.md")" 3
  run --keep 3
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_eq 3 "$(parent_of 4)"
  assert_file_contains_line "$T/out.txt" '別の親に付いているので紐付けを変えなかった子: #4 (親 #3)'
}

# --keep で、クイックモードで流用する親を 1 つに絞れる
test_keep_option_picks_quick_mode_parent() {
  setup
  parent quick '新しい名前 トラッキング'
  child 1 'A' '基盤'
  existing 5 OPEN tracking '古い名前 トラッキング' 'x'
  existing 6 OPEN tracking 'もう一つ トラッキング' 'y'
  run --keep 6
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_eq 5 "$(parent_of 7)"
}

# 行の途中の「Depends on issue-<連番>」は依存ではないので、置き換えずに残し、止まらない
test_prose_mentioning_depends_on_is_left_alone() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤'
  child 2 'B' '基盤' 1
  printf 'メモ: Depends on issue-1 の書き方は依存の節だけで使う\n' >>"$T/d/issue-2.md"
  run
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$GH_FAKE_DIR/issues/3/body" 'Depends on #2'
}

# ドラフトどうしでタイトルが重なっていたら、ドラフトの誤り (終了コード 4)
test_duplicate_titles_in_drafts_exit_4() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤'
  child 2 'A' '基盤'
  run
  assert_eq 4 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/err.txt" 'titles.tsv に同じタイトルが複数ある: A'
}

# どのドラフトとも一致しない closed の子は紐付けない (閉じた親を reopen しない)
test_closed_unmatched_child_is_not_linked() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤'
  existing 7 CLOSED ready '終わった作業' "$(printf '## ゴール\n対応 UC: 基盤\n')"
  run
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_eq '' "$(parent_of 7)"
}

# 本文が CRLF でも、中身が同じなら貼り直さない
test_crlf_body_with_same_content_is_unchanged() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤'
  existing 1 OPEN tracking 'T トラッキング' "$(cat "$T/d/parent-quick.md")"
  existing 2 OPEN ready 'A' "$(sed 's/$/\r/' "$T/d/issue-1.md")" 1
  run
  calls_without_labels
  : >"$T/empty.txt"
  assert_file_eq "$T/empty.txt" "$T/calls.txt"
}

# 既存に同じタイトルの issue が 2 件あれば、何もせずに人間に聞く (終了コード 3)
test_two_existing_issues_with_same_title_need_human() {
  setup
  parent quick 'T トラッキング'
  child 1 'A' '基盤'
  existing 5 OPEN ready 'A' 'x'
  existing 6 OPEN ready 'A' 'y'
  run
  assert_eq 3 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" 'NEEDS_HUMAN: 同じタイトルの issue が複数あり、どれに当たるか決められない: A (#5 / #6)'
}

run_tests
