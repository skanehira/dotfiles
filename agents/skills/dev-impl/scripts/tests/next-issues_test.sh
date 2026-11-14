#!/bin/sh
# next-issues.sh のテスト。偽の gh (tests/fake/gh) を PATH の先頭に置いて動かす
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../next-issues.sh"
# shellcheck source=../../../dev-spec/scripts/tests/assert.sh
. "$HERE/../../../dev-spec/scripts/tests/assert.sh"

setup() {
  export GH_FAKE_DIR="$T/gh"
  mkdir -p "$GH_FAKE_DIR/issues"
  : >"$GH_FAKE_DIR/calls.log"
  PATH="$HERE/fake:$PATH"
  export PATH
  SNAP="$T/snapshot.tsv"
}

# issue を置く。使い方: issue <番号> <OPEN|CLOSED> <ラベル> [本文の行...]
issue() {
  dir="$GH_FAKE_DIR/issues/$1"
  mkdir -p "$dir"
  echo "$2" >"$dir/state"
  printf '%s' "$3" >"$dir/labels"
  shift 3
  : >"$dir/body"
  for line in "$@"; do printf '%s\n' "$line" >>"$dir/body"; done
}

collect() {
  # 本物の gh で GitHub を読まないよう、偽物を指していなければ止める
  if [ "$(command -v gh)" != "$HERE/fake/gh" ]; then
    echo "gh が偽物を指していない: $(command -v gh)。テストを止める" >&2
    exit 99
  fi
  ${SH:-sh} "$SCRIPT" collect "$SNAP" "$@" >"$T/out.txt" 2>"$T/err.txt"
  echo $? >"$T/rc.txt"
}

