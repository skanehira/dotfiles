#!/bin/sh
# 使い方: sh cross-product.sh <リポジトリ> <基準のコミット>
#
# 基準からの差分 (コミット済み・未コミット・まだ git に足していないファイル) が足したか変えたテストのうち、
# 2 つ以上の入力の一覧を掛け合わせてテストを生成するものを "<パス>:<行番号><TAB><種類>" で標準出力に出す。
# 種類と、検出する書き方 (内側の一覧が外側の値から取られる階層の表は、掛け合わせに数えない):
#   each-generated       vitest・jest の .each / .for に、互いに独立な一覧を掛け合わせた表を渡す。表は、flatMap・map・
#                        Array.from を入れ子にした式か、その式を入れた変数か、入れ子のループで push した変数である
#   describe-each-nested describe.each / describe.for の中で .each / .for を使う
#   nested-loop          入れ子のループ (JS・TS は for・forEach・.each・.for、Go は for) の中でテストを呼ぶ。
#                        Go のテストの呼び出しは、第 2 引数が func の .Run( である
#   go-append-table      入れ子の for で表に append し、その表を回すループの中でテストを呼ぶ
#   rstest-values        rstest で #[values] を 2 つ以上使うか、#[case] や #[apply] と #[values] を併用する
# 見る範囲: JS・TS は *.test.* / *.spec.* / __tests__ の下、Go は *_test.go、Rust は *.rs。
# 生成の始まりの行か、その直前 3 行に "cross-product: <パス>:<行番号>" を含む行があるものは出さない。表を変数に入れた
# ときは、変数の定義の直前 3 行も見る。出さなかった箇所は "<パス>:<行番号><TAB>exempt<TAB><パス>:<行番号>" で標準エラーに出す。
# 終了コード: 0 見つからない / 1 見つかった / 2 使い方の誤りか、差分を取れない
set -u

