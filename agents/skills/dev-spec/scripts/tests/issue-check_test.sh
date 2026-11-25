#!/bin/sh
# issue-check.sh のテスト
# shellcheck disable=SC2016  # バッククォートは本文に書く文字そのもの
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../issue-check.sh"
# shellcheck source=assert.sh
. "$HERE/assert.sh"

# 検査に通る本文を $T/issue.md に書く。使い方: body [ゴールの本文]
body() {
  cat >"$T/issue.md" <<EOF
## ゴール
${1:-利用者が一覧を書き出せるようにする。}

**いま困っていること**: 書き出せない

**こうなる**: 書き出せる

**変わらないこと**: 一覧の並び

<details>
<summary>実装用 (AI が読む)</summary>

## 設計
対応 UC: UC-001: 書き出す
docs/design/features/export.md 参照

## DoD
- \`deno test\` が green

## 非スコープ
なし

## 依存
依存なし

</details>

## 優先度
スコア 1.0 (2026-01-01 採点)
EOF
}

# 使い方: replace <sed の式>
replace() {
  sed "$1" "$T/issue.md" >"$T/new.md" && mv "$T/new.md" "$T/issue.md"
}

# 250 B の行に分けた、指定したバイト数の文章
filler() {
  awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) printf "%s", (i % 250 == 249) ? "x\n" : "x" }'
}

run() {
  CODE=0
  OUT=$(${SH:-sh} "$SCRIPT" "$@" 2>&1) || CODE=$?
}

assert_problem() {
  run "$T/issue.md"
  assert_eq "$T/issue.md$1" "$OUT"
  assert_eq 1 "$CODE"
}

test_passes_for_valid_body() {
  body
  run "$T/issue.md"
  assert_eq "" "$OUT"
  assert_eq 0 "$CODE"
}

test_passes_without_priority_and_with_crlf() {
  body "$(awk 'BEGIN { for (i = 0; i < 22; i++) print "x" }')"
  replace '/^## 優先度/,$d'
  sed "s/\$/$(printf '\r')/" "$T/issue.md" >"$T/new.md" && mv "$T/new.md" "$T/issue.md"
  run "$T/issue.md"
  assert_eq "" "$OUT"
  assert_eq 0 "$CODE"
}

test_reports_text_before_goal() {
  body
  replace '1s/^/前書き\
\
/'
  assert_problem ': 「ゴール」節で始まっていない'
}

test_reports_empty_goal() {
  body
  replace '2,/^\*\*変わらない/d'
  run "$T/issue.md"
  assert_eq "$T/issue.md: 「ゴール」節が無いか、空である
$T/issue.md: 「ゴール」に「いま困っていること」が無い
$T/issue.md: 「ゴール」に「こうなる」が無い
$T/issue.md: 「ゴール」に「変わらないこと」が無い" "$OUT"
  assert_eq 1 "$CODE"
}

test_reports_code_identifier_in_goal() {
  body '`exportCsv` で書き出す。'
  assert_problem ':2: 実装の語 (バッククォート) がある'
}

test_reports_metadata_in_goal() {
  body '対応 UC: UC-001: 書き出す'
  assert_problem ':2: 「対応 UC」「担う受け入れ基準」は「設計」節に書く'
}

test_reports_criteria_in_goal() {
  body '担う受け入れ基準: （US-001）書き出せる'
  assert_problem ':2: 「対応 UC」「担う受け入れ基準」は「設計」節に書く'
}

test_goal_line_limit() {
  body "$(awk 'BEGIN { for (i = 0; i < 100; i++) printf "あ" }')"
  run "$T/issue.md"
  assert_eq 0 "$CODE"
  body "$(awk 'BEGIN { for (i = 0; i < 101; i++) printf "あ" }')"
  assert_problem ':2: 1 行が長い (303 B / 上限 300 B)'
}

test_goal_line_limit_ignores_link_targets() {
  body "[書き出し](https://example.com/$(awk 'BEGIN { for (i = 0; i < 300; i++) printf "a" }'))"
  run "$T/issue.md"
  assert_eq "" "$OUT"
}

test_goal_row_limit() {
  body "$(awk 'BEGIN { for (i = 0; i < 22; i++) print "x" }')"
  run "$T/issue.md"
  assert_eq 0 "$CODE"
  body "$(awk 'BEGIN { for (i = 0; i < 23; i++) print "x" }')"
  assert_problem ': 「ゴール」が長い (26 行 / 上限 25 行)'
}

test_goal_byte_limit() {
  body "$(filler 2374)"
  run "$T/issue.md"
  assert_eq "" "$OUT"
  body "$(filler 2375)"
  assert_problem ': 「ゴール」が長い (2501 B / 上限 2500 B)'
}

test_goal_byte_limit_ignores_link_targets() {
  body "$(filler 2000)
[書き出し](https://example.com/$(awk 'BEGIN { for (i = 0; i < 600; i++) printf "a" }'))"
  run "$T/issue.md"
  assert_eq "" "$OUT"
}

test_reports_unfolded_implementation() {
  body
  replace '/details>/d; /summary>/d'
  run "$T/issue.md"
  assert_eq 1 "$(printf '%s\n' "$OUT" | grep -c '折りたたみは 1 つだけにする')"
  assert_eq 1 "$CODE"
}

test_reports_unclosed_fold() {
  body
  replace '/^<\/details>/,$d'
  assert_problem ': 折りたたみは 1 つだけにする (<details> と </details> を 1 回ずつ)'
}

test_reports_section_outside_fold() {
  body
  replace '/^<\/details>/d'
  replace 's/^## 依存$/<\/details>\
\
## 依存/'
  run "$T/issue.md"
  assert_eq "$T/issue.md:25: 折りたたみの外に書いてよい見出しは「ゴール」と「優先度」だけ
$T/issue.md: 実装用の節が 設計・DoD・非スコープ・依存 の順に揃っていない" "$OUT"
  assert_eq 1 "$CODE"
}

test_reports_priority_inside_fold() {
  body
  replace '/^<\/details>/d'
  printf '\n</details>\n' >>"$T/issue.md"
  assert_problem ': 「優先度」は折りたたみの後に書く'
}

test_reports_missing_blank_line_after_summary() {
  body
  replace '/^<summary>/{n;d;}'
  assert_problem ': <summary> の次に空行が無い (中の Markdown が表示されない)'
}

test_reports_sections_that_are_missing_or_out_of_order() {
  body
  replace '/^## DoD/,/^- /d'
  assert_problem ': 実装用の節が 設計・DoD・非スコープ・依存 の順に揃っていない'
  body
  replace 's/^## DoD$/## 仮/; s/^## 非スコープ$/## DoD/; s/^## 仮$/## 非スコープ/'
  assert_problem ': 実装用の節が 設計・DoD・非スコープ・依存 の順に揃っていない'
}

test_reports_each_missing_item_of_goal() {
  for item in いま困っていること こうなる 変わらないこと; do
    body
    replace "/^\\*\\*$item/d"
    assert_problem ": 「ゴール」に「$item」が無い"
  done
}

test_reports_missing_usecase() {
  body
  replace '/^対応 UC/d'
  assert_problem ': 「設計」に「対応 UC」が無い'
}

test_reports_missing_summary() {
  body
  replace '/^<summary>/d'
  assert_problem ': <details> の次に <summary> が無い'
}

test_reports_other_heading_outside_fold() {
  body
  replace 's/^<details>$/## 背景\
長い説明\
\
<details>/'
  assert_problem ':10: 折りたたみの外に書いてよい見出しは「ゴール」と「優先度」だけ'
}

test_reports_priority_before_fold() {
  body
  replace '/^## 優先度/,$d'
  replace 's/^<details>$/## 優先度\
スコア 1.0\
\
<details>/'
  assert_problem ': 「優先度」は折りたたみの後に書く'
}

test_reports_missing_blank_line_after_fold() {
  body
  replace '/^<\/details>/{n;d;}'
  assert_problem ': </details> の次に空行が無い (次の Markdown が表示されない)'
}

test_reports_extra_fold_in_goal() {
  body '<details>
<summary>補足</summary>

長い背景

</details>
'
  run "$T/issue.md"
  assert_eq 1 "$(printf '%s\n' "$OUT" | grep -c '折りたたみは 1 つだけにする')"
}

test_follows_fence_marker_and_length() {
  body
  replace 's/^なし$/````\
```\
~~~\
## 設計\
<\/details>\
````/'
  run "$T/issue.md"
  assert_eq "" "$OUT"
  body
  replace 's/^なし$/~~~\
## 設計\
~~~/'
  run "$T/issue.md"
  assert_eq "" "$OUT"
}

test_ignores_headings_in_code_block() {
  body
  replace 's/^なし$/```\
## 設計\
<\/details>\
```/'
  run "$T/issue.md"
  assert_eq "" "$OUT"
}

test_checks_every_file() {
  body '`a` を書き出す。'
  cp "$T/issue.md" "$T/other.md"
  run "$T/issue.md" "$T/other.md"
  assert_eq "$T/issue.md:2: 実装の語 (バッククォート) がある
$T/other.md:2: 実装の語 (バッククォート) がある" "$OUT"
}

test_reports_usage_errors() {
  run
  assert_eq 2 "$CODE"
  run "$T/none.md"
  assert_eq 2 "$CODE"
}

run_tests
