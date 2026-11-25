#!/bin/sh
# 使い方: sh added-comments.sh <リポジトリ> <基準のコミット>
#
# 基準からの差分 (コミット済み・未コミット・まだ git に足していないファイル) で足した行のうち、
# コメントを含む行を "<パス>:<行番号><TAB><行>" で標準出力に出す。
# 取り損ねよりも拾いすぎに倒す。複数行の文字列の中の // や # は、コメントでなくても出る。
# 終了コード: 0 出力の有無を問わず調べ終えた / 2 使い方の誤りか、差分を取れない
set -u

if [ $# -ne 2 ]; then
  echo "usage: added-comments.sh <repo_dir> <base_sha>" >&2
  exit 2
fi
cd "$1" || exit 2
cd "$(git rev-parse --show-toplevel)" || exit 2
BASE=$(git rev-parse --verify --quiet "$2^{commit}") || {
  echo "added-comments.sh: $2 をコミットとして読めない" >&2
  exit 2
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/added-comments.XXXXXX") || exit 2
trap 'rm -rf "${WORK:?}"' EXIT
trap 'exit 2' HUP INT TERM

git -c core.quotePath=false diff -U0 -M --diff-filter=AMR --no-color --no-ext-diff \
  --src-prefix=a/ --dst-prefix=b/ "$BASE" >"$WORK/diff" || exit 2
git -c core.quotePath=false ls-files --others --exclude-standard >"$WORK/untracked" || exit 2

# 出力: <パス><TAB><追加が始まる行><TAB><行数>
awk '
  function count_of(range,   part) { return split(range, part, ",") == 2 ? part[2] + 0 : 1 }
  skip > 0 && !/^\\/ { skip--; next }
  /^\+\+\+ b\// { path = substr($0, 7); sub(/\t$/, "", path); next }
  /^@@ / {
    split($0, field, " ")
    skip = count_of(substr(field[2], 2)) + count_of(substr(field[3], 2))
    start = substr(field[3], 2); sub(/,.*/, "", start)
    if (count_of(substr(field[3], 2)) > 0) printf "%s\t%d\t%d\n", path, start, count_of(substr(field[3], 2))
  }
' "$WORK/diff" >"$WORK/ranges" || exit 2
cut -f 1 "$WORK/ranges" | uniq >"$WORK/changed"

style_of() {
  case $1 in
    docs/* | */docs/*) echo none ;;
    *.ts | *.tsx | *.mts | *.cts | *.js | *.jsx | *.mjs | *.cjs) echo js ;;
    *.rs) echo rust ;;
    *.go) echo go ;;
    *.java | *.kt | *.swift | *.c | *.h | *.cc | *.cpp | *.hpp | *.cs | *.scss | *.proto | *.jsonc) echo c ;;
    *.css) echo css ;;
    *.py) echo python ;;
    *.sh | *.bash | *.zsh | *.rb | *.yml | *.yaml | *.toml | *.tf | *.ex | *.exs) echo hash ;;
    Dockerfile | */Dockerfile | Makefile | */Makefile | *.mk) echo hash ;;
    *.nix) echo nix ;;
    *.sql) echo sql ;;
    *.lua) echo lua ;;
    *.vue | *.svelte) echo component ;;
    *.html | *.xml) echo html ;;
    *) echo none ;;
  esac
}

scan() {
  FILE=$1 STYLE=$2 RANGES=$3 awk '
    function string_end(text, from, q,   k, c) {
      for (k = from + 1; k <= length(text); k++) {
        c = substr(text, k, 1)
        if (c == "\\" && style != "sql" && !(style == "go" && q == "`")) { k++; continue }
        if (c == q) return k
      }
      return 0
    }
    function regex_end(text, from,   k, c, in_class, before) {
      before = substr(text, 1, from - 1); sub(/[ \t]+$/, "", before)
      if (before != "" && before !~ /[(,=:\[!&|?{};>]$/ && before !~ /(^|[^A-Za-z0-9_$])return$/) return 0
      for (k = from + 1; k <= length(text); k++) {
        c = substr(text, k, 1)
        if (c == "\\") { k++; continue }
        if (c == "[") in_class = 1
        else if (c == "]") in_class = 0
        else if (c == "/" && !in_class) return k
      }
      return 0
    }
    BEGIN {
      file = ENVIRON["FILE"]; style = ENVIRON["STYLE"]
      if (ENVIRON["RANGES"] == "") all = 1
      else while ((getline row < ENVIRON["RANGES"]) > 0) {
        split(row, col, "\t")
        if (col[1] == file) for (i = 0; i < col[3]; i++) added[col[2] + i] = 1
      }
      slash = (style == "js" || style == "rust" || style == "go" || style == "c")
      open_mark = (slash || style == "css" || style == "nix" || style == "sql") ? "/*" : (style == "html" || style == "component") ? "<!--" : ""
      close_mark = (open_mark == "<!--") ? "-->" : "*/"
      hash = (style == "hash" || style == "nix" || style == "python")
      dash = (style == "sql" || style == "lua")
      docstring = "^[ \t]*[rRuU]?(\"\"\"|\047\047\047)"
    }
    {
      line = $0; len = length(line); found = (depth > 0)
      if (in_doc || (style == "python" && line ~ docstring)) {
        rest = line
        if (!in_doc) { sub(docstring, "", rest); in_doc = 1 }
        if (rest ~ /"""|\047\047\047/) in_doc = 0
        if (all || (NR in added)) printf "%s:%d\t%s\n", file, NR, line
        next
      }
      if (style == "component" && line ~ /^[ \t]*(\/\/|\/\*|\*)/) found = 1
      for (i = 1; i <= len; i++) {
        if (depth > 0) {
          if (style == "rust" && substr(line, i, 2) == "/*") { depth++; i++; continue }
          if (substr(line, i, length(close_mark)) == close_mark) { depth--; i += length(close_mark) - 1 }
          continue
        }
        ch = substr(line, i, 1)
        if (ch == "\\") { i++; continue }
        if (open_mark != "" && substr(line, i, length(open_mark)) == open_mark) {
          found = 1; depth = 1; i += length(open_mark) - 1; continue
        }
        if (slash && substr(line, i, 2) == "//" && substr(line, i - 1, 1) != ":") { found = 1; break }
        if (dash && substr(line, i, 2) == "--") { found = 1; break }
        if (hash && ch == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t]/) && !(NR == 1 && i == 1 && substr(line, 2, 1) == "!")) { found = 1; break }
        if (open_mark == "<!--") continue
        end = 0
        if (ch == "/" && style == "js") end = regex_end(line, i)
        else if (ch == "\047" && style == "rust") {
          if (match(substr(line, i), /^\047(\\.|[^\047\\])\047/)) end = i + RLENGTH - 1
        } else if (ch == "\"" || ch == "\047" || ch == "`") end = string_end(line, i, ch)
        if (end > 0) i = end
      }
      if (found && (all || (NR in added))) printf "%s:%d\t%s\n", file, NR, line
    }
  ' "./$1"
}

while IFS= read -r f; do
  s=$(style_of "$f")
  [ "$s" = none ] && continue
  scan "$f" "$s" "$WORK/ranges" || exit 2
done <"$WORK/changed"

while IFS= read -r f; do
  s=$(style_of "$f")
  [ "$s" = none ] && continue
  scan "$f" "$s" "" || exit 2
done <"$WORK/untracked"
