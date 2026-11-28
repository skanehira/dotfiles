#!/bin/sh
# next-issues.sh のテスト。偽の gh と ps (tests/fake/) を PATH の先頭に置いて動かす
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../next-issues.sh"
# shellcheck source=../../../dev-spec/scripts/tests/assert.sh
. "$HERE/../../../dev-spec/scripts/tests/assert.sh"

setup() {
  export GH_FAKE_DIR="$T/gh"
  mkdir -p "$GH_FAKE_DIR/issues"
  : >"$GH_FAKE_DIR/calls.log"
  export PS_FAKE_DIR="$T/ps"
  mkdir -p "$PS_FAKE_DIR"
  PATH="$HERE/fake:$PATH"
  export PATH
  SNAP="$T/snapshot.tsv"
  # テストを動かしている Claude Code のセッションの値を持ち込まない (担当の印をテストの外へ書かないため)
  unset CLAUDE_PID CLAUDE_CODE_SESSION_ID
}

# 担当の印を置く git リポジトリを $T/repo に作る。印の置き場所は $CLAIMS
claims_repo() {
  git init -q "$T/repo"
  CLAIMS="$T/repo/.git/dev-impl-claims"
}

# 別のセッションの担当の印を置く。使い方: claim <番号> <pid> <セッション ID>
claim() {
  mkdir -p "$CLAIMS"
  printf '%s\t%s\n' "$2" "$3" >"$CLAIMS/$1"
}

