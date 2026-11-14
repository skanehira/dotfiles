#!/bin/sh
# merge-pr.sh のテスト。偽の gh (tests/fake/gh-merge) を gh という名前で PATH の先頭に置いて動かす。
# 待ちは MERGE_PR_NO_SLEEP=1 で飛ばし、そのぶん偽の時計 (MERGE_PR_CLOCK_FILE) を進める (実際の時間を待たない)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../merge-pr.sh"
# shellcheck source=../../../dev-spec/scripts/tests/assert.sh
. "$HERE/../../../dev-spec/scripts/tests/assert.sh"

setup() {
  export GH_FAKE_DIR="$T/gh"
  mkdir -p "$GH_FAKE_DIR" "$T/bin"
  ln -s "$HERE/fake/gh-merge" "$T/bin/gh"
  PATH="$T/bin:$PATH"
  export PATH
  export MERGE_PR_NO_SLEEP=1
  export MERGE_PR_CLOCK_FILE="$T/clock"
  echo 0 >"$MERGE_PR_CLOCK_FILE"
  : >"$GH_FAKE_DIR/calls.log"
  echo 5 >"$GH_FAKE_DIR/issue"
  echo 12 >"$GH_FAKE_DIR/pr_open"
  echo 5 >"$GH_FAKE_DIR/closing"
  echo 0 >"$GH_FAKE_DIR/rollup"
  echo OPEN >"$GH_FAKE_DIR/pr_state"
  echo 'MERGEABLE CLEAN' >"$GH_FAKE_DIR/mergeable"
  echo CLOSED >"$GH_FAKE_DIR/issue_state"
  echo in-progress >"$GH_FAKE_DIR/issue_labels"
  printf '1\topen\t1/2\n' >"$GH_FAKE_DIR/parent"
  # 手元の clone: main と、issue-5 のブランチ (チェックアウト中)。origin/main もある
  REPO="$T/repo"
  git init -q -b main "$REPO"
  g commit -q --allow-empty -m init
  g update-ref refs/remotes/origin/main HEAD
  g switch -q -c issue-5
  g commit -q --allow-empty -m work
  git -C "$REPO" rev-parse HEAD >"$GH_FAKE_DIR/head_sha"
}

g() { git -C "$REPO" -c user.name=t -c user.email=t@example.com "$@"; }

add_workflow() {
  mkdir -p "$REPO/.github/workflows"
  printf 'on: pull_request\n' >"$REPO/.github/workflows/ci.yml"
  g add .github/workflows/ci.yml
  g commit -q -m ci
  git -C "$REPO" rev-parse HEAD >"$GH_FAKE_DIR/head_sha"
}

run_in() { # $1: 実行するディレクトリ 残り: merge-pr.sh の引数
  # 本物の gh で PR を merge しないよう、偽物を指していなければ止める
  if [ "$(command -v gh)" != "$T/bin/gh" ]; then
    echo "gh が偽物を指していない: $(command -v gh)。テストを止める" >&2
    exit 99
  fi
  dir=$1
  shift
  (cd "$dir" && ${SH:-sh} "$SCRIPT" "$@" >"$T/out.txt" 2>"$T/err.txt")
  echo $? >"$T/rc.txt"
}
run() { run_in "$REPO" "$@"; }

calls() { grep -v '^pr checks$' "$GH_FAKE_DIR/calls.log" >"$T/calls.txt" || true; }
nothing_changed() { # merge も後片付けも完了処理もしていない
  calls
  : >"$T/empty.txt"
  assert_file_eq "$T/empty.txt" "$T/calls.txt"
  assert_eq issue-5 "$(git -C "$REPO" branch --show-current)"
}

# --- CI なし -----------------------------------------------------------------

# checks が登録されず、workflow のファイルも無い: 1 回だけ数えて、merge・後片付け・完了処理をする
test_without_ci_merges_and_completes() {
  setup
  run 5
  assert_eq 0 "$(cat "$T/rc.txt")"
  printf '%s\n' 'PR #12' 'CI: なし (checks 未登録)' 'MERGED #12' 'BRANCH: issue-5 を消した' \
    'ISSUE: #5 は merge で close された' 'LABEL: #5 から in-progress を外した' 'PARENT: #1 は open のまま (子 1/2)' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
  calls
  printf '%s\n' 'pr merge 12' 'issue edit 5 --remove-label in-progress' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/calls.txt"
  assert_eq 1 "$(cat "$GH_FAKE_DIR/rollup.count")"
  assert_eq '' "$(git -C "$REPO" branch --list issue-5)"
  assert_eq main "$(git -C "$REPO" branch --show-current)"
}