if [ $# -ne 2 ]; then
  echo "usage: cross-product.sh <repo_dir> <base_sha>" >&2
  exit 2
fi
cd "$1" || exit 2
cd "$(git rev-parse --show-toplevel)" || exit 2
BASE=$(git rev-parse --verify --quiet "$2^{commit}") || {
  echo "cross-product.sh: $2 をコミットとして読めない" >&2
  exit 2
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/cross-product.XXXXXX") || exit 2
trap 'rm -rf "${WORK:?}"' EXIT
trap 'exit 2' HUP INT TERM

git -c core.quotePath=false diff -U0 -M --diff-filter=AMR --no-color --no-ext-diff \
  --src-prefix=a/ --dst-prefix=b/ "$BASE" >"$WORK/diff" || exit 2
git -c core.quotePath=false ls-files --others --exclude-standard >"$WORK/untracked" || exit 2

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

lang_of() {
  case $1 in
    *_test.go) echo go ;;
    *.rs) echo rust ;;
    *.test.* | *.spec.* | __tests__/* | */__tests__/*)
      case $1 in
        *.ts | *.tsx | *.mts | *.cts | *.js | *.jsx | *.mjs | *.cjs) echo js ;;
        *) echo none ;;
      esac
      ;;
    *) echo none ;;
  esac
}

scan() {
  FILE=$1 LANG_KIND=$2 RANGES=$3 awk '
    function sanitize(line,   out, n, i, c) {
      out = ""; n = length(line)
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (st == "bc") { if (substr(line, i, 2) == "*/") { st = ""; i++ }; continue }
        if (st == "dq") { if (c == "\\") { i++; continue }; if (c == "\"") { st = ""; out = out c }; continue }
        if (st == "sq") { if (c == "\\") { i++; continue }; if (c == "\047") { st = ""; out = out c }; continue }
        if (st == "bt") { if (c == "\\" && lang != "go") { i++; continue }; if (c == "`") { st = ""; out = out c }; continue }
        if (substr(line, i, 2) == "//") break
        if (substr(line, i, 2) == "/*") { st = "bc"; i++; continue }
        if (c == "\"") { st = "dq"; out = out c; continue }
        if (c == "`" && lang != "rust") { st = "bt"; out = out c; continue }
        if (c == "\047") {
          if (lang == "js") { st = "sq"; out = out c; continue }
          if (match(substr(line, i), /^\047(\\.|[^\047\\])\047/)) { out = out "\047\047"; i += RLENGTH - 1; continue }
        }
        out = out c
      }
      if (st == "sq" || (st == "dq" && lang != "rust")) st = ""
      return out
    }
    function close_of(l, col, op, cl,   d, i, j, t, c) {
      d = 0
      for (i = l; i <= N; i++) {
        t = s[i]
        for (j = (i == l) ? col : 1; j <= length(t); j++) {
          c = substr(t, j, 1)
          if (c == op) d++
          else if (c == cl) { d--; if (d == 0) { ECOL = j; return i } }
        }
      }
      ECOL = length(s[N]); return N
    }
    function first_after(l, col, ch, any,   i, j, t, c) {
      for (i = l; i <= N; i++) {
        t = s[i]
        for (j = (i == l) ? col : 1; j <= length(t); j++) {
          c = substr(t, j, 1)
          if (c == ch) { PCOL = j; return i }
          if (!any && c !~ /[ \t]/) return 0
        }
      }
      return 0
    }
    function strip_else(t) {
      if (match(t, /^[ \t\n]*else/) && substr(t, RSTART + RLENGTH, 1) !~ /[A-Za-z0-9_$]/) { STRIPPED = substr(t, RSTART + RLENGTH); return 1 }
      return 0
    }
    function walk_headers(t,   o, e) {
      HN = 0; HB = 0
      while (1) {
        if (strip_else(t)) { t = STRIPPED; HN++; HB--; continue }
        if (!match(t, /^[ \t\n]*(for|if|while)[ \t]*\(/)) break
        if (substr(t, RSTART, RLENGTH) ~ /if[ \t]*\($/) HB++
        o = RSTART + RLENGTH - 1; e = text_close(t, o)
        t = substr(t, e + 1); HN++
      }
      return t
    }
    function header_only(t) { t = walk_headers(t); return HN > 0 && t ~ /^[ \t\n]*$/ }
    function else_follows(l, col,   t, i) {
      t = substr(s[l], col + 1)
      for (i = l + 1; t ~ /^[ \t]*$/ && i <= N; i++) t = s[i]
      return strip_else(t)
    }
    function stmt_end(l, col,   d, i, j, t, c, seen, nx, acc, pend) {
      d = 0; seen = 0; acc = ""; pend = 0
      for (i = l; i <= N; i++) {
        t = s[i]
        for (j = (i == l) ? col : 1; j <= length(t); j++) {
          c = substr(t, j, 1); acc = acc c
          if (c ~ /[ \t]/) continue
          seen = 1
          if (c == "(" || c == "[" || c == "{") d++
          else if (c == ")" || c == "]" || c == "}") { d--; if (d < 0) { ECOL = j - 1; return i } }
          else if (c == ";" && d == 0) {
            walk_headers(acc)
            if (!else_follows(i, j) || pend + HB <= 0) { ECOL = j; return i }
            pend += HB; acc = ""
          }
        }
        acc = acc "\n"
        if (seen && d == 0 && !header_only(acc)) {
          walk_headers(acc)
          if (else_follows(i, length(t)) && pend + HB > 0) { pend += HB; acc = ""; continue }
          nx = (i < N) ? s[i + 1] : ""
          if (nx !~ /^[ \t]*[.?:+*\/&|,)-]/) { ECOL = length(t); return i }
        }
      }
      ECOL = length(s[N]); return N
    }
    function text_between(l1, c1, l2, c2,   t, i) {
      if (l1 == l2) return substr(s[l1], c1, c2 - c1 + 1)
      t = substr(s[l1], c1)
      for (i = l1 + 1; i < l2; i++) t = t "\n" s[i]
      return t "\n" substr(s[l2], 1, c2)
    }
    function text_close(t, o,   d, j, c) {
      d = 0
      for (j = o; j <= length(t); j++) {
        c = substr(t, j, 1)
        if (c == "(") d++
        else if (c == ")") { d--; if (d == 0) return j }
      }
      return length(t) + 1
    }
    function idents(t,   n, w, k, r) {
      gsub(/[^A-Za-z0-9_$]+/, " ", t); n = split(t, w, " "); r = " "
      for (k = 1; k <= n; k++) if (w[k] !~ /^(const|let|var|of|in|async|function|range|_|[0-9].*)$/) r = r w[k] " "
      return r
    }
    function mentions(t, vars,   n, w, k) {
      n = split(idents(t), w, " ")
      for (k = 1; k <= n; k++) if (index(vars, " " w[k] " ") > 0) return 1
      return 0
    }
    function arrow_params(t, o,   r) {
      r = substr(t, o + 1)
      if (match(r, /^[ \t\n]*(async[ \t\n]+)?(\([^()]*\)|[A-Za-z_$][A-Za-z0-9_$]*)[ \t\n]*=>/)) return idents(substr(r, RSTART, RLENGTH))
      if (match(r, /^[ \t\n]*(async[ \t\n]+)?function[ \t\n]*[A-Za-z0-9_$]*[ \t\n]*\([^()]*\)/)) return idents(substr(r, RSTART, RLENGTH))
      return " "
    }
    function first_params(t,   m) {
      if (match(t, /(\([^()]*\)|[A-Za-z_$][A-Za-z0-9_$]*)[ \t\n]*=>/)) return idents(substr(t, RSTART, RLENGTH))
      if (match(t, /function[ \t\n]*[A-Za-z0-9_$]*[ \t\n]*\([^()]*\)/)) return idents(substr(t, RSTART, RLENGTH))
      return " "
    }
    function receiver_of(t, p,   k, c, d) {
      k = p - 1
      while (k >= 1) {
        c = substr(t, k, 1)
        if (c == ")" || c == "]") {
          d = 0
          for (; k >= 1; k--) {
            c = substr(t, k, 1)
            if (c == ")" || c == "]") d++
            else if (c == "(" || c == "[") { d--; if (d == 0) break }
          }
          k--; continue
        }
        if (c ~ /[A-Za-z0-9_$.?"\047`]/) { k--; continue }
        break
      }
      return substr(t, k + 1, p - k - 1)
    }
    function first_arg(t, o,   d, j, c) {
      d = 0
      for (j = o; j <= length(t); j++) {
        c = substr(t, j, 1)
        if (c == "(" || c == "[" || c == "{") d++
        else if (c == ")" || c == "]" || c == "}") { d--; if (d == 0) break }
        else if (c == "," && d == 1) break
      }
      return substr(t, o + 1, j - o - 1)
    }
    function has_independent_inner(body, vars,   q, p, h, it) {
      q = 0
      while ((p = index(substr(body, q + 1), ".map(")) > 0) { p += q; if (!mentions(receiver_of(body, p), vars)) return 1; q = p }
      q = 0
      while ((p = index(substr(body, q + 1), ".flatMap(")) > 0) { p += q; if (!mentions(receiver_of(body, p), vars)) return 1; q = p }
      q = 0
      while ((p = index(substr(body, q + 1), "Array.from(")) > 0) { p += q + 10; if (!mentions(first_arg(body, p), vars)) return 1; q = p }
      q = 0
      while (match(substr(body, q + 1), /(^|[^A-Za-z0-9_$.])for[ \t]*\(/)) {
        p = q + RSTART + RLENGTH - 1
        h = substr(body, p + 1, text_close(body, p) - p - 1)
        it = match(h, /[ \t](of|in)[ \t]/) ? substr(h, RSTART + RLENGTH) : h
        if (!mentions(it, vars)) return 1
        q = p
      }
      return 0
    }
    function first_comma(t, o,   d, j, c) {
      d = 0
      for (j = o; j <= length(t); j++) {
        c = substr(t, j, 1)
        if (c == "(" || c == "[" || c == "{") d++
        else if (c == ")" || c == "]" || c == "}") { d--; if (d == 0) return 0 }
        else if (c == "," && d == 1) return j
      }
      return 0
    }
    function generated(t,   k, n, pat, q, p, o, e, c) {
      q = 0
      while ((p = index(substr(t, q + 1), "Array.from(")) > 0) {
        p += q; o = p + 10; e = text_close(t, o); c = first_comma(t, o)
        if (c > 0 && has_independent_inner(substr(t, c + 1, e - c - 1), arrow_params(t, c))) return 1
        q = p
      }
      n = split("flatMap(|.map(", pat, "|")
      for (k = 1; k <= n; k++) {
        q = 0
        while ((p = index(substr(t, q + 1), pat[k])) > 0) {
          p += q; o = p + length(pat[k]) - 1; e = text_close(t, o)
          if (has_independent_inner(substr(t, o + 1, e - o - 1), arrow_params(t, o))) return 1
          q = p
        }
      }
      return 0
    }
    function scope_of(l, c,   k, best) {
      best = 0
      for (k = 1; k <= nb; k++)
        if (before(BO[k], BOC[k], l, c) && before(l, c, BC[k], BCC[k]) && (best == 0 || before(BO[best], BOC[best], BO[k], BOC[k]))) best = k
      SCOPE = best
    }
    function in_scope(b, l, c) { return b == 0 || (before(BO[b], BOC[b], l, c) && before(l, c, BC[b], BCC[b])) }
    function add_def(name, first, first_col, last, generated_flag) {
      nd++; DN[nd] = name; DS[nd] = first; DSCOL[nd] = first_col; DE[nd] = last; DG[nd] = generated_flag
      scope_of(first, first_col); DB[nd] = SCOPE
    }
    function uses_generated(t, at, at_col,   n, w, i, k, best) {
      n = split(idents(t), w, " ")
      for (i = 1; i <= n; i++) {
        best = 0
        for (k = 1; k <= nd; k++)
          if (DN[k] == w[i] && before(DS[k], DSCOL[k], at, at_col) && in_scope(DB[k], at, at_col) && (best == 0 || before(DS[best], DSCOL[best], DS[k], DSCOL[k]))) best = k
        if (best > 0 && DG[best]) { GENAT = best; return 1 }
      }
      return 0
    }
    function reason_at(start,   x) {
      for (x = (start > 3 ? start - 3 : 1); x <= start; x++)
        if (match(raw[x], /cross-product:.*[^ \t:]+:[0-9]+/)) {
          REASON = substr(raw[x], RSTART, RLENGTH); sub(/^cross-product:.*[ \t]/, "", REASON); sub(/^cross-product:/, "", REASON)
          match(REASON, /[^ \t:]+:[0-9]+/); REASON = substr(REASON, RSTART, RLENGTH)
          return 1
        }
      return 0
    }
    function report(start, last, kind, xs, xe,   x, touched) {
      if (start in rep || start in exempt) return
      touched = all
      for (x = start; x <= last && !touched; x++) if (x in added) touched = 1
      if (xs > 0) for (x = xs; x <= xe && !touched; x++) if (x in added) touched = 1
      if (!touched) return
      if (reason_at(start) || (xs > 0 && reason_at(xs))) { exempt[start] = REASON; return }
      rep[start] = kind
    }
    function add_loop(l1, c1, l2, c2, vars, iter) { nl++; LS[nl] = l1; LC[nl] = c1; LE[nl] = l2; LEC[nl] = c2; LV[nl] = vars; LI[nl] = iter }
    function add_call(l, c) { nc++; CL[nc] = l; CC[nc] = c }
    function before(l1, c1, l2, c2) { return l1 < l2 || (l1 == l2 && c1 < c2) }
    function inside(a, l, c) { return !before(l, c, LS[a], LC[a]) && !before(LE[a], LEC[a], l, c) }
    function nested(a, b) { return before(LS[a], LC[a], LS[b], LC[b]) && !before(LE[a], LEC[a], LE[b], LEC[b]) && !mentions(LI[b], LV[a]) }
    function scan_js(   i, t, p, off, pos, prefix, col, al, ac, cl, cc, gl, gc, args, name, body, d, j, h, hl, hc, decl, iter, rc, m) {
      for (i = 1; i <= N; i++) {
        t = s[i]
        if (match(t, /^[ \t]*(export[ \t]+)?(const|let|var)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*[ \t]*(:([^=]|=>)*)?=/) && substr(t, RSTART + RLENGTH, 1) != ">") {
          name = substr(t, RSTART, RLENGTH); p = RSTART + RLENGTH
          sub(/^[ \t]*(export[ \t]+)?(const|let|var)[ \t]+/, "", name); sub(/[ \t]*(:.*)?=$/, "", name)
          j = stmt_end(i, p); body = text_between(i, p, j, ECOL)
          defs_at[i] = name; defs_col[i] = match(t, /[^ \t]/) ? RSTART : 1; defs_end[i] = j; defs_gen[i] = generated(body)
        }
        off = 0
        while (match(substr(t, off + 1), /\.(each|for)\(/)) {
          pos = off + RSTART; off = pos + RLENGTH - 1
          prefix = substr(t, 1, pos - 1)
          if (!match(prefix, /(^|[^A-Za-z0-9_$.])(it|test|describe|bench|suite)(\.[A-Za-z]+)*$/)) continue
          col = RSTART + (substr(prefix, RSTART, 1) ~ /[A-Za-z]/ ? 0 : 1)
          al = close_of(i, off, "(", ")"); ac = ECOL
          args = text_between(i, off, al, ac)
          gl = first_after(al, ac + 1, "(", 0)
          if (gl > 0) { gc = PCOL; cl = close_of(gl, gc, "(", ")"); cc = ECOL } else { gl = al; gc = ac; cl = al; cc = ac }
          ne++; EL[ne] = i; ECC[ne] = col; EA[ne] = args; EDESC[ne] = (substr(prefix, col) ~ /^describe/)
          add_loop(i, col, cl, cc, first_params(text_between(gl, gc, cl, cc)), args); EK[ne] = nl
          add_call(i, col)
        }
        off = 0
        while (match(substr(t, off + 1), /(^|[^A-Za-z0-9_$.])for[ \t]*\(/)) {
          pos = off + RSTART + (substr(t, off + RSTART, 1) == "f" ? 0 : 1)
          off = off + RSTART + RLENGTH - 1
          hl = close_of(i, off, "(", ")"); hc = ECOL
          h = text_between(i, off + 1, hl, hc - 1)
          if (match(h, /[ \t](of|in)[ \t]/)) { decl = substr(h, 1, RSTART - 1); iter = substr(h, RSTART + RLENGTH) }
          else { decl = h; sub(/;.*/, "", decl); iter = h }
          cl = first_after(hl, hc + 1, "{", 0)
          if (cl > 0) { cl = close_of(cl, PCOL, "{", "}"); cc = ECOL } else { cl = stmt_end(hl, hc + 1); cc = ECOL }
          add_loop(i, pos, cl, cc, idents(decl), iter)
        }
        off = 0
        while ((p = index(substr(t, off + 1), ".forEach(")) > 0) {
          pos = off + p; off = pos + 8
          rc = receiver_of(t, pos)
          cl = close_of(i, off, "(", ")"); cc = ECOL
          add_loop(i, pos, cl, cc, arrow_params(text_between(i, off, cl, cc), 1), rc)
        }
        off = 0
        while (match(substr(t, off + 1), /(^|[^A-Za-z0-9_$.])(it|test)(\.(only|skip|concurrent))?[ \t]*\(/)) {
          add_call(i, off + RSTART + (substr(t, off + RSTART, 1) ~ /[A-Za-z]/ ? 0 : 1))
          off += RSTART + RLENGTH - 1
        }
        off = 0
        while (match(substr(t, off + 1), /[A-Za-z_$][A-Za-z0-9_$]*\.push\(/)) {
          m = substr(t, off + RSTART, RLENGTH); sub(/\.push\($/, "", m)
          np++; PL[np] = i; PC[np] = off + RSTART; PN[np] = m
          off += RSTART + RLENGTH - 1
        }
      }
      for (i = 1; i <= N; i++) {
        t = s[i]
        for (j = 1; j <= length(t); j++) {
          c = substr(t, j, 1)
          if (c == "{") { sp++; stack[sp] = i; stack_col[sp] = j }
          else if (c == "}" && sp > 0) { nb++; BO[nb] = stack[sp]; BOC[nb] = stack_col[sp]; BC[nb] = i; BCC[nb] = j; sp-- }
        }
      }
      for (i = 1; i <= N; i++) if (i in defs_at) add_def(defs_at[i], i, defs_col[i], defs_end[i], defs_gen[i])
      for (a = 1; a <= nl; a++) for (b = 1; b <= nl; b++) {
        if (a == b || !nested(a, b)) continue
        for (k = 1; k <= np; k++) if (inside(b, PL[k], PC[k]) && !(k in pushed)) { pushed[k] = 1; add_def(PN[k], LS[a], LC[a], LE[a], 1) }
      }
      for (k = 1; k <= ne; k++) {
        if (EDESC[k]) {
          for (x = 1; x <= ne; x++) if (x != k && nested(EK[k], EK[x])) { report(EL[k], LE[EK[k]], "describe-each-nested", 0, 0); break }
        }
        if (generated(EA[k])) report(EL[k], LE[EK[k]], "each-generated", 0, 0)
        else if (uses_generated(EA[k], EL[k], ECC[k])) report(EL[k], LE[EK[k]], "each-generated", DS[GENAT], DE[GENAT])
      }
    }
    function last_arg(t,   d, j, c, last, prev) {
      d = 0; last = 1; prev = 1
      for (j = 1; j <= length(t); j++) {
        c = substr(t, j, 1)
        if (c == "(" || c == "[" || c == "{") d++
        else if (c == ")" || c == "]" || c == "}") d--
        else if (c == "," && d == 1) { prev = last; last = j }
      }
      if (substr(t, last + 1) ~ /^[ \t\n]*\)?[ \t\n]*$/) last = prev
      return substr(t, last + 1)
    }
    function scan_go(   i, t, j, d, c, k, rest, before_t, done, hs, h, decl, iter, vars, off) {
      for (i = 1; i <= N; i++) {
        t = s[i]
        off = 0
        while (match(substr(t, off + 1), /[A-Za-z0-9_]\.Run[ \t]*\(/)) {
          fc = off + RSTART; off = off + RSTART + RLENGTH - 1
          j = close_of(i, off, "(", ")")
          if (last_arg(text_between(i, off, j, ECOL)) ~ /^[ \t\n]*func[ \t\n]*\(/) add_call(i, fc)
        }
        if (!match(t, /(^|[^A-Za-z0-9_])for([ \t{]|$)/)) continue
        hs = RSTART + RLENGTH - (substr(t, RSTART + RLENGTH - 1, 1) == "{" ? 1 : 0)
        fc = RSTART + (substr(t, RSTART, 1) == "f" ? 0 : 1)
        d = 0; done = 0
        for (j = i; j <= N && !done; j++) {
          t = s[j]
          for (k = (j == i) ? hs : 1; k <= length(t); k++) {
            c = substr(t, k, 1)
            if (c == "(" || c == "[") d++
            else if (c == ")" || c == "]" || c == "}") d--
            else if (c == "{") {
              rest = substr(t, k + 1); before_t = substr(t, 1, k - 1)
              if (d == 0 && rest ~ /^[ \t]*$/ && before_t !~ /(struct|interface)[ \t]*$/) {
                h = text_between(i, hs, j, k - 1)
                if (index(h, "range") > 0) { iter = substr(h, index(h, "range") + 5); decl = (index(h, ":=") > 0) ? substr(h, 1, index(h, ":=") - 1) : "" }
                else { decl = h; sub(/;.*/, "", decl); sub(/:=.*/, "", decl); if (index(h, ":=") == 0) decl = ""; iter = h }
                vars = idents(decl)
                add_loop(i, fc, close_of(j, k, "{", "}"), ECOL, vars, iter); done = 1; break
              }
              d++
            }
          }
        }
      }
    }
    function scan_rust(   i, j, pl, pc, bl, sig, v, tmp) {
      for (i = 1; i <= N; i++) {
        if (s[i] !~ /^[ \t]*#\[(rstest(::rstest)?[\](]|apply\()/) continue
        for (j = i; j <= N && s[j] !~ /(^|[^A-Za-z0-9_])fn[ \t]+[A-Za-z_]/; j++) ;
        if (j > N) break
        match(s[j], /(^|[^A-Za-z0-9_])fn[ \t]+[A-Za-z_]/)
        pl = first_after(j, RSTART, "(", 1); if (pl == 0) { i = j; continue }
        pl = close_of(pl, PCOL, "(", ")"); pc = ECOL
        bl = first_after(pl, pc + 1, "{", 1)
        bl = (bl > 0) ? close_of(bl, PCOL, "{", "}") : pl
        sig = text_between(i, 1, pl, pc)
        tmp = sig; v = gsub(/#\[(values|files)\(/, "", tmp)
        if (v >= 2 || (v >= 1 && (index(sig, "#[case") > 0 || index(sig, "#[apply(") > 0))) report(i, bl, "rstest-values", 0, 0)
        i = j
      }
    }
    BEGIN {
      file = ENVIRON["FILE"]; lang = ENVIRON["LANG_KIND"]
      if (ENVIRON["RANGES"] == "") all = 1
      else while ((getline row < ENVIRON["RANGES"]) > 0) {
        split(row, col, "\t")
        if (col[1] == file) for (i = 0; i < col[3]; i++) added[col[2] + i] = 1
      }
    }
    { raw[NR] = $0; s[NR] = sanitize($0) }
    END {
      N = NR
      if (lang == "js") scan_js()
      else if (lang == "go") scan_go()
      else if (lang == "rust") scan_rust()
      for (a = 1; a <= nl; a++) for (b = 1; b <= nl; b++) {
        if (a == b || !nested(a, b)) continue
        for (x = 1; x <= nc; x++) if (inside(b, CL[x], CC[x])) { cand[a] = 1; break }
        if (lang != "go") continue
        for (x = LS[b]; x <= LE[b]; x++) {
          if (!match(s[x], /[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*append\(/)) continue
          v = substr(s[x], RSTART, RLENGTH); sub(/[ \t]*=.*/, "", v)
          for (k = 1; k <= nl; k++) {
            if (index(LI[k], v) == 0 || !mentions(LI[k], " " v " ")) continue
            for (y = 1; y <= nc; y++) if (inside(k, CL[y], CC[y])) { report(LS[a], LE[a], "go-append-table", 0, 0); break }
          }
        }
      }
      for (a in cand) {
        outer = 1
        for (b in cand) if (a != b && before(LS[b], LC[b], LS[a], LC[a]) && !before(LE[b], LEC[b], LE[a], LEC[a])) outer = 0
        if (outer) report(LS[a], LE[a], "nested-loop", 0, 0)
      }
      for (x = 1; x <= N; x++) {
        if (x in rep) printf "%s:%d\t%s\n", file, x, rep[x]
        else if (x in exempt) printf "%s:%d\texempt\t%s\n", file, x, exempt[x] > "/dev/stderr"
      }
    }
  ' "./$1"
}

: >"$WORK/found"
while IFS= read -r f; do
  l=$(lang_of "$f")
  [ "$l" = none ] && continue
  scan "$f" "$l" "$WORK/ranges" >>"$WORK/found" || exit 2
done <"$WORK/changed"

while IFS= read -r f; do
  l=$(lang_of "$f")
  [ "$l" = none ] && continue
  scan "$f" "$l" "" >>"$WORK/found" || exit 2
done <"$WORK/untracked"

cat "$WORK/found"
[ -s "$WORK/found" ] && exit 1
exit 0