# 動いているプロセスを偽の ps に置く。使い方: live_process <pid> <実行ファイル名 (ps -o comm= の出力)>
live_process() {
  printf '%s\n' "$2" >"$PS_FAKE_DIR/$1"
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

# 実装用の節が折りたたまれた本文でも、依存とスコアを読む
test_reads_folded_body() {
  setup
  issue 1 OPEN ready '## ゴール' '書き出せる' '' '<details>' '<summary>実装用</summary>' '' '## 設計' '対応 UC: 基盤' '' '## 依存' 'Depends on #2' '' '</details>' '' '## 優先度' 'スコア 4.0 (2026-11-05 採点)'
  issue 2 OPEN ready '## 優先度' 'スコア 1.0 (2026-11-05 採点)'
  collect
  printf 'start\t2\t4\nwait\t1\t2\n' >"$T/exp.txt"
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

# issue が上限の件数に達したら止まる。上限は ISSUE_LIST_LIMIT で上げられる
test_issue_list_limit_is_configurable() {
  setup
  issue 1 OPEN ready '依存なし'
  issue 2 OPEN ready '依存なし'
  export ISSUE_LIST_LIMIT=2
  collect
  assert_eq 1 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/err.txt" 'issue が 2 件以上あり、取りこぼす。環境変数 ISSUE_LIST_LIMIT を 2 より大きくして再実行する'
  export ISSUE_LIST_LIMIT=3
  collect
  assert_eq 0 "$(cat "$T/rc.txt")"
  unset ISSUE_LIST_LIMIT
}

# mark started で実装中の issue を start から外し、依存元は待たせたままにする
test_mark_started_removes_from_start() {
  setup
  issue 1 OPEN ready '依存なし'
  issue 2 OPEN ready 'Depends on #1'
  issue 3 OPEN ready '依存なし'
  collect
  ${SH:-sh} "$SCRIPT" mark "$SNAP" 1 started >"$T/out.txt" 2>/dev/null
  printf 'start\t3\t-\nwait\t2\t1\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# 動いている別の Claude のセッションが担当の印を持つ issue は着手せず claimed に出し、依存元を待たせる
test_issue_claimed_by_live_session_is_not_started() {
  setup
  claims_repo
  issue 1 OPEN in-progress '依存なし'
  issue 2 OPEN ready 'Depends on #1'
  issue 3 OPEN ready '依存なし'
  claim 1 4242 other-session
  live_process 4242 'claude bg-spare'
  issue 4 OPEN ready '依存なし'
  claim 4 4245 another-session
  live_process 4245 'claude'
  # 番号の並びは文字列の順や awk の配列の順に頼らず、数の小さい順にする
  issue 12 OPEN ready '依存なし'
  claim 12 4246 twelfth-session
  live_process 4246 'claude'
  export CLAUDE_PID=1000
  (cd "$T/repo" && collect)
  assert_eq 0 "$(cat "$T/rc.txt")"
  printf 'start\t3\t-\nwait\t2\t1\nclaimed\t1\tother-session\nclaimed\t4\tanother-session\nclaimed\t12\ttwelfth-session\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# 番号を指定したときも、担当中の issue は claimed に出し、「対象にならない」とは言わない
test_asked_issue_claimed_by_live_session_is_reported_as_claimed() {
  setup
  claims_repo
  issue 1 OPEN ready '依存なし'
  claim 1 4242 other-session
  live_process 4242 '/Users/a/.local/bin/claude'
  (cd "$T/repo" && collect 1)
  printf 'claimed\t1\tother-session\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
  : >"$T/empty.txt"
  assert_file_eq "$T/empty.txt" "$T/err.txt"
}

# 印の持ち主が終わった (プロセスが無い・同じ番号の別のプロセスに変わった) issue と、自分の印の issue は着手する
test_claim_of_ended_or_own_session_does_not_block() {
  setup
  claims_repo
  issue 1 OPEN in-progress '依存なし'
  issue 2 OPEN in-progress '依存なし'
  issue 3 OPEN in-progress '依存なし'
  issue 4 OPEN in-progress '依存なし'
  claim 1 4242 ended-session
  claim 2 4243 reused-pid
  # Claude Code が起動したシェルは、コマンドラインに ~/.claude/ のパスを含むが Claude ではない
  live_process 4243 '/bin/zsh'
  # 実行ファイル名が claude で始まるだけの別のプログラムも Claude Code ではない
  claim 4 4244 helper
  live_process 4244 '/usr/local/bin/claude-helper'
  claim 3 1000 own-session
  live_process 1000 'claude'
  export CLAUDE_PID=1000
  (cd "$T/repo" && collect)
  printf 'start\t1\t-\nstart\t2\t-\nstart\t3\t-\nstart\t4\t-\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# mark started は自分の担当の印を書き、closed は消し、parked は残す (駐車しても対応中として扱う)
test_mark_writes_claim_on_start_removes_on_close_and_keeps_on_park() {
  setup
  claims_repo
  issue 1 OPEN ready '依存なし'
  issue 2 OPEN ready '依存なし'
  # collect も印を取るので、collect は印を取らせずに流し、mark started が書くことを確かめる
  (cd "$T/repo" && collect)
  export CLAUDE_PID=777 CLAUDE_CODE_SESSION_ID=my-session
  (cd "$T/repo" && ${SH:-sh} "$SCRIPT" mark "$SNAP" 1 started >/dev/null)
  printf '777\tmy-session\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$CLAIMS/1"
  (cd "$T/repo" && ${SH:-sh} "$SCRIPT" mark "$SNAP" 1 closed >/dev/null)
  assert_eq "なし" "$([ -e "$CLAIMS/1" ] && echo あり || echo なし)"
  (cd "$T/repo" && ${SH:-sh} "$SCRIPT" mark "$SNAP" 2 started >/dev/null && ${SH:-sh} "$SCRIPT" mark "$SNAP" 2 parked >/dev/null)
  printf '777\tmy-session\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$CLAIMS/2"
}

# collect は対象の issue すべての印を取る。依存先を待つ issue も取るので、別のセッションは
# 依存先が close された直後でもその issue を拾わない
test_collect_claims_all_targets_including_waiting() {
  setup
  claims_repo
  issue 1 OPEN ready '依存なし'
  issue 2 OPEN ready 'Depends on #1'
  issue 3 OPEN '' '依存なし'
  issue 4 OPEN ready '依存なし'
  live_process 777 'claude'
  export CLAUDE_PID=777 CLAUDE_CODE_SESSION_ID=my-session
  (cd "$T/repo" && collect 1 2)
  printf 'start\t1\t-\nwait\t2\t1\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
  printf '777\tmy-session\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$CLAIMS/1"
  assert_file_eq "$T/exp.txt" "$CLAIMS/2"
  assert_eq "なし なし" "$([ -e "$CLAIMS/3" ] && echo あり || echo なし) $([ -e "$CLAIMS/4" ] && echo あり || echo なし)"
  (cd "$T/repo" && CLAUDE_PID=888 CLAUDE_CODE_SESSION_ID=loop collect)
  printf 'start\t4\t-\nclaimed\t1\tmy-session\nclaimed\t2\tmy-session\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# Claude Code の外では collect も印を書けないことを 1 行だけ知らせ、着手順はいつもどおり出す
test_collect_outside_claude_code_warns_once_and_writes_no_claim() {
  setup
  claims_repo
  issue 1 OPEN ready '依存なし'
  issue 2 OPEN ready 'Depends on #1'
  (cd "$T/repo" && collect)
  printf 'start\t1\t-\nwait\t2\t1\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
  printf '担当の印を残せない (CLAUDE_PID が無い。Claude Code の外で動いている)。別のセッションが同じ issue を拾うことがある\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/err.txt"
  assert_eq "なし" "$([ -d "$CLAIMS" ] && ls "$CLAIMS" | head -1 | sed 's/^$/なし/' || echo なし)"
}

# Claude Code の外 (CLAUDE_PID が無い) では印を書けないことを知らせ、着手順はいつもどおり出す
test_mark_started_outside_claude_code_warns_and_writes_no_claim() {
  setup
  claims_repo
  issue 1 OPEN ready '依存なし'
  issue 2 OPEN ready '依存なし'
  (cd "$T/repo" && collect)
  (cd "$T/repo" && ${SH:-sh} "$SCRIPT" mark "$SNAP" 1 started >"$T/out.txt" 2>"$T/err.txt")
  assert_eq 0 $?
  printf 'start\t2\t-\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
  assert_file_contains_line "$T/err.txt" '#1 の担当の印を残せない (CLAUDE_PID が無い。Claude Code の外で動いている)。別のセッションが同じ issue を拾うことがある'
  assert_eq "なし" "$([ -e "$CLAIMS/1" ] && echo あり || echo なし)"
}


# collect の後に別のセッションが印を書いた issue は、mark の出力で start に出さず、mark started も印を上書きせずに 3 で終わる
test_issue_claimed_after_collect_is_not_started() {
  setup
  claims_repo
  issue 1 OPEN ready '依存なし'
  issue 2 OPEN ready '依存なし'
  live_process 1000 'claude'
  live_process 2000 'claude'
  export CLAUDE_PID=1000 CLAUDE_CODE_SESSION_ID=A
  (cd "$T/repo" && collect)
  claim 2 2000 B
  (cd "$T/repo" && ${SH:-sh} "$SCRIPT" mark "$SNAP" 1 started >"$T/out.txt")
  printf 'claimed\t2\tB\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
  (cd "$T/repo" && ${SH:-sh} "$SCRIPT" mark "$SNAP" 2 started >"$T/out.txt")
  assert_eq 3 $?
  assert_file_eq "$T/exp.txt" "$T/out.txt"
  printf '2000\tB\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$CLAIMS/2"
}

# 印は clone の共通の git ディレクトリに置く。worktree で書いた印を clone の直下から、直下で書いた印を worktree から読める
test_claim_is_shared_between_clone_root_and_worktree() {
  setup
  claims_repo
  git -C "$T/repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  git -C "$T/repo" worktree add -q "$T/repo/.claude/worktrees/run" -b run 2>/dev/null
  issue 1 OPEN ready '依存なし'
  issue 2 OPEN ready '依存なし'
  live_process 777 'claude'
  live_process 888 'claude'
  for pair in "$T/repo/.claude/worktrees/run:$T/repo" "$T/repo:$T/repo/.claude/worktrees/run"; do
    writer=${pair%%:*}
    reader=${pair#*:}
    rm -rf "$CLAIMS"
    (cd "$writer" && CLAUDE_PID=777 CLAUDE_CODE_SESSION_ID=writer collect 1 && CLAUDE_PID=777 CLAUDE_CODE_SESSION_ID=writer ${SH:-sh} "$SCRIPT" mark "$SNAP" 1 started >/dev/null)
    (cd "$reader" && CLAUDE_PID=888 collect)
    printf 'start\t2\t-\nclaimed\t1\twriter\n' >"$T/exp.txt"
    assert_file_eq "$T/exp.txt" "$T/out.txt"
  done
}

# git リポジトリの外では印を読み書きできないことを知らせる
test_outside_git_warns_that_claims_are_not_used() {
  setup
  issue 1 OPEN ready '依存なし'
  mkdir -p "$T/plain"
  export CLAUDE_PID=777 GIT_CEILING_DIRECTORIES="$T"
  (cd "$T/plain" && collect)
  assert_file_contains_line "$T/err.txt" '担当の印を読めない (git リポジトリの外で動いている)。別のセッションが担当中の issue も着手順に出る'
  (cd "$T/plain" && ${SH:-sh} "$SCRIPT" mark "$SNAP" 1 started >/dev/null 2>"$T/err.txt")
  assert_file_contains_line "$T/err.txt" '#1 の担当の印を残せない (git リポジトリの外で動いている)。別のセッションが同じ issue を拾うことがある'
  unset GIT_CEILING_DIRECTORIES
}


# 死んだ印 (プロセスが無い・claude ではない) のある issue は、mark started が自分の印に置き換えて着手する
test_mark_started_replaces_dead_claim() {
  setup
  claims_repo
  issue 1 OPEN in-progress '依存なし'
  issue 2 OPEN in-progress '依存なし'
  claim 1 4242 ended-session
  claim 2 4243 reused-pid
  live_process 4243 '/bin/zsh'
  # collect も死んだ印を置き換えるので、collect は印を取らせずに流し、mark started が置き換えることを確かめる
  (cd "$T/repo" && collect)
  export CLAUDE_PID=777 CLAUDE_CODE_SESSION_ID=my-session
  for n in 1 2; do
    (cd "$T/repo" && ${SH:-sh} "$SCRIPT" mark "$SNAP" "$n" started >/dev/null)
    assert_eq 0 $?
    printf '777\tmy-session\n' >"$T/exp.txt"
    assert_file_eq "$T/exp.txt" "$CLAIMS/$n"
  done
}

# mark closed は、動いている別のセッションの印を消さない
test_mark_closed_keeps_claim_of_live_other_session() {
  setup
  claims_repo
  issue 1 OPEN ready '依存なし'
  export CLAUDE_PID=777 CLAUDE_CODE_SESSION_ID=my-session
  (cd "$T/repo" && collect)
  claim 1 4242 other-session
  live_process 4242 'claude'
  (cd "$T/repo" && ${SH:-sh} "$SCRIPT" mark "$SNAP" 1 closed >/dev/null)
  printf '4242\tother-session\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$CLAIMS/1"
}

# 死んだ印のある issue を 2 つのセッションが同時に取りに来ても、片方だけが取れる (もう片方は 3 で終わる)
test_two_sessions_replacing_dead_claim_at_once_only_one_wins() {
  setup
  claims_repo
  issue 1 OPEN in-progress '依存なし'
  claim 1 999 ended-session
  : >"$PS_FAKE_DIR/999.slow"
  live_process 1000 'claude'
  live_process 2000 'claude'
  # collect が死んだ印を先に置き換えると取り合いが起きないので、collect は印を取らせずに流す
  (cd "$T/repo" && collect)
  cp "$SNAP" "$T/snap-b.tsv"
  (cd "$T/repo" && CLAUDE_PID=1000 CLAUDE_CODE_SESSION_ID=A ${SH:-sh} "$SCRIPT" mark "$SNAP" 1 started >/dev/null 2>&1; echo $? >"$T/rc-a.txt") &
  # 先に取った側が印を作り終えた後に、遅れた側が死んだ印の判定を終える時間差にする
  sleep 0.5
  (cd "$T/repo" && CLAUDE_PID=2000 CLAUDE_CODE_SESSION_ID=B ${SH:-sh} "$SCRIPT" mark "$T/snap-b.tsv" 1 started >/dev/null 2>&1; echo $? >"$T/rc-b.txt") &
  wait
  assert_eq "0 3" "$(sort "$T/rc-a.txt" "$T/rc-b.txt" | tr '\n' ' ' | sed 's/ $//')"
  if [ "$(cat "$T/rc-a.txt")" = 0 ]; then printf '1000\tA\n' >"$T/exp.txt"; else printf '2000\tB\n' >"$T/exp.txt"; fi
  assert_file_eq "$T/exp.txt" "$CLAIMS/1"
}

run_tests
