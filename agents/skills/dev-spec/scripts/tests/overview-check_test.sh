#!/bin/sh
# overview-check.sh のテスト
# shellcheck disable=SC2016  # バッククォートは文書に書く文字そのもの
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../overview-check.sh"
# shellcheck source=assert.sh
. "$HERE/assert.sh"

# 検査に通る最小の docs/design を $T/d に作る
setup() {
  mkdir -p "$T/d/features"
  printf '# 全体像\n\n- 種別: 仕様の概要\n\n[書き出し](./features/export.md)\n' >"$T/d/OVERVIEW.md"
  feature export '利用者が一覧を書き出す。'
}

# 使い方: feature <ファイル名> <「何を作るか」の本文>
feature() {
  printf '# %s\n\n## 何を作るか\n\n%s\n\n## 入出力と振る舞い\n\n`GET /api/x`\n' "$1" "$2" >"$T/d/features/$1.md"
}

# 使い方: repeat <回数> <文字列>
repeat() {
  r=0
  while [ "$r" -lt "$1" ]; do
    printf '%s' "$2"
    r=$((r + 1))
  done
}

run() {
  CODE=0
  OUT=$(${SH:-sh} "$SCRIPT" "$@" 2>&1) || CODE=$?
}

test_passes_when_overview_lists_every_feature() {
  setup
  run "$T/d"
  assert_eq "" "$OUT"
  assert_eq 0 "$CODE"
}

test_reports_missing_overview() {
  setup
  rm "$T/d/OVERVIEW.md"
  run "$T/d"
  assert_eq "$T/d/OVERVIEW.md: 無い" "$OUT"
  assert_eq 1 "$CODE"
}

test_allows_missing_overview_when_features_are_named() {
  setup
  rm "$T/d/OVERVIEW.md"
  run "$T/d" "$T/d/features/export.md"
  assert_eq "" "$OUT"
  assert_eq 0 "$CODE"
}

test_reports_feature_not_listed_in_overview() {
  setup
  feature search '利用者が検索する。'
  run "$T/d"
  assert_eq "$T/d/OVERVIEW.md: features/search.md への参照が無い" "$OUT"
  assert_eq 1 "$CODE"
}

test_reports_overview_link_to_absent_feature() {
  setup
  printf '[消えた機能](./features/gone.md#x)\n' >>"$T/d/OVERVIEW.md"
  run "$T/d"
  assert_eq "$T/d/OVERVIEW.md: features/gone.md が無い" "$OUT"
  assert_eq 1 "$CODE"
}

test_checks_only_named_features_but_the_whole_overview() {
  setup
  feature search '`searchUsers` で検索する。'
  run "$T/d" "$T/d/features/export.md"
  assert_eq "$T/d/OVERVIEW.md: features/search.md への参照が無い" "$OUT"
  assert_eq 1 "$CODE"
}

test_reports_feature_without_section() {
  setup
  printf '# export\n\n## 入出力と振る舞い\n' >"$T/d/features/export.md"
  run "$T/d"
  assert_eq "$T/d/features/export.md: 「何を作るか」節が無いか、空である" "$OUT"
  assert_eq 1 "$CODE"
}

test_reports_code_identifier_in_section_only() {
  setup
  feature export '`exportCsv` で書き出す。'
  run "$T/d"
  assert_eq "$T/d/features/export.md:5: 実装の語 (バッククォート) がある" "$OUT"
  assert_eq 1 "$CODE"
}

test_ignores_contents_of_mermaid_diagram_but_checks_after_it() {
  setup
  feature export "$(printf '概要。\n\n  ```mermaid\n## 図の中\n`図の語`\n  ```\n\n`後の語`')"
  run "$T/d"
  assert_eq "$T/d/features/export.md:12: 実装の語 (バッククォート) がある" "$OUT"
  assert_eq 1 "$CODE"
}

test_reports_fence_other_than_mermaid() {
  setup
  feature export "$(printf '概要。\n\n~~~text\n## 契約\n~~~')"
  run "$T/d"
  assert_eq "$T/d/features/export.md:7: mermaid 以外のコードブロックがある" "$OUT"
  assert_eq 1 "$CODE"
}

test_section_byte_limit() {
  setup
  feature export "$(i=0; while [ $i -lt 10 ]; do repeat 400 a; echo; i=$((i + 1)); done)"
  run "$T/d"
  assert_eq 0 "$CODE"
  feature export "$(i=0; while [ $i -lt 10 ]; do repeat 400 a; echo; i=$((i + 1)); done; echo b)"
  run "$T/d"
  assert_eq "$T/d/features/export.md: 「何を作るか」が長い (4001 B / 上限 4000 B)" "$OUT"
  assert_eq 1 "$CODE"
}

