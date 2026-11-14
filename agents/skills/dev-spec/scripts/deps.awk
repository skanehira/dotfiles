# issue の依存のグラフを計算する。POSIX の awk の機能だけで書く (macOS の awk と Ubuntu の mawk で動かすため)。
#
# 使い方: awk -F '\t' -v mode=<levels|order> -f deps.awk <入力>
#
# 入力は 1 行に 1 issue で、タブ区切りの 4 列:
#   番号 / 状態 (target・open・closed) / スコア (数値・U・空) / 依存先の番号 (カンマ区切り・空)
# 状態の target は着手の対象、open は対象外の open な issue (依存先として待つだけ)、closed は完了。
# スコアの U は緊急枠で、どのスコアよりも高い。
#
# mode=levels: 全 issue の段を出す。依存の無い issue が 0、それ以外は依存先の段の最大 + 1。
#   出力: level<TAB>番号<TAB>段 (段・番号の順)
#   入力に無い依存先があれば unknown<TAB>番号<TAB>依存先 を出して終了コード 2。
#   循環 (と、循環に依存する issue) があれば cycle<TAB>番号 を出して終了コード 3。
#
# mode=order: target の着手順を出す。止まらずに、出せるものをすべて出す。
#   start<TAB>番号<TAB>実効スコア   依存先がすべて closed の target。実効スコアの高い順、同じなら番号の小さい順
#   wait<TAB>番号<TAB>依存先        closed でない依存先が残る target (依存先はカンマ区切り)
#   cycle<TAB>番号                  循環に入った target
#   unknown<TAB>番号<TAB>依存先     入力に無い依存先を持つ target
#   実効スコアは、自分と、自分に直接・間接に依存する target のスコアの最大。どこにもスコアが無ければ -。

BEGIN { n = 0; URGENT = 1e15 }

{
  id = $1 + 0
  if (!(id in st)) ids[++n] = id
  st[id] = $2
  sc[id] = $3
  raw[id] = $4
}

function sort_ids(arr, cnt, key1, desc,    i, j, a, b, t, swap) {
  # 挿入ソート。key1 が空でなければ key1[id] を降順の第 1 キー、番号を昇順の第 2 キーにする
  for (i = 2; i <= cnt; i++) {
    t = arr[i]
    j = i - 1
    while (j >= 1) {
      a = arr[j]
      swap = 0
      if (desc) {
        if (key1[a] < key1[t] || (key1[a] == key1[t] && a > t)) swap = 1
      } else if (a > t) {
        swap = 1
      }
      if (!swap) break
      arr[j + 1] = a
      j--
    }
    arr[j + 1] = t
  }
}

function level(x,    j, d, t, m) {
  if (x in lv) return lv[x]
  if (vis[x] == 1) { bad[x] = 1; return -1 }
  vis[x] = 1
  m = 0
  for (j = 1; j <= nd[x]; j++) {
    d = dep[x, j]
    t = level(d)
    if (t < 0) { bad[x] = 1; m = -1; break }
    if (t + 1 > m) m = t + 1
  }
  vis[x] = 2
  if (m < 0) bad[x] = 1
  lv[x] = m
  return m
}

# 着手順で使う循環の検出。target と open の間だけを辿る (closed の先は辿らない)
function on_cycle(x,    j, d, r) {
  if (vis[x] == 1) { bad[x] = 1; return 1 }
  if (vis[x] == 2) return bad[x] + 0
  vis[x] = 1
  r = 0
  for (j = 1; j <= nd[x]; j++) {
    d = dep[x, j]
    if (!(d in st) || st[d] == "closed") continue
    if (on_cycle(d)) r = 1
  }
  vis[x] = 2
  if (r) bad[x] = 1
  return r
}

function own_score(x) {
  if (st[x] != "target" || sc[x] == "") return -1
  if (sc[x] == "U") return URGENT
  return sc[x] + 0
}

# 自分と、自分に依存する target のスコアの最大
function eff(x,    k, y, v, m) {
  if (x in ef) return ef[x]
  ef[x] = own_score(x)
  m = ef[x]
  for (k = 1; k <= nr[x]; k++) {
    y = rdep[x, k]
    if (bad[y] || st[y] != "target") continue
    v = eff(y)
    if (v > m) m = v
  }
  ef[x] = m
  return m
}

function show_score(v) {
  if (v < 0) return "-"
  if (v >= URGENT) return "U"
  return v
}

END {
  unknown_count = 0
  for (i = 1; i <= n; i++) {
    x = ids[i]
    nd[x] = 0
    if (raw[x] == "") continue
    k = split(raw[x], parts, ",")
    for (j = 1; j <= k; j++) {
      d = parts[j] + 0
      if (!(d in st)) {
        unk[++unknown_count] = x SUBSEP d
        unknown_of[x] = 1
        continue
      }
      dep[x, ++nd[x]] = d
      rdep[d, ++nr[d]] = x
    }
  }

  if (mode == "levels") {
    if (unknown_count > 0) {
      for (u = 1; u <= unknown_count; u++) {
        split(unk[u], pair, SUBSEP)
        printf "unknown\t%d\t%d\n", pair[1], pair[2]
      }
      exit 2
    }
    for (i = 1; i <= n; i++) level(ids[i])
    cyc = 0
    for (i = 1; i <= n; i++) if (bad[ids[i]]) cbuf[++cyc] = ids[i]
    if (cyc > 0) {
      sort_ids(cbuf, cyc, nokey, 0)
      for (i = 1; i <= cyc; i++) printf "cycle\t%d\n", cbuf[i]
      exit 3
    }
    # 段で並べ、同じ段は番号の小さい順
    for (i = 1; i <= n; i++) { out[i] = ids[i]; neglv[ids[i]] = -lv[ids[i]] }
    sort_ids(out, n, neglv, 1)
    for (i = 1; i <= n; i++) printf "level\t%d\t%d\n", out[i], lv[out[i]]
    exit 0
  }

  if (mode == "order") {
    for (i = 1; i <= n; i++) if (st[ids[i]] == "target") on_cycle(ids[i])
    ns = 0; nw = 0; nc = 0
    for (i = 1; i <= n; i++) {
      x = ids[i]
      if (st[x] != "target") continue
      if (bad[x]) { cbuf[++nc] = x; continue }
      if (unknown_of[x]) continue
      waiting = ""
      for (j = 1; j <= nd[x]; j++) {
        d = dep[x, j]
        if (st[d] != "closed") waiting = waiting (waiting == "" ? "" : ",") d
      }
      if (waiting == "") { sbuf[++ns] = x; key[x] = eff(x) }
      else { wbuf[++nw] = x; wdeps[x] = waiting }
    }
    sort_ids(sbuf, ns, key, 1)
    for (i = 1; i <= ns; i++) printf "start\t%d\t%s\n", sbuf[i], show_score(key[sbuf[i]])
    sort_ids(wbuf, nw, nokey, 0)
    for (i = 1; i <= nw; i++) printf "wait\t%d\t%s\n", wbuf[i], wdeps[wbuf[i]]
    sort_ids(cbuf, nc, nokey, 0)
    for (i = 1; i <= nc; i++) printf "cycle\t%d\n", cbuf[i]
    for (u = 1; u <= unknown_count; u++) {
      split(unk[u], pair, SUBSEP)
      if (st[pair[1]] == "target") printf "unknown\t%d\t%d\n", pair[1], pair[2]
    }
    exit 0
  }

  print "mode には levels か order を指定する" | "cat 1>&2"
  exit 1
}
