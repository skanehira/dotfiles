---
name: utility-session-profile
description: Claude Code の特定セッションのログから所要時間の内訳を集計し、図表つきの HTML レポートを作る。エージェント種別ごとの時間・並列度・ツール実行の重複・コンテキストの最大到達値を出し、dev-impl のセッションではフェーズ内訳・レビュー収束・issue 依存段のクリティカルパスも加える。「このセッションが何に時間を使ったか調べて」「セッションを分析してレポートにして」「dev-impl が遅い原因を知りたい」「セッションのプロファイルを取って」「実装ループのボトルネックを調べて」などで起動。単一の会話を要約するだけの用途、コードの性能プロファイリングは対象外。
argument-hint: "[セッション ID (先頭数文字で可)。省略時は候補から選ぶ]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion, Artifact
metadata:
  runtimes: claude
---

# セッションのプロファイル

セッションログから「何にどれだけ時間がかかったか」を集計し、HTML レポート 1 枚にする。

**図表はスクリプトが出し、解釈は自分で書く。** この分担が本スキルの骨格で、テンプレートは
セッションに依存しない器に徹する。数字の羅列ではなく「主張 → それを支える数値」を書くのが
成果物の価値になる。

## 何が取れるか (三層)

セッションによって残っている情報が違う。取れる層だけでレポートを組む。

| 層 | 入力 | 出せるもの | 条件 |
| --- | --- | --- | --- |
| **A1** | メインの JSONL | 経過時間・ターン数・コンテキストの最大到達値・モデル応答レイテンシ・ツール実行時間の分類別内訳・最長コマンド | 常に成立 |
| **A2** | `<session>/subagents/` | エージェント種別ごとの「モデル待ち / コマンド実行」の分解、同時実行数の推移、エージェント単位のガント | subagent を起動したセッション |
| **B** | メイン JSONL の `Agent` 呼び出し + subagent の span | issue × フェーズのガント、フェーズ別合計、レビュー収束の表、issue 依存段のクリティカルパス | dev-impl の run |

層 B は**打刻ファイルに依存しない**。dev-impl が契約として subagent の prompt に載せる
`mode` / `issue_number` / `report_path` / `findings_path` からフェーズを復元し、対応する
subagent の span を所要時間とする。オーケストレータが打刻を残すかどうかは run ごとに違う。

## 必要なもの

- **python3 3.8 以上** — スクリプトは標準ライブラリだけで動く。追加のインストールは要らない
  (`datetime.fromisoformat` と代入式を使う)
- **`gh`** (任意) — issue 依存段の節でだけ使う。無ければ `--no-github` を付けるか、
  そのまま実行して該当節を落とす
- ブラウザ — 生成した HTML の確認用

## 手順

### 1. 対象セッションを決める

中間ファイルと成果物は 1 か所にまとめる。以降 `<出力先>` と書くのは、この
`<スクラッチパッド>/session-profile` のことで、**毎回フルパスに展開して打つ**。
シェルの変数は Bash 呼び出しをまたいで残らないので、`K=...` のような変数に頼らない。

```bash
mkdir -p <スクラッチパッド>/session-profile
```

引数でセッションが指定されていればそれを使う。無ければ候補を出す。

```bash
python3 {{@skills-root}}/utility-session-profile/scripts/collect.py --list
```

いま自分がいるディレクトリに対応するプロジェクトのセッションが、新しい順に出る
(ID の先頭 8 文字・更新時刻・サイズ・subagent の本数)。**該当プロジェクトが無ければ
全プロジェクトから出す。** `--limit` で件数、`--cwd` で対象ディレクトリを変えられる。

{{@ask-user}} で選んでもらうときは、**最新のものを推奨として先頭に置く**。サイズと
subagent の本数が、そのセッションから何が取れるかの目安になる。

**進行中のセッションを対象にしてよい。** その場合はレポートの `snapshot_label` に採取時刻を
書き、同じ手順を再実行すれば更新できることを伝える。

### 2. 層 A を集計する

```bash
python3 {{@skills-root}}/utility-session-profile/scripts/collect.py \
  <セッション ID か JSONL のパス> -o <出力先>/data.json
```

セッション ID は先頭数文字でよく、**全プロジェクトを横断**して前方一致で探す。複数当たれば
候補を出して止まるので、絞って指定し直す。

