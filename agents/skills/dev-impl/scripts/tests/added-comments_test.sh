#!/bin/sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../added-comments.sh"
# shellcheck source=../../../dev-spec/scripts/tests/assert.sh
. "$HERE/../../../dev-spec/scripts/tests/assert.sh"

setup() {
  R="$T/repo"
  git init -q "$R"
  git -C "$R" config user.email t@example.com
  git -C "$R" config user.name t
  git -C "$R" config commit.gpgsign false
}

commit() {
  git -C "$R" add -A
  git -C "$R" commit -q -m c
  git -C "$R" rev-parse HEAD
}

run() { sh "$SCRIPT" "$R" "$1" >"$T/out" 2>"$T/err"; CODE=$?; }

test_added_line_and_trailing_comments() {
  setup
  printf 'const a = 1; // old\n' >"$R/a.ts"
  B=$(commit)
  printf 'const a = 1; // old\n// new line\nconst b = 2; // tail\nconst u = "https://example.com";\n' >"$R/a.ts"
  run "$B"
  assert_eq 0 "$CODE"
  printf 'a.ts:2\t// new line\na.ts:3\tconst b = 2; // tail\n' >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

test_block_comment_body_lines() {
  setup
  : >"$R/a.ts"
  B=$(commit)
  printf '/**\n * body\n plain body\n */\nconst a = 2 * 3;\n/* one */ f();\n' >"$R/a.ts"
  run "$B"
  printf 'a.ts:1\t/**\na.ts:2\t * body\na.ts:3\t plain body\na.ts:4\t */\na.ts:6\t/* one */ f();\n' >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

test_line_added_inside_existing_block() {
  setup
  printf '/*\n a\n */\nf();\n' >"$R/a.ts"
  B=$(commit)
  printf '/*\n a\n b\n */\nf();\n' >"$R/a.ts"
  run "$B"
  printf 'a.ts:3\t b\n' >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

test_jsx_comment() {
  setup
  : >"$R/a.tsx"
  B=$(commit)
  printf '<p>\n  {/* note */}\n</p>\n' >"$R/a.tsx"
  run "$B"
  printf 'a.tsx:2\t  {/* note */}\n' >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

# shellcheck disable=SC2016
test_hash_language_skips_shebang_and_strings() {
  setup
  : >"$R/a.sh"
  B=$(commit)
  printf '#!/bin/sh\n# note\necho "#x" ${a#b} # tail\nls\n' >"$R/a.sh"
  run "$B"
  printf 'a.sh:2\t# note\na.sh:3\techo "#x" ${a#b} # tail\n' >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

test_sql_and_html() {
  setup
  : >"$R/a.sql"
  : >"$R/b.html"
  B=$(commit)
  printf -- '-- note\nselect 1;\n' >"$R/a.sql"
  printf '<!-- note -->\n<p>a</p>\n' >"$R/b.html"
  run "$B"
  printf 'a.sql:1\t-- note\nb.html:1\t<!-- note -->\n' >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

test_untracked_files() {
  setup
  : >"$R/a.ts"
  B=$(commit)
  mkdir -p "$R/src dir"
  printf 'f();\n// new\n' >"$R/src dir/n.ts"
  run "$B"
  printf 'src dir/n.ts:2\t// new\n' >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

test_committed_changes() {
  setup
  : >"$R/a.ts"
  B=$(commit)
  printf '// c\n' >"$R/a.ts"
  commit >/dev/null
  run "$B"
  printf 'a.ts:1\t// c\n' >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

test_ignores_docs_and_unknown_extensions() {
  setup
  : >"$R/a.md"
  B=$(commit)
  printf '# heading\n' >"$R/a.md"
  printf '# x\n' >"$R/a.unknown"
  mkdir -p "$R/docs/design"
  printf '<!-- x -->\n' >"$R/docs/design/UI_SKETCH.html"
  run "$B"
  assert_eq 0 "$CODE"
  : >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

# shellcheck disable=SC2016
test_unclosed_quotes_do_not_hide_later_comments() {
  setup
  : >"$R/a.tsx"
  : >"$R/b.go"
  : >"$R/c.yml"
  B=$(commit)
  printf 'const re = /[`"]/; // one\nf();\n// two\n<p>Don'"'"'t {/* three */}</p>\nconst s = `\n  a\n`; // four\n' >"$R/a.tsx"
  printf 'strings.Split(s, `\\`)\n// five\n' >"$R/b.go"
  printf 'name: Don'"'"'t run # six\n' >"$R/c.yml"
  run "$B"
  {
    printf 'a.tsx:1\tconst re = /[`"]/; // one\n'
    printf 'a.tsx:3\t// two\n'
    printf 'a.tsx:4\t<p>Don'"'"'t {/* three */}</p>\n'
    printf 'a.tsx:7\t`; // four\n'
    printf 'b.go:2\t// five\n'
    printf 'c.yml:1\tname: Don'"'"'t run # six\n'
  } >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

test_regex_and_url_are_not_comments() {
  setup
  : >"$R/a.ts"
  B=$(commit)
  printf 'const a = s.replace(/[/*]+/g, "");\nconst b = /^https?:\\/\\//.test(s);\nreturn /[//]/;\nconst c = x / 2 / y;\n<p>https://example.com</p>\n' >"$R/a.ts"
  run "$B"
  : >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

test_sql_block_and_backslash_string() {
  setup
  : >"$R/a.sql"
  B=$(commit)
  printf "/* one\n two */\nselect 'C:\\\\'; -- three\n" >"$R/a.sql"
  run "$B"
  printf "a.sql:1\t/* one\na.sql:2\t two */\na.sql:3\tselect 'C:\\\\'; -- three\n" >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

test_rust_nested_block() {
  setup
  : >"$R/a.rs"
  B=$(commit)
  printf '/* a /* b */\n c\n*/\nlet s: &'"'"'a str = x; // d\n' >"$R/a.rs"
  run "$B"
  printf 'a.rs:1\t/* a /* b */\na.rs:2\t c\na.rs:3\t*/\na.rs:4\tlet s: &'"'"'a str = x; // d\n' >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

test_python_docstring_and_vue_script() {
  setup
  : >"$R/a.py"
  : >"$R/b.vue"
  B=$(commit)
  printf 'def f():\n    """One.\n\n    two\n    """\n    return 1\n' >"$R/a.py"
  printf '<script>\n// one\n</script>\n' >"$R/b.vue"
  run "$B"
  printf 'a.py:2\t    """One.\na.py:3\t\na.py:4\t    two\na.py:5\t    """\nb.vue:2\t// one\n' >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

test_renamed_file_reports_only_changed_lines() {
  setup
  i=0
  while [ "$i" -lt 30 ]; do printf 'f%d();\n// keep %d\n' "$i" "$i"; i=$((i + 1)); done >"$R/a.ts"
  B=$(commit)
  git -C "$R" mv a.ts b.ts
  printf '// added\n' >>"$R/b.ts"
  run "$B"
  printf 'b.ts:61\t// added\n' >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

test_added_line_that_looks_like_a_diff_header() {
  setup
  : >"$R/a.ts"
  B=$(commit)
  printf '++ b/zzz.ts\n// one\n' >"$R/a.ts"
  run "$B"
  printf 'a.ts:2\t// one\n' >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

test_fails_when_diff_unavailable() {
  setup
  : >"$R/a.ts"
  commit >/dev/null
  run no-such-commit
  assert_eq 2 "$CODE"
}

test_fails_without_args() {
  setup
  sh "$SCRIPT" "$R" >"$T/out" 2>"$T/err"
  assert_eq 2 "$?"
}

run_tests
