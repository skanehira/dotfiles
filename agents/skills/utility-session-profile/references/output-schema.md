# `data.json` と `ext.json` のキー

集計スクリプトが出す 2 つの JSON の中身。**分析の材料はここにしかない**ので、手順 4 で
「時間の行き先」を追うときはこの表からキーを選ぶ。散文の書き方は
[narrative-schema.md](narrative-schema.md)、入力ログの構造は [log-format.md](log-format.md)。

- [`data.json` (層 A1 + A2)](#datajson-層-a1--a2)
- [`ext.json` (層 B)](#extjson-層-b)
- [図に出るキーと出ないキー](#図に出るキーと出ないキー)

## `data.json` (層 A1 + A2)

`collect.py` の出力。層 A1 のセッションでは `agents` / `agent_totals` / `concurrency` が
空になる。

| キー | 型 | 内容 |
| --- | --- | --- |
| `snapshot` | 文字列 | 採取時刻 (UTC)。進行中のセッションを比べるときの基準 |
| `session` / `project` / `cwd` / `version` | 文字列 | セッション ID・プロジェクトのディレクトリ名・セッションの作業ディレクトリ・Claude Code のバージョン |
| `start` / `last` / `elapsed_min` | 文字列 / 分 | 最初と最後のレコードの時刻と、その差 |
| `main` | オブジェクト | メインループの集計。`turns` (往復数)・`model_min` (モデル待ち)・`ctx_max` (コンテキストの最大到達値)・`ctx_series` (推移)・`latency_p50` / `latency_max` (応答レイテンシ)・`out_tokens`・`models` (実際に応答したモデルの内訳)・`tool_calls_by_cat` / `tool_seconds_by_cat` (コマンド種別ごとの回数と秒)・`longest` (最長のツール呼び出し) |
| `agents` | 配列 | subagent 1 本ずつ。`name` / `kind` / `agent_type` / `description` / `requested_model` / `models` / `tool_use_id` / `start` / `end` / `wall_s` / `model_s` / `tool_s` / `turns` / `ctx_avg` / `out_tokens` / `tool_calls_by_cat` / `tool_seconds_by_cat` / `longest_calls` |
| `agent_totals` | オブジェクト | 種別ごとの合計。`n` (本数)・`wall_min`・`model_min`・`tool_min`・`turns` |
| `agent_n` / `work_min` | 数 | subagent の本数と、その実行時間の総和 (並列なので経過時間より長くなる) |
| `concurrency` | オブジェクト | `hist` (同時実行数ごとの分数)・`avg`・`series` (1 分刻みの推移)・`window_min`。要求モデルが `haiku` のエージェントは除く |
| `commands` | 配列 | コマンド種別ごとの実行回数。`cat` (`test` / `e2e` / `vcs` / `check` / `build` / `search` / `read` / `edit` / `mutation` / `other`)・`total`・`by_kind` |
| `longest_calls` | 配列 | 最も長かったツール呼び出し 15 件。`agent` / `sec` / `tool` / `cmd` |
| `spawns` | 配列 | `Agent` 呼び出し 1 件ずつ。`t` (時刻)・`tool_use_id` / `name` / `description` / `subagent_type` / `model` / `contract` (prompt から抜いた契約キー) |
| `devimpl` | オブジェクト | `detected` (層 B を出せるか)・`scratch_dir` / `scratch_exists` / `issues` / `candidates` |

## `ext.json` (層 B)

`devimpl.py` の出力。dev-impl の run でだけ作る。

| キー | 型 | 内容 |
| --- | --- | --- |
| `scratch_dir` | 文字列 | 対象 run の SCRATCH。findings をここから読む |
| `phase_order` | 配列 | 実際に現れたフェーズを描く順に並べたもの。ラウンド数はデータから決まるので `r4` 以降も出る |
| `phase_labels` / `phase_families` | オブジェクト | フェーズキー → 表示名 / 活動の種類 (色と凡例の単位) |
| `phase_totals` | オブジェクト | フェーズごとの合計分数。**バーの `m` の合計**であって `w` ではない |

1 つの issue の同じフェーズに複数のエージェントが並ぶことがある (テストとコミットは常に複数)。
その間に親の判断時間が挟まるので、**時間軸上の占有幅 `w` と実際に働いた合計 `m` は一致しない**。
ガントの幅は `w`、バーの数字と `phase_totals` は `m`、`wait` の起点は占有の終端で計算する。

| `issues` | 配列 | issue 1 件ずつ。`issue` / `phases` (キー → 分)・`bars` (`k` フェーズ・`x` 開始オフセット・`w` 時間軸上の占有幅・`m` 実際に働いた合計)・`cycle_min` / `done` |
| `rounds` | 配列 | レビュー 1 ラウンドずつ。`issue` / `round` / `high` / `medium` / `low` / `e2e` / `previous` (前ラウンドの件数)・`files` / `repeat_files` (指摘されたファイルと、前ラウンドと同じもの) |
| `findings_n` / `sev_cat` | 数 / 配列 | findings の総数と、`severity` × `category` の件数 |
| `late_high` | 配列 | 2 周目以降に新たに出た high。`issue` / `round` / `severity` / `category` / `file` / `summary` / `recurrence_of` (前ラウンドの再指摘なら、その出所) |
| `levels` / `deps` | オブジェクト | 依存の段 (段 → issue) と、issue → 依存先。`gh` が使えないと空 |
| `issue_meta` | オブジェクト | issue → `title` / `state` / `labels` |
| `critical` / `critical_sum` | 配列 / 分 | 段ごとの最長サイクル (`level` / `issues` / `max_cycle` / `measured` / `total`) と、その合計 |
| `unmatched_spawns` | 配列 | フェーズは決まったが subagent のログが無い spawn の名前 |
| `unphased_spawns` / `unphased_min` | 配列 / 分 | 契約キーが無くフェーズに寄らない spawn (`name` / `min`) と、その合計。**`phase_totals` に入らない** |
| `timing_used` | 真偽 | 打刻ファイルを併用したか。`false` なら `wait` が出ない |

## 図に出るキーと出ないキー

テンプレートが描くのは、統計タイル・ガント・並列度の推移・フェーズ別合計・種別ごとの
時間・レビューのラウンド表・コマンド実行回数・最長呼び出し・依存段の梯子。

**図にならないが分析には効くキー**が次にある。散文 (`verdicts` / `caption` / `limits`) で
使う。

| キー | 何が読めるか |
| --- | --- |
| `main.ctx_series` | コンテキストがどこで跳ねたか。圧縮の回数と位置 |
| `main.latency_p50` / `latency_max` | モデル応答が遅かったのか、待ちが長かったのか |
| `main.models` | 実際に応答したモデル。要求した alias と違うことがある |
| `ext.sev_cat` | 指摘が偏っている観点。テスト品質ばかりなら、レビューの focus を絞れる |
| `ext.unphased_spawns` | フェーズ合計に入っていない時間。大きければ `limits` に断る |
| `ext.unmatched_spawns` | spawn したのにログが無いエージェント。取りこぼしの手がかり |
