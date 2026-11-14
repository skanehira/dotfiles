# テストの共通部品。テストファイルから . で読み込む。
# test_ で始まる関数を順に、空の一時ディレクトリ $T で実行する。

FAILED=0
PASSED=0

assert_eq() {
  if [ "$1" != "$2" ]; then
    printf '    期待: %s\n    実際: %s\n' "$1" "$2"
    CASE_FAILED=1
  fi
}

# バイト単位で比べる (コマンド置換は末尾の改行を捨てるので使わない)
assert_file_eq() {
  if ! cmp -s "$1" "$2"; then
    printf '    ファイルが違う: 期待 (-) / 実際 (+)\n'
    diff "$1" "$2" | sed 's/^/    /'
    CASE_FAILED=1
  fi
}

assert_file_contains_line() {
  if ! grep -Fxq -- "$2" "$1"; then
    printf '    行が無い: %s\n' "$2"
    sed 's/^/    | /' "$1"
    CASE_FAILED=1
  fi
}

assert_file_lacks_line() {
  if grep -Fxq -- "$2" "$1"; then
    printf '    あってはならない行がある: %s\n' "$2"
    CASE_FAILED=1
  fi
}

run_tests() {
  # テストの関数名は英数字と _ だけなので、単語に分けて回してよい
  # shellcheck disable=SC2013
  for name in $(grep -E '^test_[a-z0-9_]+\(\)' "$0" | sed 's/().*//'); do
    T=$(mktemp -d "${TMPDIR:-/tmp}/deps-test.XXXXXX")
    CASE_FAILED=0
    "$name"
    if [ "$CASE_FAILED" -eq 0 ]; then
      PASSED=$((PASSED + 1))
    else
      FAILED=$((FAILED + 1))
      printf 'FAIL %s\n' "$name"
    fi
    rm -rf "${T:?}"
  done
  printf '%s: %d passed, %d failed\n' "$(basename "$0")" "$PASSED" "$FAILED"
  [ "$FAILED" -eq 0 ]
}
