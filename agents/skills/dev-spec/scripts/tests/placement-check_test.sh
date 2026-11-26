#!/bin/sh
# shellcheck disable=SC2016  # バッククォートは文書に書く文字そのもの
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../placement-check.sh"
# shellcheck source=assert.sh
. "$HERE/assert.sh"

feature() {
  feature_name=$1
  shift
  mkdir -p "$T/docs/design/features"
  {
    printf '# %s\n\n## 実装の配置\n\n' "$feature_name"
    printf '| 処理 | 層 | 実装先ファイル | 作る / 足す |\n| --- | --- | --- | --- |\n'
    for row in "$@"; do
      printf '%s\n' "$row"
    done
    printf '\n## エッジケースの決定\n\n| a | b |\n| --- | --- |\n| `src/x.ts` | 作る |\n'
  } >"$T/docs/design/features/$feature_name.md"
}

run() {
  CODE=0
  OUT=$(cd "$T" && ${SH:-sh} "$SCRIPT" "$@" 2>&1) || CODE=$?
}

test_passes_when_each_file_has_one_creator() {
  feature runtime '| git の実行口 | インフラ | `src/git-cli.ts` | 作る |'
  feature worktree '| worktree の操作 | インフラ | `src/git-cli.ts` | 足す |'
  run docs/design
  assert_eq "" "$OUT"
  assert_eq 0 "$CODE"
}

test_reports_file_created_by_two_features() {
  feature design-review '| git の実行口 | インフラ | `src/git-cli.ts` | 作る |'
  feature project-settings '| git の実行口 | インフラ | `src/git-cli.ts` | 作る |'
  run docs/design
  assert_eq 'src/git-cli.ts: 作る機能設計書が 2 本ある (docs/design/features/design-review.md, docs/design/features/project-settings.md)' "$OUT"
  assert_eq 1 "$CODE"
}

test_reports_file_only_added() {
  feature pr-review '| 差分の取得 | インフラ | `src/git-cli.ts` | 足す |'
  run docs/design
  assert_eq 'src/git-cli.ts: 作る機能設計書が無い (足す: docs/design/features/pr-review.md)' "$OUT"
  assert_eq 1 "$CODE"
}

test_allows_adding_to_file_in_repository() {
  mkdir -p "$T/src"
  : >"$T/src/git-cli.ts"
  feature pr-review '| 差分の取得 | インフラ | `src/git-cli.ts` | 足す |'
  run docs/design
  assert_eq "" "$OUT"
  assert_eq 0 "$CODE"
}

test_checks_every_path_in_a_cell() {
  feature runtime '| 実行口 | インフラ | `src/git-cli.ts`、`src/gh-cli.ts` | 作る |'
  feature issue '| issue の取得 | インフラ | `src/gh-cli.ts` | 作る |'
  run docs/design
  assert_eq 'src/gh-cli.ts: 作る機能設計書が 2 本ある (docs/design/features/issue.md, docs/design/features/runtime.md)' "$OUT"
  assert_eq 1 "$CODE"
}

test_counts_one_feature_once() {
  feature runtime '| 実行口 | インフラ | `src/git-cli.ts` | 作る |' '| 偽物 | インフラ | `src/git-cli.ts` | 作る |'
  run docs/design
  assert_eq "" "$OUT"
  assert_eq 0 "$CODE"
}

test_reports_missing_column() {
  mkdir -p "$T/docs/design/features"
  printf '# old\n\n## 実装の配置\n\n| 処理 | 層 | 実装先ファイル |\n| --- | --- | --- |\n| 保存 | ドメイン | `src/save.ts` |\n' \
    >"$T/docs/design/features/old.md"
  run docs/design
  assert_eq 'docs/design/features/old.md: 「実装の配置」の表に「作る / 足す」の列が無い' "$OUT"
  assert_eq 1 "$CODE"
}

