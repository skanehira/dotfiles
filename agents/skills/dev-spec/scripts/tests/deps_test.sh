#!/bin/sh
# deps.awk のテスト。使い方: sh deps_test.sh (PATH の先頭の awk で実行する)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
DEPS="$HERE/../deps.awk"
# shellcheck source=assert.sh
. "$HERE/assert.sh"

# 段: 依存の無い issue が L0、それ以外は依存先の最大 + 1。段・番号の順に並べる
test_levels_orders_by_level_then_number() {
  printf '1\ttarget\t\t\n2\ttarget\t\t1\n4\ttarget\t\t2\n3\ttarget\t\t2,4\n5\ttarget\t\t2,4\n' >"$T/in.tsv"
  awk -F '\t' -v mode=levels -f "$DEPS" "$T/in.tsv" >"$T/out.txt"
  echo $? >"$T/rc.txt"
  printf 'level\t1\t0\nlevel\t2\t1\nlevel\t4\t2\nlevel\t3\t3\nlevel\t5\t3\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
  assert_eq 0 "$(cat "$T/rc.txt")"
}

# 番号は数として並べる (10 は 9 の後)
test_levels_sorts_numbers_numerically() {
  printf '10\ttarget\t\t\n9\ttarget\t\t\n' >"$T/in.tsv"
  awk -F '\t' -v mode=levels -f "$DEPS" "$T/in.tsv" >"$T/out.txt"
  printf 'level\t9\t0\nlevel\t10\t0\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# 入力に無い依存先は unknown を出して終了コード 2
test_levels_unknown_dependency_exits_2() {
  printf '1\ttarget\t\t\n2\ttarget\t\t9\n' >"$T/in.tsv"
  awk -F '\t' -v mode=levels -f "$DEPS" "$T/in.tsv" >"$T/out.txt"
  echo $? >"$T/rc.txt"
  printf 'unknown\t2\t9\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
  assert_eq 2 "$(cat "$T/rc.txt")"
}

# 循環 (と、循環に依存する issue) は cycle を出して終了コード 3
test_levels_cycle_exits_3() {
  printf '1\ttarget\t\t3\n2\ttarget\t\t1\n3\ttarget\t\t2\n4\ttarget\t\t3\n5\ttarget\t\t\n' >"$T/in.tsv"
  awk -F '\t' -v mode=levels -f "$DEPS" "$T/in.tsv" >"$T/out.txt"
  echo $? >"$T/rc.txt"
  printf 'cycle\t1\ncycle\t2\ncycle\t3\ncycle\t4\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
  assert_eq 3 "$(cat "$T/rc.txt")"
}

# 着手順: 依存先がすべて closed の target だけを start に出す。open の依存先が残る target は wait
test_order_starts_only_targets_whose_dependencies_are_closed() {
  printf '1\tclosed\t\t\n2\ttarget\t\t1\n3\ttarget\t\t2\n4\topen\t\t\n5\ttarget\t\t4\n' >"$T/in.tsv"
  awk -F '\t' -v mode=order -f "$DEPS" "$T/in.tsv" >"$T/out.txt"
  echo $? >"$T/rc.txt"
  printf 'start\t2\t-\nwait\t3\t2\nwait\t5\t4\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
  assert_eq 0 "$(cat "$T/rc.txt")"
}

# 実効スコア: 自分と、自分に (間接に) 依存する target のスコアの最大。高い順、同じなら番号の小さい順
test_order_sorts_by_effective_score() {
  # 2 は自分 1 点だが、2 に依存する 4 が 9 点なので実効 9。3 は 5 点。1 はスコア無し
  printf '1\ttarget\t\t\n2\ttarget\t1\t\n3\ttarget\t5\t\n4\ttarget\t9\t2\n' >"$T/in.tsv"
  awk -F '\t' -v mode=order -f "$DEPS" "$T/in.tsv" >"$T/out.txt"
  printf 'start\t2\t9\nstart\t3\t5\nstart\t1\t-\nwait\t4\t2\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# 緊急枠 (U) はどのスコアよりも高い。依存先にも引き継がれる
test_order_urgent_is_highest_and_inherited() {
  printf '1\ttarget\t100\t\n2\ttarget\t1\t\n3\ttarget\tU\t2\n' >"$T/in.tsv"
  awk -F '\t' -v mode=order -f "$DEPS" "$T/in.tsv" >"$T/out.txt"
  printf 'start\t2\tU\nstart\t1\t100\nwait\t3\t2\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# target 以外 (open) の issue のスコアは引き継がない
test_order_does_not_inherit_score_from_non_targets() {
  printf '1\ttarget\t1\t\n2\topen\t99\t1\n3\ttarget\t5\t\n' >"$T/in.tsv"
  awk -F '\t' -v mode=order -f "$DEPS" "$T/in.tsv" >"$T/out.txt"
  printf 'start\t3\t5\nstart\t1\t1\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

# 着手順では循環しても止めず、循環した target を cycle に出して着手しない
test_order_reports_cycle_and_continues() {
  printf '1\ttarget\t\t2\n2\ttarget\t\t1\n3\ttarget\t\t\n' >"$T/in.tsv"
  awk -F '\t' -v mode=order -f "$DEPS" "$T/in.tsv" >"$T/out.txt"
  echo $? >"$T/rc.txt"
  printf 'start\t3\t-\ncycle\t1\ncycle\t2\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
  assert_eq 0 "$(cat "$T/rc.txt")"
}

# 着手順で入力に無い依存先は unknown に出し、その target は着手しない
test_order_unknown_dependency_is_reported_and_not_started() {
  printf '1\ttarget\t\t7\n2\ttarget\t\t\n' >"$T/in.tsv"
  awk -F '\t' -v mode=order -f "$DEPS" "$T/in.tsv" >"$T/out.txt"
  printf 'start\t2\t-\nunknown\t1\t7\n' >"$T/exp.txt"
  assert_file_eq "$T/exp.txt" "$T/out.txt"
}

run_tests