# workflow があっても checks が登録されないまま (paths の条件で走らないなど) なら、10 秒おきに 12 回数えてから CI なしとして merge する
test_workflow_without_registered_checks_is_treated_as_no_ci() {
  setup
  add_workflow
  run 5
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" 'CI: なし (checks 未登録)'
  assert_eq 12 "$(cat "$GH_FAKE_DIR/rollup.count")"
  assert_eq 110 "$(cat "$MERGE_PR_CLOCK_FILE")"
}

# --- CI あり -----------------------------------------------------------------

# checks の登録を待ち、pending の間は 30 秒おきに引き直し、全件 pass なら merge する
test_waits_for_registration_and_pending_checks() {
  setup
  add_workflow
  printf '0\n0\n2\n' >"$GH_FAKE_DIR/rollup"
  printf 'test\tpending\thttps://ci/1\nlint\tpass\thttps://ci/2\n' >"$GH_FAKE_DIR/checks.1.tsv"
  printf 'test\tpass\thttps://ci/1\nlint\tpass\thttps://ci/2\n' >"$GH_FAKE_DIR/checks.2.tsv"
  run 5
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" 'CI: pass (test, lint)'
  assert_file_contains_line "$T/out.txt" 'MERGED #12'
  assert_eq 2 "$(grep -c '^pr checks$' "$GH_FAKE_DIR/calls.log")"
  # 登録の待ち 10 秒 × 2 と、pending の待ち 30 秒 × 1
  assert_eq 50 "$(cat "$MERGE_PR_CLOCK_FILE")"
}

# skipping は pass と同じに扱う
test_skipping_counts_as_pass() {
  setup
  echo 2 >"$GH_FAKE_DIR/rollup"
  printf 'test\tpass\thttps://ci/1\ndeploy\tskipping\thttps://ci/3\n' >"$GH_FAKE_DIR/checks.1.tsv"
  run 5
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" 'CI: pass (test, deploy)'
}

# fail か cancel が 1 件でもあれば、pending が残っていても merge せずに止まる (終了コード 11)
test_ci_failure_stops_without_merging() {
  setup
  echo 3 >"$GH_FAKE_DIR/rollup"
  printf 'test\tfail\thttps://ci/1\nlint\tcancel\thttps://ci/2\nslow\tpending\thttps://ci/3\n' >"$GH_FAKE_DIR/checks.1.tsv"
  run 5
  assert_eq 11 "$(cat "$T/rc.txt")"
  printf '%s\n' 'PR #12' 'CI_FAIL: test	fail	https://ci/1' 'CI_FAIL: lint	cancel	https://ci/2' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
  nothing_changed
}

# 知らない bucket は終わっていないものとして待つ
test_unknown_bucket_is_waited_for() {
  setup
  echo 1 >"$GH_FAKE_DIR/rollup"
  printf 'test\tqueued\thttps://ci/1\n' >"$GH_FAKE_DIR/checks.1.tsv"
  printf 'test\tpass\thttps://ci/1\n' >"$GH_FAKE_DIR/checks.2.tsv"
  run 5
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_eq 2 "$(grep -c '^pr checks$' "$GH_FAKE_DIR/calls.log")"
}

# 待ちには上限がある: --ci-timeout の分を過ぎても終わらなければ、merge せずに止まる (終了コード 12)。
# 30 秒おきに引き直すので、1 分なら 0・30・60 秒の 3 回見てから打ち切る
test_ci_wait_has_a_timeout() {
  setup
  echo 1 >"$GH_FAKE_DIR/rollup"
  printf 'test\tpending\thttps://ci/1\n' >"$GH_FAKE_DIR/checks.1.tsv"
  run 5 --ci-timeout 1
  assert_eq 12 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" 'CI_TIMEOUT: 1 分待っても終わらない check がある: test'
  assert_eq 3 "$(grep -c '^pr checks$' "$GH_FAKE_DIR/calls.log")"
  assert_eq 60 "$(cat "$MERGE_PR_CLOCK_FILE")"
  nothing_changed
}

# 既定の上限は 60 分 (0 秒から 3600 秒まで 30 秒おきに 121 回)
test_default_ci_timeout_is_60_minutes() {
  setup
  echo 1 >"$GH_FAKE_DIR/rollup"
  printf 'test\tpending\thttps://ci/1\n' >"$GH_FAKE_DIR/checks.1.tsv"
  run 5
  assert_eq 12 "$(cat "$T/rc.txt")"
  assert_eq 121 "$(grep -c '^pr checks$' "$GH_FAKE_DIR/calls.log")"
  assert_eq 3600 "$(cat "$MERGE_PR_CLOCK_FILE")"
}