test_reports_unknown_value() {
  feature runtime '| 実行口 | インフラ | `src/git-cli.ts` | 新規 |'
  run docs/design
  assert_eq 'docs/design/features/runtime.md:7: 「作る / 足す」の値が「作る」「足す」のどちらでもない (新規)' "$OUT"
  assert_eq 1 "$CODE"
}

test_reports_token_that_is_not_a_path() {
  mkdir -p "$T/src"
  : >"$T/src/comment.lua"
  feature review '| 削除 | ドメイン | `src/comment.lua` の `remove_all` | 足す |'
  run docs/design
  assert_eq 'docs/design/features/review.md:7: 「実装先ファイル」が最上位からのファイルのパスでない (remove_all)' "$OUT"
  assert_eq 1 "$CODE"
}

test_reports_file_name_without_directory() {
  feature ready '| 画面 | UI | `ReadyScreen.tsx` | 作る |'
  run docs/design
  assert_eq 'docs/design/features/ready.md:7: 「実装先ファイル」が最上位からのファイルのパスでない (ReadyScreen.tsx)' "$OUT"
  assert_eq 1 "$CODE"
}

test_accepts_top_level_files() {
  : >"$T/package.json"
  feature build '| 設定 | インフラ | `./vite.config.ts` | 作る |' '| 依存 | インフラ | `package.json` | 足す |'
  feature lint '| 設定 | インフラ | `vite.config.ts` | 足す |'
  run docs/design
  assert_eq 'docs/design/features/lint.md:7: 「実装先ファイル」が最上位からのファイルのパスでない (vite.config.ts)' "$OUT"
  assert_eq 1 "$CODE"
}

test_treats_dot_slash_as_same_file() {
  feature build '| 設定 | インフラ | `./vite.config.ts` | 作る |'
  feature lint '| 設定 | インフラ | `./vite.config.ts` | 作る |'
  run docs/design
  assert_eq 'vite.config.ts: 作る機能設計書が 2 本ある (docs/design/features/build.md, docs/design/features/lint.md)' "$OUT"
  assert_eq 1 "$CODE"
}

test_reports_directory() {
  feature cli '| 入口 | UI | `src/cli/` | 作る |'
  run docs/design
  assert_eq 'docs/design/features/cli.md:7: 「実装先ファイル」にディレクトリを書いている (src/cli/)' "$OUT"
  assert_eq 1 "$CODE"
}

test_reports_cell_without_backquotes() {
  feature save '| 保存 | ドメイン | src/a.ts, src/b.ts | 作る |'
  run docs/design
  assert_eq 'docs/design/features/save.md:7: 「実装先ファイル」のパスをバッククォートで囲んでいない' "$OUT"
  assert_eq 1 "$CODE"
}

test_ignores_other_tables_in_section() {
  feature recap '| 要約 | ドメイン | `src/recap.ts` | 作る |' '' '| 列 | 書き手 |' '| --- | --- |' '| summary | ランナー |'
  run docs/design
  assert_eq "" "$OUT"
  assert_eq 0 "$CODE"
}

test_reads_header_of_each_table() {
  feature recap '| 要約 | ドメイン | `src/recap.ts` | 作る |' '' '| 処理 | 実装先ファイル |' '| --- | --- |' '| 配信 | `src/push.ts` |'
  run docs/design
  assert_eq 'docs/design/features/recap.md: 「実装の配置」の表に「作る / 足す」の列が無い' "$OUT"
  assert_eq 1 "$CODE"
}

test_reports_first_table_without_file_column() {
  mkdir -p "$T/docs/design/features"
  printf '# old\n\n## 実装の配置\n\n| 処理 | 実装先 | 作る / 足す |\n| --- | --- | --- |\n| 保存 | `src/save.ts` | 作る |\n' \
    >"$T/docs/design/features/old.md"
  run docs/design
  assert_eq 'docs/design/features/old.md: 「実装の配置」の表に「実装先ファイル」の列が無い' "$OUT"
  assert_eq 1 "$CODE"
}

test_fails_without_directory() {
  run docs/design
  assert_eq 2 "$CODE"
}

run_tests