標準出力に出るサマリ (経過・ターン数・エージェント本数・並列度・種別ごとの時間・dev-impl の
検出結果) を読む。ここで全体の形を掴んでから細部に入る。

### 3. dev-impl なら層 B を集計する

`collect.py` が `dev-impl 検出` と出したときだけ実行する。

```bash
python3 {{@skills-root}}/utility-session-profile/scripts/devimpl.py \
  --data <出力先>/data.json -o <出力先>/ext.json
```

**カレントディレクトリは関係ない。** `gh` はログに残った対象セッションの `cwd` で実行される
ので、`cd` しても変わらない。

- `--no-github` で issue 依存グラフの取得を省ける (gh が無い・未認証・オフラインのとき)。
  この場合 `ext.critical` が空になるので、narrative から `critical` の節を消す
- `--no-timing` で打刻ファイルを無視する。フェーズ復元が打刻に依存していないことの確認に使う
- `--scratch <dir>` で**対象 run の SCRATCH** を明示指定する (自動検出が外れたとき)。
  レポートの出力先ではないので、`<出力先>` を渡すと findings が 0 件になる

### 4. 読んで、原因を突き止める

`data.json` と `ext.json` を読む。キーの意味は
[references/output-schema.md](references/output-schema.md) にある。
**時間の行き先を数えるだけで終わらせない。** なぜそこに時間が集まったのかを、
次のような突き合わせで確かめる。

- **クリティカルパスと実測経過の一致**: `ext.critical` の段ごとの最長サイクルを足した値が
  実測の経過時間に近ければ、所要時間は「依存の段数」で決まっている。並列度を上げても縮まない
  という判定になる
- **並列度のヒストグラム**: 枠が余っているのに同時実行数が上がらないなら、並列化の余地ではなく
  依存構造の問題
- **モデル待ちとコマンド実行の比**: どちらが支配的かで、打つ手が変わる (前者はモデル選択や
  ターン数、後者はコマンドの重複)
- **フェーズ外の時間**: `devimpl.py` が `フェーズ外 N 本 M min` と出したら、その分は
  フェーズ別合計に入っていない。契約キーを持たない spawn (merge 競合の解消・事前調査) で、
  無視してよい量かどうかを見て、大きければ `limits` に書く
- **レビューのラウンドごとの severity**: 後半のラウンドで新しい high が出ていないなら、
  そのラウンドは費用に見合っていない
- **再指摘の割合**: r2 以降の findings が r1 と同じファイルを指しているなら、指摘の粒度が
  細かすぎて 1 件ずつ潰す形になっている

### 5. `narrative.json` を書く

分析結果をこのファイルに落とす。**テンプレートは器で、これが成果物**。書き方とキーの一覧は
[references/narrative-schema.md](references/narrative-schema.md) にある。

要点だけ:

- `sections` に**置いたキーの節だけが描かれる**。取れなかった層の節は書かない
- `verdicts` は 3 点前後に絞る。それぞれ「主張 (`text`)」と「支える数値 (`figure`)」の対
- `incidents` と `fixes` はログから読み取った事実に基づいて書く。`fixes` には
  **どのファイルを変えるか (`where`)** と **短縮の見込み (`gain`)** を必ず入れる
- 事故の材料は次から拾う。**ここに現れないものを推測で書かない**
  - `ext.unmatched_spawns` — spawn したのに subagent のログが無い
  - `ext.unphased_spawns` — フェーズ合計に入っていない時間 (merge 競合の解消など)
  - 同じ `name` で複数回 spawn されているエージェント (`data.spawns` を名前で数える)
  - メイン JSONL の `tool_result` で `is_error` が立っている呼び出し
- `text` / `body` / `note` / `caption` には `<em>` `<code>` `<b>` `<br>` だけ使う

### 6. レンダリングする

```bash
python3 {{@skills-root}}/utility-session-profile/scripts/render.py \
  --data <出力先>/data.json --ext <出力先>/ext.json \
  --narrative <出力先>/narrative.json -o <出力先>/report.html
```

層 B が無ければ `--ext` を省く。**材料が無いのに節を書くとエラーで止まる**ので、
その場合は narrative から該当キーを消す。止まるのは次の 5 つ。