# gh pr checks の一時的な失敗は 3 回まで続けて許し、それを超えたら止まる (終了コード 1)
test_repeated_checks_failures_stop() {
  setup
  echo 1 >"$GH_FAKE_DIR/rollup"
  echo 2 >"$GH_FAKE_DIR/checks_rc"
  run 5
  assert_eq 1 "$(cat "$T/rc.txt")"
  assert_eq 3 "$(grep -c '^pr checks$' "$GH_FAKE_DIR/calls.log")"
  nothing_changed
}

# --- PR と HEAD ---------------------------------------------------------------

# PR が無ければ何もせずに止まる (終了コード 10)。空の番号で gh pr merge を呼ばない
test_no_pr_stops_before_merge() {
  setup
  : >"$GH_FAKE_DIR/pr_open"
  run 5
  assert_eq 10 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" 'NO_PR: issue-5 のブランチの PR が無い'
  nothing_changed
}

# PR が issue を close しない (Development に紐付いていない) なら止まる (終了コード 10)
test_pr_not_linked_to_issue_stops() {
  setup
  echo 99 >"$GH_FAKE_DIR/closing"
  run 5
  assert_eq 10 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" 'NOT_LINKED: PR #12 は #5 を close しない'
  nothing_changed
}

# PR の HEAD が手元の HEAD に追いつくまで待ち、追いついたらそのコミットに限って merge する
test_waits_until_pr_head_matches_local_head() {
  setup
  local_sha=$(cat "$GH_FAKE_DIR/head_sha")
  printf '%s\n%s\n' 0000000000000000000000000000000000000000 "$local_sha" >"$GH_FAKE_DIR/head_sha"
  run 5
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$GH_FAKE_DIR/calls.log" 'pr merge 12'
}

# PR の HEAD が手元の HEAD にならないまま (push していない・別の人が push した) なら止まる (終了コード 16)
test_head_mismatch_stops() {
  setup
  echo 0000000000000000000000000000000000000000 >"$GH_FAKE_DIR/head_sha"
  run 5
  assert_eq 16 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" "HEAD_MISMATCH: PR #12 の HEAD (0000000) が手元の issue-5 の HEAD ($(git -C "$REPO" rev-parse --short=7 HEAD)) と違う"
  nothing_changed
}

# --- merge ---------------------------------------------------------------------

# merge が失敗し、コンフリクトしているなら止まる (終了コード 13)
test_conflicting_merge_stops_with_13() {
  setup
  echo 1 >"$GH_FAKE_DIR/merge_rc"
  echo 0 >"$GH_FAKE_DIR/merge_merges"
  echo 'CONFLICTING DIRTY' >"$GH_FAKE_DIR/mergeable"
  run 5
  assert_eq 13 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" 'CONFLICT: PR #12 はコンフリクトしている (mergeable: CONFLICTING, mergeStateStatus: DIRTY)'
  assert_eq issue-5 "$(git -C "$REPO" branch --show-current)"
}

# merge が失敗しても、コンフリクトでなければ (branch protection・権限など) 14 で止まる
test_non_conflict_merge_failure_stops_with_14() {
  setup
  echo 1 >"$GH_FAKE_DIR/merge_rc"
  echo 0 >"$GH_FAKE_DIR/merge_merges"
  echo 'MERGEABLE BLOCKED' >"$GH_FAKE_DIR/mergeable"
  run 5
  assert_eq 14 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" 'NOT_MERGED: PR #12 を merge できない (mergeable: MERGEABLE, mergeStateStatus: BLOCKED)'
}

# merge が成功を返しても MERGED にならなければ止まる (終了コード 14)
test_merge_that_does_not_reach_merged_stops() {
  setup
  echo 0 >"$GH_FAKE_DIR/merge_merges"
  run 5
  assert_eq 14 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" 'NOT_MERGED: PR #12 が MERGED にならない (状態: OPEN)'
}

# merge が非ゼロを返しても、MERGED なら成功として進む
test_merged_state_wins_over_exit_code() {
  setup
  echo 1 >"$GH_FAKE_DIR/merge_rc"
  run 5
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" 'MERGED #12'
}

# --- merge の後 -----------------------------------------------------------------

# merge の後の処理が失敗しても止めずに最後まで進め、15 を返す (merge 済みなので駐車しない)
test_failure_after_merge_returns_15_and_continues() {
  setup
  touch "$GH_FAKE_DIR/issue_view_fail"
  run 5
  assert_eq 15 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" 'MERGED #12'
  assert_file_contains_line "$T/out.txt" 'BRANCH: issue-5 を消した'
  assert_file_contains_line "$T/out.txt" 'PARENT: #1 は open のまま (子 1/2)'
  assert_file_contains_line "$T/out.txt" 'MERGED_INCOMPLETE: merge の後の処理に失敗したものがある (上の行)。同じコマンドを再実行すると、後片付けと完了処理をやり直す'
}

