#!/bin/sh
# dep-depth.sh のテスト
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../dep-depth.sh"
# shellcheck source=assert.sh
. "$HERE/assert.sh"

# ドラフトを 1 件書く。使い方: draft <連番> [依存先の連番...]
draft() {
  n=$1
  shift
  {
    printf '## ゴール\n対応 UC: 基盤\n\n## 依存\n'
    if [ $# -eq 0 ]; then
      printf '依存なし\n'
    else
      for d in "$@"; do printf 'Depends on issue-%s\n' "$d"; done
    fi
  } >"$T/issue-$n.md"
}

# 段は 1 → 2 → 4 → {3, 5} の 4 段。バッチは 1+1+1+1 = 4、下限は ceil(5/3) = 2
test_prints_levels_batches_and_lower_bound() {
  draft 1
  draft 2 1
  draft 4 2
  draft 3 2 4
  draft 5 2 4
  ${SH:-sh} "$SCRIPT" "$T" >"$T/out.txt"
  echo $? >"$T/rc.txt"
  printf '依存段数: L0..L3 (4 段、実行バッチ 4 / 下限 2)\nL0: issue-1\nL1: issue-2\nL2: issue-4\nL3: issue-3 issue-5\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
  assert_eq 0 "$(cat "$T/rc.txt")"
}

# 同じ段の 4 件は 2 バッチ (3 件ずつ)。依存の無い 4 件なら 1 段、バッチ 2、下限 2
test_counts_batches_by_three() {
  draft 1
  draft 2
  draft 3
  draft 4
  ${SH:-sh} "$SCRIPT" "$T" >"$T/out.txt"
  assert_file_contains_line "$T/out.txt" '依存段数: L0..L0 (1 段、実行バッチ 2 / 下限 2)'
}

# 並列の前提を満たさないプロジェクトでは、閾値の判定をしないと添える
test_serial_project_adds_note() {
  draft 1
  draft 2 1
  ${SH:-sh} "$SCRIPT" --serial "$T" >"$T/out.txt"
  assert_file_contains_line "$T/out.txt" '依存段数: L0..L1 (2 段、実行バッチ 2 / 下限 1) (並列前提を満たさないため閾値判定なし)'
}

# ドラフトに無い連番への依存は、名前を挙げて終了コード 2
test_unknown_dependency_exits_2() {
  draft 1
  draft 2 7
  ${SH:-sh} "$SCRIPT" "$T" >"$T/out.txt" 2>"$T/err.txt"
  echo $? >"$T/rc.txt"
  assert_eq 2 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/err.txt" 'issue-2.md の依存先 issue-7.md が無い'
}

# 循環は、入った連番を挙げて終了コード 3
test_cycle_exits_3() {
  draft 1 2
  draft 2 1
  ${SH:-sh} "$SCRIPT" "$T" >"$T/out.txt" 2>"$T/err.txt"
  echo $? >"$T/rc.txt"
  assert_eq 3 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/err.txt" '依存が循環している: issue-1.md issue-2.md'
}

# 1 行に複数の依存を並べた行は読めないので、行を挙げて終了コード 4
test_comma_separated_dependencies_exit_4() {
  draft 1
  draft 2
  printf '## 依存\nDepends on issue-1, issue-2\n' >"$T/issue-3.md"
  ${SH:-sh} "$SCRIPT" "$T" >"$T/out.txt" 2>"$T/err.txt"
  echo $? >"$T/rc.txt"
  assert_eq 4 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/err.txt" 'issue-3.md: 依存の行の形が違う (1 行に 1 件、Depends on issue-<連番> か Depends on #<番号>): Depends on issue-1, issue-2'
}

# 作成済みの issue への依存 (Depends on #<番号>) は段に数えない
test_existing_issue_dependency_is_not_counted() {
  printf '## 依存\nDepends on #12\n' >"$T/issue-1.md"
  draft 2 1
  ${SH:-sh} "$SCRIPT" "$T" >"$T/out.txt"
  assert_file_contains_line "$T/out.txt" '依存段数: L0..L1 (2 段、実行バッチ 2 / 下限 1)'
}

# ドラフトが 1 件も無ければ終了コード 1
test_no_drafts_exits_1() {
  ${SH:-sh} "$SCRIPT" "$T" >"$T/out.txt" 2>"$T/err.txt"
  echo $? >"$T/rc.txt"
  assert_eq 1 "$(cat "$T/rc.txt")"
}

run_tests
