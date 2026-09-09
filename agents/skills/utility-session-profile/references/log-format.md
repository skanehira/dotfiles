# セッションログの構造

集計スクリプトがどのフィールドに依存しているかと、その根拠。スクリプトを直すときは
ここを読んでから触る。**推測でフィールドを増やさず、複数セッションで実在を確かめてから使う。**

- [置き場所](#置き場所)
- [常に依存してよいもの](#常に依存してよいもの)
- [セッションによって無いもの](#セッションによって無いもの)
- [`.meta.json` のフィールド](#metajson-のフィールド)
- [`Agent` 呼び出しからフェーズを復元する](#agent-呼び出しからフェーズを復元する)
- [サイドチェーン](#サイドチェーン)

## 置き場所

`<cwd を変換したもの>` は、セッションの `cwd` の**英数以外をすべてハイフンに置き換えた**
名前。区切りの `/` だけでなくドットも変わるので、`github.com` は `github-com` になる。

```
~/.claude/projects/<cwd を変換したもの>/
├── <session-id>.jsonl          メインの会話ログ
└── <session-id>/
    ├── subagents/              subagent を起動したセッションだけ
    │   ├── agent-a<name>-<16 桁 hex>.jsonl
    │   └── agent-a<name>-<16 桁 hex>.meta.json
    └── tool-results/           大きすぎるツール出力の退避先
```

`subagents/` は**あるとは限らない**。ある調査時点では、1 プロジェクトの直近 8 セッションのうち
3 本が持ち、5 本が持たなかった。

## 常に依存してよいもの

### `type`

レコードの種類。会話の実体は `assistant` と `user` の 2 つで、残りは UI 状態やメタ情報。

観測した値: `assistant` / `user` / `attachment` / `system` / `mode` / `permission-mode` /
`last-prompt` / `ai-title` / `agent-name` / `atis-latch` / `bridge-session` / `queue-operation` /
`file-history-snapshot` / `file-history-delta` / `cost-state` / `pr-link`

**新しい種類は増える。** 未知の `type` は無視する作りにしておく (集計は `assistant` と
`user` だけを見ればよい)。

### `timestamp`

`assistant` と `user` には必ずある。メタ系のレコード (`mode` / `ai-title` / `last-prompt` /
`file-history-snapshot` / `atis-latch` / `bridge-session` / `cost-state` / `agent-name`) には
**無い**。時刻を使う集計は `select(.timestamp)` で絞る。

書式は `2026-09-08T17:06:29.272Z`。ミリ秒が付く。自分で `isoformat()` して書き戻すと
`+00:00` 形式になるので、パーサは**両方を受ける**必要がある。

```python
datetime.datetime.fromisoformat(re.sub(r"\.\d+Z$", "Z", value).replace("Z", "+00:00"))
```

### `message.usage` (assistant のみ)

確認した 5 セッション (計 811 の assistant レコード) すべてに存在した。使うのは
`input_tokens` / `output_tokens` / `cache_read_input_tokens`。

コンテキストの実効サイズは `input_tokens + cache_read_input_tokens`。キャッシュ読みを
足さないと、キャッシュが効いている間ずっと小さく見える。

### ツール呼び出しと結果の対応

assistant の `message.content[]` の `{"type": "tool_use", "id": ...}` と、
user の `message.content[]` の `{"type": "tool_result", "tool_use_id": ...}` が対になる。
巨大な出力は `tool-results/` に退避されるが、**対応そのものは壊れない**。

所要時間はこの 2 つのタイムスタンプの差。

### `cwd` / `version`

`cwd` はセッションの作業ディレクトリ。GitHub リポジトリを解決するのに使う (`gh repo view` をここで走らせる)。
`version` は Claude Code のバージョンで、**1 セッションの中で複数の値が混ざることがある**
(セッションをまたいで再開したとき)。バージョンで分岐する処理は書かない。

## セッションによって無いもの

| もの | 無いとき | 対処 |
| --- | --- | --- |
| `subagents/` | subagent を起動していないセッション | 層 A2 を落とす。並列度とエージェント棒が出ない |
| `.meta.json` の `customAgentType` | Agent 定義 (`~/.claude/agents/*.md`) を指定しない spawn | `agentType` で代用する |
| `Agent` 呼び出しの `input.prompt` の契約キー | dev-impl 以外のオーケストレータ | 層 B を落とす |
| 対象 run の SCRATCH (`report_path` の dirname) | run 後に消された・別マシン | findings が読めないのでレビュー収束の節を落とす |

## `.meta.json` のフィールド

**spawn のしかたで中身が変わる。** 名前を付けて起動した agent と、付けずに起動した agent で
持っているキーが違う。

名前付き (`Agent` に `name` を渡した場合)。ファイル名も `agent-a<name>-<16 桁 hex>.meta.json`:

```json
{"agentType": "impl-104", "description": "issue #104 の実装", "name": "impl-104",
 "model": "opus", "spawnDepth": 0, "taskKind": "in_process_teammate",
 "teamName": "session-82fc5ce1", "color": "purple",
 "planModeRequired": false, "permissionMode": "auto",
 "customAgentType": "dev-impl-implementer"}
```

名前なし。ファイル名は `agent-a<hex>.meta.json` で、`name` も `customAgentType` も無い:

```json
{"agentType": "general-purpose", "description": "Full audit viewpoint 4",
 "toolUseId": "call_05_dJhhwV3MZapUDCDbJgr33874", "spawnDepth": 1, "model": "opus"}
```

したがって:

- **表示名**は `name` → `description` (短縮) → ファイル名の識別子、の順に落とす
- **種別**は `agentType` から取る。名前付きでは `"impl-104"` のように対象まで入るので数字以降を
  落とし、名前なしでは `"general-purpose"` がそのまま残る。`name` から取ると、名前なしの
  agent でハッシュが種別になって全部バラバラになる
- **`toolUseId`** は名前なしの spawn に付く。`Agent` tool_use の `id` と一致するので、
  名前が無くても呼び出しと突き合わせられる

`model` は**呼び出し側が要求した alias** (`opus` / `haiku`) であって、実際に応答したモデルでは
ない。実際のモデルはログの `message.model` にある。両者が食い違うことがあり (別のプロバイダに
向けた設定など)、その差自体が分析の材料になる。

並列度の集計はこの `model` で「働いているエージェント」を選ぶ (`haiku` を除く)。名前で選ぶと、
オーケストレータが付ける名前は run ごとに変わるため取りこぼす。あるセッションでの実測では、
`haiku` 30 本 / `opus` 77 本に分かれ、名前を列挙する方式では漏れていた `commit-verify` も
`model` では正しく除外できた。

## `Agent` 呼び出しからフェーズを復元する

dev-impl は subagent の prompt に契約キーを載せる (`{{@skills-root}}/dev-impl/SKILL.md`)。
メイン JSONL の `Agent` tool_use の `input.prompt` にそのまま入っているので、ここから
フェーズ構造が復元できる。

```
mode: implement | fix
repo_dir: <絶対パス>
issue_number: <N>
report_path: <SCRATCH>/impl-<N>.json | <SCRATCH>/review-<N>-r<K>.json
findings_path: <SCRATCH>/review-<N>-r<K>.json   (mode: fix のみ)
base_sha: <sha>
focus: all | tests
```

あるセッションでの実測:

| 確かめたこと | 結果 |
| --- | --- |
| `Agent` tool_use の `input.name` と `.meta.json` の `name` の対応 | 103 件 / 103 件で一致、差分ゼロ |
| `report_path` の dirname が対象 run の SCRATCH を指すか | 68 件すべて同一値に収束 |

**打刻ファイル (`timing.tsv`) は dev-impl の契約ではない。** ある run でそれが在ったのは、
ユーザーが「実装時間を記録して」と指示してオーケストレータがその場で作ったからで、次の run に
あるとは限らない。フェーズ復元をそこに依存させると、最も価値のある内訳が丸ごと落ちる。

打刻の有無で結果がどう変わるかは実測してある。`--no-timing` を付けた比較で、
**`impl` / `r1` / `fix1` / `r2` / `fix2` / `r3` / `fix3` / `tail` は 1 分の違いもなく一致**した。
差が出るのは `wait` (代行エージェントが終わってから merge が成立するまでの待ち) だけで、
これは打刻からしか取れないため、打刻が無いセッションでは出ない。

**打刻で `tail` を置き換えない。** 置き換えると、打刻の有無で `tail` の意味そのものが
変わってしまい、フェーズ合計を run 間で比べられなくなる。打刻は待ちを別のフェーズとして
足すためだけに使う。

## サイドチェーン

`isSidechain: true` のレコードは、確認した範囲ではメイン JSONL に 1 件も混ざらなかった
(subagent の会話は `subagents/` に分離されている)。ただしフィールド自体は存在するので、
メイン側の集計で subagent の発話を数えたくない場合は `select(.isSidechain != true)` を
足す余地がある。