| 節 | 要る材料 | 落とす状況 |
| --- | --- | --- |
| `critical` | `ext.critical` | `--no-github` で走らせた・issue に `Depends on` が無い |
| `review` | `ext.rounds` | 層 B が無い |
| `timeline` | issue かエージェント | subagent が 0 本で層 B も無い |
| `incidents` | `narrative.incidents` | 事故を書かなかった |
| `optimize` | `narrative.fixes` | 最適化案を書かなかった |

### 7. 見て、渡す

```bash
python3 {{@skills-root}}/utility-session-profile/scripts/serve.py \
  <出力先> --port 8731   # バックグラウンドで起動する
```

`http://127.0.0.1:8731/report.html` を開いて**一度だけ**確認する。見るのは
コンソールにエラーが無いか、図表が数値と合っているか、ラベルが切れていないか。

**確認したらサーバを必ず止める。** バックグラウンドで起動したタスクを停止するか、
`lsof -nP -iTCP:8731 -sTCP:LISTEN` で PID を出して落とす。止め忘れるとポートを掴んだまま
セッションが終わる。

`file://` では開かない。ローカルサーバを使うのは、`python3 -m http.server` が charset を
返さず日本語が化けて JS が止まるためで、`serve.py` はそれを直したものである。

最後に**ファイルパスを提示する**。**Artifact 公開はしない** — 公開してほしいと言われた
ときだけ `Artifact` ツールで publish する。

## 同梱ファイル

| ファイル | 役割 |
| --- | --- |
| [scripts/collect.py](scripts/collect.py) | 層 A1 + A2 の集計。`Agent` 呼び出しの契約キーと SCRATCH の候補も報告する |
| [scripts/devimpl.py](scripts/devimpl.py) | 層 B の集計。フェーズ・レビュー収束・依存段 |
| [scripts/render.py](scripts/render.py) | テンプレートへの流し込みと、埋め込んだ JSON の検証 |
| [scripts/serve.py](scripts/serve.py) | 表示確認用のローカルサーバ (charset つき) |
| [assets/template.html](assets/template.html) | 図表の骨格。データと散文を外から受ける |
| [references/output-schema.md](references/output-schema.md) | `data.json` / `ext.json` の全キー。分析はここから材料を選ぶ |
| [references/narrative-schema.md](references/narrative-schema.md) | `narrative.json` の全キーと例 |
| [references/log-format.md](references/log-format.md) | ログのどのフィールドに依存してよいか |

## 層が足りないときの縮退

| 状況 | どうなるか |
| --- | --- |
| dev-impl ではない | ガントが「エージェント × 種別」になる。`critical` と `review` の節は書かない |
| subagent が 0 本 | 帯を描く材料が無いので `timeline` の節も落とす。メインループのツール実行内訳が主役になる |
| `gh` が使えない | 依存段の節だけ落ちる。フェーズ内訳とレビュー収束は残る |
| 打刻ファイルが無い | `wait` (merge 待ち) が出ない。他のフェーズは 1 分の違いもなく同じ値になる |

## 注意

- **進行中のセッションは値が動く。** 採取時刻をレポートに刻み、比較するときは同じ snapshot 同士で行う
- **`tail` と `wait` は別のもの。** `tail` はテストとコミットを代行したエージェントの実行時間で、
  打刻の有無によらず同じ値になる。`wait` はそれが終わってから merge が成立するまでの待ち時間で、
  打刻があるときだけ出る。`ext.timing_used` で判別できる
- **並列度は「働いているエージェント」だけを数える。** 要求モデルが `haiku` のエージェント
  (テスト実行・コミットの代行) を除く。名前ではなく要求モデルで判別するのは、
  `{{@rules-root}}/core/orchestration.md` が機械実行を haiku へ委譲すると定めているためで、
  エージェント名は run ごとに変わりうる
- **エージェント種別は `.meta.json` の `agentType` から取る。** `impl-104` → `impl`。
  名前の付け方が違うオーケストレータでは種別がばらけるので、その場合はレポートで種別に触れない
- **図表の色は活動の種類だけを表す。** レビューのラウンド番号は色の濃淡ではなくバーのラベルが持つ。
  濃淡でラウンドを表すと彩度が下がり、`dataviz` の配色検証を通らない