test_overview_byte_limit() {
  setup
  i=0
  while [ "$i" -lt 40 ]; do
    repeat 400 a >>"$T/d/OVERVIEW.md"
    echo >>"$T/d/OVERVIEW.md"
    i=$((i + 1))
  done
  run "$T/d"
  assert_eq "1" "$(printf '%s\n' "$OUT" | grep -c "OVERVIEW.md: 長い (16[0-9]* B / 上限 16000 B)")"
  assert_eq 1 "$CODE"
}

test_does_not_confuse_names_that_share_a_suffix() {
  setup
  feature night-export '夜に書き出す。'
  printf '[夜](./features/night-export.md)\n' >"$T/d/OVERVIEW.md"
  run "$T/d"
  assert_eq "$T/d/OVERVIEW.md: features/export.md への参照が無い" "$OUT"
}

test_accepts_two_links_on_a_line_and_non_ascii_names() {
  setup
  feature 注文 '注文を見る。'
  printf '[書き出し](features/export.md) [注文](./features/注文.md#x)\n' >"$T/d/OVERVIEW.md"
  run "$T/d"
  assert_eq "" "$OUT"
}

test_reports_every_absent_link_on_a_line() {
  setup
  printf '[a](./features/a.md) [b](./features/b.md) [外](https://example.com/features/c.md)\n' >>"$T/d/OVERVIEW.md"
  run "$T/d"
  assert_eq "$T/d/OVERVIEW.md: features/a.md が無い
$T/d/OVERVIEW.md: features/b.md が無い" "$OUT"
}

test_reports_named_feature_that_is_absent() {
  setup
  run "$T/d" "$T/d/features/none.md"
  assert_eq "$T/d/features/none.md: 無い" "$OUT"
  assert_eq 1 "$CODE"
}

test_reports_no_features() {
  setup
  rm "$T/d/features/export.md"
  printf '# 全体像\n' >"$T/d/OVERVIEW.md"
  run "$T/d"
  assert_eq "$T/d/features: 機能設計書が無い" "$OUT"
}

test_accepts_crlf() {
  setup
  printf '# export\r\n\r\n## 何を作るか\r\n\r\n書き出す。\r\n' >"$T/d/features/export.md"
  run "$T/d"
  assert_eq "" "$OUT"
}

test_section_line_limit_counts_bytes() {
  setup
  feature export "$(repeat 450 a)"
  run "$T/d"
  assert_eq 0 "$CODE"
  feature export "$(repeat 151 あ)"
  run "$T/d"
  assert_eq "$T/d/features/export.md:5: 1 行が長い (453 B / 上限 450 B)" "$OUT"
  assert_eq 1 "$CODE"
}

test_section_row_limit_ignores_blank_lines() {
  setup
  feature export "$(i=0; while [ $i -lt 40 ]; do printf 'x\n\n'; i=$((i + 1)); done)"
  run "$T/d"
  assert_eq 0 "$CODE"
  feature export "$(i=0; while [ $i -lt 41 ]; do printf 'x\n\n'; i=$((i + 1)); done)"
  run "$T/d"
  assert_eq "$T/d/features/export.md: 「何を作るか」が長い (41 行 / 上限 40 行)" "$OUT"
  assert_eq 1 "$CODE"
}

test_overview_row_limit() {
  setup
  i=0
  while [ "$i" -lt 148 ]; do
    echo x >>"$T/d/OVERVIEW.md"
    i=$((i + 1))
  done
  run "$T/d"
  assert_eq "$T/d/OVERVIEW.md: 長い (151 行 / 上限 150 行)" "$OUT"
  assert_eq 1 "$CODE"
}

test_reports_history_comment() {
  setup
  printf '<!-- 変更履歴 [2026-01-01]: 足した -->\n' >>"$T/d/features/export.md"
  run "$T/d"
  assert_eq "$T/d/features/export.md:10: 変更履歴のコメントがある" "$OUT"
  assert_eq 1 "$CODE"
}

test_reports_all_problems() {
  setup
  feature export '`exportCsv` で書き出す。'
  feature search '利用者が検索する。'
  run "$T/d"
  assert_eq "$T/d/OVERVIEW.md: features/search.md への参照が無い
$T/d/features/export.md:5: 実装の語 (バッククォート) がある" "$OUT"
  assert_eq 1 "$CODE"
}

test_reports_usage_error_for_absent_directory() {
  run "$T/none"
  assert_eq 2 "$CODE"
}

run_tests