# 再実行で open の PR が無ければ merge 済みの PR を引き、後片付けと完了処理だけを行う
test_rerun_after_merge_finishes_the_rest() {
  setup
  : >"$GH_FAKE_DIR/pr_open"
  echo 12 >"$GH_FAKE_DIR/pr_merged"
  echo OPEN >"$GH_FAKE_DIR/issue_state"
  run 5
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" 'ALREADY_MERGED: PR #12 は merge 済み。後片付けと完了処理だけを行う'
  assert_file_contains_line "$T/out.txt" 'ISSUE: #5 を close した'
  assert_file_lacks_line "$GH_FAKE_DIR/calls.log" 'pr merge 12'
  assert_eq 0 "$(grep -c '^pr checks$' "$GH_FAKE_DIR/calls.log")"
}

# merge で issue が close されていなければ close する
test_closes_issue_if_merge_did_not() {
  setup
  echo OPEN >"$GH_FAKE_DIR/issue_state"
  run 5
  assert_file_contains_line "$T/out.txt" 'ISSUE: #5 を close した'
  assert_file_contains_line "$GH_FAKE_DIR/calls.log" 'issue close 5'
}

# in-progress が付いていなければ外さない
test_label_absent_is_not_removed() {
  setup
  : >"$GH_FAKE_DIR/issue_labels"
  run 5
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" 'LABEL: #5 に in-progress は付いていない'
  assert_file_lacks_line "$GH_FAKE_DIR/calls.log" 'issue edit 5 --remove-label in-progress'
}

# 親の子がすべて終わっていれば、親を close する
test_closes_parent_when_all_children_are_done() {
  setup
  printf '1\topen\t2/2\n' >"$GH_FAKE_DIR/parent"
  run 5
  assert_file_contains_line "$T/out.txt" 'PARENT: #1 を close した (子 2/2)'
  assert_file_contains_line "$GH_FAKE_DIR/calls.log" 'issue close 1'
}

# 親に紐付いていない子は正常 (close しない)。親を確かめられなければ、止めずに報告する
test_parent_missing_or_unreadable_is_reported() {
  setup
  rm "$GH_FAKE_DIR/parent"
  run 5
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" 'PARENT: なし (親に紐付いていない)'
  touch "$GH_FAKE_DIR/parent_error"
  g switch -q -c issue-5
  git -C "$REPO" rev-parse HEAD >"$GH_FAKE_DIR/head_sha"
  run 5
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" 'PARENT: 確かめられない (gh: Resource not accessible by integration (HTTP 403))'
}

# --- 後片付けと worktree -----------------------------------------------------------

# 並列実行の worktree は、ブランチより先に消す
test_removes_worktree_then_branch() {
  setup
  g switch -q main
  git -C "$REPO" worktree add -q "$T/wt" issue-5
  run 5 --worktree "$T/wt"
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_eq '' "$(git -C "$REPO" branch --list issue-5)"
  [ -d "$T/wt" ] && { echo '    worktree が残っている'; CASE_FAILED=1; }
  assert_file_contains_line "$T/out.txt" 'BRANCH: issue-5 を消した'
}

# worktree の中から --worktree なしで実行しても、本体の clone からその worktree とブランチを消す
test_run_inside_worktree_uses_main_clone() {
  setup
  g switch -q main
  git -C "$REPO" worktree add -q "$T/wt" issue-5
  run_in "$T/wt" 5
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_eq '' "$(git -C "$REPO" branch --list issue-5)"
  assert_file_contains_line "$T/out.txt" 'BRANCH: issue-5 を消した'
}

# 既定のブランチを別の worktree が使っていて switch できなければ、origin の既定のブランチに detach してから消す
test_detaches_when_default_branch_is_used_elsewhere() {
  setup
  git -C "$REPO" worktree add -q "$T/main-wt" main
  run 5
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_eq '' "$(git -C "$REPO" branch --show-current)"
  assert_eq '' "$(git -C "$REPO" branch --list issue-5)"
}

# 存在しない --worktree は、何もせずに止まる (終了コード 1)
test_missing_worktree_path_stops() {
  setup
  run 5 --worktree "$T/nowhere"
  assert_eq 1 "$(cat "$T/rc.txt")"
  nothing_changed
}

# --- 引数 ----------------------------------------------------------------------

# 番号の先頭の # は外す。数でなければ止まる。--ci-timeout は 1 以上の数 (0 で始まる値は受け付けない)
test_arguments_are_validated() {
  setup
  for bad in abc '5 --ci-timeout 0' '5 --ci-timeout 08' '5 --ci-timeout' '5 --ci-timeout x'; do
    # shellcheck disable=SC2086
    run $bad
    assert_eq 1 "$(cat "$T/rc.txt")"
  done
  nothing_changed
  run '#5'
  assert_eq 0 "$(cat "$T/rc.txt")"
}

run_tests
