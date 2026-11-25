# dev-spec のスクリプトの共通部品。各スクリプトから . で読み込む。
# POSIX の sh で書く (macOS の sh と Ubuntu の dash で動かすため。bash だけの書き方を使わない)。

# 文字列はバイト単位で比べる。macOS の awk は == をロケールの照合順で比べ、en_US.UTF-8 では
# 「登録をする」と「登録する」を等しいと判定して、別のタイトルの issue に一致させてしまう
LC_ALL=C
export LC_ALL

# 終了コードと、標準エラーに出す 1 行のメッセージを受け取って止まる
die() {
  die_code=$1
  shift
  printf '%s\n' "$*" >&2
  exit "$die_code"
}

# ドラフトの子 (issue-<連番>.md) の依存を、deps.awk の入力の形 (連番<TAB>target<TAB><TAB>依存先の連番) で $2 に書く。
# 依存先は「Depends on issue-<連番>」の行だけを数える。「Depends on #<番号>」(作成済みの issue) は数えない。
# 「Depends on」で始まるのにどちらの形でもない行 (1 行に複数並べた行など) があれば、行を挙げて 4 を返す。
draft_graph() {
  graph_dir=$1
  graph_out=$2
  : >"$graph_out"
  for graph_file in "$graph_dir"/issue-*.md; do
    [ -f "$graph_file" ] || continue
    graph_name=$(basename "$graph_file")
    graph_num=${graph_name#issue-}
    graph_num=${graph_num%.md}
    case $graph_num in
      '' | *[!0-9]*)
        printf '%s: ファイル名の連番が数でない\n' "$graph_name" >&2
        return 4
        ;;
    esac
    awk -v n="$graph_num" -v name="$graph_name" '
      /^Depends on/ {
        if ($0 ~ /^Depends on issue-[0-9]+[ \t]*$/) {
          d = $0
          sub(/^Depends on issue-/, "", d)
          sub(/[ \t]*$/, "", d)
          deps = deps (deps == "" ? "" : ",") d
        } else if ($0 !~ /^Depends on #[0-9]+[ \t]*$/) {
          printf "%s: 依存の行の形が違う (1 行に 1 件、Depends on issue-<連番> か Depends on #<番号>): %s\n", name, $0 | "cat 1>&2"
          bad = 1
        }
      }
      END {
        if (bad) exit 4
        printf "%s\ttarget\t\t%s\n", n, deps
      }
    ' "$graph_file" >>"$graph_out" || return 4
  done
  return 0
}

# deps.awk の levels の出力のうち、unknown と cycle をメッセージにして標準エラーに出す
explain_graph_error() {
  awk -F '\t' '
    $1 == "unknown" { printf "issue-%s.md の依存先 issue-%s.md が無い\n", $2, $3 }
    $1 == "cycle" { c = c (c == "" ? "" : " ") "issue-" $2 ".md" }
    END { if (c != "") printf "依存が循環している: %s\n", c }
  ' "$1" >&2
}

# 人が読む文章の長さと語を検査し、問題を 1 件につき 1 行で出す。リンクの先は長さに数えない。
# 使い方: check_text <ファイル> <節の見出し。空ならファイル全体> <行数の上限> <バイト数の上限> <1 行のバイト数の上限>
check_text() {
  awk -v file="$1" -v section="$2" -v max_rows="$3" -v max_bytes="$4" -v max_line="$5" '
    { sub(/[ \t\r]+$/, "") }
    /<!--[ \t]*変更履歴/ { printf "%s:%d: 変更履歴のコメントがある\n", file, NR; next }
    /^[ \t]*(```|~~~)/ {
      if (!fence && $0 !~ /^[ \t]*```mermaid$/ && (section == "" || in_section))
        printf "%s:%d: mermaid 以外のコードブロックがある\n", file, NR
      fence = !fence
      fence_row = 1
    }
    !fence && !fence_row && /^## / {
      in_section = ($0 == "## " section)
      if (section != "") next
    }
    (section == "" || in_section) && $0 != "" {
      shown = $0
      gsub(/\]\([^)]*\)/, "]", shown)
      rows++
      bytes += length(shown)
      if (length(shown) > max_line)
        printf "%s:%d: 1 行が長い (%d B / 上限 %d B)\n", file, NR, length(shown), max_line
      if (!fence && !fence_row && index($0, "`"))
        printf "%s:%d: 実装の語 (バッククォート) がある\n", file, NR
    }
    { fence_row = 0 }
    END {
      label = (section == "") ? "" : "「" section "」が"
      if (section != "" && rows == 0)
        printf "%s: 「%s」節が無いか、空である\n", file, section
      if (rows > max_rows)
        printf "%s: %s長い (%d 行 / 上限 %d 行)\n", file, label, rows, max_rows
      if (bytes > max_bytes)
        printf "%s: %s長い (%d B / 上限 %d B)\n", file, label, bytes, max_bytes
    }
  ' "$1" || printf '%s: 読めない\n' "$1"
}
