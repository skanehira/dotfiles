#!/bin/sh
# dev-impl の 2.4 手順 4 (CI ゲートと merge) と 2.5 (完了処理) を行う。規則の正本は SKILL.md の同じ節。
#
# 使い方: sh merge-pr.sh <issue 番号> [--worktree <パス>] [--ci-timeout <分>]
#   dev-impl の REPO_DIR (clone の直下か、セッションが動いている worktree) で実行する。実行した場所を REPO_DIR として扱う
#   --worktree <パス>: 作業場所が worktree のときと、Step 1 で引き継いだ issue の worktree。merge の後、ブランチより先に消す。
#                     issue の worktree (名前が issue-<番号>) の中で --worktree なしに実行すると、何も変えずに止まる
#   --ci-timeout <分>: CI の待ちの上限 (既定 60 分)。checks の登録を待ち始めてからの経過時間で数える
#
# 行うこと:
#   1. issue-<番号> のブランチの open の PR を引き、その PR が同じリポジトリの issue を close することを確かめる。
#      open の PR が無く merge 済みの PR があれば (前の実行が merge の後で止まった)、5 と 6 だけを行う
#   2. PR の HEAD が手元のブランチの HEAD に追いつくまで待つ (push の反映待ち)
#   3. CI を待つ。workflow のファイルがあれば checks の登録を 10 秒おきに最大 12 回待つ。checks が 0 件なら CI なし。
#      checks があれば 30 秒おきに引き直し、fail か cancel が出たら止める。全件が pass か skipping になるまで、
#      上限まで待つ (gh pr checks --watch は上限を持たないので使わない)
#   4. 2 で確かめたコミットに限って squash で merge し (--match-head-commit)、PR が MERGED になったかで成否を判定する
#   5. 手元の worktree とブランチを消す (gh pr merge --repo --delete-branch はリモートのブランチしか消さない)
#   6. issue が close されていなければ close し、in-progress を外す。親の子がすべて終わっていれば親を close する
#   merge の後 (5 と 6) は失敗しても止めずに最後まで進める。完了コメントは書かない (中身を知るエージェントが書く)
#
# 標準出力: PR #<番号> / CI: ... / MERGED #<番号> / BRANCH: ... / ISSUE: ... / LABEL: ... / PARENT: ...
#
# 終了コード:
#   0  merge と完了処理を終えた
#   1  使い方の誤り・gh や git の失敗 (merge の前)。merge の後に PR の状態を取れないときも 1 (MERGE_UNKNOWN)
#   10 PR が無い (NO_PR) か、PR が issue を close しない (NOT_LINKED)。何も変えていない
#   11 CI が失敗した (CI_FAIL: <名前><TAB><bucket><TAB><リンク> を 1 行ずつ)。merge していない
#   12 CI が上限までに終わらない (CI_TIMEOUT)。merge していない
#   13 PR がコンフリクトしていて merge できない (CONFLICT)
#   14 merge できない・MERGED にならない (NOT_MERGED)。branch protection・権限・マージキューなどを疑う
#   15 merge は済んだが、その後の処理に失敗したものがある (MERGED_INCOMPLETE)。再実行で続きから行う
#   16 PR の HEAD が手元の HEAD にならない (HEAD_MISMATCH)。何も変えていない
#
# テストでは MERGE_PR_NO_SLEEP=1 で待ちを飛ばし、MERGE_PR_CLOCK_FILE の時計を進める。
# POSIX の sh で書く (macOS の sh と Ubuntu の dash で動かすため。bash だけの書き方を使わない)。
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SPEC="$HERE/../../dev-spec/scripts"
# shellcheck source=../../dev-spec/scripts/lib.sh
. "$SPEC/lib.sh"