# ready の issue を、依存先がすべて close されたものから番号の順に出す。close されていない依存先が残るものは wait
test_collect_orders_ready_issues() {
  setup
  issue 1 CLOSED '' '## ゴール'
  issue 2 OPEN ready '## 依存' 'Depends on #1'
  issue 3 OPEN ready '## 依存' 'Depends on #2'
  issue 4 OPEN ready '## 依存' '依存なし'
  collect
  assert_eq 0 "$(cat "$T/rc.txt")"
  printf 'start\t2\t-\nstart\t4\t-\nwait\t3\t2\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# needs-human と tracking は着手しない。それらに依存する issue は wait
test_needs_human_and_tracking_are_not_started() {
  setup
  issue 1 OPEN 'ready,needs-human' '依存なし'
  issue 2 OPEN tracking '依存なし'
  issue 3 OPEN ready 'Depends on #1'
  issue 4 OPEN ready '依存なし'
  collect
  printf 'start\t4\t-\nwait\t3\t1\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# 「## 優先度」のスコアと緊急枠で並べ、依存先は依存元の高いほうのスコアを引き継ぐ
test_orders_by_priority_section() {
  setup
  issue 1 OPEN ready '## 優先度' 'スコア 2.5 (2026-11-05 採点)'
  issue 2 OPEN ready '## 優先度' 'スコア 9.0 (2026-11-05 採点)' '## 依存' 'Depends on #3'
  issue 3 OPEN ready '## 優先度' 'スコア 1.0 (2026-11-05 採点)'
  issue 4 OPEN ready '## 優先度' '緊急枠 (2026-11-11 判定、採点しない): 本番でログインできない'
  issue 5 OPEN ready '依存なし'
  collect
  printf 'start\t4\tU\nstart\t3\t9\nstart\t1\t2.5\nstart\t5\t-\nwait\t2\t3\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# 「## 優先度」の節の外にあるスコアや、行の先頭でない「緊急枠」は数えない
test_ignores_score_outside_priority_section() {
  setup
  issue 1 OPEN ready '## ゴール' 'スコア 99 のように見える行' 'これは 緊急枠 (ではない)'
  issue 2 OPEN ready '## 優先度' 'スコア 1.0 (2026-11-05 採点)'
  collect
  printf 'start\t2\t1\nstart\t1\t-\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# 前回から再開する in-progress の issue は、新しく着手する issue より先に出す
test_in_progress_comes_first() {
  setup
  issue 1 OPEN ready '## 優先度' 'スコア 9.0 (2026-11-05 採点)'
  issue 2 OPEN in-progress '依存なし'
  collect
  printf 'start\t2\t-\nstart\t1\t9\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# issue-<番号> のブランチが手元か origin に残っている ready の issue も、再開として先に出す
test_issue_with_leftover_branch_comes_first() {
  setup
  issue 1 OPEN ready '## 優先度' 'スコア 9.0 (2026-11-05 採点)'
  issue 2 OPEN ready '依存なし'
  issue 3 OPEN ready '依存なし'
  git init -q "$T/repo"
  git -C "$T/repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  git -C "$T/repo" branch issue-3
  git -C "$T/repo" update-ref refs/remotes/origin/issue-2 HEAD
  (cd "$T/repo" && collect)
  printf 'start\t2\t-\nstart\t3\t-\nstart\t1\t9\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# 番号を指定すると、その issue と、まだ終わっていない依存先だけを対象にする
test_arguments_limit_targets_to_issue_and_open_dependencies() {
  setup
  issue 1 OPEN ready '依存なし'
  issue 2 OPEN ready 'Depends on #1'
  issue 3 OPEN ready 'Depends on #2'
  issue 4 OPEN ready '依存なし'
  collect 3
  printf 'start\t1\t-\nwait\t2\t1\nwait\t3\t2\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# mark closed で依存元が着手できるようになる。GitHub は読み直さない
test_mark_closed_releases_dependents_without_refetching() {
  setup
  issue 1 OPEN ready '依存なし'
  issue 2 OPEN ready 'Depends on #1'
  collect
  # collect の後に ready が付いた issue は拾わない
  issue 9 OPEN ready '依存なし'
  : >"$GH_FAKE_DIR/calls.log"
  ${SH:-sh} "$SCRIPT" mark "$SNAP" 1 closed >"$T/out.txt"
  printf 'start\t2\t-\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
  : >"$T/empty.txt"
  assert_file_eq "$T/empty.txt" "$GH_FAKE_DIR/calls.log"
}

# mark parked (needs-human に駐車) は着手せず、依存元も待たせる
test_mark_parked_keeps_dependents_waiting() {
  setup
  issue 1 OPEN ready '依存なし'
  issue 2 OPEN ready 'Depends on #1'
  issue 3 OPEN ready '依存なし'
  collect
  ${SH:-sh} "$SCRIPT" mark "$SNAP" 1 parked >"$T/out.txt"
  printf 'start\t3\t-\nwait\t2\t1\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# order はスナップショットだけから出し直す
test_order_reads_snapshot_only() {
  setup
  issue 1 OPEN ready '依存なし'
  collect
  : >"$GH_FAKE_DIR/calls.log"
  ${SH:-sh} "$SCRIPT" order "$SNAP" >"$T/out.txt"
  printf 'start\t1\t-\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
  : >"$T/empty.txt"
  assert_file_eq "$T/empty.txt" "$GH_FAKE_DIR/calls.log"
}

# 循環と、無い issue への依存は報告し、着手しない
test_reports_cycles_and_unknown_dependencies() {
  setup
  issue 1 OPEN ready 'Depends on #2'
  issue 2 OPEN ready 'Depends on #1'
  issue 3 OPEN ready 'Depends on #99'
  issue 4 OPEN ready '依存なし'
  collect
  printf 'start\t4\t-\ncycle\t1\ncycle\t2\nunknown\t3\t99\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# 1 行に並べた依存の行は読めないので、行を挙げて報告する
test_reports_malformed_dependency_line() {
  setup
  issue 1 CLOSED '' '依存なし'
  issue 2 CLOSED '' '依存なし'
  issue 3 OPEN ready 'Depends on #1, #2'
  collect
  printf 'badline\t3\tDepends on #1, #2\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# closed の issue の地の文は読まない
test_badline_only_for_open_issues() {
  setup
  issue 4 CLOSED '' 'Depends on whether we ship'
  issue 5 OPEN ready '依存なし'
  collect
  printf 'start\t5\t-\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# Web の画面で編集された CRLF の本文でも、依存と優先度を読む
test_reads_crlf_bodies() {
  setup
  issue 1 OPEN ready '依存なし'
  issue 2 OPEN ready "$(printf '## 優先度\r')" "$(printf 'スコア 4.0 (2026-11-05 採点)\r')" "$(printf 'Depends on #1\r')"
  collect
  printf 'start\t1\t4\nwait\t2\t1\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# 番号の先頭の # は外して読む。数でなければ止まる。対象にならない番号は標準エラーに出す
test_arguments_accept_hash_and_reject_garbage() {
  setup
  issue 1 OPEN ready '依存なし'
  issue 2 OPEN 'ready,needs-human' '依存なし'
  collect '#1' 2 9
  printf 'start\t1\t-\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
  assert_file_contains_line "$T/err.txt" '#2 は対象にならない (open で ready か in-progress が付き、needs-human と tracking が付いていない issue だけが対象)'
  assert_file_contains_line "$T/err.txt" '#9 は対象にならない (open で ready か in-progress が付き、needs-human と tracking が付いていない issue だけが対象)'
  collect abc
  assert_eq 1 "$(cat "$T/rc.txt")"
}

# mark started で実装中の issue を start から外し、依存元は待たせたままにする
test_mark_started_removes_from_start() {
  setup
  issue 1 OPEN ready '依存なし'
  issue 2 OPEN ready 'Depends on #1'
  issue 3 OPEN ready '依存なし'
  collect
  ${SH:-sh} "$SCRIPT" mark "$SNAP" 1 started >"$T/out.txt"
  printf 'start\t3\t-\nwait\t2\t1\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

run_tests