USAGE="使い方: sh merge-pr.sh <issue 番号> [--worktree <パス>] [--ci-timeout <分>]"
N=""
WT=""
TIMEOUT_MIN=60
while [ $# -gt 0 ]; do
  case $1 in
    --worktree)
      [ $# -ge 2 ] || die 1 "$USAGE"
      WT=$2
      shift 2
      ;;
    --ci-timeout)
      [ $# -ge 2 ] || die 1 "$USAGE"
      TIMEOUT_MIN=$2
      shift 2
      ;;
    *)
      [ -z "$N" ] || die 1 "$USAGE"
      N=${1#\#}
      shift
      ;;
  esac
done
case $N in '' | *[!0-9]*) die 1 "$USAGE" ;; esac
case $TIMEOUT_MIN in '' | *[!0-9]* | 0*) die 1 "--ci-timeout には 1 以上の分を渡す (0 で始めない): $TIMEOUT_MIN" ;; esac

POLL_SECONDS=30
REGISTER_TRIES=12
REGISTER_INTERVAL=10
CHECKS_RETRIES=3

now() { if [ -n "${MERGE_PR_CLOCK_FILE:-}" ]; then cat "$MERGE_PR_CLOCK_FILE"; else date +%s; fi; }
nap() {
  if [ "${MERGE_PR_NO_SLEEP:-0}" = 1 ]; then
    [ -n "${MERGE_PR_CLOCK_FILE:-}" ] && echo $(($(cat "$MERGE_PR_CLOCK_FILE") + $1)) >"$MERGE_PR_CLOCK_FILE"
  else
    sleep "$1"
  fi
  return 0
}
run_gh() { gh "$@" </dev/null; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/merge-pr.XXXXXX") || die 1 "一時ディレクトリを作れない"
trap 'rm -rf "$TMP"' EXIT

# 実行した場所 (dev-impl の REPO_DIR) を基準にする。dev-impl のセッション自身が worktree (claude --worktree) で
# 動くことがあり、本体の clone を探して使うと、セッションの worktree を issue の worktree と取り違えて消しうる
TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || die 1 "git のリポジトリの中で実行する"
REPO_DIR=$(cd "$TOPLEVEL" && pwd -P) || die 1 "作業ツリーを決められない"
if [ -n "$WT" ]; then
  [ -d "$WT" ] || die 1 "--worktree のディレクトリが無い: $WT"
  WT=$(cd "$WT" && pwd -P)
  [ "$WT" != "$REPO_DIR" ] || die 1 "--worktree に実行した場所 (REPO_DIR) を渡している: $WT"
elif [ "$(basename "$REPO_DIR")" = "issue-$N" ]; then
  die 1 "issue-$N の worktree の中で実行している。dev-impl の REPO_DIR で --worktree $REPO_DIR を付けて実行する"
fi
WORK_DIR=${WT:-$REPO_DIR}

REPO=$(run_gh repo view --json nameWithOwner -q .nameWithOwner) || die 1 "GitHub のリポジトリを決められない"
OWNER=${REPO%%/*}
DEFAULT=$(run_gh repo view --json defaultBranchRef -q .defaultBranchRef.name) || die 1 "既定のブランチを取れない"
[ -n "$DEFAULT" ] || die 1 "既定のブランチを取れない (リポジトリにコミットが無い)"

# --- 1. PR -------------------------------------------------------------------

# 同じ持ち主のリポジトリの issue-<番号> のブランチの PR (fork の同名のブランチを取り違えない)
find_pr() { # $1: open か merged
  run_gh pr list --repo "$REPO" --head "issue-$N" --state "$1" --json number,headRepositoryOwner \
    --jq ".[] | select(.headRepositoryOwner.login == \"$OWNER\") | .number" >"$TMP/pr.txt" ||
    die 1 "PR の一覧を取れない"
  head -n 1 "$TMP/pr.txt"
}

ALREADY_MERGED=0
PR=$(find_pr open) || exit 1
if [ -z "$PR" ]; then
  PR=$(find_pr merged) || exit 1
  [ -n "$PR" ] && ALREADY_MERGED=1
fi
if [ -z "$PR" ]; then
  # 空の番号で gh pr merge を呼ぶと、カレントブランチの別の PR を merge しうる
  echo "NO_PR: issue-$N のブランチの PR が無い"
  exit 10
fi
echo "PR #$PR"
run_gh pr view "$PR" --repo "$REPO" --json closingIssuesReferences \
  --jq ".closingIssuesReferences[] | select((.repository.owner.login + \"/\" + .repository.name) == \"$REPO\") | .number" \
  >"$TMP/closing.txt" || die 1 "PR #$PR の紐付けを取れない"
if ! grep -qx "$N" "$TMP/closing.txt"; then
  echo "NOT_LINKED: PR #$PR は #$N を close しない"
  exit 10
fi

if [ "$ALREADY_MERGED" = 1 ]; then
  echo "ALREADY_MERGED: PR #$PR は merge 済み。後片付けと完了処理だけを行う"
else
  # --- 2. PR の HEAD -----------------------------------------------------------

  LOCAL_SHA=$(git -C "$WORK_DIR" rev-parse HEAD) || die 1 "手元の HEAD を取れない"
  tries=0
  while :; do
    tries=$((tries + 1))
    PR_SHA=$(run_gh pr view "$PR" --repo "$REPO" --json headRefOid -q .headRefOid) || die 1 "PR #$PR の HEAD を取れない"
    [ "$PR_SHA" = "$LOCAL_SHA" ] && break
    if [ "$tries" -ge "$REGISTER_TRIES" ]; then
      echo "HEAD_MISMATCH: PR #$PR の HEAD ($(printf '%.7s' "$PR_SHA")) が手元の $(git -C "$WORK_DIR" branch --show-current) の HEAD ($(printf '%.7s' "$LOCAL_SHA")) と違う"
      exit 16
    fi
    nap "$REGISTER_INTERVAL"
  done

  # --- 3. CI -------------------------------------------------------------------

  DEADLINE=$(($(now) + TIMEOUT_MIN * 60))
  ci_count() {
    run_gh pr view "$PR" --repo "$REPO" --json statusCheckRollup -q '.statusCheckRollup | length' >"$TMP/count.txt" ||
      die 1 "PR #$PR の checks の件数を取れない"
    cat "$TMP/count.txt"
  }
  count=$(ci_count) || exit 1
  if [ -n "$(git -C "$WORK_DIR" ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml')" ]; then
    # push の直後は checks の登録が遅れる
    tries=1
    while [ "$count" -eq 0 ] && [ "$tries" -lt "$REGISTER_TRIES" ]; do
      nap "$REGISTER_INTERVAL"
      count=$(ci_count) || exit 1
      tries=$((tries + 1))
    done
  fi

  if [ "$count" -eq 0 ]; then
    CI_LINE="CI: なし (checks 未登録)"
  else
    failures=0
    while :; do
      # gh pr checks は pending で 8、失敗で 1 を返すので、終了コードでは判定しない
      run_gh pr checks "$PR" --repo "$REPO" --json name,bucket,link --jq '.[] | [.name, .bucket, .link] | @tsv' \
        >"$TMP/checks.tsv" 2>"$TMP/checks_err.txt"
      rc=$?
      if { [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ] && [ "$rc" -ne 8 ]; } || [ ! -s "$TMP/checks.tsv" ]; then
        failures=$((failures + 1))
        [ "$failures" -lt "$CHECKS_RETRIES" ] ||
          die 1 "PR #$PR の checks を $CHECKS_RETRIES 回続けて取れない (終了コード $rc): $(cat "$TMP/checks_err.txt")"
        nap "$POLL_SECONDS"
        continue
      fi
      failures=0
      if awk -F '\t' '$2 == "fail" || $2 == "cancel" { found = 1 } END { exit !found }' "$TMP/checks.tsv"; then
        awk -F '\t' '$2 == "fail" || $2 == "cancel" { print "CI_FAIL: " $0 }' "$TMP/checks.tsv"
        exit 11
      fi
      # pass と skipping 以外 (pending と、知らない bucket) が残っていれば待つ
      awk -F '\t' '$2 != "pass" && $2 != "skipping" { found = 1 } END { exit !found }' "$TMP/checks.tsv" || break
      if [ "$(now)" -ge "$DEADLINE" ]; then
        echo "CI_TIMEOUT: $TIMEOUT_MIN 分待っても終わらない check がある: $(awk -F '\t' '$2 != "pass" && $2 != "skipping" { s = s (s == "" ? "" : ", ") $1 } END { print s }' "$TMP/checks.tsv")"
        exit 12
      fi
      nap "$POLL_SECONDS"
    done
    CI_LINE="CI: pass ($(awk -F '\t' '{ s = s (NR > 1 ? ", " : "") $1 } END { print s }' "$TMP/checks.tsv"))"
  fi
  echo "$CI_LINE"

  # --- 4. merge ----------------------------------------------------------------

  run_gh pr merge "$PR" --repo "$REPO" --squash --delete-branch --match-head-commit "$LOCAL_SHA" \
    >/dev/null 2>"$TMP/merge_err.txt"
  merge_rc=$?
  # merge の後に状態を取れなければ、merge したかが分からない。再実行すると open の PR か merge 済みの PR を引き直す
  read_pr_state() { # PR の状態を $state に入れる。2 回続けて取れなければ止まる
    run_gh pr view "$PR" --repo "$REPO" --json state -q .state >"$TMP/state.txt" 2>/dev/null || {
      nap 5
      run_gh pr view "$PR" --repo "$REPO" --json state -q .state >"$TMP/state.txt" 2>/dev/null
    } || {
      echo "MERGE_UNKNOWN: PR #$PR を merge したかを確かめられない。同じコマンドを再実行すると確かめ直す"
      exit 1
    }
    state=$(cat "$TMP/state.txt")
  }
  read_pr_state
  if [ "$state" != MERGED ]; then
    if [ "$merge_rc" -ne 0 ]; then
      run_gh pr view "$PR" --repo "$REPO" --json mergeable,mergeStateStatus -q '.mergeable + " " + .mergeStateStatus' \
        >"$TMP/mergeable.txt" 2>/dev/null || echo "UNKNOWN UNKNOWN" >"$TMP/mergeable.txt"
      read -r mergeable merge_status <"$TMP/mergeable.txt"
      cat "$TMP/merge_err.txt" >&2
      case "$mergeable $merge_status" in
        CONFLICTING* | *" DIRTY" | *" BEHIND")
          echo "CONFLICT: PR #$PR はコンフリクトしている (mergeable: $mergeable, mergeStateStatus: $merge_status)"
          exit 13
          ;;
      esac
      echo "NOT_MERGED: PR #$PR を merge できない (mergeable: $mergeable, mergeStateStatus: $merge_status)"
      exit 14
    fi
    nap 5
    read_pr_state
    if [ "$state" != MERGED ]; then
      echo "NOT_MERGED: PR #$PR が MERGED にならない (状態: $state)"
      exit 14
    fi
  fi
  echo "MERGED #$PR"
fi

# --- 5. 後片付け (merge は済んでいる。ここから先は失敗しても止めずに最後まで進める) ----

INCOMPLETE=0
if [ -n "$WT" ] && [ -d "$WT" ]; then
  git -C "$REPO_DIR" worktree remove "$WT" 2>"$TMP/wt_err.txt" ||
    echo "BRANCH: worktree $WT を消せない ($(tail -n 1 "$TMP/wt_err.txt"))"
fi
if [ "$(git -C "$REPO_DIR" branch --show-current)" = "issue-$N" ]; then
  # チェックアウト中のブランチは消せない。既定のブランチを別の worktree が使っていれば detach する
  git -C "$REPO_DIR" switch -q "$DEFAULT" 2>/dev/null || git -C "$REPO_DIR" switch -q --detach "origin/$DEFAULT" 2>/dev/null
fi
git -C "$REPO_DIR" show-ref --verify --quiet "refs/heads/issue-$N"
case $? in
  0)
    if git -C "$REPO_DIR" branch -D "issue-$N" >/dev/null 2>"$TMP/br_err.txt"; then
      echo "BRANCH: issue-$N を消した"
    else
      echo "BRANCH: issue-$N が残った ($(tail -n 1 "$TMP/br_err.txt"))"
    fi
    ;;
  1) echo "BRANCH: issue-$N は手元に無い" ;;
  *) echo "BRANCH: issue-$N があるか確かめられない" ;;
esac

# --- 6. 完了処理 -------------------------------------------------------------

if issue_state=$(run_gh issue view "$N" --repo "$REPO" --json state -q .state); then
  if [ "$issue_state" = CLOSED ]; then
    echo "ISSUE: #$N は merge で close された"
  elif run_gh issue close "$N" --repo "$REPO" >/dev/null; then
    echo "ISSUE: #$N を close した"
  else
    echo "ISSUE: #$N を close できない"
    INCOMPLETE=1
  fi
else
  echo "ISSUE: #$N の状態を取れない"
  INCOMPLETE=1
fi

# close しても in-progress は自動では外れず、残ると Step 1 の再開の判定に紛れる
if run_gh issue view "$N" --repo "$REPO" --json labels -q '.labels[].name' >"$TMP/labels.txt"; then
  if ! grep -qx in-progress "$TMP/labels.txt"; then
    echo "LABEL: #$N に in-progress は付いていない"
  elif run_gh issue edit "$N" --remove-label in-progress --repo "$REPO" >/dev/null; then
    echo "LABEL: #$N から in-progress を外した"
  else
    echo "LABEL: #$N の in-progress を外せない"
    INCOMPLETE=1
  fi
else
  echo "LABEL: #$N のラベルを確かめられない"
  INCOMPLETE=1
fi

# 親の子の数は API が数える値を使う (自前で数え直さない)。merge 直後は子の close が反映されていないことがあるが、
# 再試行はしない (取りこぼしは dev-impl の Step 3 が回収する)
if run_gh api "repos/$REPO/issues/$N/parent" \
  --jq '"\(.number)\t\(.state)\t\(.sub_issues_summary.completed)/\(.sub_issues_summary.total)"' \
  >"$TMP/parent.txt" 2>"$TMP/parent_err.txt"; then
  IFS="$(printf '\t')" read -r parent parent_state progress <"$TMP/parent.txt"
  done_count=${progress%/*}
  total=${progress#*/}
  if [ "$parent_state" = open ] && [ "$done_count" = "$total" ]; then
    if run_gh issue close "$parent" --repo "$REPO" --comment "この親 issue の sub-issue がすべて完了したため close する (dev-impl)" >/dev/null; then
      echo "PARENT: #$parent を close した (子 $progress)"
    else
      echo "PARENT: #$parent を close できなかった (子 $progress)"
    fi
  elif [ "$parent_state" = open ]; then
    echo "PARENT: #$parent は open のまま (子 $progress)"
  else
    echo "PARENT: #$parent は close 済み (子 $progress)"
  fi
elif grep -q 'HTTP 404' "$TMP/parent_err.txt"; then
  echo "PARENT: なし (親に紐付いていない)"
else
  echo "PARENT: 確かめられない ($(tail -n 1 "$TMP/parent_err.txt"))"
fi

if [ "$INCOMPLETE" = 1 ]; then
  echo "MERGED_INCOMPLETE: merge の後の処理に失敗したものがある (上の行)。同じコマンドを再実行すると、後片付けと完了処理をやり直す"
  exit 15
fi
exit 0
